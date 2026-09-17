import AppKit
import Combine
import Foundation

/// State and behaviour of the launcher's file mode. The launcher feeds it the
/// query and key events; it owns the results, the selection, Quick Look, and
/// the actions.
@MainActor
public final class FileSearchController: ObservableObject {
  public enum Status: Equatable, Sendable {
    case idle
    case searching
    case recents
    case noRecents
    case results
    case empty(String)
    case unavailable
    case needsAccess(String)
  }

  public struct KeyHint: Identifiable, Equatable, Sendable {
    public let key: String
    public let label: String

    public var id: String {
      key
    }
  }

  /// Ask the host to make the launcher panel key again (after Quick Look closes).
  public var onRequestFocus: (@MainActor () -> Void)?
  /// Ask the host to hide the launcher (after an action ran).
  public var onRequestDismiss: (@MainActor () -> Void)?
  /// Ask the host to activate the app so an auxiliary panel can take keyboard focus.
  public var onRequestActivation: (@MainActor () -> Void)?
  /// Opens the normal guided folder-selection flow without dismissing Photon.
  public var onRequestAccess: (@MainActor () -> Void)?

  @Published public private(set) var results: [RankedFile] = []
  @Published public private(set) var status: Status = .idle
  @Published public private(set) var isSearching = false
  @Published public private(set) var showsInfo = false
  @Published public private(set) var notice: String?
  @Published public private(set) var accessNotice: String?
  @Published public var selectedID: String? {
    didSet {
      if selectedID != oldValue {
        quickLook.update(selected?.url)
      }
    }
  }

  public var settings: FileSearchSettings
  public let quickLook = QuickLookCoordinator()

  private let engine: FileSearchEngine
  private var query = ""
  private var searchTask: Task<Void, Never>?
  private var noticeTask: Task<Void, Never>?
  private var selectionMovedByUser = false
  private var protectedResumeQuery: String?
  private var resumeProtectionTask: Task<Void, Never>?

  public var prefersCompactLauncherLayout: Bool {
    false
  }

  public var currentQuery: String {
    query
  }

  public init(settings: FileSearchSettings = FileSearchSettings(), engine: FileSearchEngine = FileSearchEngine()) {
    self.settings = settings
    self.engine = engine
    quickLook.onDidClose = { [weak self] in
      self?.onRequestFocus?()
    }
  }

  public var selected: FileResult? {
    results.first { $0.id == selectedID }?.file
  }

  /// True while Quick Look owns keyboard focus; the launcher must not hide itself then.
  public var holdsFocus: Bool {
    quickLook.isVisible
  }

  public var keyHints: [KeyHint] {
    [
      KeyHint(key: "\u{21A9}", label: settings.defaultAction.title),
      KeyHint(key: "\u{2318}\u{21A9}", label: settings.defaultAction.other.title),
      KeyHint(key: "Space", label: "Quick Look"),
      KeyHint(key: "\u{2318}C", label: "Copy Path"),
      KeyHint(key: "\u{2318}I", label: "Info")
    ]
  }

  // MARK: - Lifecycle

  public func activate(query: String) {
    showsInfo = false
    update(query: query)
  }

  /// Drops grant-resume protection so the next `deactivate`/`activate` is a
  /// real session, not a replay of the previous Files query.
  public func clearResumeProtection() {
    resumeProtectionTask?.cancel()
    resumeProtectionTask = nil
    protectedResumeQuery = nil
  }

  /// Keeps inline filename hits visible while the full Files search runs.
  public func seedResults(_ files: [RankedFile], query: String) {
    guard !files.isEmpty else {
      return
    }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }
    results = files
    status = .results
    selectedID = files.first?.id
    isSearching = true
    self.query = trimmed
  }

  public func update(query: String) {
    let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmed = requested.isEmpty ? protectedResumeQuery ?? requested : requested
    self.query = trimmed
    searchTask?.cancel()
    guard !trimmed.isEmpty else {
      engine.cancel()
      searchTask?.cancel()
      results = []
      selectedID = nil
      isSearching = true
      status = .searching
      loadRecents()
      return
    }
    isSearching = true
    if results.isEmpty {
      status = .searching
    }
    searchTask = Task { [weak self] in
      await self?.runSearch(trimmed)
    }
  }

  public func update(settings: FileSearchSettings, accessNotice: String? = nil) {
    let changed = self.settings != settings
    self.settings = settings
    self.accessNotice = accessNotice
    if changed, !query.isEmpty {
      update(query: query)
    }
  }

  public func requestFileAccess() {
    onRequestAccess?()
  }

  public func resumeAfterAccess(query: String) {
    resumeProtectionTask?.cancel()
    protectedResumeQuery = query
    update(query: query)
    resumeProtectionTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else {
        return
      }
      self?.protectedResumeQuery = nil
    }
  }

  private func loadRecents() {
    isSearching = true
    status = .searching
    searchTask = Task { [weak self] in
      guard let self else {
        return
      }
      let response = await engine.recent(settings: settings, limit: settings.clampedMaxResults)
      guard !Task.isCancelled, query.isEmpty else {
        return
      }
      isSearching = false
      results = response?.files ?? []
      status = results.isEmpty ? .noRecents : .recents
      selectedID = results.first?.id
      selectionMovedByUser = false
    }
  }

  public func deactivate() {
    if protectedResumeQuery != nil {
      quickLook.hide()
      return
    }
    searchTask?.cancel()
    searchTask = nil
    engine.cancel()
    quickLook.hide()
    noticeTask?.cancel()
    notice = nil
    showsInfo = false
    query = ""
    clearResults()
  }

  private func runSearch(_ query: String) async {
    let request = FileSearchEngine.Request(query: query, settings: settings, limit: settings.clampedMaxResults)
    let response = await engine.search(request)
    guard !Task.isCancelled, query == self.query else {
      return
    }
    isSearching = false
    guard let response else {
      if results.isEmpty {
        status = .empty(query)
      }
      return
    }
    results = response.files
    if !response.spotlightAvailable {
      status = .unavailable
    } else if results.isEmpty {
      if !response.spotlightAvailable, settings.grantedFolders.isEmpty {
        status = .needsAccess(response.query)
      } else {
        status = .empty(response.query)
      }
    } else {
      status = .results
    }
    selectionMovedByUser = false
    if let selectedID, results.contains(where: { $0.id == selectedID }) {
      return
    }
    selectedID = results.first?.id
  }

  private func clearResults() {
    results = []
    status = .idle
    isSearching = false
    selectedID = nil
    selectionMovedByUser = false
  }

  // MARK: - Selection

  public func moveSelection(_ delta: Int) {
    guard !results.isEmpty else {
      return
    }
    let index = results.firstIndex { $0.id == selectedID } ?? 0
    let next = (index + delta + results.count) % results.count
    selectedID = results[next].id
    selectionMovedByUser = true
  }

  public func select(_ file: FileResult) {
    selectedID = file.id
    selectionMovedByUser = true
  }

  // MARK: - Actions

  /// Runs the default action (Enter). Returns true when the launcher should hide.
  @discardableResult
  public func performPrimaryAction() -> Bool {
    perform(settings.defaultAction)
  }

  /// Runs the other action (Cmd+Enter). Returns true when the launcher should hide.
  @discardableResult
  public func performSecondaryAction() -> Bool {
    perform(settings.defaultAction.other)
  }

  public func copyPath() {
    guard let selected else {
      return
    }
    FileActions.copyPath(selected)
    show(notice: "Path copied")
  }

  public func toggleInfo() {
    if showsInfo {
      showsInfo = false
    } else if selected != nil {
      showsInfo = true
    }
  }

  public func toggleQuickLook() {
    if quickLook.isVisible {
      quickLook.hide()
    } else if let selected {
      onRequestActivation?()
      quickLook.show(selected.url)
    }
  }

  private func perform(_ action: FileDefaultAction) -> Bool {
    guard let selected else {
      return false
    }
    quickLook.hide()
    do {
      try FileActions.perform(action, on: selected)
      return true
    } catch {
      show(notice: error.localizedDescription)
      return false
    }
  }

  private func show(notice text: String) {
    noticeTask?.cancel()
    notice = text
    noticeTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(1500))
      guard !Task.isCancelled else {
        return
      }
      self?.notice = nil
    }
  }

  // MARK: - Keys

  /// Handles file-mode shortcuts. Returns true when the event was consumed.
  /// Up, down, Enter, and Escape (outside Quick Look) stay with the launcher.
  public func handle(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command) {
      return handleCommandShortcut(event)
    }
    switch event.keyCode {
    case 49:
      return handleSpace()
    case 53:
      return handleEscape()
    default:
      return false
    }
  }

  private func handleCommandShortcut(_ event: NSEvent) -> Bool {
    if event.keyCode == 36 || event.keyCode == 76 {
      if performSecondaryAction() {
        onRequestDismiss?()
      }
      return true
    }
    switch event.charactersIgnoringModifiers?.lowercased() ?? "" {
    case "c":
      copyPath()
      return true
    case "i":
      toggleInfo()
      return true
    case "y":
      toggleQuickLook()
      return true
    default:
      return false
    }
  }

  /// Space previews once the user has moved the selection; before that it
  /// keeps typing into the query so multi-word searches still work.
  private func handleSpace() -> Bool {
    if quickLook.isVisible {
      quickLook.hide()
      return true
    }
    guard selectionMovedByUser, selected != nil else {
      return false
    }
    toggleQuickLook()
    return true
  }

  private func handleEscape() -> Bool {
    guard quickLook.isVisible else {
      return false
    }
    quickLook.hide()
    return true
  }
}
