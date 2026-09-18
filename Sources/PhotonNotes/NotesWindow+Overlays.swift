import AppKit
import SwiftUI

struct NotesOverlayView: View {
  let kind: NotesWindow.OverlayKind
  @ObservedObject var switcher: NoteSwitcherModel
  @ObservedObject var actions: NoteActionsModel
  var onDismiss: () -> Void
  var onStyle: (MarkdownFormatStyle) -> Void

  var body: some View {
    ZStack {
      if kind == .switcher || kind == .actions {
        Color.black.opacity(0.2)
          .ignoresSafeArea()
          .onTapGesture(perform: onDismiss)
        VStack {
          Spacer().frame(height: 88)
          if kind == .switcher {
            NoteSwitcherView(model: switcher)
          }
          if kind == .actions {
            NoteActionsView(model: actions)
          }
          Spacer()
        }
      }
      if kind == .format {
        VStack {
          Spacer()
          NoteFormatBar(onStyle: onStyle, onClose: onDismiss)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(kind != .none)
  }
}

extension NotesWindow {
  func rebuildOverlay() {
    overlayHosting?.removeFromSuperview()
    overlayHosting = nil
    guard overlayKind != .none else {
      overlayContainer.isHidden = true
      return
    }
    let view = NotesOverlayView(
      kind: overlayKind,
      switcher: switcherModel,
      actions: actionsModel,
      onDismiss: { [weak self] in
        self?.dismissOverlay()
      },
      onStyle: { [weak self] style in
        self?.applyFormat(style)
      }
    )
    let host = NSHostingView(rootView: view)
    host.translatesAutoresizingMaskIntoConstraints = false
    overlayContainer.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor),
      host.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
      host.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor),
    ])
    overlayHosting = host
    overlayContainer.isHidden = false
    panel.makeFirstResponder(host)
  }
}
