import PhotonCore
import SwiftUI

struct AppearanceSettingsView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Form {
      Section("Launcher") {
        Toggle("Show suggestions before typing", isOn: $settings.launcherShowsSuggestions)
        Text(
          "On: the launcher opens with your most used apps and commands. "
            + "Off: it stays a single search field until you type."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Picker("Panel width", selection: $settings.launcherPanelWidth) {
          ForEach(LauncherPanelWidth.allCases) { width in
            Text(width.title).tag(width)
          }
        }
        .pickerStyle(.segmented)
        Button("Reset launcher position to center") {
          settings.resetLauncherPositionToCenter()
        }
        Text(
          "Hold your launcher shortcut and drag the search bar to move the panel. "
            + "Vertical dotted guides mark the horizontal center for snapping."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Appearance") {
        Picker("Appearance", selection: $settings.appearance) {
          ForEach(AppAppearance.allCases) { appearance in
            Text(appearance.title).tag(appearance)
          }
        }
        .pickerStyle(.segmented)
        Text("Applies to the launcher, notes, and this window.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Appearance")
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
