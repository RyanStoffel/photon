import SwiftUI

enum LauncherSearchBarDragPhase: Equatable {
  case began
  case changed(translation: CGSize)
  case ended
}
