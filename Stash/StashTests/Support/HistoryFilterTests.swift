// ABOUTME: Tests for the shared history search filter used by the popover and history window.
// ABOUTME: Uses an in-memory ModelContainer to build real ClipboardItems rather than fixtures.

import XCTest
import SwiftData
@testable import Stash

@MainActor
final class HistoryFilterTests: XCTestCase {

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

    func testEmptyQueryReturnsEveryEntry() throws {
        try storage.save(contentType: .plainText, plainText: "One", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "Two", sourceAppBundleID: nil, sourceAppName: nil)

        let items = try storage.fetchAll()
        XCTAssertEqual(HistoryFilter.apply(items, query: "").count, 2)
    }

    func testQueryMatchesPlainTextAndExcludesTheRest() throws {
        try storage.save(contentType: .plainText, plainText: "apple pie", sourceAppBundleID: nil, sourceAppName: nil)
        try storage.save(contentType: .plainText, plainText: "banana bread", sourceAppBundleID: nil, sourceAppName: nil)

        let items = try storage.fetchAll()
        XCTAssertEqual(HistoryFilter.apply(items, query: "apple").map(\.plainText), ["apple pie"])
    }

    func testQueryIgnoresCaseAndDiacritics() throws {
        try storage.save(contentType: .plainText, plainText: "Crème brûlée", sourceAppBundleID: nil, sourceAppName: nil)

        let items = try storage.fetchAll()
        XCTAssertEqual(HistoryFilter.apply(items, query: "CREME BRULEE").count, 1)
    }

    func testQueryMatchesSourceAppName() throws {
        try storage.save(contentType: .plainText, plainText: "some snippet", sourceAppBundleID: "com.googlecode.iterm2", sourceAppName: "iTerm2")
        try storage.save(contentType: .plainText, plainText: "other snippet", sourceAppBundleID: "com.apple.Safari", sourceAppName: "Safari")

        let items = try storage.fetchAll()
        XCTAssertEqual(HistoryFilter.apply(items, query: "iterm").map(\.plainText), ["some snippet"])
    }

    func testQueryMatchesURL() throws {
        try storage.save(contentType: .url, urlString: "https://example.com/widgets", sourceAppBundleID: nil, sourceAppName: nil)

        let items = try storage.fetchAll()
        XCTAssertEqual(HistoryFilter.apply(items, query: "widgets").count, 1)
    }

    func testQueryMatchesFilePaths() throws {
        try storage.save(contentType: .fileURL, filePaths: ["/Users/test/Documents/report.pdf"], sourceAppBundleID: nil, sourceAppName: nil)

        let items = try storage.fetchAll()
        XCTAssertEqual(HistoryFilter.apply(items, query: "report.pdf").count, 1)
    }
}
