import AppKit

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var query = "" {
        didSet { selectFirst() }
    }
    @Published var selectionID: UUID?

    let store: ClipboardStore
    var onPaste: ((ClipboardItem) -> Void)?
    var onClose: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
    }

    var filteredItems: [ClipboardItem] { store.filtered(by: query) }

    func reset() {
        query = ""
        selectFirst()
    }

    func selectFirst() {
        selectionID = filteredItems.first?.id
    }

    func ensureValidSelection() {
        guard filteredItems.contains(where: { $0.id == selectionID }) else {
            selectFirst()
            return
        }
    }

    func moveSelection(by offset: Int) {
        let results = filteredItems
        guard !results.isEmpty else { selectionID = nil; return }
        guard let selectionID, let current = results.firstIndex(where: { $0.id == selectionID }) else {
            self.selectionID = results.first?.id
            return
        }
        let next = min(results.count - 1, max(0, current + offset))
        self.selectionID = results[next].id
    }

    func pasteSelected() {
        guard let item = filteredItems.first(where: { $0.id == selectionID }) else { return }
        onPaste?(item)
    }

    func deleteSelected() {
        guard let selectionID else { return }
        store.delete(selectionID)
        selectFirst()
    }

    func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126:
            moveSelection(by: -1)
        case 125:
            moveSelection(by: 1)
        case 36, 76:
            pasteSelected()
        case 53:
            if query.isEmpty { onClose?() } else { query = "" }
        case 117:
            deleteSelected()
        case 51 where event.modifierFlags.contains(.command):
            deleteSelected()
        default:
            return false
        }
        return true
    }
}
