import Foundation
import CryptoKit

enum Hashing {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }

    /// Hash for duplicate detection: type + normalized content.
    static func itemHash(type: ClipboardType, content: Data) -> String {
        var combined = Data(type.rawValue.utf8)
        combined.append(content)
        return sha256(combined)
    }

    static func itemHash(type: ClipboardType, text: String) -> String {
        itemHash(type: type, content: Data(normalize(text).utf8))
    }

    /// Trim whitespace, normalize line endings, cap very large text.
    static func normalize(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count > 100_000 {
            normalized = String(normalized.prefix(100_000))
        }
        return normalized
    }
}
