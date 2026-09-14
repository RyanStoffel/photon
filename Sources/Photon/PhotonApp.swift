import AppKit
import SwiftUI

@main
struct PhotonApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsRootView()
        .environmentObject(appDelegate.runtime.settings)
        .frame(minWidth: 560, minHeight: 400)
    }

    MenuBarExtra("Photon", systemImage: "sun.max.fill") {
      Button("Open Launcher") {
        appDelegate.runtime.toggleLauncher()
      }
      Button("Settings…") {
        appDelegate.runtime.openSettings()
      }
      Divider()
      Button("Quit Photon") {
        NSApp.terminate(nil)
      }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = AppRuntime()

  func applicationDidFinishLaunching(_: Notification) {
    runtime.start()
  }

  func applicationWillTerminate(_: Notification) {
    runtime.stop()
  }
}
