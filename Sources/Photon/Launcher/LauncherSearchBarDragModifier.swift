import AppKit
import SwiftUI

struct LauncherSearchBarDragModifier: ViewModifier {
  let hotkey: HotkeyCombo
  let onSearchBarDrag: ((LauncherSearchBarDragPhase) -> Void)?

  @State private var dragActive = false

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .highPriorityGesture(
        DragGesture(minimumDistance: 2)
          .onChanged { value in
            guard onSearchBarDrag != nil else {
              return
            }
            if !dragActive {
              guard hotkey.holdsRequiredModifiers(NSEvent.modifierFlags) else {
                return
              }
              dragActive = true
              onSearchBarDrag?(.began)
            }
            if dragActive {
              onSearchBarDrag?(.changed(translation: value.translation))
            }
          }
          .onEnded { value in
            guard dragActive else {
              return
            }
            dragActive = false
            onSearchBarDrag?(.changed(translation: value.translation))
            onSearchBarDrag?(.ended)
          }
      )
  }
}

extension View {
  func launcherSearchBarDrag(
    hotkey: HotkeyCombo,
    onSearchBarDrag: ((LauncherSearchBarDragPhase) -> Void)?
  ) -> some View {
    modifier(LauncherSearchBarDragModifier(hotkey: hotkey, onSearchBarDrag: onSearchBarDrag))
  }
}
