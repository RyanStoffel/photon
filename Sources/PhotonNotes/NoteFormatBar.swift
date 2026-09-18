import SwiftUI

/// Bottom format bar: headings, emphasis, code, link, and lists.
struct NoteFormatBar: View {
  var onStyle: (MarkdownFormatStyle) -> Void
  var onClose: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Menu {
        Button("Heading 1") { onStyle(.heading(1)) }
        Button("Heading 2") { onStyle(.heading(2)) }
        Button("Heading 3") { onStyle(.heading(3)) }
      } label: {
        label("H", systemImage: "chevron.down")
      }
      .menuIndicator(.hidden)
      iconButton("bold", help: "Bold") { onStyle(.bold) }
      iconButton("italic", help: "Italic") { onStyle(.italic) }
      iconButton("strikethrough", help: "Strikethrough") { onStyle(.strikethrough) }
      iconButton("underline", help: "Underline") { onStyle(.underline) }
      iconButton("chevron.left.forwardslash.chevron.right", help: "Code") { onStyle(.inlineCode) }
      iconButton("link", help: "Link") { onStyle(.link) }
      iconButton("text.quote", help: "Quote") { onStyle(.quote) }
      iconButton("list.bullet", help: "Bullet list") { onStyle(.bulletList) }
      iconButton("list.number", help: "Numbered list") { onStyle(.numberedList) }
      iconButton("checklist", help: "Checklist") { onStyle(.checklist) }
      Spacer(minLength: 8)
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 22, height: 22)
      }
      .buttonStyle(.plain)
      .help("Close")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }

  private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private func label(_ title: String, systemImage: String) -> some View {
    HStack(spacing: 2) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
      Image(systemName: systemImage)
        .font(.system(size: 8, weight: .bold))
    }
    .foregroundStyle(.secondary)
    .frame(width: 28, height: 26)
  }
}
