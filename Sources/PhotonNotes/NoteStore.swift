import Foundation

public enum NoteStoreError: Error, Equatable, Sendable {
  case unknownNote(String)
  case unreadable(URL)
}

/// What changed on disk since the last scan.
public struct NoteStoreChanges: Equatable, Sendable {
  public var added: [String]
  public var updated: [String]
  public var removed: [String]

  public init(added: [String] = [], updated: [String] = [], removed: [String] = []) {
    self.added = added
    self.updated = updated
    self.removed = removed
  }

  public var isEmpty: Bool {
    added.isEmpty && updated.isEmpty && removed.isEmpty
  }
}

/// Directory-backed note storage. One markdown file per note, written atomically.
///
/// Not thread-safe: the owner is expected to call it from a single actor.
public final class NoteStore {
  public static let fileExtension = "md"
  static let readableExtensions: Set<String> = ["md", "markdown"]

  public let directory: URL
  public private(set) var notes: [Note] = []
  private var fingerprints: [String: FileFingerprint] = [:]
  private var loaded = false

  public init(directory: URL) {
    self.directory = directory
  }

  /// `~/Library/Application Support/Photon/Notes`.
  public static func defaultDirectory() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return support
      .appendingPathComponent("Photon", isDirectory: true)
      .appendingPathComponent("Notes", isDirectory: true)
  }

  public func note(id: String) -> Note? {
    notes.first { $0.id == id }
  }

  /// Reads every note from disk. Safe to call repeatedly; later calls behave like `rescan()`.
  @discardableResult
  public func load() throws -> [Note] {
    if loaded {
      try rescan()
      return notes
    }
    try ensureDirectory()
    var found: [Note] = []
    var prints: [String: FileFingerprint] = [:]
    for url in try noteFiles() {
      guard let print = FileFingerprint(url: url), let note = read(url, fingerprint: print) else {
        continue
      }
      found.append(note)
      prints[note.id] = print
    }
    notes = Self.sorted(found)
    fingerprints = prints
    loaded = true
    return notes
  }

  /// Diffs the directory against the last scan and reloads changed files.
  @discardableResult
  public func rescan() throws -> NoteStoreChanges {
    guard loaded else {
      try load()
      return NoteStoreChanges(added: notes.map(\.id))
    }
    try ensureDirectory()
    var changes = NoteStoreChanges()
    var seen: Set<String> = []
    var next = notes
    for url in try noteFiles() {
      guard let print = FileFingerprint(url: url) else {
        continue
      }
      let id = url.deletingPathExtension().lastPathComponent
      seen.insert(id)
      if let previous = fingerprints[id], previous == print {
        continue
      }
      guard let note = read(url, fingerprint: print) else {
        continue
      }
      if let index = next.firstIndex(where: { $0.id == id }) {
        next[index] = note
        changes.updated.append(id)
      } else {
        next.append(note)
        changes.added.append(id)
      }
      fingerprints[id] = print
    }
    for note in notes where !seen.contains(note.id) {
      next.removeAll { $0.id == note.id }
      fingerprints[note.id] = nil
      changes.removed.append(note.id)
    }
    notes = Self.sorted(next)
    return changes
  }

  /// Creates a new file named after the creation time, for example `Note 2026-09-14 at 03.12.45.md`.
  public func create(content: String = "", now: Date = Date()) throws -> Note {
    try load()
    let url = availableURL(for: Self.fileName(for: now))
    let id = url.deletingPathExtension().lastPathComponent
    try write(content, to: url)
    let print = FileFingerprint(url: url) ?? FileFingerprint(modifiedAt: now, size: content.utf8.count)
    let note = Note(id: id, url: url, content: content, modifiedAt: print.modifiedAt)
    notes = Self.sorted(notes + [note])
    fingerprints[id] = print
    return note
  }

  /// Writes `content` atomically. Returns the refreshed note, or the unchanged one if nothing differed.
  @discardableResult
  public func save(id: String, content: String) throws -> Note {
    guard let index = notes.firstIndex(where: { $0.id == id }) else {
      throw NoteStoreError.unknownNote(id)
    }
    var note = notes[index]
    if note.content == content, FileManager.default.fileExists(atPath: note.url.path) {
      return note
    }
    try write(content, to: note.url)
    let print = FileFingerprint(url: note.url) ?? FileFingerprint(modifiedAt: Date(), size: content.utf8.count)
    note.content = content
    note.modifiedAt = print.modifiedAt
    notes[index] = note
    notes = Self.sorted(notes)
    fingerprints[id] = print
    return note
  }

  /// Moves the file to the Trash (macOS only; deleted outright elsewhere or when `trash` is false).
  public func delete(id: String, trash: Bool = true) throws {
    guard let note = note(id: id) else {
      throw NoteStoreError.unknownNote(id)
    }
    if FileManager.default.fileExists(atPath: note.url.path) {
      #if os(macOS)
      if trash {
        try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
      } else {
        try FileManager.default.removeItem(at: note.url)
      }
      #else
      try FileManager.default.removeItem(at: note.url)
      #endif
    }
    notes.removeAll { $0.id == id }
    fingerprints[id] = nil
  }

  static func fileName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Note \(formatter.string(from: date))"
  }

  static func sorted(_ notes: [Note]) -> [Note] {
    notes.sorted { lhs, rhs in
      if lhs.modifiedAt != rhs.modifiedAt {
        return lhs.modifiedAt > rhs.modifiedAt
      }
      return lhs.id > rhs.id
    }
  }

  private func ensureDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private func noteFiles() throws -> [URL] {
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    return urls.filter { Self.readableExtensions.contains($0.pathExtension.lowercased()) }
  }

  private func read(_ url: URL, fingerprint: FileFingerprint) -> Note? {
    guard let data = try? Data(contentsOf: url),
          let content = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1)
    else {
      return nil
    }
    return Note(
      id: url.deletingPathExtension().lastPathComponent,
      url: url,
      content: content,
      modifiedAt: fingerprint.modifiedAt
    )
  }

  private func write(_ content: String, to url: URL) throws {
    try ensureDirectory()
    try Data(content.utf8).write(to: url, options: .atomic)
  }

  private func availableURL(for baseName: String) -> URL {
    var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(Self.fileExtension)
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory
        .appendingPathComponent("\(baseName) \(suffix)")
        .appendingPathExtension(Self.fileExtension)
      suffix += 1
    }
    return candidate
  }
}

struct FileFingerprint: Equatable {
  var modifiedAt: Date
  var size: Int

  init(modifiedAt: Date, size: Int) {
    self.modifiedAt = modifiedAt
    self.size = size
  }

  init?(url: URL) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let date = attributes[.modificationDate] as? Date
    else {
      return nil
    }
    modifiedAt = date
    size = (attributes[.size] as? NSNumber)?.intValue ?? 0
  }
}
