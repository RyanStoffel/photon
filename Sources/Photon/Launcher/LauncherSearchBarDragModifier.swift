import AppKit
import SwiftUI

/// Drag the launcher by its search bar chrome. No modifier keys required; mouse-up
/// always ends the drag and hides snap guides.
struct LauncherSearchBarDragModifier: ViewModifier {
  let onSearchBarDrag: ((LauncherSearchBarDragPhase) -> Void)?

  @State private var dragActive = false

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .highPriorityGesture(dragGesture)
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        guard onSearchBarDrag != nil else {
          return
        }
        if !dragActive {
          dragActive = true
          onSearchBarDrag?(.began)
        }
        onSearchBarDrag?(.changed(translation: value.translation))
      }
      .onEnded { value in
        guard dragActive else {
          return
        }
        onSearchBarDrag?(.changed(translation: value.translation))
        onSearchBarDrag?(.ended)
        dragActive = false
      }
  }
}

extension View {
  func launcherSearchBarDrag(onSearchBarDrag: ((LauncherSearchBarDragPhase) -> Void)?) -> some View {
    modifier(LauncherSearchBarDragModifier(onSearchBarDrag: onSearchBarDrag))
  }
}
