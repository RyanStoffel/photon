import AppKit
import SwiftUI

struct HotkeyRecorder: NSViewRepresentable {
  @Binding var combo: HotkeyCombo

  func makeNSView(context _: Context) -> HotkeyRecorderView {
    let view = HotkeyRecorderView()
    view.combo = combo
    view.onChange = { combo = $0 }
    return view
  }

  func updateNSView(_ nsView: HotkeyRecorderView, context _: Context) {
    nsView.combo = combo
    nsView.onChange = { combo = $0 }
    nsView.refresh()
  }
}

/// Recorder for an optional shortcut. Shows "None" when unset; Delete while recording clears it.
struct OptionalHotkeyRecorder: NSViewRepresentable {
  @Binding var combo: HotkeyCombo?

  func makeNSView(context _: Context) -> HotkeyRecorderView {
    let view = HotkeyRecorderView()
    view.allowsClear = true
    view.combo = combo
    view.onChange = { combo = $0 }
    view.onClear = { combo = nil }
    return view
  }

  func updateNSView(_ nsView: HotkeyRecorderView, context _: Context) {
    nsView.combo = combo
    nsView.onChange = { combo = $0 }
    nsView.onClear = { combo = nil }
    nsView.refresh()
  }
}

final class HotkeyRecorderView: NSView {
  var combo: HotkeyCombo? = .defaultCombo
  var onChange: ((HotkeyCombo) -> Void)?
  var onClear: (() -> Void)?
  var allowsClear = false
  private var recording = false
  private let button = NSButton(title: "", target: nil, action: nil)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    button.bezelStyle = .rounded
    button.setButtonType(.momentaryPushIn)
    button.target = self
    button.action = #selector(toggle)
    button.translatesAutoresizingMaskIntoConstraints = false
    addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.topAnchor.constraint(equalTo: topAnchor),
      button.bottomAnchor.constraint(equalTo: bottomAnchor),
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
    ])
    refresh()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  func refresh() {
    button.title = recording ? "Press a shortcut" : combo?.displayString ?? "None"
  }

  @objc
  private func toggle() {
    recording.toggle()
    if recording {
      window?.makeFirstResponder(self)
    }
    refresh()
  }

  override func keyDown(with event: NSEvent) {
    guard recording else {
      super.keyDown(with: event)
      return
    }
    if event.keyCode == UInt16(kVKEscape) {
      recording = false
      refresh()
      return
    }
    if allowsClear, event.keyCode == UInt16(kVKDelete) || event.keyCode == UInt16(kVKForwardDelete) {
      combo = nil
      onClear?()
      recording = false
      refresh()
      return
    }
    let flags = UInt32(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
    let carbon = HotkeyCombo.carbonModifiers(fromApple: flags)
    guard carbon != 0 else {
      return
    }
    let next = HotkeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    combo = next
    onChange?(next)
    recording = false
    refresh()
  }

  override func flagsChanged(with event: NSEvent) {
    if recording {
      return
    }
    super.flagsChanged(with: event)
  }
}

private let kVKEscape: Int = 53
private let kVKDelete: Int = 51
private let kVKForwardDelete: Int = 117
