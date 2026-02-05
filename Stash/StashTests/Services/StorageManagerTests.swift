// ABOUTME: Tests for StorageManager CRUD, consecutive dedup, history limit, and pinning.
// ABOUTME: Uses in-memory ModelContainer for test isolation.

import XCTest
import SwiftData
@testable import Stash

@MainActor
final class StorageManagerTests: XCTestCase {

    private var storage: StorageManager!

    override func setUp() {
        super.setUp()
        storage = StorageManager(inMemory: true)
    }

    override func tearDown() {
        storage = nil
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

    // MARK: - Delete

    func testDeleteEntry() throws {
        let entry = try storage.save(contentType: .plainText, plainText: "Delete me", sourceAppBundleID: nil, sourceAppName: nil)!
        try storage.delete(entry)

        let entries = try storage.fetchAll()
        XCTAssertEqual(entries.count, 0)
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

    // MARK: - Search

    func testSearchFiltersByText() throws {
        try storage.save(contentType: .plainText, plainText: "Hello world", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "Goodbye world", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "Unrelated", sourceAppBundleID: nil, sourceAppName: nil)

        let results = try storage.search("world")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchIsCaseInsensitive() throws {
        try storage.save(contentType: .plainText, plainText: "HELLO", sourceAppBundleID: nil, sourceAppName: nil)

        let results = try storage.search("hello")
        XCTAssertEqual(results.count, 1)
    }
}
