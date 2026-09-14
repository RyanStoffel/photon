import SwiftUI

struct GeneralSettingsView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Form {
      Section("Hotkey") {
        HStack {
          Text("Open launcher")
          Spacer()
          HotkeyRecorder(combo: $settings.hotkey)
            .frame(width: 180, height: 24)
        }
        Text(
          "Photon registers this shortcut globally. If Spotlight still owns it, disable "
            + "Spotlight’s shortcut under System Settings > Keyboard > Keyboard Shortcuts > Spotlight."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Button("Open Keyboard Settings") {
          SpotlightConflict.openKeyboardSettings()
        }
      }

      Section("Startup") {
        Toggle("Launch at login", isOn: $settings.launchAtLogin)
        if let launchAtLoginError = settings.launchAtLoginError {
          Text(launchAtLoginError)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("General")
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
