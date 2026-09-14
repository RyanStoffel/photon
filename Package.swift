// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Photon",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "PhotonCore", targets: ["PhotonCore"])
  ],
  targets: [
    .target(name: "PhotonCore"),
    .testTarget(name: "PhotonCoreTests", dependencies: ["PhotonCore"]),
  ]
)

#if os(macOS)
package.products.append(.executable(name: "Photon", targets: ["Photon"]))
package.targets.append(.executableTarget(name: "Photon"))
#endif
