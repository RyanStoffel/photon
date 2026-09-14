#if canImport(AppKit)
import AppKit
import Foundation

/// Polls `NSPasteboard.general.changeCount` on a utility-QoS queue and turns
/// new contents into `ClipboardCapture`s.
///
/// Skips concealed and transient items (the convention password managers use),
/// anything copied while an excluded app is frontmost, and Photon's own writes.
public final class PasteboardMonitor: @unchecked Sendable {
  public static var concealedType: NSPasteboard.PasteboardType {
    NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
  }

  public static var transientType: NSPasteboard.PasteboardType {
    NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
  }

  private let pasteboard = NSPasteboard.general
  private let queue = DispatchQueue(label: "com.ryanstoffel.photon.clipboard.monitor", qos: .utility)
  private let interval: TimeInterval
  private let lock = NSLock()
  private var timer: DispatchSourceTimer?
  private var lastChangeCount: Int
  private var excludedBundleIDs: [String] = []
  private var captureHandler: (@Sendable (ClipboardCapture) -> Void)?

  public init(interval: TimeInterval = 0.3) {
    self.interval = interval
    lastChangeCount = NSPasteboard.general.changeCount
  }

  deinit {
    timer?.cancel()
  }

  /// Invoked on the monitor queue for every new, storable pasteboard change.
  public var onCapture: (@Sendable (ClipboardCapture) -> Void)? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return captureHandler
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      captureHandler = newValue
    }
  }

  public func setExcludedBundleIDs(_ ids: [String]) {
    lock.lock()
    defer { lock.unlock() }
    excludedBundleIDs = ids
  }

  public var isRunning: Bool {
    lock.lock()
    defer { lock.unlock() }
    return timer != nil
  }

  /// Starts polling. Whatever is on the pasteboard right now is not recorded.
  public func start() {
    lock.lock()
    defer { lock.unlock() }
    guard timer == nil else {
      return
    }
    lastChangeCount = pasteboard.changeCount
    let source = DispatchSource.makeTimerSource(queue: queue)
    source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
    source.setEventHandler { [weak self] in
      self?.poll()
    }
    source.resume()
    timer = source
  }

  public func stop() {
    lock.lock()
    defer { lock.unlock() }
    timer?.cancel()
    timer = nil
  }

  /// Call right after Photon writes to the pasteboard so the write is not
  /// recorded as a new capture.
  public func acknowledgeOwnWrite(changeCount: Int) {
    lock.lock()
    defer { lock.unlock() }
    lastChangeCount = changeCount
  }

  private func poll() {
    let count = pasteboard.changeCount
    lock.lock()
    let changed = count != lastChangeCount
    lastChangeCount = count
    let excluded = excludedBundleIDs
    let handler = captureHandler
    lock.unlock()
    guard changed, let handler else {
      return
    }
    guard let capture = readCapture(excludedBundleIDs: excluded) else {
      return
    }
    handler(capture)
  }

  private func readCapture(excludedBundleIDs: [String]) -> ClipboardCapture? {
    let types = pasteboard.types ?? []
    if types.contains(Self.concealedType) || types.contains(Self.transientType) {
      return nil
    }

    let frontmost = NSWorkspace.shared.frontmostApplication
    let bundleID = frontmost?.bundleIdentifier
    if let bundleID, excludedBundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
      return nil
    }

    var capture = ClipboardCapture(
      sourceBundleID: bundleID,
      sourceAppName: frontmost?.localizedName,
      date: Date()
    )

    if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
      capture.filePaths = objects.compactMap { ($0 as? URL)?.path }
    }

    if let string = pasteboard.string(forType: .string), !string.isEmpty {
      capture.text = string
      if let rtf = pasteboard.data(forType: .rtf), !rtf.isEmpty {
        capture.richText = rtf
      }
    }

    if capture.filePaths.isEmpty {
      readImage(types: types, into: &capture)
    }

    return capture.primaryKind == nil ? nil : capture
  }

  private func readImage(types: [NSPasteboard.PasteboardType], into capture: inout ClipboardCapture) {
    var png: Data?
    if types.contains(.png), let data = pasteboard.data(forType: .png), !data.isEmpty {
      png = data
    } else if types.contains(.tiff), let tiff = pasteboard.data(forType: .tiff) {
      png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
    guard let png, png.count <= ClipboardCapture.maxImageBytes, let rep = NSBitmapImageRep(data: png) else {
      return
    }
    capture.imagePNG = png
    capture.imageWidth = rep.pixelsWide
    capture.imageHeight = rep.pixelsHigh
  }
}
#endif
