import Foundation

/// `mdfind` command line, matching how Raycast talks to Spotlight: a metadata
/// query plus `-onlyin` folders (home by default). No filesystem walk.
enum MdfindInvocation: Sendable {
  static let executable = "/usr/bin/mdfind"

  /// Arguments after the executable. `-0` emits NUL-separated paths so names
  /// with spaces and newlines stay intact.
  static func arguments(queryString: String, onlyIn: [String]) -> [String] {
    arguments(queryString: queryString, fileName: nil, onlyIn: onlyIn)
  }

  /// Filename/basename fallback (`mdfind -name`) used when the metadata
  /// predicate misses underscore-tokenized names such as `Ember_Individual_Pitch.pdf`.
  static func nameArguments(fileName: String, onlyIn: [String]) -> [String] {
    arguments(queryString: nil, fileName: fileName, onlyIn: onlyIn)
  }

  static func arguments(queryString: String?, fileName: String?, onlyIn: [String]) -> [String] {
    var args: [String] = []
    for folder in onlyIn {
      args.append("-onlyin")
      args.append(folder)
    }
    if let fileName {
      args.append("-name")
      args.append(fileName)
    }
    args.append("-0")
    if let queryString {
      args.append(queryString)
    } else if let fileName {
      args.append(fileName)
    }
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
        if zero > start, let path = String(data: data[start ..< zero], encoding: .utf8), !path.isEmpty {
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
