import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let fileURL: URL
    private let settings: SettingsManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(settings: SettingsManager, fileURL: URL? = nil) {
        self.settings = settings
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? base.appendingPathComponent("ClipBoard/history.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
        enforceLimitAndSave()
        settings.onHistoryLimitChanged = { [weak self] in self?.enforceLimitAndSave() }
    }

    func add(_ content: String, at date: Date = Date()) {
        guard !content.isEmpty, content.unicodeScalars.contains(where: { !$0.properties.isWhitespace }) else { return }
        guard items.first?.content != content else { return }
        items.insert(ClipboardItem(content: content, createdAt: date), at: 0)
        enforceLimitAndSave()
    }

    func filtered(by query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.content.localizedCaseInsensitiveContains(query) }
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        enforceLimitAndSave()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear(preservingPinned: Bool = true) {
        if preservingPinned {
            items.removeAll { !$0.isPinned }
        } else {
            items.removeAll()
        }
        save()
    }

    private func sortItems() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    private func enforceLimitAndSave() {
        sortItems()
        let pinned = items.filter(\.isPinned)
        let allowedRegular = max(0, settings.historyLimit - pinned.count)
        items = pinned + items.filter { !$0.isPinned }.prefix(allowedRegular)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Clipboard contents are intentionally never included in diagnostics.
            NSLog("ClipBoard could not save history: %@", error.localizedDescription)
        }
    }
}
