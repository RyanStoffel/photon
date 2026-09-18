import Foundation
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
    } else if command.hasPrefix("showFiles:") {
      runtime.launcher.showFilesMode(query: String(command.dropFirst("showFiles:".count)))
    } else if command.hasPrefix("setFilesQuery:") {
      runtime.launcher.model.query = String(command.dropFirst("setFilesQuery:".count))
    } else if command == "resetLauncherPosition" {
      runtime.settings.resetLauncherPositionToCenter()
      if let panel = runtime.launcher.panel {
        runtime.launcher.position(panel)
      }
    } else if command.hasPrefix("requestFileAccess:") {
      let query = String(command.dropFirst("requestFileAccess:".count))
      runtime.fileSearch?.controller.update(query: query)
      runtime.fileSearch?.controller.requestFileAccess()
    }
  }
}
