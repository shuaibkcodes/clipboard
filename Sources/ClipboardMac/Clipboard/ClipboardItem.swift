import Foundation

struct ClipboardItem: Equatable {
    let id: String
    let type: ClipboardType
    var preview: String
    var plainText: String?
    var sourceApp: String?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    let hash: String
    var filePath: String?
    var thumbnailPath: String?
    var metadata: [String: String]
    var tags: [String] = []

    /// File URLs for `.file` items (stored newline-separated in plainText).
    var fileURLs: [URL] {
        guard type == .file, let text = plainText else { return [] }
        return text
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
    }

    /// In-memory search match, used because encrypted fields can't be
    /// filtered with SQL LIKE. A "#query" searches tags only.
    func matches(_ query: String) -> Bool {
        if query.hasPrefix("#") {
            let tagQuery = String(query.dropFirst())
            guard !tagQuery.isEmpty else { return !tags.isEmpty }
            return tags.contains { $0.localizedCaseInsensitiveContains(tagQuery) }
        }
        if preview.localizedCaseInsensitiveContains(query) { return true }
        if let plainText = plainText, plainText.localizedCaseInsensitiveContains(query) { return true }
        if let sourceApp = sourceApp, sourceApp.localizedCaseInsensitiveContains(query) { return true }
        if type.rawValue.localizedCaseInsensitiveContains(query) { return true }
        if type.displayName.localizedCaseInsensitiveContains(query) { return true }
        return tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct ClipboardItemFormat {
    let id: String
    let clipboardItemId: String
    let pasteboardType: String
    let dataPath: String?
    let textValue: String?
    let createdAt: Date
}
