import AppKit
import PhotonCore
import QuickLookUI
import SwiftUI

/// A feature the launcher can switch into (file search today). Clipboard
/// history still uses `LauncherSession.clipboard` beside this hook; do not
/// fold it in without the follow-up chore. While a mode is active it owns
/// the results area, the selection, and the keys the launcher does not
/// handle itself. Enter, Escape, up and down stay with the launcher.
@MainActor
protocol LauncherMode: AnyObject {
  var id: String { get }
  /// Mode name shown in the footer corner while the mode is active.
  var title: String { get }
  var placeholder: String { get }
  /// Typed prefixes that switch the launcher into this mode, matched case-insensitively.
  var prefixes: [String] { get }
  /// Executing this command enters the mode instead of closing the launcher.
  var activationCommandID: String? { get }
  /// Provider whose results (other than the activation command) are listed after primary results.
  var inlineProviderID: String? { get }
  /// True while an auxiliary panel such as Quick Look holds keyboard focus.
  var holdsFocus: Bool { get }
  /// When true the launcher stays at compact height (search field + footer only).
  var prefersCompactLauncherLayout: Bool { get }

  func attach(host: any LauncherModeHost)
  func activate(query: String)
  func update(query: String)
  func deactivate()
  func moveSelection(_ delta: Int)
  /// Enter. Returns true when the launcher should hide afterwards.
  func performPrimaryAction() -> Bool
  /// Returns true when the event was consumed.
  func handle(_ event: NSEvent) -> Bool
  /// Icon for one of this mode's inline results in the default list.
  func icon(for command: Command) -> NSImage?
  func makeResultsView() -> AnyView

  var acceptsPreviewPanelControl: Bool { get }
  func beginPreviewPanelControl(_ panel: QLPreviewPanel)
  func endPreviewPanelControl(_ panel: QLPreviewPanel)
}

extension LauncherMode {
  /// When true the launcher stays at compact height (search field + footer only).
  var prefersCompactLauncherLayout: Bool {
    false
  }
}

/// What a mode may ask of the launcher.
@MainActor
protocol LauncherModeHost: AnyObject {
  /// Make the launcher panel key again, for example after Quick Look closes.
  func modeRequestsFocus()
  /// Hide the launcher after an action ran.
  func modeRequestsDismiss()
  /// Activate the app so an auxiliary panel can take keyboard focus.
  func modeRequestsActivation()
  /// Recompute panel height (compact vs results) after async mode state changes.
  func modeRequestsLayoutUpdate()
}
