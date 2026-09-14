import AppKit
import CoreGraphics
import Foundation

struct Options {
  var pid: pid_t?
  var owner: String?
  var layer: Int = 0
  var scenario: String?
}

struct WindowCandidate {
  let id: CGWindowID
  let title: String
  let width: CGFloat
  let height: CGFloat
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
    case "--scenario":
      index += 1
      guard index < args.count else {
        return nil
      }
      options.scenario = args[index]
    default:
      return nil
    }
    index += 1
  }
  return options
}

func bounds(from entry: [String: Any]) -> (CGFloat, CGFloat)? {
  guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? CGFloat,
        let height = bounds["Height"] as? CGFloat
  else {
    return nil
  }
  return (width, height)
}

func matchesScenario(_ candidate: WindowCandidate, scenario: String) -> Bool {
  switch scenario {
  case "launcher-empty", "launcher-query":
    if candidate.title == "Photon Launcher" {
      return true
    }
    return candidate.width >= 520 && candidate.width <= 720 && candidate.height >= 320 && candidate.height <= 520
  case "settings":
    if candidate.title == "General" || candidate.title == "Settings" {
      return candidate.width >= 520
    }
    return false
  case "notes":
    if candidate.title == "Screenshot sample" || candidate.title == "Notes" {
      return true
    }
    return candidate.width >= 260 && candidate.width <= 460 && candidate.height >= 200
  default:
    return true
  }
}

func score(_ candidate: WindowCandidate, scenario: String) -> Int {
  var score = Int(candidate.width * candidate.height)
  switch scenario {
  case "launcher-empty", "launcher-query":
    if candidate.title == "Photon Launcher" {
      score += 1_000_000
    }
  case "settings":
    if candidate.title == "General" {
      score += 1_000_000
    }
  case "notes":
    if candidate.title == "Screenshot sample" {
      score += 1_000_000
    }
  default:
    break
  }
  return score
}

guard let options = parseOptions() else {
  fputs(
    "usage: photon-window-id.swift --pid <pid> [--owner Photon] [--layer 0] [--scenario launcher-empty|settings|notes]\n",
    stderr
  )
  exit(2)
}

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var candidates: [WindowCandidate] = []
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
  guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
        let (width, height) = bounds(from: entry)
  else {
    continue
  }
  let title = entry[kCGWindowName as String] as? String ?? ""
  candidates.append(WindowCandidate(id: windowID, title: title, width: width, height: height))
}

if let scenario = options.scenario {
  let key: String = {
    if scenario.hasPrefix("launcher-query") {
      return "launcher-query"
    }
    if scenario.hasPrefix("settings") {
      return "settings"
    }
    return scenario
  }()
  let filtered = candidates.filter { matchesScenario($0, scenario: key) }
  if let best = filtered.max(by: { score($0, scenario: key) < score($1, scenario: key) }) {
    print(best.id)
    exit(0)
  }
  exit(1)
}

guard let first = candidates.first else {
  exit(1)
}
print(first.id)
