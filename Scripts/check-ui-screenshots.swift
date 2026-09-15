#!/usr/bin/env swift

import AppKit
import Foundation

enum ScreenshotFailure: Error, CustomStringConvertible {
  case invalid(String)

  var description: String {
    switch self {
    case let .invalid(message):
      message
    }
  }
}

func bitmap(at path: String) throws -> NSBitmapImageRep {
  guard let image = NSImage(contentsOfFile: path),
        let data = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: data)
  else {
    throw ScreenshotFailure.invalid("Could not decode \(path)")
  }
  return bitmap
}

func resemblesTrafficLight(_ color: NSColor) -> Bool {
  guard let rgb = color.usingColorSpace(.deviceRGB) else {
    return false
  }
  let red = rgb.redComponent
  let green = rgb.greenComponent
  let blue = rgb.blueComponent
  let opaque = rgb.alphaComponent > 0.7
  let close = red > 0.75 && green < 0.45 && blue < 0.45
  let minimize = red > 0.75 && green > 0.45 && green < 0.8 && blue < 0.35
  let zoom = green > 0.55 && red < 0.45 && blue < 0.55
  return opaque && (close || minimize || zoom)
}

do {
  guard CommandLine.arguments.count > 1 else {
    throw ScreenshotFailure.invalid("usage: check-ui-screenshots.swift <png> [...]")
  }
  for path in CommandLine.arguments.dropFirst() {
    let image = try bitmap(at: path)
    let scanWidth = min(110, image.pixelsWide)
    let scanHeight = min(42, image.pixelsHigh)
    var trafficPixels = 0
    for y in 0 ..< scanHeight {
      for x in 0 ..< scanWidth {
        if let color = image.colorAt(x: x, y: y), resemblesTrafficLight(color) {
          trafficPixels += 1
        }
      }
    }
    if trafficPixels > 20 {
      throw ScreenshotFailure.invalid(
        "\(path) contains \(trafficPixels) traffic-light-like pixels in its title-bar region"
      )
    }
    // CI captures Retina pixels and includes the panel shadow. The compact
    // 89-point panel is currently about 275 px; the old clipped overlay was
    // several hundred points tall.
    if path.contains("launcher-empty-"), image.pixelsHigh > 320 {
      throw ScreenshotFailure.invalid(
        "\(path) is \(image.pixelsHigh) px tall; compact launcher must remain under 320 Retina px"
      )
    }
    print("PASS: \(path) has no traffic-light chrome and valid compact sizing")
  }
} catch {
  fputs("SCREENSHOT CHECK FAILED: \(error)\n", stderr)
  exit(1)
}
