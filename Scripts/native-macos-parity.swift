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
let pasteSentinel = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE_SENTINEL"] ?? ""
let pasteTargetValueURL = URL(
  fileURLWithPath: ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE_TARGET_VALUE"] ?? ""
)
let pasteInjectionURL = URL(
  fileURLWithPath: ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE_INJECTION_PATH"] ?? ""
)
let pasteTargetPID = pid_t(
  Int32(ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE_TARGET_PID"] ?? "") ?? 0
)
let pasteTargetCommandURL = URL(
  fileURLWithPath: ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE_TARGET_COMMAND"] ?? ""
)

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
  let captureDeadline = Date().addingTimeInterval(8)
  while process.isRunning, Date() < captureDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }
  if process.isRunning {
    process.terminate()
    throw ParityFailure.failed("screencapture timed out for \(name).png")
  }
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

func fulfillPasteInjectionIfNeeded() {
  guard FileManager.default.fileExists(atPath: pasteInjectionURL.path) else {
    return
  }
  try? FileManager.default.removeItem(at: pasteInjectionURL)
  postKey(9, flags: .maskCommand)
  try? "paste".write(to: pasteTargetCommandURL, atomically: true, encoding: .utf8)
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

func windowPoint(_ report: [String: Any], xFromLeft: Double, yFromTop: Double) -> CGPoint {
  let windowFrame = frame(report)
  let display = CGDisplayBounds(CGMainDisplayID())
  return CGPoint(
    x: double(windowFrame["x"]) + xFromLeft,
    y: display.maxY - double(windowFrame["top"]) + yFromTop
  )
}

func clickLauncher(_ report: [String: Any], xFromLeft: Double, yFromTop: Double) {
  let point = windowPoint(report, xFromLeft: xFromLeft, yFromTop: yFromTop)
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

func dragLauncher(
  _ report: [String: Any],
  xFromLeft: Double,
  yFromTop: Double,
  deltaX: Double,
  deltaY: Double
) -> Bool {
  let start = windowPoint(report, xFromLeft: xFromLeft, yFromTop: yFromTop)
  guard let source = CGEventSource(stateID: .combinedSessionState),
        let down = CGEvent(
          mouseEventSource: source,
          mouseType: .leftMouseDown,
          mouseCursorPosition: start,
          mouseButton: .left
        )
  else {
    return false
  }
  var sawGuides = false
  down.post(tap: .cghidEventTap)
  for step in 1 ... 12 {
    let fraction = Double(step) / 12
    let point = CGPoint(
      x: start.x + deltaX * fraction,
      y: start.y + deltaY * fraction
    )
    guard let dragged = CGEvent(
      mouseEventSource: source,
      mouseType: .leftMouseDragged,
      mouseCursorPosition: point,
      mouseButton: .left
    ) else {
      continue
    }
    dragged.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.04)
    if let liveReport = readReport(),
       bool(dictionary(liveReport["launcherDrag"])["guidesVisible"])
    {
      sawGuides = true
    }
  }
  let end = CGPoint(x: start.x + deltaX, y: start.y + deltaY)
  if let up = CGEvent(
    mouseEventSource: source,
    mouseType: .leftMouseUp,
    mouseCursorPosition: end,
    mouseButton: .left
  ) {
    up.post(tap: .cghidEventTap)
  }
  Thread.sleep(forTimeInterval: 0.25)
  return sawGuides
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

func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
    return ""
  }
  if let string = value as? String {
    return string
  }
  if let number = value as? NSNumber, number.boolValue {
    return "true"
  }
  return ""
}

func axIsSelected(_ element: AXUIElement) -> Bool {
  var value: CFTypeRef?
  if AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &value) == .success,
     (value as? NSNumber)?.boolValue == true
  {
    return true
  }
  let traits = axStringAttribute(element, "AXDOMClassList")
  if traits.localizedCaseInsensitiveContains("selected") {
    return true
  }
  return axStringAttribute(element, kAXValueAttribute as String) == "selected"
    || axStringAttribute(element, kAXDescriptionAttribute as String).localizedCaseInsensitiveContains("selected")
}

func axElementTitle(_ element: AXUIElement) -> String {
  for attribute in [
    kAXTitleAttribute as String,
    kAXDescriptionAttribute as String,
    kAXValueAttribute as String,
    "AXIdentifier",
  ] {
    let text = axStringAttribute(element, attribute)
    if !text.isEmpty, text != "selected", text != "unselected", text != "clipboard-row" {
      return text
    }
  }
  return ""
}

func axSelectedClipboardTitle(pid: pid_t, candidates: [String]) -> String? {
  func matches(_ text: String) -> String? {
    candidates.first { candidate in
      text.localizedCaseInsensitiveContains(candidate) || candidate.localizedCaseInsensitiveContains(text)
    }
  }
  func walk(_ element: AXUIElement, depth: Int) -> String? {
    guard depth < 24 else {
      return nil
    }
    let identifier = axStringAttribute(element, "AXIdentifier")
    let title = axElementTitle(element)
    if identifier == "clipboard-row", axIsSelected(element), let match = matches(title) {
      return match
    }
    if axIsSelected(element), let match = matches(title) {
      return match
    }
    for child in accessibilityChildren(of: element) {
      if let found = walk(child, depth: depth + 1) {
        return found
      }
    }
    return nil
  }
  return walk(AXUIElementCreateApplication(pid), depth: 0)
}

func meanLuminance(of image: CGImage, rect: CGRect) -> Double? {
  let clamped = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
  guard clamped.width >= 2, clamped.height >= 2 else {
    return nil
  }
  let width = Int(clamped.width)
  let height = Int(clamped.height)
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
    guard let context = CGContext(
      data: raw.baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return false
    }
    context.draw(image, in: CGRect(x: -clamped.minX, y: -clamped.minY, width: image.width, height: image.height))
    return true
  }
  guard drawn else {
    return nil
  }
  var total = 0.0
  let count = width * height
  for index in 0 ..< count {
    let offset = index * 4
    let red = Double(pixels[offset])
    let green = Double(pixels[offset + 1])
    let blue = Double(pixels[offset + 2])
    total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }
  return total / Double(count)
}

func visuallyHighlightedTitle(at url: URL, candidates: [String], leftFraction: Double) -> String? {
  guard let image = NSImage(contentsOf: url),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  else {
    return nil
  }
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  let handler = VNImageRequestHandler(cgImage: cgImage)
  try? handler.perform([request])
  let width = Double(cgImage.width)
  let height = Double(cgImage.height)
  var scored: [(title: String, luminance: Double)] = []
  for observation in request.results ?? [] {
    guard let text = observation.topCandidates(1).first?.string else {
      continue
    }
    let box = observation.boundingBox
    guard box.midX < leftFraction else {
      continue
    }
    let match = candidates.first { candidate in
      text.localizedCaseInsensitiveContains(candidate) || candidate.localizedCaseInsensitiveContains(text)
    }
    guard let match else {
      continue
    }
    let pixel = CGRect(
      x: box.minX * width,
      y: (1 - box.maxY) * height,
      width: max(box.width * width, 8),
      height: max(box.height * height, 8)
    ).insetBy(dx: -18, dy: -6)
    if let luminance = meanLuminance(of: cgImage, rect: pixel) {
      scored.append((match, luminance))
    }
  }
  guard scored.count >= 2 else {
    return scored.first?.title
  }
  let median = scored.map(\.luminance).sorted()[scored.count / 2]
  return scored.max { lhs, rhs in
    abs(lhs.luminance - median) < abs(rhs.luminance - median)
  }?.title
}

func requireClipboardListHighlight(
  pid: pid_t,
  report: [String: Any],
  screenshot: String
) throws {
  let selected = string(launcher(report)["clipboardSelectedTitle"])
  let titles = displayedTitles(report)
  try require(!selected.isEmpty, "clipboard exposes a selected title")
  try require(titles.count >= 2, "clipboard list has multiple rows to highlight")
  try require(
    titles.first != selected,
    "highlighted selection moved off the first list row (\(titles.first ?? ""))"
  )
  try captureLauncher(report, name: screenshot, expectedText: selected)
  if let axTitle = axSelectedClipboardTitle(pid: pid, candidates: titles) {
    try require(
      axTitle.localizedCaseInsensitiveContains(selected)
        || selected.localizedCaseInsensitiveContains(axTitle),
      "AX selected left-row title matches \(selected)"
    )
    return
  }
  let screenshotURL = screenshotDirectory.appendingPathComponent(screenshot + ".png")
  if let visual = visuallyHighlightedTitle(at: screenshotURL, candidates: titles, leftFraction: 0.42) {
    try require(
      visual.localizedCaseInsensitiveContains(selected)
        || selected.localizedCaseInsensitiveContains(visual),
      "visually highlighted left-row title matches \(selected)"
    )
    return
  }
  throw ParityFailure.failed("could not read the highlighted clipboard left-row title")
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

  try sendRuntimeCommand("showLauncher")
  report = try wait("drag checks open the compact launcher") {
    bool(launcher($0)["visible"])
      && bool(launcher($0)["key"])
      && string(launcher($0)["content"]) == "searchOnly"
  }
  let centeredX = double(frame(report)["x"])
  let firstY = double(frame(report)["y"])
  let panelWidth = double(frame(report)["width"])
  let firstGuides = dragLauncher(
    report,
    xFromLeft: 12,
    yFromTop: 30,
    deltaX: -430,
    deltaY: 70
  )
  report = try wait("left chrome drag keeps outside-corridor X free and adjusts Y") {
    abs(double(frame($0)["x"]) - centeredX) > 120
      && abs(double(frame($0)["y"]) - firstY) > 30
      && bool(dictionary(dictionary($0["settings"])["launcherPosition"])["centered"]) == false
  }
  try require(firstGuides, "left chrome drag displays center guides")
  try require(
    double(dictionary(report["launcherDrag"])["guideSpan"]) >= panelWidth * 0.9,
    "snap guides span the centered panel width rather than a collapsed corridor"
  )

  let freeX = double(frame(report)["x"])
  let freeY = double(frame(report)["y"])
  let secondGuides = dragLauncher(
    report,
    xFromLeft: 12,
    yFromTop: 30,
    deltaX: centeredX - freeX,
    deltaY: -55
  )
  report = try wait("left chrome drag snaps X inside corridor while preserving chosen Y") {
    abs(double(frame($0)["x"]) - centeredX) < 1
      && abs(double(frame($0)["y"]) - freeY) > 25
      && bool(dictionary(dictionary($0["settings"])["launcherPosition"])["centered"])
  }
  try require(secondGuides, "left chrome drag displays center guides")

  let snappedY = double(frame(report)["y"])
  _ = dragLauncher(
    report,
    xFromLeft: panelWidth - 12,
    yFromTop: 30,
    deltaX: 0,
    deltaY: 45
  )
  report = try wait("right chrome drag tracks vertically without frame drift") {
    abs(double(frame($0)["x"]) - centeredX) < 1
      && abs(double(frame($0)["y"]) - snappedY) > 20
  }

  try sendRuntimeCommand("resetLauncherPosition")
  report = try wait("launcher returns on-screen after drag checks") {
    double(frame($0)["y"]) > 0
      && abs(double(frame($0)["x"]) - centeredX) < 80
  }

  clickSearchField(report)
  try require(focusPhotonTextField(pid: pid), "drag chrome does not hijack the search field")
  try require(setPhotonTextFieldValue(pid: pid, value: "clipboard"), "search field remains editable after dragging")
  report = try wait("row remains clickable after dragging") {
    string(launcher($0)["query"]) == "clipboard" && int(launcher($0)["resultCount"]) > 0
  }
  clickLauncher(
    report,
    xFromLeft: panelWidth / 2,
    yFromTop: 56 + 1 + 6 + 20
  )
  _ = try wait("row click enters clipboard instead of starting a drag") {
    string(launcher($0)["session"]) == "clipboard"
  }
  try sendRuntimeCommand("hideLauncher")
  _ = try wait("drag interaction checks close cleanly") {
    !bool(launcher($0)["visible"])
  }

  report = try wait("clipboard monitor captured text and image runtime fixtures") {
    int($0["clipboardCaptureCount"]) >= 6
  }
  try require(bool(report["clipboardAccessibilityTrusted"]), "trusted AX state is reported without stale caching")
  let pasteTarget = NSRunningApplication(processIdentifier: pasteTargetPID)
  try require(pasteTarget != nil, "real paste target process is running")
  try require(
    pasteTarget?.activate(options: [.activateIgnoringOtherApps]) == true,
    "real paste target owns focus before Photon opens"
  )
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
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
    string(launcher($0)["content"]) == "fullHeight"
      && int(launcher($0)["clipboardSelectedIndex"]) >= 0
      && abs(top($0) - anchoredTop) < 0.5
  }
  try require(
    string(launcher(report)["clipboardSelectedKind"]) == "image",
    "expanded clipboard selects the seeded image"
  )
  try captureLauncher(
    report,
    name: "clipboard-image-detail",
    expectedText: "Photon Image Detail"
  )
  postKey(125)
  postKey(125)
  postKey(126)
  report = try wait("Down/Down/Up moves clipboard selection off the first row") {
    int(launcher($0)["clipboardSelectedIndex"]) > 0
      && !string(launcher($0)["clipboardSelectedTitle"]).isEmpty
      && displayedTitles($0).first != string(launcher($0)["clipboardSelectedTitle"])
  }
  try requireClipboardListHighlight(
    pid: pid,
    report: report,
    screenshot: "clipboard-hotkey-selection"
  )
  try require(setPhotonTextFieldValue(pid: pid, value: "long clipboard detail sentinel"), "filters long text")
  report = try wait("typing filters clipboard and renders full text detail") {
    string(launcher($0)["query"]) == "long clipboard detail sentinel"
      && int(launcher($0)["clipboardResultCount"]) == 1
      && abs(top($0) - anchoredTop) < 0.5
  }
  try captureLauncher(
    report,
    name: "clipboard-text-detail",
    expectedText: "PHOTON-COMPLETE-TEXT-3391"
  )

  try require(setPhotonTextFieldValue(pid: pid, value: pasteSentinel), "filters the unique paste sentinel")
  report = try wait("paste sentinel filter is applied") {
    string(launcher($0)["query"]) == pasteSentinel
      && int(launcher($0)["clipboardResultCount"]) >= 1
  }
  if !string(launcher(report)["clipboardSelectedTitle"]).contains("paste sentinel") {
    postKey(126)
  }
  _ = try wait("unique paste sentinel is selected") {
    string(launcher($0)["clipboardSelectedTitle"]).contains("paste sentinel")
  }
  postKey(36)
  report = try wait("Enter uses the selected clipboard item and dismisses") {
    !bool(launcher($0)["visible"])
  }
  try require(
    NSPasteboard.general.string(forType: .string) == pasteSentinel,
    "Enter copied the selected clipboard item"
  )
  _ = try wait("Photon restores the previously focused paste target") { _ in
    NSWorkspace.shared.frontmostApplication?.processIdentifier == pasteTargetPID
  }
  try require(
    focusPhotonTextField(pid: pasteTargetPID),
    "paste target text field regains keyboard focus"
  )
  RunLoop.current.run(until: Date().addingTimeInterval(0.5))
  _ = try wait("packaged Photon pastes into the previously focused target") { _ in
    fulfillPasteInjectionIfNeeded()
    return (try? String(contentsOf: pasteTargetValueURL, encoding: .utf8)) == pasteSentinel
  }
  try require(
    string(launcher(report)["clipboardNotice"]).isEmpty,
    "trusted paste never reports a missing Accessibility permission"
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
  let compactWidth = double(dictionary(launcher(report)["frame"])["width"])
  try require(confirmPhotonTextField(pid: pid), "Accessibility confirms the selected launcher result")
  report = try wait("launcher Clipboard History Enter expands detail vertically") {
    string(launcher($0)["session"]) == "clipboard"
      && string(launcher($0)["content"]) == "fullHeight"
      && int(launcher($0)["clipboardSelectedIndex"]) >= 0
      && abs(double(launcher($0)["panelWidth"]) - compactWidth) < 0.5
      && abs(double(dictionary(launcher($0)["frame"])["width"]) - compactWidth) < 0.5
  }
  clickSearchField(report)
  report = try wait("launcher-entry clipboard panel is the key-event target") {
    bool(launcher($0)["key"])
  }
  try require(
    focusPhotonTextField(pid: pid),
    "Accessibility focuses launcher-entry clipboard search field"
  )
  let launcherEntryFirstSelection = int(launcher(report)["clipboardSelectedIndex"])
  postKey(125)
  postKey(125)
  postKey(126)
  report = try wait("launcher-entry Down/Down/Up visibly moves selection") {
    int(launcher($0)["clipboardSelectedIndex"]) != launcherEntryFirstSelection
      && int(launcher($0)["clipboardSelectedIndex"]) >= 0
      && !string(launcher($0)["clipboardSelectedTitle"]).isEmpty
      && displayedTitles($0).first != string(launcher($0)["clipboardSelectedTitle"])
  }
  try requireClipboardListHighlight(
    pid: pid,
    report: report,
    screenshot: "clipboard-launcher-selection"
  )

  try sendRuntimeCommand("hideLauncher")
  _ = try wait("clipboard session closes before file-search tests") {
    !bool(launcher($0)["visible"])
  }
  try sendRuntimeCommand("showFiles:")
  report = try wait("native runtime hook opens ungranted Files mode") {
    let value = launcher($0)
    return bool(value["visible"])
      && bool(value["key"])
      && string(value["session"]) == "commands"
      && string(value["mode"]) == "files"
  }
  try require(
    int(dictionary(report["fileAccess"])["grantCount"]) == 0,
    "packaged app starts with no folder grant"
  )
  try sendRuntimeCommand("requestFileAccess:\(fileAccessQuery)")
  report = try wait("controlled folder grant is persisted while Photon remains alive", timeout: 8) {
    int($0["pid"]) == Int(pid)
      && int(dictionary($0["fileAccess"])["grantCount"]) == 1
      && string(dictionary($0["fileAccess"])["status"]) == "granted"
  }
  report = try wait("guided setup restores the pending Files session", timeout: 8) {
    bool(launcher($0)["visible"])
      && string(launcher($0)["mode"]) == "files"
      && string(launcher($0)["query"]) == fileAccessQuery
  }
  report = try wait("guided setup resumes the pending file search", timeout: 12) {
    displayedTitles($0).contains(fileAccessResult)
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
  let launcherBarWidth = double(dictionary(launcher(report)["frame"])["width"])
  let expectedFile = "Ember_Individual_Pitch.pdf"
  clickSearchField(report)
  try require(focusPhotonTextField(pid: pid), "Accessibility focuses mixed-search field")
  try require(setPhotonTextFieldValue(pid: pid, value: "ember"), "Accessibility enters mixed file query")
  report = try wait("mixed launcher promotes into Files split UI with the seeded PDF", timeout: 12) {
    string(launcher($0)["query"]) == "ember"
      && string(launcher($0)["mode"]) == "files"
      && string(launcher($0)["content"]) == "fullHeight"
      && displayedTitles($0).contains(expectedFile)
      && string(launcher($0)["fileSelectedName"]) == expectedFile
      && abs(double(dictionary(launcher($0)["frame"])["width"]) - launcherBarWidth) < 0.5
  }
  try captureLauncher(
    report,
    name: "ember-mixed-search",
    expectedText: expectedFile,
    additionalExpectedText: ["Results", "Metadata", "Name", "Where", "Type"]
  )

  try sendRuntimeCommand("hideLauncher")
  _ = try wait("launcher closes before explicit Files recents check") {
    !bool(launcher($0)["visible"])
  }
  try sendRuntimeCommand("showFiles:")
  report = try wait("empty Files mode shows seeded recents and selects the PDF", timeout: 35) {
    let status = string(launcher($0)["fileStatus"])
    let loaded = status == "recents" || status == "results"
    return string(launcher($0)["mode"]) == "files"
      && string(launcher($0)["query"]).isEmpty
      && string(launcher($0)["fileControllerQuery"]).isEmpty
      && bool(launcher($0)["key"])
      && loaded
      && displayedTitles($0).contains("Ember_Individual_Pitch.pdf")
      && displayedTitles($0).contains("Photon_Recent_Image.png")
      && string(launcher($0)["fileSelectedName"]) == "Ember_Individual_Pitch.pdf"
  }
  try captureLauncher(
    report,
    name: "files-recents-pdf-preview",
    expectedText: "Ember_Individual_Pitch.pdf",
    additionalExpectedText: ["Recent Files", "Metadata", "Name", "Where", "Type"]
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

  let ryanLikePath = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_RYAN_LIKE_FILE"] ?? ""
  if !ryanLikePath.isEmpty {
    try sendRuntimeCommand("hideLauncher")
    _ = try wait("launcher closes before Ryan-like Documents search") {
      !bool(launcher($0)["visible"])
    }
    try sendRuntimeCommand("showFiles:")
    report = try wait("Ryan-like Documents path opens Files mode") {
      string(launcher($0)["mode"]) == "files" && bool(launcher($0)["visible"])
    }
    try require(setPhotonTextFieldValue(pid: pid, value: "ember"), "Accessibility searches Ryan-like ember path")
    report = try wait("Ryan-like Documents tree finds Ember PDF without mdimport", timeout: 15) {
      string(launcher($0)["query"]) == "ember"
        && displayedTitles($0).contains(expectedFile)
        && abs(double(dictionary(launcher($0)["frame"])["width"]) - launcherBarWidth) < 0.5
    }
    try captureLauncher(
      report,
      name: "ember-ryan-documents-path",
      expectedText: expectedFile
    )
  }

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
