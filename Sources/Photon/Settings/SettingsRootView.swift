import SwiftUI

struct SettingsRootView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      ClipboardSettingsView()
        .tabItem { Label("Clipboard", systemImage: "clipboard") }
      NotesSettingsView()
        .tabItem { Label("Notes", systemImage: "note.text") }
      FilesSettingsView()
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

private struct KeybindsSettingsPlaceholder: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Section("Hyper key") {
      Toggle("Caps Lock → Control + Option + Shift + Command", isOn: $settings.hyperKeyEnabled)
        .disabled(true)
    }
  }
}
