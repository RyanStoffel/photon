#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: create-preview-fixtures.swift <pdf-path> <image-path>\n", stderr)
  exit(2)
}

final class FixtureView: NSView {
  let title: String

  init(size: NSSize, title: String) {
    self.title = title
    super.init(frame: NSRect(origin: .zero, size: size))
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    dirtyRect.fill()
    title.draw(
      at: NSPoint(x: 72, y: bounds.midY),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .bold),
        .foregroundColor: NSColor.black,
      ]
    )
    "Quick Look runtime fixture".draw(
      at: NSPoint(x: 72, y: bounds.midY - 48),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 18),
        .foregroundColor: NSColor.darkGray,
      ]
    )
  }
}

let pdfURL = URL(fileURLWithPath: CommandLine.arguments[1])
let imageURL = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(
  at: pdfURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)

let pdfView = FixtureView(size: NSSize(width: 612, height: 792), title: "EMBER PDF PREVIEW")
try pdfView.dataWithPDF(inside: pdfView.bounds).write(to: pdfURL)

let imageView = FixtureView(size: NSSize(width: 640, height: 420), title: "PHOTON IMAGE PREVIEW")
let bitmap = imageView.bitmapImageRepForCachingDisplay(in: imageView.bounds)!
imageView.cacheDisplay(in: imageView.bounds, to: bitmap)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  throw CocoaError(.fileWriteUnknown)
}
try png.write(to: imageURL)
