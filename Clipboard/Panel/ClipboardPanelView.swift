import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var store: ClipboardStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            search
                .padding(12)

            Divider().opacity(0.55)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if viewModel.filteredItems.isEmpty {
                            emptyState
                        } else {
                            ForEach(viewModel.filteredItems) { item in
                                ClipboardRowView(
                                    item: item,
                                    isSelected: viewModel.selectionID == item.id,
                                    onPaste: { viewModel.onPaste?(item) },
                                    onTogglePin: {
                                        store.togglePin(item.id)
                                        viewModel.ensureValidSelection()
                                    },
                                    onDelete: {
                                        store.delete(item.id)
                                        viewModel.ensureValidSelection()
                                    }
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: viewModel.selectionID) { selected in
                    guard let selected else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }

            Divider().opacity(0.55)

            HStack {
                Text("\(viewModel.filteredItems.count) \(viewModel.filteredItems.count == 1 ? "item" : "items")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { store.clear(preservingPinned: true) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear unpinned clipboard entries")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 46)
        }
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear {
            searchFocused = true
            viewModel.ensureValidSelection()
        }
        .onReceive(store.$items) { _ in viewModel.ensureValidSelection() }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
            if !viewModel.query.isEmpty {
                Button { viewModel.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(searchFocused ? Color.accentColor : Color.white.opacity(0.12), lineWidth: searchFocused ? 1.5 : 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: viewModel.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.query.isEmpty ? "Clipboard history is empty" : "No matching clips")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
