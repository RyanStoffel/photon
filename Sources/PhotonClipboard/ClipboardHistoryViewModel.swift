#if canImport(AppKit)
import AppKit
import Combine
import Foundation

/// State for the clipboard view inside the launcher panel: query, ranked
/// results, selection, and the keyboard actions. The launcher forwards its
/// search text into `query` and key events into `handleKeyDown`.
@MainActor
public final class ClipboardHistoryViewModel: ObservableObject {
  public struct Notice: Equatable, Sendable {
    public let message: String
    public let offersAccessibility: Bool
  }

  @Published public var query = "" {
    didSet {
      if query != oldValue {
        notice = nil
        refilter()
      }
    }
  }

  @Published public private(set) var results: [ClipboardItem] = []
  @Published public var selectedID: UUID?
  @Published public private(set) var notice: Notice?
  @Published public private(set) var isConfirmingClear = false

  public let manager: ClipboardManager

  /// Asks the host to close the panel (after a paste or copy).
  public var onDismiss: (() -> Void)?

  private var subscriptions: Set<AnyCancellable> = []
  private var hasPromptedForAccessibility = false

  public init(manager: ClipboardManager) {
    self.manager = manager
    manager.$items
      .sink { [weak self] items in
        self?.refilter(items: items)
      }
      .store(in: &subscriptions)
    refilter()
  }

  /// Called every time the launcher enters clipboard mode.
  public func reset() {
    notice = nil
    isConfirmingClear = false
    manager.refreshAccessibility()
    if query.isEmpty {
      refilter()
    } else {
      query = ""
    }
    selectedID = results.first?.id
  }

  public var selectedItem: ClipboardItem? {
    guard let selectedID else {
      return nil
    }
    return results.first { $0.id == selectedID }
  }

  public var selectedIndex: Int? {
    guard let selectedID else {
      return nil
    }
    return results.firstIndex { $0.id == selectedID }
  }

  /// One-line empty state when history is off or a filter has no matches.
  public var showsCompactEmptyRow: Bool {
    if !manager.isEnabled {
      return true
    }
    if manager.items.isEmpty {
      return false
    }
    return !query.isEmpty
  }

  public var compactEmptyMessage: String {
    if !manager.isEnabled {
      return "Clipboard history is off"
    }
    return "No matches"
  }

  /// Short hint for the footer when the list is collapsed.
  public var footerEmptyHint: String? {
    if !manager.isEnabled {
      return "Turn on in Settings \u{203A} Clipboard"
    }
    if manager.items.isEmpty {
      return "Copy something in any app"
    }
    return nil
  }

  public func moveSelection(_ delta: Int) {
    guard !results.isEmpty else {
      return
    }
    let count = results.count
    let index = selectedIndex ?? 0
    let next = ((index + delta) % count + count) % count
    selectedID = results[next].id
  }

  public func selectFirst() {
    selectedID = results.first?.id
  }

  public func selectLast() {
    selectedID = results.last?.id
  }

  // MARK: Keyboard

  /// Returns `true` when the event was consumed. Esc is only consumed while a
  /// clear-all confirmation is pending; the host decides what Esc means otherwise.
  /// Up/Down stay with the launcher so the compact bar can expand before the
  /// selection moves.
  public func handleKeyDown(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let command = flags.contains(.command)
    let shift = flags.contains(.shift)

    switch event.keyCode {
    case 36, 76:
      handleReturn(command: command)
      return true
    case 53 where isConfirmingClear:
      isConfirmingClear = false
      return true
    case 51 where command:
      if shift {
        requestClearAll()
      } else {
        deleteSelected()
      }
      return true
    case 35 where command:
      togglePinSelected()
      return true
    default:
      return false
    }
  }

  private func handleReturn(command: Bool) {
    if isConfirmingClear {
      confirmClearAll()
    } else if command {
      Task { await copySelected() }
    } else {
      Task { await performPrimaryAction() }
    }
  }

  // MARK: Actions

  public func performPrimaryAction() async {
    guard let item = selectedItem else {
      return
    }
    switch await manager.paste(item) {
    case .pasted:
      break
    case .copied:
      onDismiss?()
    case .accessibilityRequired:
      if !hasPromptedForAccessibility {
        hasPromptedForAccessibility = true
        manager.requestAccessibility()
      }
      notice = Notice(
        message: "Copied. Grant Photon Accessibility access to paste directly.",
        offersAccessibility: true
      )
    case .eventInjectionFailed:
      notice = Notice(
        message: "Copied, but Photon could not send Paste. Try again or use Copy Only.",
        offersAccessibility: false
      )
    }
  }

  public func paste(_ item: ClipboardItem) {
    selectedID = item.id
    Task { await performPrimaryAction() }
  }

  public func copySelected() async {
    guard let item = selectedItem else {
      return
    }
    await manager.copy(item)
    onDismiss?()
  }

  public func copy(_ item: ClipboardItem) {
    selectedID = item.id
    Task { await copySelected() }
  }

  public func togglePinSelected() {
    guard let item = selectedItem else {
      return
    }
    togglePin(item)
  }

  public func togglePin(_ item: ClipboardItem) {
    manager.togglePin(id: item.id)
  }

  public func deleteSelected() {
    guard let item = selectedItem else {
      return
    }
    delete(item)
  }

  public func delete(_ item: ClipboardItem) {
    let index = selectedIndex ?? 0
    manager.delete(id: item.id)
    let remaining = results.filter { $0.id != item.id }
    results = remaining
    if !remaining.isEmpty {
      selectedID = remaining[min(index, remaining.count - 1)].id
    } else {
      selectedID = nil
    }
  }

  public func requestClearAll() {
    guard !manager.items.isEmpty else {
      return
    }
    isConfirmingClear = true
  }

  public func cancelClearAll() {
    isConfirmingClear = false
  }

  public func confirmClearAll() {
    isConfirmingClear = false
    manager.clearAll()
    results = []
    selectedID = nil
  }

  public func openAccessibilitySettings() {
    manager.openAccessibilitySettings()
  }

  // MARK: Internals

  private func refilter(items: [ClipboardItem]? = nil) {
    let source = items ?? manager.items
    results = ClipboardSearch.rank(source, query: query)
    if let selectedID, results.contains(where: { $0.id == selectedID }) {
      return
    }
    selectedID = results.first?.id
  }
}
#endif
