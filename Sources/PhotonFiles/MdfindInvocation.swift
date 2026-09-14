import Foundation

/// `mdfind` command line, matching how Raycast talks to Spotlight: a metadata
/// query plus `-onlyin` folders (home by default). No filesystem walk.
enum MdfindInvocation: Sendable {
  static let executable = "/usr/bin/mdfind"

  /// Arguments after the executable. `-0` emits NUL-separated paths so names
  /// with spaces and newlines stay intact.
  static func arguments(queryString: String, onlyIn: [String]) -> [String] {
    var args: [String] = []
    for folder in onlyIn {
      args.append("-onlyin")
      args.append(folder)
    }
    args.append("-0")
    args.append(queryString)
    return args
  }

  static func paths(fromNullTerminated data: Data, limit: Int) -> [String] {
    guard limit > 0, !data.isEmpty else {
      return []
    }
    var paths: [String] = []
    var start = data.startIndex
    while start < data.endIndex, paths.count < limit {
      if let zero = data[start...].firstIndex(of: 0) {
        if zero > start, let path = String(data: data[start..<zero], encoding: .utf8), !path.isEmpty {
          paths.append(path)
        }
        start = data.index(after: zero)
      } else {
        if let path = String(data: data[start...], encoding: .utf8), !path.isEmpty {
          paths.append(path)
        }
        break
      }
    }
    return paths
  }
}
