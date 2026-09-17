import AppKit

/// Full-height vertical guides shown while repositioning the launcher.
@MainActor
final class LauncherCenterGuidesOverlay {
  private var window: NSWindow?

  var isVisible: Bool {
    window?.isVisible == true
  }

  /// Screen-space span between the two guides from the most recent `show` call.
  private(set) var lastGuideSpan: CGFloat = 0

  func show(visibleFrame: NSRect, guideXLeft: CGFloat, guideXRight: CGFloat) {
    lastGuideSpan = abs(guideXRight - guideXLeft)
    hide()
    let window = NSWindow(
      contentRect: visibleFrame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.ignoresMouseEvents = true
    let view = GuidesView(frame: NSRect(origin: .zero, size: visibleFrame.size))
    view.guideXLeft = guideXLeft - visibleFrame.minX
    view.guideXRight = guideXRight - visibleFrame.minX
    window.contentView = view
    window.orderFrontRegardless()
    self.window = window
  }

  func hide() {
    window?.orderOut(nil)
    window = nil
  }
}

private final class GuidesView: NSView {
  var guideXLeft: CGFloat = 0
  var guideXRight: CGFloat = 0

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
    let pattern: [CGFloat] = [4, 4]
    let path = NSBezierPath()
    path.lineWidth = 1
    path.setLineDash(pattern, count: 2, phase: 0)
    path.move(to: NSPoint(x: guideXLeft, y: bounds.minY))
    path.line(to: NSPoint(x: guideXLeft, y: bounds.maxY))
    path.move(to: NSPoint(x: guideXRight, y: bounds.minY))
    path.line(to: NSPoint(x: guideXRight, y: bounds.maxY))
    path.stroke()
  }
}
