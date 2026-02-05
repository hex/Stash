// ABOUTME: Tests for ClipboardEntry SwiftData model creation and hash computation.
// ABOUTME: Uses in-memory ModelContainer for isolation.

import XCTest
import SwiftData
@testable import Stash

final class ClipboardEntryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([ClipboardEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Creation

    func testCreatePlainTextEntry() {
        let entry = ClipboardEntry(
            contentType: .plainText,
            plainText: "Hello, world!",
            sourceAppBundleID: "com.apple.TextEdit",
            sourceAppName: "TextEdit"
        )
        context.insert(entry)
        try! context.save()

        let entries = try! context.fetch(FetchDescriptor<ClipboardEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].plainText, "Hello, world!")
        XCTAssertEqual(entries[0].contentType, .plainText)
        XCTAssertEqual(entries[0].sourceAppBundleID, "com.apple.TextEdit")
        XCTAssertEqual(entries[0].sourceAppName, "TextEdit")
        XCTAssertFalse(entries[0].isPinned)
    }

    func testCreateURLEntry() {
        let entry = ClipboardEntry(
            contentType: .url,
            plainText: "https://example.com",
            urlString: "https://example.com",
            sourceAppBundleID: "com.apple.Safari",
            sourceAppName: "Safari"
        )
        context.insert(entry)
        try! context.save()

        let entries = try! context.fetch(FetchDescriptor<ClipboardEntry>())
        XCTAssertEqual(entries[0].contentType, .url)
        XCTAssertEqual(entries[0].urlString, "https://example.com")
    }

    func testCreateImageEntry() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        let entry = ClipboardEntry(
            contentType: .image,
            imageData: imageData,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        context.insert(entry)
        try! context.save()

        let entries = try! context.fetch(FetchDescriptor<ClipboardEntry>())
        XCTAssertEqual(entries[0].contentType, .image)
        XCTAssertEqual(entries[0].imageData, imageData)
        XCTAssertNil(entries[0].plainText)
    }

    func testCreateFileURLEntry() {
        let paths = ["/Users/test/file.txt", "/Users/test/file2.txt"]
        let entry = ClipboardEntry(
            contentType: .fileURL,
            plainText: paths.joined(separator: "\n"),
            filePaths: paths,
            sourceAppBundleID: "com.apple.finder",
            sourceAppName: "Finder"
        )
        context.insert(entry)
        try! context.save()

        let entries = try! context.fetch(FetchDescriptor<ClipboardEntry>())
        XCTAssertEqual(entries[0].contentType, .fileURL)
        XCTAssertEqual(entries[0].filePaths, paths)
    }

    func testCreateRichTextEntry() {
        let rtfData = "{\\rtf1 Hello}".data(using: .utf8)!
        let entry = ClipboardEntry(
            contentType: .richText,
            plainText: "Hello",
            richTextData: rtfData,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        context.insert(entry)
        try! context.save()

        let entries = try! context.fetch(FetchDescriptor<ClipboardEntry>())
        XCTAssertEqual(entries[0].contentType, .richText)
        XCTAssertEqual(entries[0].richTextData, rtfData)
        XCTAssertEqual(entries[0].plainText, "Hello")
    }

    // MARK: - Content hash

    func testContentHashDeterministic() {
        let entry1 = ClipboardEntry(
            contentType: .plainText,
            plainText: "test content",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        let entry2 = ClipboardEntry(
            contentType: .plainText,
            plainText: "test content",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        XCTAssertEqual(entry1.contentHash, entry2.contentHash)
        XCTAssertFalse(entry1.contentHash.isEmpty)
    }

    func testContentHashDiffersForDifferentContent() {
        let entry1 = ClipboardEntry(
            contentType: .plainText,
            plainText: "hello",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        let entry2 = ClipboardEntry(
            contentType: .plainText,
            plainText: "world",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        XCTAssertNotEqual(entry1.contentHash, entry2.contentHash)
    }

    func testContentHashUsesImageDataForImages() {
        let data1 = Data([1, 2, 3])
        let data2 = Data([4, 5, 6])
        let entry1 = ClipboardEntry(
            contentType: .image,
            imageData: data1,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        let entry2 = ClipboardEntry(
            contentType: .image,
            imageData: data2,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        XCTAssertNotEqual(entry1.contentHash, entry2.contentHash)
    }

    // MARK: - Pin

    func testDefaultUnpinned() {
        let entry = ClipboardEntry(
            contentType: .plainText,
            plainText: "test",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        XCTAssertFalse(entry.isPinned)
    }

    // MARK: - Timestamp

    func testTimestampIsAutoSet() {
        let before = Date()
        let entry = ClipboardEntry(
            contentType: .plainText,
            plainText: "test",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        let after = Date()
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }
}
