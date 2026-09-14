// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Photon",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "PhotonCore", targets: ["PhotonCore"]),
  ],
  targets: [
    .target(name: "PhotonCore"),
    .testTarget(name: "PhotonCoreTests", dependencies: ["PhotonCore"]),
    // AppKit-backed files in PhotonClipboard are wrapped in `#if canImport(AppKit)`,
    // so the models, history rules, search, and store compile and test on Linux.
    .target(name: "PhotonClipboard", dependencies: ["PhotonCore"]),
    .testTarget(name: "PhotonClipboardTests", dependencies: ["PhotonClipboard"]),
  ]
)

#if os(macOS)
package.products.append(.executable(name: "Photon", targets: ["Photon"]))
package.targets.append(contentsOf: [
  .target(name: "PhotonApps", dependencies: ["PhotonCore"]),
  .target(name: "PhotonNotes", dependencies: ["PhotonCore"]),
  .target(name: "PhotonFiles", dependencies: ["PhotonCore"]),
  .testTarget(name: "PhotonFilesTests", dependencies: ["PhotonFiles"]),
  .target(name: "PhotonKeybinds", dependencies: ["PhotonCore"]),
  .executableTarget(
    name: "Photon",
    dependencies: [
      "PhotonCore",
      "PhotonApps",
      "PhotonClipboard",
      "PhotonNotes",
      "PhotonFiles",
      "PhotonKeybinds",
    ]
  ),
])
#endif
