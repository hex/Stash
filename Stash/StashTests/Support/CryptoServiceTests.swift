// ABOUTME: Tests for CryptoService encrypt/decrypt round-trip and key persistence.
// ABOUTME: Uses a unique Keychain service name per test to avoid cross-contamination.

import XCTest
@testable import Stash

final class CryptoServiceTests: XCTestCase {

    private var crypto: CryptoService!
    private var keychainService: String!

    override func setUp() {
        super.setUp()
        keychainService = "com.hexul.Stash.tests.\(UUID().uuidString)"
        crypto = CryptoService(keychainService: keychainService)
    }

    override func tearDown() {
        crypto.deleteKey()
        crypto = nil
        keychainService = nil
        super.tearDown()
    }

    // MARK: - String round-trip

    func testEncryptDecryptStringRoundTrip() throws {
        let plaintext = "Hello, clipboard!"
        let encrypted = try crypto.encrypt(plaintext)
        XCTAssertNotEqual(encrypted, plaintext, "Encrypted text should differ from plaintext")

        let decrypted = try crypto.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptEmptyString() throws {
        let encrypted = try crypto.encrypt("")
        let decrypted = try crypto.decrypt(encrypted)
        XCTAssertEqual(decrypted, "")
    }

    func testEncryptDecryptUnicodeString() throws {
        let plaintext = "Clipboard emoji test"
        let encrypted = try crypto.encrypt(plaintext)
        let decrypted = try crypto.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Data round-trip

    func testEncryptDecryptDataRoundTrip() throws {
        let data = Data([0x00, 0x01, 0x02, 0xFF, 0xFE])
        let encrypted = try crypto.encrypt(data: data)
        XCTAssertNotEqual(encrypted, data)

        let decrypted = try crypto.decrypt(data: encrypted)
        XCTAssertEqual(decrypted, data)
    }

    func testEncryptDecryptEmptyData() throws {
        let encrypted = try crypto.encrypt(data: Data())
        let decrypted = try crypto.decrypt(data: encrypted)
        XCTAssertEqual(decrypted, Data())
    }

    // MARK: - Key persistence

    func testKeyPersistsAcrossInstances() throws {
        let plaintext = "Persistent key test"
        let encrypted = try crypto.encrypt(plaintext)

        let crypto2 = CryptoService(keychainService: keychainService)
        let decrypted = try crypto2.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Nonce uniqueness

    func testEncryptProducesDifferentCiphertextEachTime() throws {
        let plaintext = "Same input"
        let encrypted1 = try crypto.encrypt(plaintext)
        let encrypted2 = try crypto.encrypt(plaintext)
        XCTAssertNotEqual(encrypted1, encrypted2, "Each encryption should use a unique nonce")
    }
}
