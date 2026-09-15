import AppKit
import PhotonFiles
import SwiftUI

struct FilesSettingsView: View {
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var fileAccess: FileAccessCoordinator

  var body: some View {
    Form {
      Section("Search") {
        Picker("Look in", selection: $settings.filesSearchScope) {
          ForEach(FileSearchScope.allCases, id: \.rawValue) { scope in
            Text(scope.title).tag(scope.rawValue)
          }
        }
        Toggle("Search file contents", isOn: $settings.filesSearchContents)
        Text("Matches words inside documents as well as names. Slower on large libraries.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Stepper(value: $settings.filesMaxResults, in: FileSearchSettings.maxResultsRange, step: 10) {
          Text("Show up to \(settings.filesMaxResults) results")
        }
      }

      Section("Actions") {
        Picker("Enter", selection: $settings.filesDefaultAction) {
          ForEach(FileDefaultAction.allCases, id: \.rawValue) { action in
            Text(action.title).tag(action.rawValue)
          }
        }
        Text("Command-Enter performs the other action. Space or Command-Y opens Quick Look.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle("Show file matches in the main list", isOn: $settings.filesInlineResults)
        Text("Up to three strong matches appear below applications once you have typed three characters.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Folder Access") {
        if fileAccess.grants.isEmpty {
          Text("Choose only the folders Photon may search directly when Spotlight has no match.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(fileAccess.grants) { grant in
          HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: grant.path))
              .resizable()
              .frame(width: 16, height: 16)
            Text(PathFormatter.abbreviatingHome(grant.path))
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer()
            Button("Remove", systemImage: "minus.circle") {
              fileAccess.remove(path: grant.path)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
          }
        }
        Button(fileAccess.grants.isEmpty ? "Choose Folders…" : "Add Folder…") {
          fileAccess.requestAccess()
        }
        if fileAccess.status == .requesting {
          ProgressView()
            .controlSize(.small)
        } else if let message = fileAccess.statusMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.orange)
        }
        Text("Photon stores security-scoped bookmarks so access survives relaunch.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Never search") {
        FolderListEditor(
          folders: $settings.filesExcludedFolders,
          emptyText: "Files inside these folders never appear in results."
        )
        Text(
          "Folders listed under System Settings > Siri & Spotlight > Spotlight Privacy "
            + "are already excluded by Spotlight."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Files")
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct FolderListEditor: View {
  @Binding var folders: [String]
  let emptyText: String

  var body: some View {
    if folders.isEmpty {
      Text(emptyText)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    ForEach(folders, id: \.self) { folder in
      HStack(spacing: 8) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: folder))
          .resizable()
          .frame(width: 16, height: 16)
        Text(PathFormatter.abbreviatingHome(folder))
          .lineLimit(1)
          .truncationMode(.middle)
          .help(folder)
        Spacer()
        Button("Remove", systemImage: "minus.circle") {
          folders.removeAll { $0 == folder }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
      }
    }
    Button("Add Folder\u{2026}") {
      addFolders()
    }
  }

  private func addFolders() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Add"
    panel.message = "Choose folders"
    guard panel.runModal() == .OK else {
      return
    }
    for url in panel.urls {
      let path = url.standardizedFileURL.path(percentEncoded: false)
      let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
      if !folders.contains(trimmed) {
        folders.append(trimmed)
      }
    }
  }
}
