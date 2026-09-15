#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: native-paste-target.swift <value-file> <command-file>\n", stderr)
  exit(2)
}

@MainActor
final class PasteTargetDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
  private let valueURL = URL(fileURLWithPath: CommandLine.arguments[1])
  private let commandURL = URL(fileURLWithPath: CommandLine.arguments[2])
  private let field = NSTextField(frame: NSRect(x: 24, y: 52, width: 432, height: 28))
  private var window: NSWindow?
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
    self.window = window
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeFirstResponder(field)
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.writeValue()
        self?.handleCommand()
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

  private func handleCommand() {
    guard FileManager.default.fileExists(atPath: commandURL.path) else {
      return
    }
    try? FileManager.default.removeItem(at: commandURL)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    window?.makeFirstResponder(field)
    let expected = NSPasteboard.general.string(forType: .string)
    if field.stringValue != expected {
      field.currentEditor()?.paste(nil)
    }
    writeValue()
  }
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated {
  PasteTargetDelegate()
}

application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
