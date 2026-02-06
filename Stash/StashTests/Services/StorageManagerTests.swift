// ABOUTME: Tests for StorageManager CRUD, consecutive dedup, history limit, pinning, and encryption.
// ABOUTME: Uses in-memory ModelContainer and per-test Keychain key for isolation.

import XCTest
import SwiftData
@testable import Stash

@MainActor
final class StorageManagerTests: XCTestCase {

    private var storage: StorageManager!
    private var crypto: CryptoService!

    override func setUp() {
        super.setUp()
        crypto = CryptoService(keychainService: "com.hexul.Stash.tests.\(UUID().uuidString)")
        storage = StorageManager(inMemory: true, crypto: crypto)
    }

    override func tearDown() {
        crypto.deleteKey()
        storage = nil
        crypto = nil
        super.tearDown()
    }

    // MARK: - Save

    func testSaveCreatesEntry() throws {
        let saved = try storage.save(
            contentType: .plainText,
            plainText: "Hello",
            sourceAppBundleID: "com.test",
            sourceAppName: "Test"
        )
        XCTAssertNotNil(saved)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].plainText, "Hello")
    }

    func testSaveMultipleEntries() throws {
        try storage.save(contentType: .plainText, plainText: "One", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "Two", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "Three", sourceAppBundleID: nil, sourceAppName: nil)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 3)
    }

    // MARK: - Consecutive dedup

    func testSkipsConsecutiveDuplicate() throws {
        try storage.save(contentType: .plainText, plainText: "Same", sourceAppBundleID: nil, sourceAppName: nil)
        let second = try storage.save(contentType: .plainText, plainText: "Same", sourceAppBundleID: nil, sourceAppName: nil)

        XCTAssertNil(second, "Consecutive duplicate should be skipped")
        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 1)
    }

    func testAllowsNonConsecutiveDuplicate() throws {
        try storage.save(contentType: .plainText, plainText: "A", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "B", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "A", sourceAppBundleID: nil, sourceAppName: nil)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 3)
    }

    // MARK: - History limit

    func testEnforcesHistoryLimit() throws {
        storage.historyLimit = 3

        try storage.save(contentType: .plainText, plainText: "1", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "2", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "3", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "4", sourceAppBundleID: nil, sourceAppName: nil)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 3)
        // Oldest ("1") should be pruned
        XCTAssertFalse(entries.contains(where: { $0.plainText == "1" }))
        XCTAssertTrue(entries.contains(where: { $0.plainText == "4" }))
    }

    // MARK: - Pinned entries survive pruning

    func testPinnedEntriesSurvivePruning() throws {
        storage.historyLimit = 2

        let pinned = try storage.save(contentType: .plainText, plainText: "Pinned", sourceAppBundleID: nil, sourceAppName: nil)
        pinned!.isPinned = true
        try storage.save(contentType: .plainText, plainText: "Two", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "Three", sourceAppBundleID: nil, sourceAppName: nil)

        let entries = try storage.fetchAll()
        XCTAssertTrue(entries.contains(where: { $0.plainText == "Pinned" }), "Pinned entry should survive pruning")
    }

    // MARK: - Delete all

    func testDeleteAll() throws {
        try storage.save(contentType: .plainText, plainText: "A", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "B", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.deleteAll()

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 0)
    }

    // MARK: - Fetch ordering

    func testFetchAllOrderedByTimestampDescending() throws {
        try storage.save(contentType: .plainText, plainText: "Oldest", sourceAppBundleID: nil, sourceAppName: nil)
        // Small delay to ensure distinct timestamps
        Thread.sleep(forTimeInterval: 0.01)
        try storage.save(contentType: .plainText, plainText: "Newest", sourceAppBundleID: nil, sourceAppName: nil)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries[0].plainText, "Newest")
        XCTAssertEqual(entries[1].plainText, "Oldest")
    }

    // MARK: - Delete expired

    func testDeleteExpiredRemovesOldEntries() throws {
        let old = try storage.save(contentType: .plainText, plainText: "Old", sourceAppBundleID: nil, sourceAppName: nil)!
        old.timestamp = Date().addingTimeInterval(-8 * 86400) // 8 days ago
        try storage.context.save()

        try storage.save(contentType: .plainText, plainText: "Recent", sourceAppBundleID: nil, sourceAppName: nil)

        let deleted = try storage.deleteExpired(olderThanDays: 7)
        XCTAssertEqual(deleted, 1)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].plainText, "Recent")
    }

    func testDeleteExpiredKeepsPinnedEntries() throws {
        let old = try storage.save(contentType: .plainText, plainText: "Pinned old", sourceAppBundleID: nil, sourceAppName: nil)!
        old.timestamp = Date().addingTimeInterval(-8 * 86400)
        old.isPinned = true
        try storage.context.save()

        let deleted = try storage.deleteExpired(olderThanDays: 7)
        XCTAssertEqual(deleted, 0)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 1)
    }

    func testDeleteExpiredKeepsRecentEntries() throws {
        try storage.save(contentType: .plainText, plainText: "Today", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "Also today", sourceAppBundleID: nil, sourceAppName: nil)

        let deleted = try storage.deleteExpired(olderThanDays: 1)
        XCTAssertEqual(deleted, 0)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 2)
    }

    func testDeleteExpiredWithZeroDaysDeletesNothing() throws {
        let old = try storage.save(contentType: .plainText, plainText: "Old", sourceAppBundleID: nil, sourceAppName: nil)!
        old.timestamp = Date().addingTimeInterval(-365 * 86400) // 1 year ago
        try storage.context.save()

        let deleted = try storage.deleteExpired(olderThanDays: 0)
        XCTAssertEqual(deleted, 0, "0 days means 'forever' — nothing should be deleted")
    }

    // MARK: - Delete by ID

    func testDeleteByID() throws {
        let entry = try storage.save(contentType: .plainText, plainText: "Delete me", sourceAppBundleID: nil, sourceAppName: nil)!
        let id = entry.persistentModelID

        try storage.delete(entryWithID: id)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 0)
    }

    func testDeleteByIDIgnoresMissingEntry() throws {
        try storage.save(contentType: .plainText, plainText: "Keep me", sourceAppBundleID: nil, sourceAppName: nil)

        // Use a fake ID by saving and deleting an entry first
        let temp = try storage.save(contentType: .plainText, plainText: "Temp", sourceAppBundleID: nil, sourceAppName: nil)!
        let tempID = temp.persistentModelID
        try storage.delete(entryWithID: tempID)

        // Deleting the already-deleted ID should not crash
        try storage.delete(entryWithID: tempID)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - Toggle pin by ID

    func testTogglePinByID() throws {
        let entry = try storage.save(contentType: .plainText, plainText: "Pin me", sourceAppBundleID: nil, sourceAppName: nil)!
        let id = entry.persistentModelID

        try storage.togglePin(entryWithID: id)
        var entries = try storage.fetchAll()
        XCTAssertTrue(entries[0].isPinned)

        try storage.togglePin(entryWithID: id)
        entries = try storage.fetchAll()
        XCTAssertFalse(entries[0].isPinned)
    }

    // MARK: - Encryption

    func testContentIsEncryptedAtRest() throws {
        try storage.save(contentType: .plainText, plainText: "Secret text", sourceAppBundleID: nil, sourceAppName: nil)

        // Read raw entry from the write context (encrypted data)
        let rawEntries = try storage.context.fetch(FetchDescriptor<ClipboardEntry>())
        XCTAssertEqual(rawEntries.count, 1)
        XCTAssertNotEqual(rawEntries[0].plainText, "Secret text", "Raw stored value should be encrypted")

        // Read via fetchAll (decrypted data)
        let entries = try storage.fetchAll()
        XCTAssertEqual(entries[0].plainText, "Secret text", "fetchAll should return decrypted values")
    }

    func testImageDataIsEncryptedAtRest() throws {
        let imageData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try storage.save(
            contentType: .image,
            imageData: imageData,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )

        let rawEntries = try storage.context.fetch(FetchDescriptor<ClipboardEntry>())
        XCTAssertNotEqual(rawEntries[0].imageData, imageData, "Raw stored image should be encrypted")

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries[0].imageData, imageData, "fetchAll should return decrypted image data")
    }

    func testDedupStillWorksWithEncryption() throws {
        try storage.save(contentType: .plainText, plainText: "Same", sourceAppBundleID: nil, sourceAppName: nil)
        let second = try storage.save(contentType: .plainText, plainText: "Same", sourceAppBundleID: nil, sourceAppName: nil)

        XCTAssertNil(second, "Dedup should work even though stored content is encrypted")
    }
}
