import Foundation
import PhotonCore
import PhotonNotes

extension NativeParityReporter {
  func dispatchParityCommand(_ command: String, runtime: AppRuntime) {
    if handleNotesParityCommand(command, notes: runtime.notes.controller) {
      return
    }
    handleLauncherParityCommand(command, runtime: runtime)
  }

  private func handleNotesParityCommand(_ command: String, notes: NotesController) -> Bool {
    switch command {
    case "showNotes":
      notes.show(focus: true)
    case "seedNotes":
      _ = notes.createNote(content: "# JIRA API KEY\nsecret")
      _ = notes.createNote(content: "Test\n\nbla bla")
    case "seedAndShowNotes":
      _ = notes.createNote(content: "# JIRA API KEY\nsecret")
      _ = notes.createNote(content: "Test\n\nbla bla")
      notes.show(focus: true)
    case "showNotesSwitcher":
      notes.presentSwitcher()
    case "showNotesActions":
      notes.presentActions()
    case "showNotesFormat":
      notes.presentFormatBar()
    case "hideNotes":
      notes.hide()
    default:
      return false
    }
    return true
  }

  private func handleLauncherParityCommand(_ command: String, runtime: AppRuntime) {
    if command == "hideLauncher" {
      runtime.launcher.hide()
    } else if command == "showLauncher" {
      runtime.launcher.show()
    } else if command == "resetLauncherPosition" {
      runtime.settings.resetLauncherPositionToCenter()
      if let panel = runtime.launcher.panel {
        runtime.launcher.position(panel)
      }
    } else if command == "scrollRecsPastFirstPage" {
      scrollRecsPastFirstPage(runtime: runtime)
    } else {
      handleLauncherPrefixCommand(command, runtime: runtime)
    }
  }

  /// Down from the last on-screen rec, atomically, so the command file cannot
  /// drop the follow-up key between two writes.
  private func scrollRecsPastFirstPage(runtime: AppRuntime) {
    let model = runtime.launcher.model
    let visible = LauncherLayout.visibleRecommendationRows
    guard model.results.count > visible else {
      return
    }
    model.selectedID = model.results[visible - 1].id
    model.moveSelection(1)
  }

  private func handleLauncherPrefixCommand(_ command: String, runtime: AppRuntime) {
    if command.hasPrefix("showFiles:") {
      runtime.launcher.showFilesMode(query: String(command.dropFirst("showFiles:".count)))
    } else if command.hasPrefix("setFilesQuery:") {
      runtime.launcher.model.query = String(command.dropFirst("setFilesQuery:".count))
    } else if command.hasPrefix("requestFileAccess:") {
      let query = String(command.dropFirst("requestFileAccess:".count))
      runtime.fileSearch?.controller.update(query: query)
      runtime.fileSearch?.controller.requestFileAccess()
    } else if command.hasPrefix("selectLauncherIndex:") {
      let raw = String(command.dropFirst("selectLauncherIndex:".count))
      guard let index = Int(raw) else {
        return
      }
      let results = runtime.launcher.model.results
      guard results.indices.contains(index) else {
        return
      }
      runtime.launcher.model.selectedID = results[index].id
    } else if command.hasPrefix("moveLauncherSelection:") {
      let raw = String(command.dropFirst("moveLauncherSelection:".count))
      runtime.launcher.model.moveSelection(Int(raw) ?? 0)
    }
  }
}
