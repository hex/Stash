// ABOUTME: Tests for PasteService placing various content types on NSPasteboard.
// ABOUTME: Verifies correct pasteboard types and self-capture prevention.

import XCTest
@preconcurrency import AppKit
@testable import Stash

@MainActor
final class PasteServiceTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var pasteService: PasteService!
    private var monitor: ClipboardMonitor!
    private var storage: StorageManager!
    private var crypto: CryptoService!

    override func setUp() {
        super.setUp()
        let pb = NSPasteboard(name: .init("com.hexul.Stash.test.\(UUID().uuidString)"))
        pasteboard = pb
        monitor = ClipboardMonitor()
        crypto = CryptoService(keychainService: "com.hexul.Stash.tests.\(UUID().uuidString)")
        storage = StorageManager(inMemory: true, crypto: crypto)
        pasteService = PasteService(pasteboard: pb, monitor: monitor, storage: storage)
    }

    override func tearDown() {
        pasteboard?.releaseGlobally()
        crypto?.deleteKey()
        pasteService = nil
        monitor = nil
        storage = nil
        crypto = nil
        pasteboard = nil
        super.tearDown()
    }

    /// Round-trips content through the store so tests exercise the same encrypt →
    /// persist → decrypt path the app uses, rather than a hand-built snapshot.
    private func storedItem(
        contentType: ContentType,
        plainText: String? = nil,
        urlString: String? = nil,
        filePaths: [String]? = nil,
        imageData: Data? = nil,
        richTextData: Data? = nil
    ) throws -> ClipboardItem {
        try storage.save(
            contentType: contentType,
            plainText: plainText,
            urlString: urlString,
            filePaths: filePaths,
            imageData: imageData,
            richTextData: richTextData,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        return try XCTUnwrap(try storage.fetchAll().first)
    }

    // MARK: - Plain text

    func testPastePlainText() throws {
        pasteService.paste(try storedItem(contentType: .plainText, plainText: "Hello, world!"))

        XCTAssertEqual(pasteboard.string(forType: .string), "Hello, world!")
    }

    // MARK: - URL

    func testPasteURL() throws {
        pasteService.paste(try storedItem(
            contentType: .url,
            plainText: "https://example.com",
            urlString: "https://example.com"
        ))

        XCTAssertEqual(pasteboard.string(forType: .string), "https://example.com")
    }

    // MARK: - Image

    func testPasteImage() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        pasteService.paste(try storedItem(contentType: .image, imageData: imageData))

        XCTAssertEqual(
            pasteboard.data(forType: .png), imageData,
            "Full-fidelity bytes must survive encrypt → store → decrypt"
        )
    }

    // MARK: - Rich text

    func testPasteRichTextIncludesPlainFallback() throws {
        let rtfData = Data("{\\rtf1 Hello}".utf8)
        pasteService.paste(try storedItem(
            contentType: .richText,
            plainText: "Hello",
            richTextData: rtfData
        ))

        XCTAssertEqual(pasteboard.data(forType: .rtf), rtfData, "RTF data should be on pasteboard")
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello", "Plain text fallback should be present")
    }

    // MARK: - File URLs

    func testPasteFileURLs() throws {
        pasteService.paste(try storedItem(
            contentType: .fileURL,
            plainText: "/tmp/test.txt",
            filePaths: ["/tmp/test.txt"]
        ))

        XCTAssertEqual(pasteboard.string(forType: .string), "/tmp/test.txt")
    }

    /// A rich-text entry whose formatted bytes are gone still places its plain-text
    /// fallback, so it reports a paste rather than a failure.
    func testPasteRichTextReportsSuccessOnPlainFallbackAlone() throws {
        let item = try storedItem(
            contentType: .richText,
            plainText: "Hello",
            richTextData: Data("{\\rtf1 Hello}".utf8)
        )
        try storage.delete(entryWithID: item.id)

        let pasted = pasteService.paste(item)

        XCTAssertTrue(pasted, "Plain-text fallback landed, so this is a degraded paste, not a failure")
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello")
        XCTAssertNil(pasteboard.data(forType: .rtf), "Formatted bytes are gone with the row")
    }

    func testPasteImageReportsFailureWhenPayloadGone() throws {
        let item = try storedItem(contentType: .image, imageData: Data([0x89, 0x50, 0x4E, 0x47]))
        try storage.delete(entryWithID: item.id)

        let pasted = pasteService.paste(item)

        XCTAssertFalse(pasted, "Nothing was placed, so the caller must not claim success")
        XCTAssertNil(pasteboard.data(forType: .png))
    }

    // MARK: - Self-capture prevention

    func testPasteUpdatesMonitorChangeCount() throws {
        let beforeCount = pasteboard.changeCount
        pasteService.paste(try storedItem(contentType: .plainText, plainText: "test"))

        XCTAssertGreaterThan(pasteboard.changeCount, beforeCount)
    }
}
