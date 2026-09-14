import SwiftUI

struct SettingsRootView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    TabView(selection: $settings.selectedPane) {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(SettingsPaneID.general)
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

  /// `appearance` is valid for branches with an Appearance tab; on `develop` it maps to General.
  private static func resolve(_ pane: SettingsPaneID) -> SettingsPaneID {
    if pane == .appearance {
      return .general
    }
    return pane
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
