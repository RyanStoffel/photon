import AppKit

/// Maps `MarkdownSpan`s onto text storage attributes. Every font derives from one base size.
@MainActor
struct MarkdownTextStyler {
  let baseSize: CGFloat

  var baseFont: NSFont {
    .systemFont(ofSize: baseSize)
  }

  var codeFont: NSFont {
    .monospacedSystemFont(ofSize: (baseSize * 0.92).rounded(), weight: .regular)
  }

  /// The first line of a note, sized like the Notes title style relative to the body.
  var titleFont: NSFont {
    .systemFont(ofSize: (baseSize * 1.7).rounded(), weight: .bold)
  }

  var baseAttributes: [NSAttributedString.Key: Any] {
    [
      .font: baseFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: baseParagraphStyle
    ]
  }

  private var baseParagraphStyle: NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = (baseSize * 0.22).rounded()
    return paragraph
  }

  private var titleParagraphStyle: NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = (baseSize * 0.22).rounded()
    paragraph.paragraphSpacing = (baseSize * 0.5).rounded()
    return paragraph
  }

  /// Resets `range` to the base look, then layers the spans that intersect it.
  func apply(_ spans: [MarkdownSpan], to storage: NSTextStorage, in range: NSRange) {
    storage.setAttributes(baseAttributes, range: range)
    for span in spans {
      let clipped = NSIntersectionRange(span.range, range)
      guard clipped.length > 0 else {
        continue
      }
      var attributes = colorAttributes(for: span.kind)
      if let font = font(for: span.kind, at: clipped.location, in: storage) {
        attributes[.font] = font
      }
      storage.addAttributes(attributes, range: clipped)
      if span.kind == .title {
        let paragraph = (storage.string as NSString).paragraphRange(for: clipped)
        storage.addAttribute(.paragraphStyle, value: titleParagraphStyle, range: paragraph)
      }
    }
  }

  func headingFont(level: Int) -> NSFont {
    let scales: [CGFloat] = [1.5, 1.3, 1.15, 1.05, 1, 1]
    let index = max(0, min(level - 1, scales.count - 1))
    return .systemFont(ofSize: (baseSize * scales[index]).rounded(), weight: level <= 2 ? .bold : .semibold)
  }

  private func font(for kind: MarkdownSpanKind, at location: Int, in storage: NSTextStorage) -> NSFont? {
    switch kind {
    case .title:
      return titleFont
    case let .heading(level), let .headingMarker(level):
      return headingFont(level: level)
    case .bold:
      return font(at: location, in: storage, adding: .boldFontMask)
    case .italic:
      return font(at: location, in: storage, adding: .italicFontMask)
    case .boldItalic:
      let bold = font(at: location, in: storage, adding: .boldFontMask)
      return NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
    case .inlineCode, .codeFence, .codeBlock:
      return codeFont
    default:
      return nil
    }
  }

  private func colorAttributes(for kind: MarkdownSpanKind) -> [NSAttributedString.Key: Any] {
    switch kind {
    case .headingMarker, .codeFence, .syntax:
      [.foregroundColor: NSColor.tertiaryLabelColor]
    case .listMarker:
      [.foregroundColor: NSColor.secondaryLabelColor]
    case let .checkbox(checked):
      [
        .foregroundColor: checked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        .cursor: NSCursor.pointingHand
      ]
    case .completedItem:
      [
        .foregroundColor: NSColor.secondaryLabelColor,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ]
    case .inlineCode:
      [.backgroundColor: NSColor.quaternarySystemFill]
    default:
      [:]
    }
  }

  private func font(at location: Int, in storage: NSTextStorage, adding trait: NSFontTraitMask) -> NSFont {
    let current = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont ?? baseFont
    return NSFontManager.shared.convert(current, toHaveTrait: trait)
  }
}
