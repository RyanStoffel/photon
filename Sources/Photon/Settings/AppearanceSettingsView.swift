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
          "Drag the top or side chrome to move the panel. Dotted guides mark the left and right "
            + "edges of a centered panel; the panel snaps horizontally when its midpoint sits between them."
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
