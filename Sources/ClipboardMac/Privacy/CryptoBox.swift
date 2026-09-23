import CryptoKit
import Foundation
import Security

/// AES-GCM encryption for stored clipboard content (database text fields
/// and blob files). The 256-bit key is created on first use and stored in
/// the user's Keychain, so the on-disk history is unreadable without it.
///
/// Encrypted values are self-describing: text carries an "encv1:" prefix
/// and files a "CMENC1" magic header, so mixed plaintext/encrypted data
/// (e.g. mid-migration) always reads back correctly.
enum CryptoBox {
    private static let textPrefix = "encv1:"
    private static let fileMagic = Data("CMENC1".utf8)
    private static let keychainService = "com.clipboardmac.app"
    private static let keychainAccount = "clipboard-encryption-key"
    private static var cachedKey: SymmetricKey?

    struct CryptoError: Error, CustomStringConvertible {
        let message: String
        var description: String { "CryptoError: \(message)" }
    }

    #if DEBUG
    /// Test hook: inject a process-local key so headless tests never touch
    /// the real Keychain.
    static func setTestKey(_ key: SymmetricKey) {
        cachedKey = key
    }
    #endif

    // MARK: - Text fields

    static func isEncrypted(text: String) -> Bool {
        text.hasPrefix(textPrefix)
    }

    static func encrypt(text: String) throws -> String {
        let sealed = try seal(Data(text.utf8))
        return textPrefix + sealed.base64EncodedString()
    }

    /// Returns plaintext as-is; decrypts marked values. A value that can't
    /// be decrypted (missing key) is shown as a locked placeholder rather
    /// than crashing or leaking ciphertext.
    static func decryptIfNeeded(text: String) -> String {
        guard text.hasPrefix(textPrefix) else { return text }
        guard let data = Data(base64Encoded: String(text.dropFirst(textPrefix.count))),
              let plain = try? open(data),
              let string = String(data: plain, encoding: .utf8) else {
            return "🔒 encrypted item (key unavailable)"
        }
        return string
    }

    // MARK: - Blob files

    static func isEncrypted(data: Data) -> Bool {
        data.starts(with: fileMagic)
    }

    static func encrypt(data: Data) throws -> Data {
        fileMagic + (try seal(data))
    }

    static func decryptIfNeeded(data: Data) -> Data? {
        guard data.starts(with: fileMagic) else { return data }
        return try? open(data.dropFirst(fileMagic.count))
    }

    // MARK: - AES-GCM

    private static func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key()).combined else {
            throw CryptoError(message: "sealing produced no combined representation")
        }
        return combined
    }

    private static func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key())
    }

    // MARK: - Keychain-backed key

    private static func key() throws -> SymmetricKey {
        if let cachedKey = cachedKey { return cachedKey }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
        guard status == errSecItemNotFound else {
            throw CryptoError(message: "Keychain read failed (status \(status))")
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CryptoError(message: "Keychain write failed (status \(addStatus))")
        }
        cachedKey = key
        return key
    }
}
