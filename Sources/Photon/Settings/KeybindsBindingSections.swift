import AppKit
import PhotonKeybinds
import SwiftUI
import UniformTypeIdentifiers

/// User-defined shortcuts that launch, focus, or hide an application.
struct AppHotkeysSection: View {
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var keybinds: KeybindsController
  @State private var addError: String?

  var body: some View {
    Section {
      if settings.keybinds.appHotkeys.isEmpty {
        Text("No app hotkeys yet. Add an application, then record a shortcut for it.")
          .foregroundStyle(.secondary)
      }
      ForEach($settings.keybinds.appHotkeys) { $hotkey in
        AppHotkeyRow(
          hotkey: $hotkey,
          conflict: conflicts.contains(.app(hotkey.id)),
          failure: hotkey.shortcut.flatMap { keybinds.registrationFailures[$0] },
          onRemove: { remove(hotkey.id) }
        )
      }
      HStack {
        Button("Add Application…") {
          addApplication()
        }
        if let addError {
          Text(addError)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    } header: {
      Text("App hotkeys")
    } footer: {
      Text("The shortcut launches or focuses the app. Press it again while the app is frontmost to hide it.")
    }
  }

  private var conflicts: Set<BindingOwner> {
    settings.keybinds.conflictingOwners(launcher: KeyShortcut(settings.hotkey))
  }

  private func remove(_ id: UUID) {
    settings.keybinds.appHotkeys.removeAll { $0.id == id }
  }

  private func addApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Add"
    panel.message = "Choose an application to bind to a shortcut."
    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }
    guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
      addError = "\(url.lastPathComponent) has no bundle identifier."
      return
    }
    addError = nil
    guard !settings.keybinds.appHotkeys.contains(where: { $0.bundleIdentifier == identifier }) else {
      return
    }
    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? url.deletingPathExtension().lastPathComponent
    settings.keybinds.appHotkeys.append(AppHotkey(bundleIdentifier: identifier, name: name))
  }
}

private struct AppHotkeyRow: View {
  @Binding var hotkey: AppHotkey
  let conflict: Bool
  let failure: String?
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(hotkey.name)
        if let failure {
          Text(failure)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      Spacer()
      if conflict {
        ConflictBadge()
      }
      ShortcutField(shortcut: $hotkey.shortcut)
      Button(action: onRemove) {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .help("Remove")
    }
  }

  private var icon: NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hotkey.bundleIdentifier) {
      return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSWorkspace.shared.icon(for: .application)
  }
}

/// Window commands with editable shortcuts.
struct WindowCommandsSection: View {
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var keybinds: KeybindsController

  var body: some View {
    Section {
      ForEach($settings.keybinds.windowBindings) { $binding in
        HStack(spacing: 10) {
          Text(binding.action.title)
          Spacer()
          if conflicts.contains(.window(binding.action)) {
            ConflictBadge()
          }
          if let shortcut = binding.shortcut, let failure = keybinds.registrationFailures[shortcut] {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundStyle(.red)
              .help(failure)
          }
          ShortcutField(shortcut: $binding.shortcut)
        }
      }
      Button("Reset to Defaults") {
        settings.keybinds.resetWindowBindings()
      }
    } header: {
      Text("Window management")
    } footer: {
      Text("Every command is also searchable in the launcher, for example \"Left Half\" or \"Maximize\".")
    }
  }

  private var conflicts: Set<BindingOwner> {
    settings.keybinds.conflictingOwners(launcher: KeyShortcut(settings.hotkey))
  }
}

/// Recorder plus a clear button, bound to an optional `KeyShortcut`.
struct ShortcutField: View {
  @Binding var shortcut: KeyShortcut?
  @EnvironmentObject private var keybinds: KeybindsController

  var body: some View {
    HStack(spacing: 4) {
      OptionalHotkeyRecorder(
        combo: comboBinding,
        title: { KeyShortcut($0).displayString },
        onRecordingChanged: { keybinds.isRecording = $0 }
      )
      .frame(width: 150, height: 24)
      Button {
        shortcut = nil
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help("Clear shortcut")
      .disabled(shortcut == nil)
      .opacity(shortcut == nil ? 0 : 1)
    }
  }

  private var comboBinding: Binding<HotkeyCombo?> {
    Binding(
      get: { shortcut?.hotkeyCombo },
      set: { combo in
        shortcut = combo.map { KeyShortcut($0) }
      }
    )
  }
}

struct ConflictBadge: View {
  var body: some View {
    Image(systemName: "exclamationmark.triangle.fill")
      .foregroundStyle(.orange)
      .help("This shortcut is assigned more than once. Only the first binding fires.")
  }
}
