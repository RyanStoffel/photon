#!/usr/bin/env swift

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision

enum ParityFailure: Error, CustomStringConvertible {
  case failed(String)

  var description: String {
    switch self {
    case let .failed(message):
      message
    }
  }
}

let (reportURL, commandURL, screenshotDirectory): (URL, URL, URL) = {
  guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 5 else {
    fputs(
      "usage: native-macos-parity.swift <report.json> <command-file> <screenshot-directory> [relaunch]\n",
      stderr
    )
    exit(2)
  }
  return (
    URL(fileURLWithPath: CommandLine.arguments[1]),
    URL(fileURLWithPath: CommandLine.arguments[2]),
    URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
  )
}()

let isRelaunchVerification = CommandLine.arguments.last == "relaunch"
let fileAccessQuery = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_FILE_ACCESS_QUERY"] ?? ""
let fileAccessResult = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_FILE_ACCESS_RESULT"] ?? ""

func readReport() -> [String: Any]? {
  guard let data = try? Data(contentsOf: reportURL),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return nil
  }
  return object
}

func dictionary(_ value: Any?) -> [String: Any] {
  value as? [String: Any] ?? [:]
}

func int(_ value: Any?) -> Int {
  (value as? NSNumber)?.intValue ?? -1
}

func double(_ value: Any?) -> Double {
  (value as? NSNumber)?.doubleValue ?? .nan
}

func string(_ value: Any?) -> String {
  value as? String ?? ""
}

func bool(_ value: Any?) -> Bool {
  (value as? NSNumber)?.boolValue ?? false
}

func strings(_ value: Any?) -> [String] {
  value as? [String] ?? []
}

@discardableResult
func wait(
  _ label: String,
  timeout: TimeInterval = 15,
  condition: ([String: Any]) -> Bool
) throws -> [String: Any] {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if let report = readReport(), condition(report) {
      print("PASS: \(label)")
      return report
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  }
  throw ParityFailure.failed("Timed out: \(label)")
}

func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
  guard condition() else {
    throw ParityFailure.failed(label)
  }
  print("PASS: \(label)")
}

func launcher(_ report: [String: Any]) -> [String: Any] {
  dictionary(report["launcher"])
}

func frame(_ report: [String: Any]) -> [String: Any] {
  dictionary(launcher(report)["frame"])
}

func top(_ report: [String: Any]) -> Double {
  double(frame(report)["top"])
}

func displayedTitles(_ report: [String: Any]) -> [String] {
  strings(launcher(report)["displayedRowTitles"])
}

func captureLauncher(
  _ report: [String: Any],
  name: String,
  expectedText: String,
  additionalExpectedText: [String] = []
) throws {
  try FileManager.default.createDirectory(
    at: screenshotDirectory,
    withIntermediateDirectories: true
  )
  RunLoop.current.run(until: Date().addingTimeInterval(0.75))
  let destination = screenshotDirectory.appendingPathComponent(name + ".png")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  process.arguments = [
    "-x",
    "-l",
    String(int(launcher(report)["windowNumber"])),
    destination.path,
  ]
  try process.run()
  process.waitUntilExit()
  let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  try require(process.terminationStatus == 0 && size > 0, "captured \(name).png")
  let recognition = VNRecognizeTextRequest()
  recognition.recognitionLevel = .accurate
  let handler = VNImageRequestHandler(url: destination)
  try handler.perform([recognition])
  let renderedText = (recognition.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")
  try require(
    renderedText.localizedCaseInsensitiveContains(expectedText),
    "\(name).png visibly contains \(expectedText)"
  )
  for expected in additionalExpectedText {
    try require(
      renderedText.localizedCaseInsensitiveContains(expected),
      "\(name).png visibly contains \(expected)"
    )
  }
}

func sendRuntimeCommand(_ command: String) throws {
  try command.write(to: commandURL, atomically: true, encoding: .utf8)
}

func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
  guard let source = CGEventSource(stateID: .combinedSessionState),
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
  else {
    return
  }
  down.flags = flags
  up.flags = flags
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.12)
}

func postText(_ text: String) {
  guard let source = CGEventSource(stateID: .combinedSessionState) else {
    return
  }
  for scalar in text.unicodeScalars {
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else {
      continue
    }
    var value = UniChar(scalar.value)
    down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
    up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.04)
  }
}

func clickSearchField(_ report: [String: Any]) {
  let windowFrame = frame(report)
  let x = double(windowFrame["x"]) + double(windowFrame["width"]) / 2
  let nsTop = double(windowFrame["top"])
  let display = CGDisplayBounds(CGMainDisplayID())
  let y = display.maxY - nsTop + 25
  let point = CGPoint(x: x, y: y)
  guard let source = CGEventSource(stateID: .combinedSessionState),
        let down = CGEvent(
          mouseEventSource: source,
          mouseType: .leftMouseDown,
          mouseCursorPosition: point,
          mouseButton: .left
        ),
        let up = CGEvent(
          mouseEventSource: source,
          mouseType: .leftMouseUp,
          mouseCursorPosition: point,
          mouseButton: .left
        )
  else {
    return
  }
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.2)
}

func runningWindowBounds(pid: pid_t, expectedSize: CGSize) -> CGRect? {
  let windows = CGWindowListCopyWindowInfo(
    .optionAll,
    kCGNullWindowID
  ) as? [[String: Any]] ?? []
  return windows.compactMap { entry -> CGRect? in
    guard int(entry[kCGWindowOwnerPID as String]) == pid,
          let bounds = entry[kCGWindowBounds as String] as? [String: Any]
    else {
      return nil
    }
    return CGRect(
      x: double(bounds["X"]),
      y: double(bounds["Y"]),
      width: double(bounds["Width"]),
      height: double(bounds["Height"])
    )
  }.min { lhs, rhs in
    let lhsDistance = abs(lhs.width - expectedSize.width) + abs(lhs.height - expectedSize.height)
    let rhsDistance = abs(rhs.width - expectedSize.width) + abs(rhs.height - expectedSize.height)
    return lhsDistance < rhsDistance
  }
}

func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(
    element,
    kAXChildrenAttribute as CFString,
    &value
  ) == .success
  else {
    return []
  }
  return value as? [AXUIElement] ?? []
}

func accessibilityRole(of element: AXUIElement) -> String {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(
    element,
    kAXRoleAttribute as CFString,
    &value
  ) == .success
  else {
    return ""
  }
  return value as? String ?? ""
}

func findTextField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
  guard depth < 16 else {
    return nil
  }
  if accessibilityRole(of: element) == kAXTextFieldRole as String {
    return element
  }
  for child in accessibilityChildren(of: element) {
    if let result = findTextField(in: child, depth: depth + 1) {
      return result
    }
  }
  return nil
}

func accessibilityTitle(of element: AXUIElement) -> String {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(
    element,
    kAXTitleAttribute as CFString,
    &value
  ) == .success
  else {
    return ""
  }
  return value as? String ?? ""
}

func findButton(in element: AXUIElement, title: String, depth: Int = 0) -> AXUIElement? {
  guard depth < 16 else {
    return nil
  }
  if accessibilityRole(of: element) == kAXButtonRole as String,
     accessibilityTitle(of: element) == title
  {
    return element
  }
  for child in accessibilityChildren(of: element) {
    if let result = findButton(in: child, title: title, depth: depth + 1) {
      return result
    }
  }
  return nil
}

func pressPhotonButton(pid: pid_t, title: String) -> Bool {
  let application = AXUIElementCreateApplication(pid)
  guard let button = findButton(in: application, title: title) else {
    return false
  }
  return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
}

func focusPhotonTextField(pid: pid_t) -> Bool {
  let application = AXUIElementCreateApplication(pid)
  guard let textField = findTextField(in: application) else {
    return false
  }
  return AXUIElementSetAttributeValue(
    textField,
    kAXFocusedAttribute as CFString,
    kCFBooleanTrue
  ) == .success
}

func setPhotonTextFieldValue(pid: pid_t, value: String) -> Bool {
  let application = AXUIElementCreateApplication(pid)
  guard let textField = findTextField(in: application) else {
    return false
  }
  return AXUIElementSetAttributeValue(
    textField,
    kAXValueAttribute as CFString,
    value as CFString
  ) == .success
}

func confirmPhotonTextField(pid: pid_t) -> Bool {
  let application = AXUIElementCreateApplication(pid)
  guard let textField = findTextField(in: application) else {
    return false
  }
  return AXUIElementPerformAction(textField, kAXConfirmAction as CFString) == .success
}

func setSystemAppearance(dark: Bool) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
  process.arguments = dark
    ? ["write", "-g", "AppleInterfaceStyle", "Dark"]
    : ["delete", "-g", "AppleInterfaceStyle"]
  try? process.run()
  process.waitUntilExit()
  DistributedNotificationCenter.default().post(
    name: Notification.Name("AppleInterfaceThemeChangedNotification"),
    object: nil
  )
}

do {
  var report = try wait("packaged Photon.app started") { int($0["pid"]) > 0 }
  let pid = pid_t(int(report["pid"]))
  let app = NSRunningApplication(processIdentifier: pid)
  try require(app != nil, "NSRunningApplication resolves Photon")
  try require(app?.activationPolicy == .accessory, "activation policy is accessory (no Dock app)")
  try require(
    int(report["activationPolicy"]) == NSApplication.ActivationPolicy.accessory.rawValue,
    "in-process activation policy is accessory"
  )

  let status = dictionary(report["statusItem"])
  try require(bool(status["visible"]), "menu-bar status item is visible")
  try require(bool(status["hasButton"]), "menu-bar status item has a button")
  try require(int(status["menuItemCount"]) >= 6, "menu-bar item has the Photon menu")

  report = try wait("launcher panel exists while hidden") {
    bool(launcher($0)["exists"]) && !bool(launcher($0)["visible"])
  }
  let panel = launcher(report)
  try require(
    string(panel["class"]) == "Photon.LauncherPanel"
      || string(panel["class"]).hasSuffix(".LauncherPanel"),
    "launcher uses LauncherPanel"
  )
  try require(bool(panel["borderless"]), "launcher is borderless")
  try require(bool(panel["nonactivatingPanel"]), "launcher is non-activating")
  try require(!bool(panel["titled"]), "launcher has no title chrome")
  try require(!bool(panel["standardButtonVisible"]), "launcher has no traffic-light buttons")
  try require(bool(panel["floating"]), "launcher is a floating panel")
  try require(!bool(panel["canBecomeMain"]), "launcher cannot become the main window")

  if isRelaunchVerification {
    report = try wait("security-scoped folder grant restores after packaged-app relaunch") {
      int(dictionary($0["fileAccess"])["grantCount"]) == 1
        && string(dictionary($0["fileAccess"])["status"]) == "granted"
    }
    try sendRuntimeCommand("showFiles:\(fileAccessQuery)")
    report = try wait("restored grant finds the unindexed file after relaunch", timeout: 8) {
      bool(launcher($0)["visible"])
        && string(launcher($0)["mode"]) == "files"
        && displayedTitles($0).contains(fileAccessResult)
    }
    try captureLauncher(report, name: "file-access-after-relaunch", expectedText: fileAccessResult)
    print("Native macOS file-access relaunch parity checks passed.")
    exit(0)
  }

  _ = try wait("application bundle icon resolves in the packaged app", timeout: 30) {
    int($0["appIconProbeCount"]) > 0
  }

  _ = try wait("clipboard monitor captured four runtime fixtures") { int($0["clipboardCaptureCount"]) >= 4 }
  postKey(9, flags: [.maskCommand, .maskShift])
  report = try wait("Cmd+Shift+V opens compact clipboard history") {
    let value = launcher($0)
    return bool(value["visible"])
      && string(value["session"]) == "clipboard"
      && string(value["content"]) == "searchOnly"
  }
  let anchoredTop = top(report)

  let nativeFrame = frame(report)
  let expectedSize = CGSize(
    width: double(nativeFrame["width"]),
    height: double(nativeFrame["height"])
  )
  if let cgBounds = runningWindowBounds(pid: pid, expectedSize: expectedSize) {
    try require(
      abs(cgBounds.width - double(frame(report)["width"])) < 2,
      "CGWindow width matches the native panel"
    )
    try require(
      abs(cgBounds.height - double(frame(report)["height"])) < 2,
      "CGWindow height matches the native panel"
    )
  } else {
    print(
      "INFO: CGWindow cross-process bounds unavailable on this runner; "
        + "in-process NSPanel frame checks remain active"
    )
  }

  let applicationElement = AXUIElementCreateApplication(pid)
  var axWindows: CFTypeRef?
  let axResult = AXUIElementCopyAttributeValue(
    applicationElement,
    kAXWindowsAttribute as CFString,
    &axWindows
  )
  if axResult == .success {
    let count = (axWindows as? [AXUIElement])?.count ?? 0
    try require(count > 0, "Accessibility sees the Photon window")
  } else {
    print(
      "INFO: Accessibility introspection unavailable on this runner "
        + "(\(axResult.rawValue)); CGWindow checks remain authoritative"
    )
  }

  clickSearchField(report)
  report = try wait("click keeps the panel anchored") {
    bool(launcher($0)["key"]) && abs(top($0) - anchoredTop) < 0.5
  }

  postKey(125)
  report = try wait("Down expands clipboard results without moving the top edge") {
    string(launcher($0)["content"]) == "rows"
      && int(launcher($0)["clipboardSelectedIndex"]) >= 0
      && abs(top($0) - anchoredTop) < 0.5
  }
  let firstSelection = int(launcher(report)["clipboardSelectedIndex"])
  postKey(125)
  report = try wait("Down cycles clipboard selection") {
    int(launcher($0)["clipboardSelectedIndex"]) != firstSelection
  }
  try require(
    !string(launcher(report)["clipboardSelectedTitle"]).isEmpty,
    "expanded clipboard exposes the visibly selected row"
  )
  try captureLauncher(
    report,
    name: "clipboard-hotkey-selection",
    expectedText: string(launcher(report)["clipboardSelectedTitle"])
  )
  postKey(126)
  _ = try wait("Up cycles clipboard selection") {
    int(launcher($0)["clipboardSelectedIndex"]) == firstSelection
  }

  postText("needle")
  _ = try wait("typing filters clipboard and preserves the anchor") {
    string(launcher($0)["query"]) == "needle"
      && int(launcher($0)["clipboardResultCount"]) == 1
      && abs(top($0) - anchoredTop) < 0.5
  }

  postKey(36)
  _ = try wait("Enter uses the selected clipboard item and dismisses") {
    !bool(launcher($0)["visible"])
  }
  try require(
    NSPasteboard.general.string(forType: .string)?.contains("needle") == true,
    "Enter copied the selected clipboard item"
  )

  postKey(9, flags: [.maskCommand, .maskShift])
  _ = try wait("clipboard hotkey reopens compact and unclipped") {
    let value = launcher($0)
    return bool(value["visible"])
      && string(value["session"]) == "clipboard"
      && string(value["content"]) == "searchOnly"
      && string(value["query"]).isEmpty
  }

  try sendRuntimeCommand("hideLauncher")
  _ = try wait("clipboard session closes before launcher-entry test") {
    !bool(launcher($0)["visible"])
  }
  postKey(35, flags: [.maskCommand, .maskAlternate, .maskControl])
  report = try wait("configured global hotkey reopens the compact launcher") {
    bool(launcher($0)["visible"])
      && string(launcher($0)["session"]) == "commands"
      && string(launcher($0)["content"]) == "searchOnly"
  }
  clickSearchField(report)
  try require(focusPhotonTextField(pid: pid), "Accessibility focuses the launcher search field")
  try require(setPhotonTextFieldValue(pid: pid, value: "clipboard"), "Accessibility enters launcher search text")
  _ = try wait("launcher search finds Clipboard History") {
    string(launcher($0)["query"]) == "clipboard" && int(launcher($0)["resultCount"]) > 0
  }
  try require(confirmPhotonTextField(pid: pid), "Accessibility confirms the selected launcher result")
  report = try wait("launcher Clipboard History entry opens compact") {
    string(launcher($0)["session"]) == "clipboard"
      && string(launcher($0)["content"]) == "searchOnly"
  }
  clickSearchField(report)
  report = try wait("launcher-entry clipboard panel is the key-event target") {
    bool(launcher($0)["key"])
  }
  try require(
    focusPhotonTextField(pid: pid),
    "Accessibility focuses launcher-entry clipboard search field"
  )
  postKey(125)
  report = try wait("launcher-entry Down expands clipboard history") {
    string(launcher($0)["content"]) == "rows"
      && int(launcher($0)["clipboardSelectedIndex"]) >= 0
      && bool(launcher($0)["key"])
  }
  let launcherEntryFirstSelection = int(launcher(report)["clipboardSelectedIndex"])
  postKey(125)
  report = try wait("launcher-entry Down visibly moves selection") {
    int(launcher($0)["clipboardSelectedIndex"]) != launcherEntryFirstSelection
      && !string(launcher($0)["clipboardSelectedTitle"]).isEmpty
  }
  try captureLauncher(
    report,
    name: "clipboard-launcher-selection",
    expectedText: string(launcher(report)["clipboardSelectedTitle"])
  )
  postKey(126)
  _ = try wait("launcher-entry Up visibly restores selection") {
    int(launcher($0)["clipboardSelectedIndex"]) == launcherEntryFirstSelection
  }

  try sendRuntimeCommand("hideLauncher")
  _ = try wait("clipboard session closes before file-search tests") {
    !bool(launcher($0)["visible"])
  }
  try sendRuntimeCommand("showLauncher")
  report = try wait("native runtime hook opens the launcher for mixed file search") {
    let value = launcher($0)
    return bool(value["visible"])
      && bool(value["key"])
      && string(value["session"]) == "commands"
      && string(value["mode"]).isEmpty
  }
  clickSearchField(report)
  try require(focusPhotonTextField(pid: pid), "Accessibility focuses file-access setup field")
  try require(setPhotonTextFieldValue(pid: pid, value: "files"), "Accessibility searches for Files command")
  _ = try wait("launcher visibly displays Search Files for setup") {
    displayedTitles($0).contains("Search Files")
  }
  try require(confirmPhotonTextField(pid: pid), "Accessibility invokes Search Files for setup")
  report = try wait("ungranted Files mode opens") {
    string(launcher($0)["mode"]) == "files" && bool(launcher($0)["key"])
  }
  clickSearchField(report)
  try require(focusPhotonTextField(pid: pid), "Accessibility refocuses the Files mode field")
  postText(fileAccessQuery)
  report = try wait("ungranted fallback offers one guided folder action", timeout: 8) {
    string(launcher($0)["query"]) == fileAccessQuery
      && string(launcher($0)["fileStatus"]) == "needsAccess"
      && bool(launcher($0)["visible"])
      && int(dictionary($0["fileAccess"])["grantCount"]) == 0
  }
  try require(
    pressPhotonButton(pid: pid, title: "Choose Folders…"),
    "guided access button drives the controlled open-panel adapter"
  )
  report = try wait("folder grant keeps Photon alive and resumes the search", timeout: 8) {
    int($0["pid"]) == Int(pid)
      && bool(launcher($0)["visible"])
      && string(launcher($0)["mode"]) == "files"
      && string(launcher($0)["query"]) == fileAccessQuery
      && displayedTitles($0).contains(fileAccessResult)
      && int(dictionary($0["fileAccess"])["grantCount"]) == 1
      && string(dictionary($0["fileAccess"])["status"]) == "granted"
  }
  try captureLauncher(report, name: "guided-file-access-resumed", expectedText: fileAccessResult)

  try sendRuntimeCommand("hideLauncher")
  _ = try wait("guided setup closes before mixed-search verification") {
    !bool(launcher($0)["visible"])
  }
  try sendRuntimeCommand("showLauncher")
  report = try wait("launcher reopens after guided file setup") {
    bool(launcher($0)["visible"]) && string(launcher($0)["mode"]).isEmpty
  }
  let expectedFile = "Ember_Individual_Pitch.pdf"
  clickSearchField(report)
  try require(focusPhotonTextField(pid: pid), "Accessibility focuses mixed-search field")
  try require(setPhotonTextFieldValue(pid: pid, value: "ember"), "Accessibility enters mixed file query")
  report = try wait("mixed launcher visibly displays the seeded PDF", timeout: 8) {
    string(launcher($0)["query"]) == "ember"
      && string(launcher($0)["mode"]).isEmpty
      && displayedTitles($0).contains(expectedFile)
  }
  try captureLauncher(report, name: "ember-mixed-search", expectedText: expectedFile)

  try require(bool(launcher(report)["key"]), "launcher remains the key-event target")
  try require(setPhotonTextFieldValue(pid: pid, value: "files"), "Accessibility searches for Files command")
  _ = try wait("launcher visibly displays Search Files") {
    displayedTitles($0).contains("Search Files")
  }
  try require(confirmPhotonTextField(pid: pid), "Accessibility invokes Search Files")
  report = try wait("empty Files mode shows seeded recents and selects the PDF") {
    string(launcher($0)["mode"]) == "files"
      && bool(launcher($0)["key"])
      && displayedTitles($0).contains("Ember_Individual_Pitch.pdf")
      && displayedTitles($0).contains("Photon_Recent_Image.png")
      && string(launcher($0)["fileSelectedName"]) == "Ember_Individual_Pitch.pdf"
  }
  try captureLauncher(
    report,
    name: "files-recents-pdf-preview",
    expectedText: "EMBER PDF PREVIEW",
    additionalExpectedText: ["Recent Files", "Name", "Where", "Type", "Size", "Created", "Modified"]
  )
  postKey(125)
  report = try wait("Down updates the recents preview to the seeded image") {
    string(launcher($0)["fileSelectedName"]) == "Photon_Recent_Image.png"
  }
  try captureLauncher(
    report,
    name: "files-recents-image-preview",
    expectedText: "PHOTON IMAGE PREVIEW",
    additionalExpectedText: ["Metadata", "PNG"]
  )
  postKey(126)
  _ = try wait("Up restores the recent PDF preview") {
    string(launcher($0)["fileSelectedName"]) == "Ember_Individual_Pitch.pdf"
  }
  try require(setPhotonTextFieldValue(pid: pid, value: "ember"), "Accessibility enters explicit Files query")
  report = try wait("explicit Files mode visibly displays the seeded PDF", timeout: 8) {
    string(launcher($0)["query"]) == "ember"
      && string(launcher($0)["mode"]) == "files"
      && displayedTitles($0).contains(expectedFile)
  }
  try captureLauncher(report, name: "ember-files-mode", expectedText: expectedFile)

  let light = dictionary(report["appearance"])
  setSystemAppearance(dark: true)
  report = try wait("running UI follows live dark appearance") {
    string(dictionary($0["appearance"])["name"]).contains("DarkAqua")
  }
  try captureLauncher(
    report,
    name: "files-query-dark",
    expectedText: expectedFile,
    additionalExpectedText: ["Metadata"]
  )
  let dark = dictionary(report["appearance"])
  let lightBackground = dictionary(light["controlBackground"])
  let darkBackground = dictionary(dark["controlBackground"])
  let colorDistance = abs(double(lightBackground["red"]) - double(darkBackground["red"]))
    + abs(double(lightBackground["green"]) - double(darkBackground["green"]))
    + abs(double(lightBackground["blue"]) - double(darkBackground["blue"]))
  try require(colorDistance > 0.1, "light and dark runtime colors differ")
  setSystemAppearance(dark: false)
  _ = try wait("running UI follows live light appearance") {
    string(dictionary($0["appearance"])["name"]).contains("Aqua")
      && !string(dictionary($0["appearance"])["name"]).contains("Dark")
  }

  print("Native macOS parity harness passed.")
} catch {
  setSystemAppearance(dark: false)
  fputs("::error title=Native parity failed::\(error)\n", stderr)
  fputs("NATIVE PARITY FAILED: \(error)\n", stderr)
  exit(1)
}
