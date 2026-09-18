import AppKit
import Foundation

public enum NotesError: Error, Sendable {
  case noteNotFound(String)
}

/// Owns the note store, the current note, autosave, and the floating window.
///
/// The app talks to this type only: the provider calls it for launcher commands and the
/// settings integration pushes `preferences` into it.
@MainActor
public final class NotesController: NSObject {
  public static let autosaveDelay: TimeInterval = 0.6

  public let directory: URL
  public var onPreferencesChange: ((NotesPreferences) -> Void)?

  public var preferences: NotesPreferences {
    didSet {
      if preferences != oldValue {
        window?.apply(preferences)
      }
    }
  }

  public private(set) var currentNoteID: String?
  public private(set) var pinStore = NotePinStore()

  public var pinnedIDs: Set<String> {
    pinStore.pinnedIDs
  }

  let store: NoteStore
  private let debouncer: Debouncer
  private var window: NotesWindow?
  private var pendingContent: String?
  /// Notes created blank in this session that have never received text. Only these are pruned.
  private var untouchedNoteIDs: Set<String> = []

  public init(directory: URL = NoteStore.defaultDirectory(), preferences: NotesPreferences = NotesPreferences()) {
    self.directory = directory
    self.preferences = preferences
    store = NoteStore(directory: directory)
    debouncer = Debouncer(delay: Self.autosaveDelay)
    super.init()
    pinStore = NotePinStore(defaults: .standard)
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(applicationWillTerminate),
      name: NSApplication.willTerminateNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  // MARK: Launcher-facing API

  public var isWindowVisible: Bool {
    window?.isVisible ?? false
  }

  public var screenshotWindow: NSWindow? {
    window?.panel
  }

  /// Newest first, including unsaved edits to the current note.
  public func noteSummaries() -> [NoteSummary] {
    loadIfNeeded()
    return orderedNotes().map(NoteSummary.init)
  }

  /// Re-reads the directory so externally added or edited files show up.
  public func refreshFromDisk() {
    loadIfNeeded()
    applyExternalChanges()
  }

  public func show(focus: Bool = true) {
    loadIfNeeded()
    ensureCurrentNote()
    presentWindow().show(focus: focus)
  }

  public func hide() {
    guard let window, window.isVisible else {
      return
    }
    flush()
    pruneBlankCurrentNote()
    window.hide()
  }

  public func toggle() {
    if let window, window.isVisible, window.isKey {
      hide()
    } else {
      show()
    }
  }

  public func open(noteID: String) throws {
    loadIfNeeded()
    guard store.note(id: noteID) != nil else {
      throw NotesError.noteNotFound(noteID)
    }
    switchTo(noteID)
    presentWindow().show(focus: true)
  }

  public func openFromSwitcher(_ id: String) {
    try? open(noteID: id)
  }

  public func togglePin(_ id: String) {
    pinStore.toggle(id)
    pinStore.save(to: .standard)
    window?.notesDidChange()
  }

  public func deleteNote(id: String) {
    loadIfNeeded()
    guard let note = store.note(id: id) else {
      return
    }
    flush()
    let window = presentWindow()
    Task {
      if await window.confirmDelete(of: note.title) {
        performDelete(id)
        window.notesDidChange()
      }
    }
  }

  @discardableResult
  public func duplicateCurrentNote() -> Note? {
    flush()
    let content = pendingContent ?? currentNote?.content ?? ""
    return createNote(content: content)
  }

  public func copyCurrentNote() {
    flush()
    let content = pendingContent ?? currentNote?.content ?? ""
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
  }

  public func copyDeepLink() {
    guard let id = currentNoteID, let url = NoteDeepLink.url(for: id) else {
      return
    }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(url.absoluteString, forType: .string)
  }

  public func presentSwitcher() {
    let window = presentWindow()
    window.notesDidChange()
    window.show(focus: true)
    window.presentSwitcher()
  }

  public func presentActions() {
    presentWindow().show(focus: true)
    presentWindow().presentActions()
  }

  public func presentFormatBar() {
    presentWindow().show(focus: true)
    presentWindow().presentFormatBar()
  }

  public var overlayName: String {
    window?.overlayName ?? "none"
  }

  public var windowWidth: Double {
    window?.panel.frame.width ?? NotesLayout.panelWidth
  }

  public var windowHeight: Double {
    window?.panel.frame.height ?? NotesLayout.defaultHeight
  }

  public var windowNumber: Int {
    window?.panel.windowNumber ?? 0
  }

  @discardableResult
  public func createNote(content: String = "") -> Note? {
    loadIfNeeded()
    flush()
    pruneBlankCurrentNote()
    do {
      let note = try store.create(content: content)
      if note.isBlank {
        untouchedNoteIDs.insert(note.id)
      }
      switchTo(note.id)
      let window = presentWindow()
      window.show(focus: true)
      window.focusEditor(atEnd: true)
      return note
    } catch {
      NSLog("Photon Notes: could not create note: \(error)")
      return nil
    }
  }

  /// Asks for confirmation, then moves the current note to the Trash.
  public func deleteCurrentNote() {
    guard let id = currentNoteID, let note = store.note(id: id), let window else {
      return
    }
    flush()
    Task {
      if await window.confirmDelete(of: note.title) {
        performDelete(id)
      }
    }
  }

  public func revealInFinder() {
    if let note = currentNote {
      NSWorkspace.shared.activateFileViewerSelecting([note.url])
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([directory])
    }
  }

  public func adjustFontSize(by steps: Int) {
    updatePreferences(preferences.adjustingFontSize(by: steps))
  }

  public func resetFontSize() {
    var next = preferences
    next.fontSize = NotesPreferences.defaultFontSize
    updatePreferences(next)
  }

  /// Toolbar "Float on Top". Round-trips through `onPreferencesChange` like the font size does.
  public func setFloatsAboveOtherWindows(_ floats: Bool) {
    var next = preferences
    next.floatsAboveOtherWindows = floats
    updatePreferences(next)
  }

  /// Writes any pending edit immediately.
  public func flush() {
    debouncer.flush()
  }

  // MARK: Window callbacks

  public var currentNote: Note? {
    currentNoteID.flatMap { store.note(id: $0) }
  }

  func orderedNotes() -> [Note] {
    var notes = store.notes
    if let id = currentNoteID, let pending = pendingContent, let index = notes.firstIndex(where: { $0.id == id }) {
      notes[index].content = pending
    }
    return notes
  }

  func editorDidChange(_ content: String) {
    guard let id = currentNoteID else {
      return
    }
    pendingContent = content
    if !content.allSatisfy(\.isWhitespace) {
      untouchedNoteIDs.remove(id)
    }
    window?.updateTitle(NoteTitle.extract(from: content))
    window?.notesDidChange()
    debouncer.schedule { [weak self] in
      self?.save(id: id, content: content)
    }
  }

  func windowDidBecomeKey() {
    applyExternalChanges()
  }

  func windowDidResignKey() {
    flush()
  }

  /// Sidebar selection. Focus stays in the list so arrow keys keep switching notes.
  func sidebarDidSelect(_ id: String) {
    switchTo(id)
  }

  // MARK: Private

  private func presentWindow() -> NotesWindow {
    if let window {
      return window
    }
    let window = NotesWindow(controller: self)
    window.apply(preferences)
    self.window = window
    if let note = currentNote {
      window.display(note, cursorAtEnd: false)
    }
    return window
  }

  private func loadIfNeeded() {
    guard !store.isLoaded else {
      return
    }
    do {
      try store.load()
    } catch {
      NSLog("Photon Notes: could not load notes: \(error)")
    }
  }

  private func ensureCurrentNote() {
    if let id = currentNoteID, store.note(id: id) != nil {
      return
    }
    if let newest = store.notes.first {
      switchTo(newest.id)
      return
    }
    do {
      let welcome = try store.create(content: WelcomeNote.content)
      switchTo(welcome.id)
    } catch {
      NSLog("Photon Notes: could not create the first note: \(error)")
    }
  }

  private func switchTo(_ id: String) {
    guard id != currentNoteID else {
      return
    }
    flush()
    pruneBlankCurrentNote()
    guard let note = store.note(id: id) else {
      return
    }
    currentNoteID = id
    pendingContent = nil
    window?.display(note, cursorAtEnd: false)
  }

  private func save(id: String, content: String) {
    do {
      try store.save(id: id, content: content)
      if currentNoteID == id, pendingContent == content {
        pendingContent = nil
      }
    } catch {
      NSLog("Photon Notes: could not save note \(id): \(error)")
    }
  }

  /// Drops an untouched new note so ⌘N never litters the folder with empty files.
  private func pruneBlankCurrentNote() {
    guard let id = currentNoteID, untouchedNoteIDs.contains(id), store.notes.count > 1 else {
      return
    }
    let content = pendingContent ?? store.note(id: id)?.content ?? ""
    guard content.allSatisfy(\.isWhitespace) else {
      untouchedNoteIDs.remove(id)
      return
    }
    do {
      try store.delete(id: id, trash: false)
      untouchedNoteIDs.remove(id)
      pendingContent = nil
      currentNoteID = nil
    } catch {
      NSLog("Photon Notes: could not remove blank note \(id): \(error)")
    }
  }

  private func performDelete(_ id: String) {
    do {
      try store.delete(id: id)
    } catch {
      NSLog("Photon Notes: could not delete note \(id): \(error)")
      return
    }
    untouchedNoteIDs.remove(id)
    if currentNoteID == id {
      currentNoteID = nil
      pendingContent = nil
    }
    ensureCurrentNote()
  }

  private func applyExternalChanges() {
    let changes: NoteStoreChanges
    do {
      changes = try store.rescan()
    } catch {
      NSLog("Photon Notes: could not rescan notes: \(error)")
      return
    }
    guard !changes.isEmpty, let window else {
      return
    }
    if let id = currentNoteID, changes.removed.contains(id) {
      currentNoteID = nil
      pendingContent = nil
    }
    ensureCurrentNote()
    if let note = currentNote, changes.updated.contains(note.id), pendingContent == nil {
      window.display(note, cursorAtEnd: false)
    }
    window.notesDidChange()
  }

  private func updatePreferences(_ next: NotesPreferences) {
    guard next != preferences else {
      return
    }
    preferences = next
    onPreferencesChange?(next)
  }

  @objc
  private func applicationWillTerminate(_: Notification) {
    flush()
  }

  @objc
  private func applicationDidBecomeActive(_: Notification) {
    if window?.isVisible == true {
      applyExternalChanges()
    }
  }
}

enum WelcomeNote {
  static let content = """
  # Welcome to Photon Notes

  Notes are plain markdown files that save as you type.

  - Press ⌘N for a new note, ⌘P to browse notes, and ⌘K for actions
  - Type `notes` or `n <title>` in the launcher to jump straight to a note
  - ⌘+ and ⌘- change the text size; the window keeps a fixed width and remembers its height

  ## Formatting

  **Bold**, *italic*, `code`, headings, and lists are styled as you write.

  - [ ] Click a checkbox to toggle it
  - [x] Like this one

  Files live in ~/Library/Application Support/Photon/Notes.
  """
}
