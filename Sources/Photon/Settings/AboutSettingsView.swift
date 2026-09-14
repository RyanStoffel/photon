import AppKit
import PhotonCore
import SwiftUI

struct AboutSettingsView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
      Text("Photon")
        .font(.title.weight(.semibold))
      Text("Version \(PhotonVersion.string)")
        .foregroundStyle(.secondary)
      Text("com.ryanstoffel.photon")
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
      Text("A small, fast macOS launcher.")
        .multilineTextAlignment(.center)
      Link("github.com/RyanStoffel/photon", destination: Self.repositoryURL)
      Text("Copyright 2026 Ryan Stoffel. MIT License.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }

  private static let repositoryURL = URL(string: "https://github.com/RyanStoffel/photon")!
}
