import Foundation
import UniformTypeIdentifiers

/// Runs one `NSMetadataQuery` through its gathering phase and hands back plain
/// `FileResult` values. Start and cancel on the main actor; Spotlight posts the
/// finish notification on a private queue, so result extraction never touches
/// the main thread. The query is stopped as soon as gathering completes: the
/// launcher wants a snapshot, not live updates.
final class SpotlightQueryRunner: NSObject, @unchecked Sendable {
  struct Request: Sendable {
    /// Raw Spotlight query syntax, see `SpotlightQueryBuilder`.
    let queryString: String
    /// `NSMetadataQuery*Scope` constants or absolute folder paths.
    let scopes: [String]
    /// Upper bound on how many Spotlight hits are converted and ranked.
    let scanLimit: Int
  }

  struct Outcome: Sendable {
    var files: [FileResult] = []
    var spotlightAvailable = true
    var cancelled = false
  }

  private let lock = NSLock()
  private let queue: OperationQueue
  private var query: NSMetadataQuery?
  private var observer: (any NSObjectProtocol)?
  private var completion: (@Sendable (Outcome) -> Void)?
  private var scanLimit = 0

  override init() {
    queue = OperationQueue()
    queue.name = "com.ryanstoffel.photon.files.spotlight"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInitiated
    super.init()
  }

  @MainActor
  func start(_ request: Request, completion: @escaping @Sendable (Outcome) -> Void) {
    guard let predicate = NSPredicate(fromMetadataQueryString: request.queryString) else {
      NSLog("Photon: Spotlight rejected query %@", request.queryString)
      completion(Outcome())
      return
    }
    let query = NSMetadataQuery()
    query.predicate = predicate
    query.searchScopes = request.scopes.map(Self.scope)
    query.sortDescriptors = [
      NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false),
      NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
    ]
    query.operationQueue = queue

    lock.lock()
    self.query = query
    self.completion = completion
    scanLimit = request.scanLimit
    observer = NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidFinishGathering,
      object: query,
      queue: queue
    ) { [weak self] _ in
      self?.gatheringFinished()
    }
    lock.unlock()

    if !query.start() {
      finish(Outcome(spotlightAvailable: false))
    }
  }

  @MainActor
  func cancel() {
    finish(Outcome(cancelled: true))
  }

  /// Runs on `queue`.
  private func gatheringFinished() {
    lock.lock()
    let query = query
    let limit = scanLimit
    lock.unlock()
    guard let query else {
      return
    }
    query.disableUpdates()
    let count = min(query.resultCount, limit)
    var files: [FileResult] = []
    files.reserveCapacity(count)
    for index in 0 ..< count {
      if let item = query.result(at: index) as? NSMetadataItem, let file = FileResultMapper.file(from: item) {
        files.append(file)
      }
    }
    finish(Outcome(files: files))
  }

  private func finish(_ outcome: Outcome) {
    lock.lock()
    let completion = completion
    let query = query
    let observer = observer
    self.completion = nil
    self.query = nil
    self.observer = nil
    lock.unlock()

    guard let completion else {
      return
    }
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
    if let query {
      let box = UncheckedSendableBox(query)
      Task { @MainActor in
        box.value.stop()
      }
    }
    completion(outcome)
  }

  private static func scope(_ scope: String) -> Any {
    scope.hasPrefix("/") ? URL(fileURLWithPath: scope, isDirectory: true) : scope
  }
}

/// Converts `NSMetadataItem` attributes into a `FileResult`.
enum FileResultMapper {
  static let attributes: [String] = [
    NSMetadataItemPathKey,
    NSMetadataItemDisplayNameKey,
    NSMetadataItemFSNameKey,
    NSMetadataItemContentTypeKey,
    NSMetadataItemContentTypeTreeKey,
    NSMetadataItemKindKey,
    NSMetadataItemFSSizeKey,
    NSMetadataItemFSCreationDateKey,
    NSMetadataItemFSContentChangeDateKey,
    NSMetadataItemLastUsedDateKey
  ]

  static func file(from item: NSMetadataItem) -> FileResult? {
    guard let values = item.values(forAttributes: attributes),
          let path = values[NSMetadataItemPathKey] as? String, !path.isEmpty
    else {
      return nil
    }
    let fileName = values[NSMetadataItemFSNameKey] as? String ?? (path as NSString).lastPathComponent
    let displayName = values[NSMetadataItemDisplayNameKey] as? String ?? fileName
    let contentType = values[NSMetadataItemContentTypeKey] as? String
    let tree = values[NSMetadataItemContentTypeTreeKey] as? [String] ?? []
    let isApplication = contentType == "com.apple.application-bundle" || tree.contains("com.apple.application")
    let isFolder = !isApplication && (contentType == "public.folder" || tree.contains("public.folder"))
    let kind = values[NSMetadataItemKindKey] as? String
      ?? fallbackKind(contentType: contentType, isFolder: isFolder, fileName: fileName)
    return FileResult(
      path: path,
      displayName: displayName.isEmpty ? fileName : displayName,
      fileName: fileName,
      kind: kind,
      contentType: contentType,
      isFolder: isFolder,
      isApplication: isApplication,
      size: (values[NSMetadataItemFSSizeKey] as? NSNumber)?.int64Value,
      created: values[NSMetadataItemFSCreationDateKey] as? Date,
      modified: values[NSMetadataItemFSContentChangeDateKey] as? Date,
      lastUsed: values[NSMetadataItemLastUsedDateKey] as? Date
    )
  }

  static func fallbackKind(contentType: String?, isFolder: Bool, fileName: String) -> String {
    if isFolder {
      return "Folder"
    }
    if let contentType, let type = UTType(contentType), let description = type.localizedDescription {
      return description
    }
    let ext = (fileName as NSString).pathExtension
    return ext.isEmpty ? "Document" : ext.uppercased() + " file"
  }
}

/// Carries a non-Sendable object across an isolation boundary when the caller
/// guarantees exclusive access.
struct UncheckedSendableBox<Value>: @unchecked Sendable {
  let value: Value

  init(_ value: Value) {
    self.value = value
  }
}
