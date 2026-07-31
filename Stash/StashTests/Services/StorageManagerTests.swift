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

        let item = try XCTUnwrap(try storage.fetchAll().first)
        XCTAssertEqual(
            try storage.imageData(for: item.id), imageData,
            "The on-demand payload fetch should return decrypted image data"
        )
    }

    func testDedupStillWorksWithEncryption() throws {
        try storage.save(contentType: .plainText, plainText: "Same", sourceAppBundleID: nil, sourceAppName: nil)
        let second = try storage.save(contentType: .plainText, plainText: "Same", sourceAppBundleID: nil, sourceAppName: nil)

        XCTAssertNil(second, "Dedup should work even though stored content is encrypted")
    }

    // MARK: - Snapshot detachment

    /// fetchAll must return value-type snapshots, not live managed objects.
    /// Managed objects strongly reference their ModelContext; handing them to a
    /// long-lived view pins the context's entire object graph and leaks memory.
    func testFetchAllReturnsDetachedValueSnapshots() throws {
        let saved = try XCTUnwrap(try storage.save(
            contentType: .image,
            plainText: "caption",
            imageData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            sourceAppBundleID: "com.test",
            sourceAppName: "Test"
        ))

        let items: [ClipboardItem] = try storage.fetchAll()
        let item = try XCTUnwrap(items.first)

        // Carries the persistent id so delete/pin/paste/payload-fetch can target the entry
        XCTAssertEqual(item.id, saved.persistentModelID)
        // Carries decrypted metadata and text for display
        XCTAssertEqual(item.contentType, .image)
        XCTAssertEqual(item.plainText, "caption")
        // Binary payloads are deliberately absent from the snapshot: SwiftUI retains
        // successive generations of @State, so bytes carried here get multiplied by
        // the number of live generations. They resolve on demand instead.
        XCTAssertEqual(try storage.imageData(for: item.id), Data([0xDE, 0xAD, 0xBE, 0xEF]))

        // Value semantics: identity, metadata and text stay intact after the entry is gone…
        try storage.delete(entryWithID: item.id)
        XCTAssertTrue(try storage.fetchAll().isEmpty)
        XCTAssertEqual(item.plainText, "caption", "Snapshot must survive deletion of its entry")
        // …but the payload lives only in the store, so it goes with the row.
        XCTAssertNil(
            try storage.imageData(for: item.id),
            "Payload access after deletion must degrade to nil, never crash"
        )
    }

    // MARK: - On-demand payloads

    func testImageDataForIDReturnsDecryptedBytes() throws {
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        try storage.save(
            contentType: .image,
            imageData: bytes,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        let item = try XCTUnwrap(try storage.fetchAll().first)

        XCTAssertEqual(try storage.imageData(for: item.id), bytes)
    }

    /// Guards the deleted-row path. `model(for:)` returns a shell for a missing row
    /// whose first attribute access traps, so without an existence check this test
    /// kills the whole suite rather than failing.
    func testImageDataForDeletedEntryReturnsNil() throws {
        try storage.save(
            contentType: .image,
            imageData: Data([0x01, 0x02, 0x03, 0x04]),
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        let item = try XCTUnwrap(try storage.fetchAll().first)
        try storage.delete(entryWithID: item.id)

        XCTAssertNil(try storage.imageData(for: item.id))
    }

    func testRichTextDataForIDReturnsDecryptedBytes() throws {
        let rtf = Data("{\\rtf1\\ansi hello}".utf8)
        try storage.save(
            contentType: .richText,
            plainText: "hello",
            richTextData: rtf,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        let item = try XCTUnwrap(try storage.fetchAll().first)

        XCTAssertEqual(try storage.richTextData(for: item.id), rtf)
    }

    /// `.externalStorage` only engages on a SQLite-backed store; an in-memory container
    /// keeps every blob inline whatever its size. The rest of this suite therefore only
    /// ever exercises the inline path, while the shipping app runs both.
    func testPayloadRoundTripThroughExternalStorage() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StashTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let diskStorage = StorageManager(
            storeURL: dir.appendingPathComponent("Stash.store"),
            crypto: crypto
        )
        let payload = Data((0..<(512 * 1024)).map { UInt8($0 % 251) })

        try diskStorage.save(
            contentType: .image,
            imageData: payload,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )

        // Premise guard: without this, raising the externalisation threshold would
        // silently turn this into a second inline test that still passes.
        let externalFiles = FileManager.default
            .enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.path.contains("_EXTERNAL_DATA") && !$0.hasDirectoryPath } ?? []
        XCTAssertFalse(
            externalFiles.isEmpty,
            "512 KB payload should be stored externally; if empty, raise the payload size"
        )

        let item = try XCTUnwrap(try diskStorage.fetchAll().first)
        XCTAssertEqual(try diskStorage.imageData(for: item.id), payload)

        try diskStorage.delete(entryWithID: item.id)
        XCTAssertNil(try diskStorage.imageData(for: item.id))
    }
}
