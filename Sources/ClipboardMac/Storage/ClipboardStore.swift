import Foundation

/// Persistence layer: saves, queries, and cleans up clipboard history.
/// Text fields and blob files are AES-GCM encrypted when the encryption
/// preference is on; values are self-describing, so reads always work.
final class ClipboardStore {
    private let database: Database
    private let fileStorage: FileStorage

    init(database: Database, fileStorage: FileStorage) throws {
        self.database = database
        self.fileStorage = fileStorage
        try Migrations.run(on: database)
    }

    // MARK: - Save

    /// Saves a captured clipboard. If an item with the same hash exists,
    /// it is moved to the top instead of duplicated.
    @discardableResult
    func save(_ captured: CapturedClipboard, sourceApp: String?) throws -> ClipboardItem {
        let now = Int64(Date().timeIntervalSince1970)

        if let existing = try item(withHash: captured.hash) {
            try database.run(
                "UPDATE clipboard_items SET updated_at = ? WHERE id = ?;",
                [.int(now), .text(existing.id)]
            )
            var updated = existing
            updated.updatedAt = Date(timeIntervalSince1970: TimeInterval(now))
            return updated
        }

        let id = UUID().uuidString
        var filePath: String?

        if let imageData = captured.imageData {
            filePath = try fileStorage.saveData(imageData, name: "\(id).png")
        }

        let metadataJSON = (try? JSONEncoder().encode(captured.metadata)).flatMap {
            String(data: $0, encoding: .utf8)
        }

        try database.run("""
        INSERT INTO clipboard_items
            (id, type, preview, plain_text, source_app, created_at, updated_at,
             is_pinned, hash, file_path, thumbnail_path, metadata_json, tags)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, NULL, ?, NULL);
        """, [
            .text(id),
            .text(captured.type.rawValue),
            storedText(captured.preview),
            captured.plainText.map(storedText) ?? .null,
            sourceApp.map(SQLValue.text) ?? .null,
            .int(now),
            .int(now),
            .text(captured.hash),
            filePath.map(SQLValue.text) ?? .null,
            metadataJSON.map(storedText) ?? .null
        ])

        // Preserve additional pasteboard representations (HTML, RTF, ...).
        for format in captured.extraFormats {
            var dataPath: String?
            if let data = format.data {
                let safeType = format.pasteboardType.replacingOccurrences(of: "/", with: "_")
                dataPath = try? fileStorage.saveData(data, name: "\(id)-\(safeType).bin")
            }
            try database.run("""
            INSERT INTO clipboard_item_formats
                (id, clipboard_item_id, pasteboard_type, data_path, text_value, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """, [
                .text(UUID().uuidString),
                .text(id),
                .text(format.pasteboardType),
                dataPath.map(SQLValue.text) ?? .null,
                format.text.map(storedText) ?? .null,
                .int(now)
            ])
        }

        return ClipboardItem(
            id: id,
            type: captured.type,
            preview: captured.preview,
            plainText: captured.plainText,
            sourceApp: sourceApp,
            createdAt: Date(timeIntervalSince1970: TimeInterval(now)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(now)),
            isPinned: false,
            hash: captured.hash,
            filePath: filePath,
            thumbnailPath: nil,
            metadata: captured.metadata
        )
    }

    // MARK: - Query

    /// Pinned items first, then most recently copied. Search is filtered in
    /// memory so it also works over encrypted fields and tags.
    func items(matching query: String? = nil, limit: Int = 200) throws -> [ClipboardItem] {
        let trimmed = query?.trimmingCharacters(in: .whitespaces) ?? ""
        let sql = "SELECT * FROM clipboard_items ORDER BY is_pinned DESC, updated_at DESC"

        if trimmed.isEmpty {
            return try database.query(sql + " LIMIT ?;", [.int(Int64(limit))])
                .map(Self.itemFromRow)
        }

        let all = try database.query(sql + ";").map(Self.itemFromRow)
        return Array(all.filter { $0.matches(trimmed) }.prefix(limit))
    }

    func formats(for itemId: String) throws -> [ClipboardItemFormat] {
        try database.query(
            "SELECT * FROM clipboard_item_formats WHERE clipboard_item_id = ?;",
            [.text(itemId)]
        ).map { row in
            ClipboardItemFormat(
                id: row.string("id") ?? "",
                clipboardItemId: row.string("clipboard_item_id") ?? "",
                pasteboardType: row.string("pasteboard_type") ?? "",
                dataPath: row.string("data_path"),
                textValue: row.string("text_value").map { CryptoBox.decryptIfNeeded(text: $0) },
                createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at") ?? 0))
            )
        }
    }

    private func item(withHash hash: String) throws -> ClipboardItem? {
        try database.query(
            "SELECT * FROM clipboard_items WHERE hash = ? LIMIT 1;",
            [.text(hash)]
        ).map(Self.itemFromRow).first
    }

    // MARK: - Mutations

    func setPinned(_ pinned: Bool, id: String) throws {
        try database.run(
            "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?;",
            [.int(pinned ? 1 : 0), .text(id)]
        )
    }

    func setTags(_ tags: [String], id: String) throws {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = cleaned.joined(separator: ",")
        try database.run(
            "UPDATE clipboard_items SET tags = ? WHERE id = ?;",
            [joined.isEmpty ? .null : storedText(joined), .text(id)]
        )
    }

    func delete(id: String) throws {
        try deleteItems(where: "id = ?", bindings: [.text(id)])
    }

    /// Clears history. Pinned items are kept unless keepPinned is false.
    func clearHistory(keepPinned: Bool = true) throws {
        if keepPinned {
            try deleteItems(where: "is_pinned = 0", bindings: [])
        } else {
            try deleteItems(where: "1 = 1", bindings: [])
        }
    }

    /// Enforces the history limit and max age for unpinned items.
    func cleanup(historyLimit: Int, maxAgeDays: Int) throws {
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(maxAgeDays) * 86_400
        try deleteItems(where: "is_pinned = 0 AND updated_at < ?", bindings: [.int(cutoff)])
        try deleteItems(
            where: """
            is_pinned = 0 AND id NOT IN (
                SELECT id FROM clipboard_items WHERE is_pinned = 0
                ORDER BY updated_at DESC LIMIT ?
            )
            """,
            bindings: [.int(Int64(historyLimit))]
        )
    }

    /// Deletes matching items along with their formats and on-disk blobs.
    private func deleteItems(where condition: String, bindings: [SQLValue]) throws {
        let doomed = try database.query(
            "SELECT id, file_path, thumbnail_path FROM clipboard_items WHERE \(condition);",
            bindings
        )
        guard !doomed.isEmpty else { return }

        for row in doomed {
            fileStorage.deleteFile(at: row.string("file_path"))
            fileStorage.deleteFile(at: row.string("thumbnail_path"))
            guard let id = row.string("id") else { continue }
            let formats = try database.query(
                "SELECT data_path FROM clipboard_item_formats WHERE clipboard_item_id = ?;",
                [.text(id)]
            )
            for format in formats {
                fileStorage.deleteFile(at: format.string("data_path"))
            }
            try database.run(
                "DELETE FROM clipboard_item_formats WHERE clipboard_item_id = ?;",
                [.text(id)]
            )
            try database.run("DELETE FROM clipboard_items WHERE id = ?;", [.text(id)])
        }
    }

    // MARK: - Encryption

    /// Encrypts or decrypts every stored text field and blob file, then
    /// records the new setting. Throws before touching anything if the
    /// encryption key is unavailable.
    func applyEncryptionSetting(_ enabled: Bool) throws {
        // Fail fast if the Keychain key can't be created/read.
        _ = try CryptoBox.encrypt(text: "probe")

        let itemRows = try database.query(
            "SELECT id, preview, plain_text, metadata_json, tags, file_path FROM clipboard_items;"
        )
        for row in itemRows {
            guard let id = row.string("id") else { continue }
            try database.run(
                "UPDATE clipboard_items SET preview = ?, plain_text = ?, metadata_json = ?, tags = ? WHERE id = ?;",
                [
                    try recoded(row.string("preview"), encrypt: enabled),
                    try recoded(row.string("plain_text"), encrypt: enabled),
                    try recoded(row.string("metadata_json"), encrypt: enabled),
                    try recoded(row.string("tags"), encrypt: enabled),
                    .text(id)
                ]
            )
            try recodeBlob(atPath: row.string("file_path"), encrypt: enabled)
        }

        let formatRows = try database.query(
            "SELECT id, text_value, data_path FROM clipboard_item_formats;"
        )
        for row in formatRows {
            guard let id = row.string("id") else { continue }
            try database.run(
                "UPDATE clipboard_item_formats SET text_value = ? WHERE id = ?;",
                [try recoded(row.string("text_value"), encrypt: enabled), .text(id)]
            )
            try recodeBlob(atPath: row.string("data_path"), encrypt: enabled)
        }

        PreferencesManager.shared.encryptionEnabled = enabled
    }

    /// Encrypts a text field when the preference is on. Falls back to
    /// plaintext (with a log) rather than dropping the clipboard item if
    /// the Keychain key is unavailable.
    private func storedText(_ value: String) -> SQLValue {
        guard PreferencesManager.shared.encryptionEnabled else { return .text(value) }
        do {
            return .text(try CryptoBox.encrypt(text: value))
        } catch {
            NSLog("ClipboardMac: encryption unavailable, storing plaintext: \(error)")
            return .text(value)
        }
    }

    private func recoded(_ value: String?, encrypt: Bool) throws -> SQLValue {
        guard let value = value else { return .null }
        let plain = CryptoBox.decryptIfNeeded(text: value)
        return .text(encrypt ? try CryptoBox.encrypt(text: plain) : plain)
    }

    private func recodeBlob(atPath path: String?, encrypt: Bool) throws {
        guard let path = path, !path.isEmpty,
              let raw = FileManager.default.contents(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        if encrypt {
            guard !CryptoBox.isEncrypted(data: raw) else { return }
            try CryptoBox.encrypt(data: raw).write(to: url, options: .atomic)
        } else {
            guard CryptoBox.isEncrypted(data: raw),
                  let plain = CryptoBox.decryptIfNeeded(data: raw) else { return }
            try plain.write(to: url, options: .atomic)
        }
    }

    // MARK: - Export / import

    /// Exports the whole history (including image and rich-format blobs)
    /// as plaintext JSON. Encrypted content is decrypted for the export.
    func exportJSON() throws -> Data {
        let allItems = try items(matching: nil, limit: Int(Int32.max))
        let exported = try allItems.map { item -> HistoryExport.Item in
            let formats = try formats(for: item.id).map { format in
                HistoryExport.Format(
                    pasteboardType: format.pasteboardType,
                    text: format.textValue,
                    dataBase64: FileStorage.loadData(atPath: format.dataPath)?.base64EncodedString()
                )
            }
            return HistoryExport.Item(
                type: item.type.rawValue,
                preview: item.preview,
                plainText: item.plainText,
                sourceApp: item.sourceApp,
                createdAt: Int64(item.createdAt.timeIntervalSince1970),
                updatedAt: Int64(item.updatedAt.timeIntervalSince1970),
                isPinned: item.isPinned,
                hash: item.hash,
                tags: item.tags,
                metadata: item.metadata,
                imageBase64: item.type == .image
                    ? FileStorage.loadData(atPath: item.filePath)?.base64EncodedString()
                    : nil,
                formats: formats
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(HistoryExport(items: exported))
    }

    /// Imports items from an export file. Items whose hash already exists
    /// are skipped; imported content follows the current encryption setting.
    func importJSON(_ data: Data) throws -> (imported: Int, skipped: Int) {
        let export = try JSONDecoder().decode(HistoryExport.self, from: data)
        var imported = 0
        var skipped = 0

        for entry in export.items {
            if try item(withHash: entry.hash) != nil {
                skipped += 1
                continue
            }
            try insertImported(entry)
            imported += 1
        }
        return (imported, skipped)
    }

    private func insertImported(_ entry: HistoryExport.Item) throws {
        let id = UUID().uuidString

        var filePath: String?
        if let base64 = entry.imageBase64, let imageData = Data(base64Encoded: base64) {
            filePath = try fileStorage.saveData(imageData, name: "\(id).png")
        }

        let metadataJSON = (try? JSONEncoder().encode(entry.metadata)).flatMap {
            String(data: $0, encoding: .utf8)
        }
        let tags = entry.tags.joined(separator: ",")

        try database.run("""
        INSERT INTO clipboard_items
            (id, type, preview, plain_text, source_app, created_at, updated_at,
             is_pinned, hash, file_path, thumbnail_path, metadata_json, tags)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?);
        """, [
            .text(id),
            .text(entry.type),
            storedText(entry.preview),
            entry.plainText.map(storedText) ?? .null,
            entry.sourceApp.map(SQLValue.text) ?? .null,
            .int(entry.createdAt),
            .int(entry.updatedAt),
            .int(entry.isPinned ? 1 : 0),
            .text(entry.hash),
            filePath.map(SQLValue.text) ?? .null,
            metadataJSON.map(storedText) ?? .null,
            tags.isEmpty ? .null : storedText(tags)
        ])

        for format in entry.formats {
            var dataPath: String?
            if let base64 = format.dataBase64, let blob = Data(base64Encoded: base64) {
                let safeType = format.pasteboardType.replacingOccurrences(of: "/", with: "_")
                dataPath = try? fileStorage.saveData(blob, name: "\(id)-\(safeType).bin")
            }
            try database.run("""
            INSERT INTO clipboard_item_formats
                (id, clipboard_item_id, pasteboard_type, data_path, text_value, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """, [
                .text(UUID().uuidString),
                .text(id),
                .text(format.pasteboardType),
                dataPath.map(SQLValue.text) ?? .null,
                format.text.map(storedText) ?? .null,
                .int(entry.createdAt)
            ])
        }
    }

    // MARK: - Row mapping

    private static func itemFromRow(_ row: [String: SQLValue]) -> ClipboardItem {
        var metadata: [String: String] = [:]
        if let json = row.string("metadata_json").map({ CryptoBox.decryptIfNeeded(text: $0) }),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            metadata = decoded
        }
        let tags = row.string("tags")
            .map { CryptoBox.decryptIfNeeded(text: $0) }
            .map { $0.split(separator: ",").map(String.init) } ?? []
        return ClipboardItem(
            id: row.string("id") ?? "",
            type: ClipboardType(rawValue: row.string("type") ?? "text") ?? .text,
            preview: row.string("preview").map { CryptoBox.decryptIfNeeded(text: $0) } ?? "",
            plainText: row.string("plain_text").map { CryptoBox.decryptIfNeeded(text: $0) },
            sourceApp: row.string("source_app"),
            createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at") ?? 0)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row.int("updated_at") ?? 0)),
            isPinned: (row.int("is_pinned") ?? 0) == 1,
            hash: row.string("hash") ?? "",
            filePath: row.string("file_path"),
            thumbnailPath: row.string("thumbnail_path"),
            metadata: metadata,
            tags: tags
        )
    }
}
