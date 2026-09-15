import Foundation

/// Dependency-free persistence: a Codable `index.json` plus one blob file per
/// large payload under the given directory (by default
/// `~/Library/Application Support/Photon/Clipboard/`).
///
/// ```
/// Clipboard/
///   index.json          [ClipboardItem]
///   blobs/<uuid>.txt    full text when it exceeds the inline limit
///   blobs/<uuid>.rtf    rich text captured next to plain text
///   blobs/<uuid>.png    image rendition
/// ```
///
/// Every mutation returns a `Snapshot` so callers can publish without a second hop.
public actor ClipboardStore {
  public struct Snapshot: Equatable, Sendable {
    public let items: [ClipboardItem]
    public let storageBytes: Int64

    public init(items: [ClipboardItem], storageBytes: Int64) {
      self.items = items
      self.storageBytes = storageBytes
    }
  }

  public struct InsertResult: Equatable, Sendable {
    public let outcome: ClipboardHistory.InsertOutcome
    public let snapshot: Snapshot
  }

  /// Full payload of an item, read back from blobs where needed.
  public struct Payload: Equatable, Sendable {
    public var text: String?
    public var richText: Data?
    public var imagePNG: Data?
    public var filePaths: [String]
  }

  public static func defaultDirectory() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return support
      .appendingPathComponent("Photon", isDirectory: true)
      .appendingPathComponent("Clipboard", isDirectory: true)
  }

  public let directory: URL
  private let indexURL: URL
  private let blobsURL: URL
  private var history = ClipboardHistory()
  private var indexBytes: Int64 = 0
  private var isLoaded = false

  public init(directory: URL) {
    self.directory = directory
    indexURL = directory.appendingPathComponent("index.json")
    blobsURL = directory.appendingPathComponent("blobs", isDirectory: true)
  }

  // MARK: Reading

  /// Loads the index once. Safe to call repeatedly.
  @discardableResult
  public func load() -> Snapshot {
    if !isLoaded {
      isLoaded = true
      if let data = try? Data(contentsOf: indexURL) {
        indexBytes = Int64(data.count)
        if let items = try? Self.makeDecoder().decode([ClipboardItem].self, from: data) {
          history = ClipboardHistory(items: items)
        }
      }
    }
    return snapshot()
  }

  public func snapshot() -> Snapshot {
    let blobBytes = history.items.reduce(0) { $0 + Int64($1.byteCount) }
    return Snapshot(items: history.items, storageBytes: blobBytes + indexBytes)
  }

  public var items: [ClipboardItem] {
    history.items
  }

  public func item(id: UUID) -> ClipboardItem? {
    history.item(id: id)
  }

  public func fullText(for item: ClipboardItem) -> String? {
    guard item.isTextTruncated else {
      return item.text
    }
    let url = blobURL(id: item.id, extension: "txt")
    if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
      return text
    }
    return item.text
  }

  public func richText(for item: ClipboardItem) -> Data? {
    guard item.hasRichText else {
      return nil
    }
    return try? Data(contentsOf: blobURL(id: item.id, extension: "rtf"))
  }

  public func imageData(for item: ClipboardItem) -> Data? {
    guard item.hasImage else {
      return nil
    }
    return try? Data(contentsOf: blobURL(id: item.id, extension: "png"))
  }

  public func payload(for item: ClipboardItem) -> Payload {
    Payload(
      text: fullText(for: item),
      richText: richText(for: item),
      imagePNG: imageData(for: item),
      filePaths: item.filePaths
    )
  }

  // MARK: Writing

  /// Stores a capture, collapsing duplicates, then applies retention and the
  /// item limit. Returns `nil` when the capture holds nothing storable.
  public func insert(_ capture: ClipboardCapture, settings: ClipboardSettings) -> InsertResult? {
    load()
    guard let hash = capture.contentHash else {
      return nil
    }
    if history.contains(contentHash: hash), let probe = capture.makeItem() {
      let outcome = history.insert(probe)
      saveIndex()
      return InsertResult(outcome: outcome, snapshot: snapshot())
    }
    guard let item = capture.makeItem() else {
      return nil
    }
    writeBlobs(for: item, capture: capture)
    let outcome = history.insert(item)
    let removed = history.prune(retention: settings.retention, maxItems: settings.maxItems, now: capture.date)
    removeBlobs(for: removed)
    saveIndex()
    return InsertResult(outcome: outcome, snapshot: snapshot())
  }

  /// Marks an item as just used (moves it to the top).
  public func touch(id: UUID, at date: Date = Date()) -> Snapshot {
    load()
    if history.touch(id: id, at: date) {
      saveIndex()
    }
    return snapshot()
  }

  public func setPinned(_ pinned: Bool, id: UUID) -> Snapshot {
    load()
    if history.setPinned(pinned, id: id) {
      saveIndex()
    }
    return snapshot()
  }

  public func togglePin(id: UUID) -> Snapshot {
    load()
    if history.togglePin(id: id) != nil {
      saveIndex()
    }
    return snapshot()
  }

  public func remove(id: UUID) -> Snapshot {
    load()
    if let removed = history.remove(id: id) {
      removeBlobs(for: [removed])
      saveIndex()
    }
    return snapshot()
  }

  public func removeAll() -> Snapshot {
    load()
    let removed = history.removeAll()
    removeBlobs(for: removed)
    try? FileManager.default.removeItem(at: blobsURL)
    saveIndex()
    return snapshot()
  }

  public func prune(settings: ClipboardSettings, now: Date = Date()) -> Snapshot {
    load()
    let removed = history.prune(retention: settings.retention, maxItems: settings.maxItems, now: now)
    if !removed.isEmpty {
      removeBlobs(for: removed)
      saveIndex()
    }
    return snapshot()
  }

  // MARK: Files

  public func blobURL(id: UUID, extension ext: String) -> URL {
    blobsURL.appendingPathComponent("\(id.uuidString).\(ext)")
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }

  private func writeBlobs(for item: ClipboardItem, capture: ClipboardCapture) {
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: blobsURL, withIntermediateDirectories: true)
      if item.isTextTruncated, let text = capture.text {
        try Data(text.utf8).write(to: blobURL(id: item.id, extension: "txt"), options: .atomic)
      }
      if let richText = capture.richText {
        try richText.write(to: blobURL(id: item.id, extension: "rtf"), options: .atomic)
      }
      if let png = capture.imagePNG {
        try png.write(to: blobURL(id: item.id, extension: "png"), options: .atomic)
      }
    } catch {
      NSLog("Photon: could not write clipboard blob: \(error)")
    }
  }

  private func removeBlobs(for items: [ClipboardItem]) {
    let fm = FileManager.default
    for item in items {
      for ext in ["txt", "rtf", "png"] {
        let url = blobURL(id: item.id, extension: ext)
        if fm.fileExists(atPath: url.path) {
          try? fm.removeItem(at: url)
        }
      }
    }
  }

  private func saveIndex() {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try Self.makeEncoder().encode(history.items)
      try data.write(to: indexURL, options: .atomic)
      indexBytes = Int64(data.count)
    } catch {
      NSLog("Photon: could not save clipboard index: \(error)")
    }
  }
}
