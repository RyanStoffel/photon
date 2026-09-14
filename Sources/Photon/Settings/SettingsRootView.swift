import SwiftUI

struct SettingsRootView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      AppearanceSettingsView()
        .tabItem { Label("Appearance", systemImage: "paintpalette") }
      ClipboardSettingsView()
        .tabItem { Label("Clipboard", systemImage: "clipboard") }
      NotesSettingsView()
        .tabItem { Label("Notes", systemImage: "note.text") }
      FilesSettingsView()
        .tabItem { Label("Files", systemImage: "folder") }
      KeybindsSettingsView()
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
