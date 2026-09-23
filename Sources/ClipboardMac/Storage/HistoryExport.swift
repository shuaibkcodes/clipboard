import Foundation

/// JSON document format for history export/import. Blobs (images, RTF
/// data) are embedded base64 so a single file round-trips everything.
struct HistoryExport: Codable {
    var version: Int = 1
    var items: [Item]

    struct Item: Codable {
        var type: String
        var preview: String
        var plainText: String?
        var sourceApp: String?
        var createdAt: Int64
        var updatedAt: Int64
        var isPinned: Bool
        var hash: String
        var tags: [String]
        var metadata: [String: String]
        var imageBase64: String?
        var formats: [Format]
    }

    struct Format: Codable {
        var pasteboardType: String
        var text: String?
        var dataBase64: String?
    }
}
