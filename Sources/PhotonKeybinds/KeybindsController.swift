import AppKit
import Foundation

/// What a bound shortcut does.
public enum BindingTarget: Hashable, Sendable {
  case window(WindowAction)
  case app(bundleIdentifier: String)
}

/// Owns the Hyper key engine, the HID remap, Carbon registrations, and window management.
/// `apply(_:)` is idempotent: the settings tab calls it after every change.
@MainActor
public final class KeybindsController: ObservableObject {
  public enum HyperStatus: Equatable, Sendable {
    case disabled
    case needsAccessibility
    case active(HyperKeySource)
    case failed(String)
  }

  private static let permissionPollInterval: TimeInterval = 2
  private static let accessibilityGuidanceKey = "hasShownAccessibilityGuidance"

  @Published public private(set) var hyperStatus: HyperStatus = .disabled
  @Published public private(set) var accessibilityGranted = false
  @Published public private(set) var inputMonitoringGranted = false
  @Published public private(set) var lastError: String?
  /// Plain shortcuts macOS refused to register, usually because another app owns them.
  @Published public private(set) var registrationFailures: [KeyShortcut: String] = [:]

  /// Set by shortcut recorders. While recording, bound shortcuts pass through so they can be re-recorded.
  public var isRecording = false {
    didSet {
      if isRecording != oldValue {
        engine.setSuspended(isRecording)
        rebuildBindings()
      }
    }
  }

  private let hotkeys: any GlobalHotkeyRegistrar
  private let engine = HyperKeyEngine()
  private let windows = WindowManager()
  private var configuration = KeybindsConfiguration.default
  private var carbonTokens: [GlobalHotkeyToken] = []
  private var hyperBindings: [UInt16: BindingTarget] = [:]
  private var installedSource: HyperKeySource?
  private var didCleanStaleMapping = false
  private var permissionTimer: Timer?

  public init(hotkeys: any GlobalHotkeyRegistrar) {
    self.hotkeys = hotkeys
    engine.onHyperShortcut = { [weak self] keyCode in
      Task { @MainActor in
        self?.fire(hyperKeyCode: keyCode)
      }
    }
    refreshPermissions()
  }

  public var currentConfiguration: KeybindsConfiguration {
    configuration
  }

  public func apply(_ configuration: KeybindsConfiguration) {
    self.configuration = configuration.normalized()
    rebuildBindings()
    applyHyperKey()
    updatePermissionPolling()
  }

  /// Restores the keyboard: removes the HID remap, stops the tap, unregisters shortcuts.
  public func stop() {
    permissionTimer?.invalidate()
    permissionTimer = nil
    unregisterCarbon()
    engine.stop()
    removeRemap()
    hyperStatus = .disabled
  }

  public func perform(_ action: WindowAction) throws {
    try windows.perform(action)
  }

  public func refreshPermissions() {
    accessibilityGranted = AccessibilityPermission.isTrusted
    inputMonitoringGranted = AccessibilityPermission.hasInputMonitoring
  }

  /// Shows the macOS prompt (which also lists Photon under Accessibility) and opens System Settings.
  public func requestAccessibility() {
    AccessibilityPermission.requestTrust()
    AccessibilityPermission.openAccessibilitySettings()
    refreshPermissions()
    applyHyperKey()
    updatePermissionPolling()
  }

  /// Emergency exit: puts the physical key back even if state got out of sync, then re-applies settings.
  public func resetKeyMapping() {
    engine.stop()
    installedSource = nil
    didCleanStaleMapping = false
    removeRemap()
    applyHyperKey()
  }

  /// One-time first-run alert when the Hyper key is on but Accessibility is missing.
  public func adviseAccessibilityIfNeeded() {
    let defaults = UserDefaults.standard
    guard configuration.hyperKey.enabled, !accessibilityGranted,
          !defaults.bool(forKey: Self.accessibilityGuidanceKey)
    else {
      return
    }
    defaults.set(true, forKey: Self.accessibilityGuidanceKey)

    let alert = NSAlert()
    alert.messageText = "Photon needs Accessibility access"
    alert.informativeText = """
    The Hyper key and window management work through macOS Accessibility.

    1. Open System Settings > Privacy & Security > Accessibility
    2. Turn on Photon

    Until then your keyboard is untouched. You can change this later in Settings > Keybinds.
    """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")
    if alert.runModal() == .alertFirstButtonReturn {
      requestAccessibility()
    }
  }

  // MARK: - Dispatch

  private func fire(hyperKeyCode: UInt16) {
    guard let target = hyperBindings[hyperKeyCode] else {
      return
    }
    run(target)
  }

  private func run(_ target: BindingTarget) {
    switch target {
    case let .window(action):
      do {
        try windows.perform(action)
        lastError = nil
      } catch {
        lastError = error.localizedDescription
      }
    case let .app(bundleIdentifier):
      Task { @MainActor [weak self] in
        do {
          try await AppActivator.toggle(bundleIdentifier: bundleIdentifier)
          self?.lastError = nil
        } catch {
          self?.lastError = error.localizedDescription
        }
      }
    }
  }

  // MARK: - Bindings

  private func rebuildBindings() {
    unregisterCarbon()
    hyperBindings = [:]
    registrationFailures = [:]

    var entries: [(shortcut: KeyShortcut, target: BindingTarget)] = []
    for hotkey in configuration.appHotkeys {
      if let shortcut = hotkey.shortcut {
        entries.append((shortcut, .app(bundleIdentifier: hotkey.bundleIdentifier)))
      }
    }
    for binding in configuration.windowBindings {
      if let shortcut = binding.shortcut {
        entries.append((shortcut, .window(binding.action)))
      }
    }

    // First owner wins when two bindings share a shortcut; the settings tab flags the conflict.
    var seen = Set<KeyShortcut>()
    for entry in entries where entry.shortcut.isBindable {
      guard seen.insert(entry.shortcut).inserted else {
        continue
      }
      if entry.shortcut.isHyper {
        hyperBindings[entry.shortcut.keyCode] = entry.target
      }
      if !isRecording {
        registerCarbon(entry.shortcut, target: entry.target)
      }
    }
    engine.update(engineConfiguration())
  }

  /// Every shortcut goes through Carbon so it also works when the four modifiers are held by hand.
  /// Hyper combinations additionally fire from the event tap, so a Carbon refusal is only a problem
  /// for plain combinations.
  private func registerCarbon(_ shortcut: KeyShortcut, target: BindingTarget) {
    do {
      let token = try hotkeys.register(shortcut) { [weak self] in
        self?.run(target)
      }
      carbonTokens.append(token)
    } catch {
      if !shortcut.isHyper {
        registrationFailures[shortcut] = "\(shortcut.displayString) is already taken by another app."
      }
    }
  }

  private func unregisterCarbon() {
    for token in carbonTokens {
      hotkeys.unregister(token)
    }
    carbonTokens.removeAll()
  }

  private func engineConfiguration() -> HyperKeyEngine.Configuration {
    HyperKeyEngine.Configuration(
      hyperKeyCode: HyperKeySource.destinationKeyCode,
      tapBehavior: configuration.hyperKey.tapBehavior,
      boundKeyCodes: Set(hyperBindings.keys)
    )
  }

  // MARK: - Hyper key

  private func applyHyperKey() {
    refreshPermissions()
    let settings = configuration.hyperKey
    guard settings.enabled else {
      engine.stop()
      removeRemap()
      hyperStatus = .disabled
      return
    }
    guard accessibilityGranted else {
      engine.stop()
      removeRemap()
      hyperStatus = .needsAccessibility
      return
    }

    engine.update(engineConfiguration())
    if !engine.isRunning {
      do {
        try engine.start()
      } catch {
        removeRemap()
        hyperStatus = .failed(error.localizedDescription)
        return
      }
    }

    if let usage = settings.source.hidUsage {
      if installedSource != settings.source {
        do {
          try HIDKeyRemapper.install(source: usage)
          installedSource = settings.source
          didCleanStaleMapping = true
        } catch {
          engine.stop()
          hyperStatus = .failed(error.localizedDescription)
          return
        }
      }
    } else {
      removeRemap()
    }
    hyperStatus = .active(settings.source)
  }

  /// Removes Photon's HID mapping. Also runs once at startup to clean up after a crash.
  private func removeRemap() {
    guard installedSource != nil || !didCleanStaleMapping else {
      return
    }
    didCleanStaleMapping = true
    do {
      try HIDKeyRemapper.removeAll()
      installedSource = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  // MARK: - Permission polling

  private func updatePermissionPolling() {
    let shouldPoll = configuration.hyperKey.enabled
    if shouldPoll, permissionTimer == nil {
      permissionTimer = Timer.scheduledTimer(
        withTimeInterval: Self.permissionPollInterval,
        repeats: true
      ) { [weak self] _ in
        Task { @MainActor in
          self?.pollPermissions()
        }
      }
    } else if !shouldPoll {
      permissionTimer?.invalidate()
      permissionTimer = nil
    }
  }

  private func pollPermissions() {
    let wasGranted = accessibilityGranted
    refreshPermissions()
    if wasGranted != accessibilityGranted {
      applyHyperKey()
    }
  }
}
