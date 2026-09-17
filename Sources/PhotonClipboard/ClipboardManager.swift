#if canImport(AppKit)
import AppKit
import Foundation

/// Owns the store, the pasteboard monitor, and paste-back. Everything the UI
/// and `AppRuntime` touch goes through here on the main actor.
@MainActor
public final class ClipboardManager: ObservableObject {
  public enum PasteOutcome: Equatable, Sendable {
    /// Written to the pasteboard and Cmd+V scheduled.
    case pasted
    /// Written to the pasteboard only (setting or explicit copy).
    case copied
    /// Written to the pasteboard; pasting needs Accessibility access.
    case accessibilityRequired
    /// Written to the pasteboard, but Photon could not create the paste events.
    case eventInjectionFailed
  }

  @Published public private(set) var items: [ClipboardItem] = []
  @Published public private(set) var storageBytes: Int64 = 0
  @Published public private(set) var isAccessibilityTrusted: Bool

  public var settings: ClipboardSettings {
    didSet {
      if settings != oldValue {
        applySettings()
      }
    }
  }

  private let store: ClipboardStore
  private let monitor: PasteboardMonitor
  private let imageCache = NSCache<NSUUID, NSImage>()
  private let accessibilityTrust: @MainActor () -> Bool
  private let pasteInjector: @MainActor () -> ClipboardPaster.PasteInjectionResult
  private var pruneTimer: Timer?
  private var isStarted = false

  /// Delay between hiding the panel and sending Cmd+V, so key focus is back in the target app.
  public var pasteDelay: Duration = .milliseconds(300)
  /// Hides the launcher and restores the app that owned focus before Photon opened.
  public var onPrepareForPaste: (@MainActor () -> Void)?
  /// Reopens clipboard history when trusted event creation unexpectedly fails.
  public var onPasteFailure: (@MainActor () -> Void)?

  public init(
    settings: ClipboardSettings,
    directory: URL = ClipboardStore.defaultDirectory(),
    accessibilityTrust: @escaping @MainActor () -> Bool = { ClipboardPaster.isAccessibilityTrusted },
    pasteInjector: @escaping @MainActor () -> ClipboardPaster.PasteInjectionResult = {
      ClipboardPaster.sendPasteKeystroke()
    }
  ) {
    self.settings = settings
    self.accessibilityTrust = accessibilityTrust
    self.pasteInjector = pasteInjector
    isAccessibilityTrusted = accessibilityTrust()
    store = ClipboardStore(directory: directory)
    monitor = PasteboardMonitor()
    imageCache.countLimit = 12
    monitor.setExcludedBundleIDs(settings.excludedBundleIDs)
    monitor.onCapture = { [weak self] capture in
      Task { @MainActor [weak self] in
        await self?.ingest(capture)
      }
    }
  }

  // MARK: Lifecycle

  public func start() {
    guard !isStarted else {
      return
    }
    isStarted = true
    Task {
      let snapshot = await store.load()
      apply(snapshot)
      await prune()
    }
    applySettings()
    let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.prune()
      }
    }
    timer.tolerance = 30
    RunLoop.main.add(timer, forMode: .common)
    pruneTimer = timer
  }

  public func stop() {
    monitor.stop()
    pruneTimer?.invalidate()
    pruneTimer = nil
    isStarted = false
  }

  public var isEnabled: Bool {
    settings.isEnabled
  }

  public func refreshAccessibility() {
    isAccessibilityTrusted = accessibilityTrust()
  }

  public func requestAccessibility() {
    ClipboardPaster.requestAccessibility()
    refreshAccessibility()
  }

  public func openAccessibilitySettings() {
    ClipboardPaster.openAccessibilitySettings()
  }

  // MARK: Items

  public func item(id: UUID) -> ClipboardItem? {
    items.first { $0.id == id }
  }

  public func togglePin(id: UUID) {
    Task {
      await apply(store.togglePin(id: id))
    }
  }

  public func delete(id: UUID) {
    imageCache.removeObject(forKey: id as NSUUID)
    Task {
      await apply(store.remove(id: id))
    }
  }

  public func clearAll() {
    imageCache.removeAllObjects()
    Task {
      await apply(store.removeAll())
    }
  }

  public func prune() async {
    await apply(store.prune(settings: settings))
  }

  public func fullText(for item: ClipboardItem) async -> String? {
    await store.fullText(for: item)
  }

  public func image(for item: ClipboardItem) async -> NSImage? {
    guard item.hasImage else {
      return nil
    }
    let key = item.id as NSUUID
    if let cached = imageCache.object(forKey: key) {
      return cached
    }
    guard let data = await store.imageData(for: item), let image = NSImage(data: data) else {
      return nil
    }
    imageCache.setObject(image, forKey: key)
    return image
  }

  // MARK: Paste back

  /// Writes the item to the pasteboard without sending a keystroke.
  public func copy(_ item: ClipboardItem) async {
    await writeToPasteboard(item)
  }

  /// Applies the configured paste behaviour. The target app is restored before
  /// Cmd+V is posted, and the current AX trust state is checked at action time.
  public func paste(_ item: ClipboardItem) async -> PasteOutcome {
    await writeToPasteboard(item)
    guard settings.pasteBehavior == .paste else {
      return .copied
    }
    refreshAccessibility()
    guard isAccessibilityTrusted else {
      return .accessibilityRequired
    }
    onPrepareForPaste?()
    let delay = pasteDelay
    try? await Task.sleep(for: delay)
    switch pasteInjector() {
    case .posted:
      return .pasted
    case .accessibilityRequired:
      refreshAccessibility()
      onPasteFailure?()
      return .accessibilityRequired
    case .eventCreationFailed:
      onPasteFailure?()
      return .eventInjectionFailed
    }
  }

  private func writeToPasteboard(_ item: ClipboardItem) async {
    let payload = await store.payload(for: item)
    let changeCount = ClipboardPaster.write(item, payload: payload)
    monitor.acknowledgeOwnWrite(changeCount: changeCount)
    await apply(store.touch(id: item.id))
  }

  // MARK: Internals

  private func ingest(_ capture: ClipboardCapture) async {
    guard settings.isEnabled else {
      return
    }
    if let result = await store.insert(capture, settings: settings) {
      apply(result.snapshot)
    }
  }

  private func apply(_ snapshot: ClipboardStore.Snapshot) {
    if items != snapshot.items {
      items = snapshot.items
    }
    storageBytes = snapshot.storageBytes
  }

  private func applySettings() {
    monitor.setExcludedBundleIDs(settings.excludedBundleIDs)
    if settings.isEnabled, isStarted {
      monitor.start()
    } else {
      monitor.stop()
    }
    if isStarted {
      Task {
        await prune()
      }
    }
  }
}
#endif
