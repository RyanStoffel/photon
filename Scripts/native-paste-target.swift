#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: native-paste-target.swift <value-file>\n", stderr)
  exit(2)
}

@MainActor
final class PasteTargetDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
  private let valueURL = URL(fileURLWithPath: CommandLine.arguments[1])
  private let field = NSTextField(frame: NSRect(x: 24, y: 52, width: 432, height: 28))
  private var timer: Timer?

  func applicationDidFinishLaunching(_: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Photon Paste Target"
    field.placeholderString = "Photon paste sentinel target"
    field.delegate = self
    window.contentView?.addSubview(field)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeFirstResponder(field)
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.writeValue()
      }
    }
    writeValue()
  }

  func controlTextDidChange(_: Notification) {
    writeValue()
  }

  private func writeValue() {
    try? field.stringValue.write(to: valueURL, atomically: true, encoding: .utf8)
  }
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated {
  PasteTargetDelegate()
}
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
