import Foundation

/// Manages the app's on-disk data directory:
/// ~/Library/Application Support/ClipboardMac/
final class FileStorage {
    let baseDirectory: URL
    let dataDirectory: URL

    /// Pass baseDirectory to store data somewhere else (used by tests).
    init(baseDirectory: URL? = nil) throws {
        if let baseDirectory = baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.baseDirectory = appSupport.appendingPathComponent("ClipboardMac", isDirectory: true)
        }
        dataDirectory = self.baseDirectory.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    var databasePath: String {
        baseDirectory.appendingPathComponent("clipboard.sqlite").path
    }

    /// Writes blob data for an item and returns the absolute file path.
    /// Data is encrypted when database encryption is enabled.
    func saveData(_ data: Data, name: String) throws -> String {
        let url = dataDirectory.appendingPathComponent(name)
        let payload = PreferencesManager.shared.encryptionEnabled
            ? try CryptoBox.encrypt(data: data)
            : data
        try payload.write(to: url, options: .atomic)
        return url.path
    }

    /// Reads blob data, transparently decrypting encrypted files.
    static func loadData(atPath path: String?) -> Data? {
        guard let path = path, !path.isEmpty,
              let raw = FileManager.default.contents(atPath: path) else { return nil }
        return CryptoBox.decryptIfNeeded(data: raw)
    }

    func deleteFile(at path: String?) {
        guard let path = path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
