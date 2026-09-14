import PhotonClipboard
import PhotonCore
import SwiftUI

struct LauncherView: View {
  @ObservedObject var model: LauncherViewModel
  var onRun: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      content
      if let lastError = model.lastError {
        Text(lastError)
          .font(.caption)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
      }
    }
    .frame(width: 640, height: 420)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
    )
    .onAppear {
      Task { await model.refresh() }
    }
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      sessionBadge
      TextField(placeholder, text: $model.query)
        .textFieldStyle(.plain)
        .font(.system(size: 22, weight: .medium))
        .onSubmit {
          Task { await run() }
        }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
  }

  @ViewBuilder
  private var sessionBadge: some View {
    if model.session == .clipboard {
      Label("Clipboard", systemImage: "clipboard")
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    } else if let mode = model.activeMode {
      Text(mode.title)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
        .foregroundStyle(Color.accentColor)
    } else {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
    }
  }

  private var placeholder: String {
    if model.session == .clipboard {
      "Search clipboard history"
    } else if let mode = model.activeMode {
      mode.placeholder
    } else {
      "Search applications"
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.session {
    case .clipboard:
      if let clipboard = model.clipboard {
        ClipboardHistoryView(model: clipboard)
      } else {
        results
      }
    case .commands:
      if let mode = model.activeMode {
        mode.makeResultsView()
      } else {
        results
      }
    }
  }

  @ViewBuilder
  private var results: some View {
    if model.isLoading, model.results.isEmpty {
      ProgressView("Scanning…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.results.isEmpty {
      Text(model.query.isEmpty ? "No applications indexed yet" : "No results")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollViewReader { proxy in
        List(model.results, selection: $model.selectedID) { item in
          resultRow(item)
            .tag(item.id)
            .id(item.id)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onChange(of: model.selectedID) { _, newValue in
          if let newValue {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
    }
  }

  private func resultRow(_ item: RankedCommand) -> some View {
    HStack(spacing: 12) {
      resultIcon(for: item.command)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.command.title)
          .font(.body.weight(.medium))
        if !item.command.subtitle.isEmpty {
          Text(item.command.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Spacer()
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onTapGesture {
      model.selectedID = item.id
      Task { await run() }
    }
  }

  @ViewBuilder
  private func resultIcon(for command: Command) -> some View {
    if let icon = model.mode(forInlineProvider: command.providerID)?.icon(for: command) {
      Image(nsImage: icon)
        .resizable()
        .interpolation(.high)
        .frame(width: 24, height: 24)
    } else {
      Image(systemName: symbolName(for: command))
        .foregroundStyle(.secondary)
    }
  }

  private func symbolName(for command: Command) -> String {
    switch command.providerID {
    case "apps": "app.fill"
    case "clipboard": "clipboard"
    case "files": "doc"
    case "notes": "note.text"
    default: "circle.grid.3x3"
    }
  }

  private func run() async {
    switch model.session {
    case .clipboard:
      await model.clipboard?.performPrimaryAction()
    case .commands:
      if await model.runSelection() {
        onRun()
      }
    }
  }
}
