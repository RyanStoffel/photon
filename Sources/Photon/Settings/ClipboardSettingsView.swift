import AppKit
import PhotonClipboard
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var clipboard: ClipboardManager

  @State private var newBundleID = ""
  @State private var isConfirmingClear = false

  var body: some View {
    Form {
      historySection
      pasteSection
      shortcutSection
      excludedAppsSection
      storageSection
    }
    .formStyle(.grouped)
    .navigationTitle("Clipboard")
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      clipboard.refreshAccessibility()
    }
    .confirmationDialog(
      "Clear clipboard history?",
      isPresented: $isConfirmingClear,
      titleVisibility: .visible
    ) {
      Button("Clear \(clipboard.items.count) Items", role: .destructive) {
        clipboard.clearAll()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes every item, including pinned ones. It cannot be undone.")
    }
  }

  private var historySection: some View {
    Section("History") {
      Toggle("Save clipboard history", isOn: $settings.clipboardEnabled)
      Picker("Keep items for", selection: $settings.clipboardRetention) {
        ForEach(ClipboardRetention.allCases) { retention in
          Text(retention.label).tag(retention)
        }
      }
      .disabled(!settings.clipboardEnabled)
      Stepper(
        value: $settings.clipboardMaxItems,
        in: ClipboardSettings.maxItemsRange,
        step: 50
      ) {
        HStack {
          Text("Maximum items")
          Spacer()
          Text("\(settings.clipboardMaxItems)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      .disabled(!settings.clipboardEnabled)
      Text("Pinned items never expire and do not count against the limit.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var pasteSection: some View {
    Section("Paste") {
      Picker("Return key", selection: $settings.clipboardPasteBehavior) {
        ForEach(ClipboardPasteBehavior.allCases) { behavior in
          Text(behavior.label).tag(behavior)
        }
      }
      Text("Cmd+Return always copies without pasting.")
        .font(.caption)
        .foregroundStyle(.secondary)
      if settings.clipboardPasteBehavior == .paste {
        accessibilityStatus
      }
    }
  }

  private var accessibilityStatus: some View {
    let trusted = clipboard.isAccessibilityTrusted
    return HStack(spacing: 8) {
      Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(trusted ? .green : .orange)
      Text(
        trusted
          ? "Accessibility access granted. Photon can paste into the frontmost app."
          : "Pasting needs Accessibility access. Until it is granted, Return only copies."
      )
      .font(.caption)
      Spacer()
      if !trusted {
        Button("Open Accessibility Settings") {
          clipboard.requestAccessibility()
          clipboard.openAccessibilitySettings()
        }
      }
    }
  }

  private var shortcutSection: some View {
    Section("Shortcut") {
      Toggle("Open clipboard history with a shortcut", isOn: $settings.clipboardHotkeyEnabled)
        .disabled(!settings.clipboardEnabled)
      HStack {
        Text("Shortcut")
        Spacer()
        HotkeyRecorder(combo: $settings.clipboardHotkey)
          .frame(width: 180, height: 24)
      }
      Text("You can also type \"cb\" or \"clipboard\" followed by a space in the launcher.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var excludedAppsSection: some View {
    Section {
      if settings.clipboardExcludedBundleIDs.isEmpty {
        Text("No excluded apps. Everything you copy is recorded.")
          .foregroundStyle(.secondary)
      }
      ForEach(settings.clipboardExcludedBundleIDs, id: \.self) { bundleID in
        HStack(spacing: 10) {
          Image(nsImage: AppIconCache.shared.icon(forBundleID: bundleID))
            .resizable()
            .frame(width: 20, height: 20)
          VStack(alignment: .leading, spacing: 1) {
            Text(AppIconCache.shared.appName(forBundleID: bundleID))
            Text(bundleID)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            removeExcluded(bundleID)
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
          .help("Remove")
        }
      }
      HStack {
        TextField("Bundle identifier, e.g. com.example.app", text: $newBundleID)
          .textFieldStyle(.roundedBorder)
          .onSubmit(addTypedBundleID)
        Button("Add", action: addTypedBundleID)
          .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Choose App…", action: chooseApp)
      }
    } header: {
      Text("Excluded apps")
    } footer: {
      Text(
        "Nothing copied while one of these apps is frontmost is recorded. "
          + "Password managers are excluded by default."
      )
    }
  }

  private var storageSection: some View {
    Section("Storage") {
      HStack {
        Text("History")
        Spacer()
        Text("\(clipboard.items.count) items · \(formattedBytes(clipboard.storageBytes))")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      HStack {
        Text("Stored in ~/Library/Application Support/Photon/Clipboard")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Clear History…", role: .destructive) {
          isConfirmingClear = true
        }
        .disabled(clipboard.items.isEmpty)
      }
    }
  }

  // MARK: Actions

  private func addTypedBundleID() {
    let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }
    addExcluded(trimmed)
    newBundleID = ""
  }

  private func addExcluded(_ bundleID: String) {
    let exists = settings.clipboardExcludedBundleIDs.contains {
      $0.caseInsensitiveCompare(bundleID) == .orderedSame
    }
    guard !exists else {
      return
    }
    settings.clipboardExcludedBundleIDs.append(bundleID)
  }

  private func removeExcluded(_ bundleID: String) {
    settings.clipboardExcludedBundleIDs.removeAll { $0 == bundleID }
  }

  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.title = "Exclude an app from clipboard history"
    panel.prompt = "Exclude"
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    guard panel.runModal() == .OK else {
      return
    }
    for url in panel.urls {
      if let bundleID = Bundle(url: url)?.bundleIdentifier {
        addExcluded(bundleID)
      }
    }
  }

  private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
