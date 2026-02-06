// ABOUTME: AES-256-GCM field-level encryption for clipboard entry content.
// ABOUTME: Symmetric key stored in Keychain; generated on first use.

import CryptoKit
import Foundation

struct CryptoService {
    private let keychainService: String

    init(keychainService: String = "com.hexul.Stash.encryption") {
        self.keychainService = keychainService
    }

    // MARK: - String encrypt/decrypt

    func encrypt(_ string: String) throws -> String {
        let data = Data(string.utf8)
        let encrypted = try encrypt(data: data)
        return encrypted.base64EncodedString()
    }

    func decrypt(_ base64String: String) throws -> String {
        guard let data = Data(base64Encoded: base64String) else {
            throw CryptoError.invalidData
        }
        let decrypted = try decrypt(data: data)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw CryptoError.invalidData
        }
        return string
    }

    // MARK: - Data encrypt/decrypt

    func encrypt(data: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    func decrypt(data: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Key management

    func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "encryptionKey",
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func getOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        try saveKey(key)
        return key
    }

    private func loadKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "encryptionKey",
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw CryptoError.keychainError(status)
        }
    }

    private func saveKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "encryptionKey",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CryptoError.keychainError(status)
        }
    }
}

enum CryptoError: Error {
    case invalidData
    case encryptionFailed
    case keychainError(OSStatus)
}
