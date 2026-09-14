import PhotonKeybinds
import SwiftUI

struct KeybindsSettingsView: View {
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var keybinds: KeybindsController

  var body: some View {
    Form {
      permissionsSection
      hyperKeySection
      AppHotkeysSection()
      WindowCommandsSection()
    }
    .formStyle(.grouped)
    .navigationTitle("Keybinds")
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      keybinds.refreshPermissions()
    }
  }

  private var permissionsSection: some View {
    Section("Permissions") {
      PermissionRow(
        title: "Accessibility",
        detail: "Required for the Hyper key and window management.",
        granted: keybinds.accessibilityGranted,
        action: { keybinds.requestAccessibility() }
      )
      PermissionRow(
        title: "Input Monitoring",
        detail: "Optional. macOS may ask for it the first time the Hyper key is enabled.",
        granted: keybinds.inputMonitoringGranted,
        action: { AccessibilityPermission.openInputMonitoringSettings() }
      )
    }
  }

  private var hyperKeySection: some View {
    Section {
      Toggle("Enable Hyper key", isOn: $settings.keybinds.hyperKey.enabled)
        .onChange(of: settings.keybinds.hyperKey.enabled) { _, enabled in
          if enabled, !keybinds.accessibilityGranted {
            keybinds.requestAccessibility()
          }
        }
      Picker("Key", selection: $settings.keybinds.hyperKey.source) {
        ForEach(HyperKeySource.allCases) { source in
          Text(source.title).tag(source)
        }
      }
      .disabled(!settings.keybinds.hyperKey.enabled)
      Picker("On tap", selection: $settings.keybinds.hyperKey.tapBehavior) {
        ForEach(HyperTapBehavior.allCases) { behavior in
          Text(behavior.title).tag(behavior)
        }
      }
      .disabled(!settings.keybinds.hyperKey.enabled)
      statusRow
    } header: {
      Text("Hyper key")
    } footer: {
      Text(
        "Holding the key acts as Control + Option + Shift + Command, shown as ✦. "
          + "The remap only exists while Photon runs and is removed when Photon quits or the Hyper key is turned off."
      )
    }
  }

  private var statusRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
        Text(statusText)
          .foregroundStyle(.secondary)
        Spacer()
        statusAction
      }
      if let lastError = keybinds.lastError {
        Text(lastError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  @ViewBuilder
  private var statusAction: some View {
    switch keybinds.hyperStatus {
    case .needsAccessibility:
      Button("Grant Access") {
        keybinds.requestAccessibility()
      }
    case .failed:
      Button("Reset Key Mapping") {
        keybinds.resetKeyMapping()
      }
    case .disabled, .active:
      EmptyView()
    }
  }

  private var statusText: String {
    switch keybinds.hyperStatus {
    case .disabled:
      "Off. The key keeps its normal behaviour."
    case .needsAccessibility:
      "Waiting for Accessibility access. The key keeps its normal behaviour until then."
    case let .active(source):
      "Active. \(source.title) is the Hyper key while Photon runs."
    case let .failed(message):
      message
    }
  }

  private var statusColor: Color {
    switch keybinds.hyperStatus {
    case .disabled: .secondary
    case .needsAccessibility: .orange
    case .active: .green
    case .failed: .red
    }
  }
}

private struct PermissionRow: View {
  let title: String
  let detail: String
  let granted: Bool
  let action: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Circle()
        .fill(granted ? Color.green : Color.orange)
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if granted {
        Text("Granted")
          .foregroundStyle(.secondary)
      } else {
        Button("Open System Settings", action: action)
      }
    }
  }
}
