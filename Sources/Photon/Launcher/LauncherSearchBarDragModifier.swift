import AppKit
import PhotonCore
import SwiftUI

/// Drag the launcher by its search bar chrome. The gesture only starts the
/// move; AppKit then tracks screen-space mouse location until mouse-up so the
/// panel follows the pointer instead of SwiftUI's view-local translation.
struct LauncherSearchBarDragModifier: ViewModifier {
  let onSearchBarDrag: ((LauncherSearchBarDragPhase) -> Void)?

  @State private var dragActive = false

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .simultaneousGesture(dragGesture)
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: LauncherLayout.panelDragSlop)
      .onChanged { _ in
        guard onSearchBarDrag != nil else {
          return
        }
        if !dragActive {
          dragActive = true
          onSearchBarDrag?(.began)
        }
      }
      .onEnded { _ in
        dragActive = false
      }
  }
}

extension View {
  func launcherSearchBarDrag(onSearchBarDrag: ((LauncherSearchBarDragPhase) -> Void)?) -> some View {
    modifier(LauncherSearchBarDragModifier(onSearchBarDrag: onSearchBarDrag))
  }
}
