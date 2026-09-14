import PhotonCore
import SwiftUI

struct LauncherView: View {
  @ObservedObject var model: LauncherViewModel
  var onRun: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      results
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
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Search applications", text: $model.query)
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
      Image(systemName: item.command.providerID == "apps" ? "app.fill" : "circle.grid.3x3")
        .foregroundStyle(.secondary)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.command.title)
          .font(.body.weight(.medium))
        if !item.command.subtitle.isEmpty {
          Text(item.command.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
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

  private func run() async {
    await model.runSelection()
    if model.lastError == nil {
      onRun()
    }
  }
}
