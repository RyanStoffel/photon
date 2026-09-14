import AppKit
import Foundation

struct Options {
  var pid: pid_t?
  var owner: String?
  var layer: Int = 0
}

func parseOptions() -> Options? {
  var options = Options()
  var index = 1
  let args = CommandLine.arguments
  while index < args.count {
    switch args[index] {
    case "--pid":
      index += 1
      guard index < args.count, let value = Int32(args[index]) else {
        return nil
      }
      options.pid = pid_t(value)
    case "--owner":
      index += 1
      guard index < args.count else {
        return nil
      }
      options.owner = args[index]
    case "--layer":
      index += 1
      guard index < args.count, let value = Int(args[index]) else {
        return nil
      }
      options.layer = value
    default:
      return nil
    }
    index += 1
  }
  return options
}

guard let options = parseOptions() else {
  fputs("usage: photon-window-id.swift --pid <pid> [--owner Photon] [--layer 0]\n", stderr)
  exit(2)
}

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for entry in list {
  if let windowLayer = entry[kCGWindowLayer as String] as? Int, windowLayer != options.layer {
    continue
  }
  if let pid = options.pid, let windowPID = entry[kCGWindowOwnerPID as String] as? Int32, windowPID != pid {
    continue
  }
  if let owner = options.owner, let windowOwner = entry[kCGWindowOwnerName as String] as? String, windowOwner != owner {
    continue
  }
  if let windowID = entry[kCGWindowNumber as String] as? CGWindowID {
    print(windowID)
  }
}
