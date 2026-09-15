import SwiftUI

struct SettingsRootView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    TabView(selection: $settings.selectedPane) {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(SettingsPaneID.general)
      AppearanceSettingsView()
        .tabItem { Label("Appearance", systemImage: "paintpalette") }
        .tag(SettingsPaneID.appearance)
      ClipboardSettingsView()
        .tabItem { Label("Clipboard", systemImage: "clipboard") }
        .tag(SettingsPaneID.clipboard)
      NotesSettingsView()
        .tabItem { Label("Notes", systemImage: "note.text") }
        .tag(SettingsPaneID.notes)
      FilesSettingsView()
        .tabItem { Label("Files", systemImage: "folder") }
        .tag(SettingsPaneID.files)
      KeybindsSettingsView()
        .tabItem { Label("Keybinds", systemImage: "keyboard") }
        .tag(SettingsPaneID.keybinds)
      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
        .tag(SettingsPaneID.about)
    }
    .environmentObject(settings)
    .padding(20)
    .onAppear {
      if let pending = settings.pendingSettingsPane {
        settings.selectedPane = Self.resolve(pending)
        settings.pendingSettingsPane = nil
      }
    }
  }

  private static func resolve(_ pane: SettingsPaneID) -> SettingsPaneID {
    pane
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
