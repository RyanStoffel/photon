import PhotonCore
import SwiftUI

/// Raycast-style calculator / unit conversion hero inside the launcher list.
struct LauncherCalculatorHeroSection: View {
  let model: CalculatorDisplayModel
  let selected: Bool
  var onSelect: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: LauncherLayout.calculatorSectionSpacing) {
      Text(CalculatorDisplayModel.sectionTitle)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)

      HStack(spacing: 0) {
        expressionColumn
        arrowColumn
        resultColumn
      }
      .frame(height: LauncherLayout.calculatorCardHeight)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.primary.opacity(selected ? 0.1 : 0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color.primary.opacity(selected ? 0.14 : 0.08), lineWidth: 1)
      )
      .contentShape(Rectangle())
      .onTapGesture {
        onSelect()
      }
    }
    .padding(.horizontal, 4)
    .padding(.bottom, LauncherLayout.listInset)
  }

  private var expressionColumn: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(model.expression)
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      captionPill(model.expressionCaption)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, 16)
    .padding(.trailing, 8)
  }

  private var arrowColumn: some View {
    Image(systemName: "arrow.right")
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.secondary)
      .frame(width: 28)
  }

  private var resultColumn: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(model.value)
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      if let caption = model.valueCaption {
        captionPill(caption)
      } else {
        Color.clear.frame(height: 22)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, 8)
    .padding(.trailing, 16)
  }

  private func captionPill(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(Color.primary.opacity(0.08))
      )
  }
}
