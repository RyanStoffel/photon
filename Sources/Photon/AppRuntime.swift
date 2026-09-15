import AppKit
import Carbon
import PhotonApps
import PhotonCalculator
import PhotonClipboard
import PhotonCore
import PhotonFiles
import PhotonKeybinds
import PhotonNotes
import SwiftUI

/// Process-wide wiring. Phase 2 features register here with a single line.
@MainActor
final class AppRuntime: ObservableObject {
  let settings: SettingsStore
  let registry = CommandRegistry()
  let launcher: LauncherPanelController
  let clipboard: ClipboardManager
  let notes: NotesIntegration
  let keybinds: KeybindsController
  private let hotkey = HotkeyManager.shared
  private let frecencyURL: URL
  var fileSearch: FileSearchIntegration?
  private var appearanceObserver: NSObjectProtocol?
  private var settingsWindowController: NSWindowController?

  init() {
    let defaults = Self.userDefaultsForLaunch()
    let settings = SettingsStore(defaults: defaults)
    self.settings = settings
    let dir = Self.applicationSupportDirectory()
    frecencyURL = dir.appendingPathComponent("frecency.json")
    launcher = LauncherPanelController(settings: settings, registry: registry, frecencyURL: frecencyURL)
    let clipboardDirectory = dir.appendingPathComponent("Clipboard", isDirectory: true)
    if Self.usesNativeParityPasteTrustOverride {
      clipboard = ClipboardManager(
        settings: settings.clipboardSettings,
        directory: clipboardDirectory,
        accessibilityTrust: { true },
        pasteInjector: {
          Self.nativeParityPasteInjection()
        }
      )
    } else {
      clipboard = ClipboardManager(
        settings: settings.clipboardSettings,
        directory: clipboardDirectory
      )
    }
    launcher.attachClipboard(clipboard)
    let notesDirectory = dir.appendingPathComponent("Notes", isDirectory: true)
    notes = NotesIntegration(settings: settings, notesDirectory: notesDirectory)
    keybinds = KeybindsController(hotkeys: hotkey)
    registerProviders()
  }

  func start() {
    if NativeParityReporter.isRequested {
      // Avoid the runner's Spotlight reservation while exercising configurable
      // global launcher registration. Clipboard remains the shipping Cmd+Shift+V.
      settings.hotkey = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(cmdKey | optionKey | controlKey)
      )
      settings.clipboardPasteBehavior = Self.usesNativeParityPasteTrustOverride ? .paste : .copy
      clipboard.settings = settings.clipboardSettings
      settings.appearance = .system
    }
    observeSystemAppearance()
    applyAppearance()
    settings.onAppearanceChange = { [weak self] in
      self?.applyAppearance()
    }
    launcher.preload()
    if UIScenario.current == nil {
      clipboard.start()
    }
    Task {
      await registry.reloadAll()
      launcher.warmIcons()
    }
    if UIScenario.current == nil {
      applyHotkey()
      applyClipboardHotkey()
      settings.onHotkeyChange = { [weak self] in
        self?.applyHotkey()
      }
      settings.onClipboardChange = { [weak self] in
        self?.applyClipboardSettings()
      }
      notes.start()
      keybinds.apply(settings.keybinds)
      settings.onKeybindsChange = { [weak self] in
        guard let self else {
          return
        }
        keybinds.apply(settings.keybinds)
      }
      SpotlightConflict.adviseIfNeeded(current: settings.hotkey)
      keybinds.adviseAccessibilityIfNeeded()
    } else {
      notes.startWithoutOpenOnLaunch()
    }
  }

  private static func applicationSupportDirectory() -> URL {
    if let root = isolatedDataRoot {
      return root.appendingPathComponent("Photon", isDirectory: true)
    }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return support.appendingPathComponent("Photon", isDirectory: true)
  }

  private static func userDefaultsForLaunch() -> UserDefaults {
    if let root = isolatedDataRoot {
      let suite = "photon-ui-scenario-" + root.path.replacingOccurrences(of: "/", with: "-")
      return UserDefaults(suiteName: suite) ?? .standard
    }
    return .standard
  }

  private static var isolatedDataRoot: URL? {
    let environment = ProcessInfo.processInfo.environment
    guard UIScenario.current != nil || NativeParityReporter.isRequested,
          let path = environment["PHOTON_ISOLATED_DATA_ROOT"],
          !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  private static var usesNativeParityPasteTrustOverride: Bool {
    NativeParityReporter.isRequested
      && ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE"] == "1"
  }

  private static func nativeParityPasteInjection() -> ClipboardPaster.PasteInjectionResult {
    guard let path = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE_INJECTION_PATH"] else {
      return ClipboardPaster.sendPasteKeystroke(requireAccessibilityTrust: false)
    }
    do {
      try "paste".write(toFile: path, atomically: true, encoding: .utf8)
      return .posted
    } catch {
      return .eventCreationFailed
    }
  }

  func stop() {
    keybinds.stop()
    notes.stop()
    hotkey.unregisterAll()
    clipboard.stop()
    persistFrecency()
    settings.onHotkeyChange = nil
    settings.onClipboardChange = nil
    settings.onKeybindsChange = nil
    settings.onAppearanceChange = nil
    if let appearanceObserver {
      DistributedNotificationCenter.default().removeObserver(appearanceObserver)
      self.appearanceObserver = nil
    }
  }

  /// Settings > Appearance applies to every Photon window, including the launcher panel.
  private func applyAppearance() {
    if settings.appearance == .system {
      let followsDarkSystem = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
      NSApp.appearance = NSAppearance(named: followsDarkSystem ? .darkAqua : .aqua)
    } else {
      NSApp.appearance = settings.appearance.nsAppearance
    }
  }

  private func observeSystemAppearance() {
    appearanceObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.applyAppearance()
      }
    }
  }

  func toggleLauncher() {
    launcher.toggle()
  }

  func showClipboardHistory() {
    launcher.showClipboard()
  }

  func toggleNotes() {
    notes.controller.toggle()
  }

  func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    if settingsWindowController == nil {
      let host = NSHostingController(
        rootView: SettingsRootView()
          .environmentObject(settings)
          .environmentObject(clipboard)
          .environmentObject(keybinds)
          .frame(minWidth: 560, minHeight: 400)
      )
      let window = NSWindow(contentViewController: host)
      window.title = "Settings"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.setContentSize(NSSize(width: 640, height: 480))
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindowController = NSWindowController(window: window)
    }
    settingsWindowController?.showWindow(nil)
    settingsWindowController?.window?.makeKeyAndOrderFront(nil)
  }

  /// Phase 2: add `registry.register(YourProvider())` here. Do not edit PhotonCore.
  private func registerProviders() {
    registry.register(AppsProvider())
    let clipboardProvider = ClipboardProvider()
    clipboardProvider.openHistory = { [weak self] in
      Task { @MainActor [weak self] in
        self?.showClipboardHistory()
      }
    }
    registry.register(clipboardProvider)
    registry.register(notes.provider)
    fileSearch = FileSearchIntegration(settings: settings, registry: registry, launcher: launcher)
    registry.register(KeybindsProvider(controller: keybinds))
    registry.register(CalculatorProvider())
  }

  private func applyHotkey() {
    hotkey.onPressed = { [weak self] in
      self?.toggleLauncher()
    }
    do {
      try hotkey.register(combo: settings.hotkey)
    } catch {
      NSLog("Photon: failed to register hotkey: \(error)")
    }
  }

  private func applyClipboardSettings() {
    clipboard.settings = settings.clipboardSettings
    applyClipboardHotkey()
  }

  private func applyClipboardHotkey() {
    guard settings.clipboardEnabled, settings.clipboardHotkeyEnabled else {
      hotkey.unregister(id: HotkeyManager.HotkeyID.clipboard)
      return
    }
    do {
      try hotkey.register(combo: settings.clipboardHotkey, id: HotkeyManager.HotkeyID.clipboard) { [weak self] in
        self?.showClipboardHistory()
      }
    } catch {
      NSLog("Photon: failed to register clipboard hotkey: \(error)")
    }
  }

  private func persistFrecency() {
    do {
      try launcher.currentFrecency().save(to: frecencyURL)
    } catch {
      NSLog("Photon: could not save frecency: \(error)")
    }
  }
}
