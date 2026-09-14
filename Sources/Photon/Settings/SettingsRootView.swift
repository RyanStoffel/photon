import SwiftUI

struct SettingsRootView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      PlaceholderSettingsView(
        title: "Clipboard",
        detail: "History, pin, paste, retention, and excluded apps land in Phase 2.",
        content: { ClipboardSettingsPlaceholder() }
      )
      .tabItem { Label("Clipboard", systemImage: "clipboard") }
      PlaceholderSettingsView(
        title: "Notes",
        detail: "Floating notes and markdown persistence land in Phase 2.",
        content: { NotesSettingsPlaceholder() }
      )
      .tabItem { Label("Notes", systemImage: "note.text") }
      PlaceholderSettingsView(
        title: "Files",
        detail: "Spotlight-backed file search lands in Phase 2.",
        content: { FilesSettingsPlaceholder() }
      )
      .tabItem { Label("Files", systemImage: "folder") }
      PlaceholderSettingsView(
        title: "Keybinds",
        detail: "Hyper key, app hotkeys, and window management land in Phase 2.",
        content: { KeybindsSettingsPlaceholder() }
      )
      .tabItem { Label("Keybinds", systemImage: "keyboard") }
      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .environmentObject(settings)
    .padding(20)
  }
}

struct PlaceholderSettingsView<Content: View>: View {
  let title: String
  let detail: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    Form {
      Section {
        Text(detail)
          .foregroundStyle(.secondary)
      }
      content()
    }
    .formStyle(.grouped)
    .navigationTitle(title)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct ClipboardSettingsPlaceholder: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Section("Retention") {
      Stepper(value: $settings.clipboardRetentionDays, in: 1 ... 365) {
        Text("Keep items for \(settings.clipboardRetentionDays) days")
      }
      .disabled(true)
      TextField("Excluded apps", text: $settings.clipboardExcludeApps)
        .disabled(true)
    }
  }
}

private struct NotesSettingsPlaceholder: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Section("Storage") {
      Text(settings.notesFolderBookmark.isEmpty ? "Default notes folder (not configured)" : "Custom folder")
        .foregroundStyle(.secondary)
    }
  }
}

private struct FilesSettingsPlaceholder: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Section("Scope") {
      Picker("Search", selection: $settings.filesSearchScope) {
        Text("Home folder").tag("home")
        Text("This Mac").tag("this-mac")
      }
      .disabled(true)
    }
  }
}

private struct KeybindsSettingsPlaceholder: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Section("Hyper key") {
      Toggle("Caps Lock → Control + Option + Shift + Command", isOn: $settings.hyperKeyEnabled)
        .disabled(true)
    }
  }
}
