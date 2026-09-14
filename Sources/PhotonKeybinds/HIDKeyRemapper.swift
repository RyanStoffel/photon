import Foundation

public enum HIDRemapError: LocalizedError {
  case hidutilMissing
  case failed(status: Int32, output: String)

  public var errorDescription: String? {
    switch self {
    case .hidutilMissing:
      return "hidutil is missing from /usr/bin. Photon cannot remap the Hyper key on this system."
    case let .failed(status, output):
      let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
      return "hidutil exited with status \(status)." + (detail.isEmpty ? "" : " \(detail)")
    }
  }
}

/// Remaps a physical key to F18 for the current login session using `hidutil`, the same mechanism
/// Hyperkey-style apps use. Mappings are not persistent: logging out clears them, and Photon removes
/// its own entries on quit or when the Hyper key is disabled. Other tools' entries are preserved.
public enum HIDKeyRemapper {
  static let hidutilPath = "/usr/bin/hidutil"

  /// Photon only ever maps one of these to F18, so these are the only entries it will remove.
  static var ownedSources: Set<UInt64> {
    Set(HyperKeySource.allCases.compactMap(\.hidUsage))
  }

  public static func currentMapping() throws -> [HIDKeyMappingPair] {
    let output = try run(["property", "--get", HIDKeyMapping.propertyKey])
    return HIDKeyMapping.parse(hidutilOutput: output)
  }

  /// Maps `source` to F18, replacing any Photon mapping for a different source.
  public static func install(source: UInt64) throws {
    let existing = try currentMapping()
    let cleaned = HIDKeyMapping.removing(
      sources: ownedSources,
      destination: HyperKeySource.destinationUsage,
      from: existing
    )
    let pair = HIDKeyMappingPair(source: source, destination: HyperKeySource.destinationUsage)
    let merged = HIDKeyMapping.merging(cleaned, with: pair)
    if merged != existing {
      try apply(merged)
    }
  }

  /// Removes every Photon mapping. Safe to call when nothing is mapped.
  public static func removeAll() throws {
    let existing = try currentMapping()
    let cleaned = HIDKeyMapping.removing(
      sources: ownedSources,
      destination: HyperKeySource.destinationUsage,
      from: existing
    )
    if cleaned != existing {
      try apply(cleaned)
    }
  }

  /// True when a Photon mapping is present in the current session.
  public static func isInstalled(source: UInt64) -> Bool {
    guard let existing = try? currentMapping() else {
      return false
    }
    return existing.contains(HIDKeyMappingPair(source: source, destination: HyperKeySource.destinationUsage))
  }

  private static func apply(_ pairs: [HIDKeyMappingPair]) throws {
    _ = try run(["property", "--set", HIDKeyMapping.propertyArgument(for: pairs)])
  }

  private static func run(_ arguments: [String]) throws -> String {
    guard FileManager.default.isExecutableFile(atPath: hidutilPath) else {
      throw HIDRemapError.hidutilMissing
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: hidutilPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(bytes: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw HIDRemapError.failed(status: process.terminationStatus, output: output)
    }
    return output
  }
}
