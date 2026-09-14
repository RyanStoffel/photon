import AppKit
import PhotonNotes
import SwiftUI

struct NotesSettingsView: View {
  @EnvironmentObject private var settings: SettingsStore

  private let directory = NoteStore.defaultDirectory()

  var body: some View {
    Form {
      Section("Editor") {
        Stepper(
          value: $settings.notesFontSize,
          in: NotesPreferences.fontSizeRange,
          step: NotesPreferences.fontSizeStep
        ) {
          HStack {
            Text("Text size")
            Spacer()
            Text("\(Int(settings.notesFontSize)) pt")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
        Text("⌘+ and ⌘- change the size from the notes window as well.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Window") {
        Toggle("Float above other windows", isOn: $settings.notesFloatsAboveOtherWindows)
        Toggle("Open notes when Photon launches", isOn: $settings.notesOpenOnLaunch)
      }

      Section("Shortcut") {
        HStack {
          Text("Toggle notes window")
          Spacer()
          OptionalHotkeyRecorder(combo: $settings.notesHotkey)
            .frame(width: 180, height: 24)
          if settings.notesHotkey != nil {
            Button("Remove") {
              settings.notesHotkey = nil
            }
          }
        }
        Text("Notes are always available from the launcher: type “notes”, or “n” followed by a title.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Storage") {
        LabeledContent("Location") {
          Text(abbreviatedPath)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
        }
        HStack {
          Text("One markdown file per note. The first line is the title.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Show in Finder") {
            showInFinder()
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Notes")
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var abbreviatedPath: String {
    (directory.path as NSString).abbreviatingWithTildeInPath
  }

  private func showInFinder() {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    NSWorkspace.shared.open(directory)
  }
}
