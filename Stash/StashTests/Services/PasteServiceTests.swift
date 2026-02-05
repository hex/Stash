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

    override func setUp() {
        super.setUp()
        let pb = NSPasteboard(name: .init("com.hexul.Stash.test.\(UUID().uuidString)"))
        pasteboard = pb
        monitor = ClipboardMonitor()
        pasteService = PasteService(pasteboard: pb, monitor: monitor)
    }

    override func tearDown() {
        pasteboard?.releaseGlobally()
        pasteService = nil
        monitor = nil
        pasteboard = nil
        super.tearDown()
    }

    // MARK: - Plain text

    func testPastePlainText() {
        let entry = ClipboardEntry(
            contentType: .plainText,
            plainText: "Hello, world!",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        pasteService.paste(entry)

        XCTAssertEqual(pasteboard.string(forType: .string), "Hello, world!")
    }

    // MARK: - URL

    func testPasteURL() {
        let entry = ClipboardEntry(
            contentType: .url,
            plainText: "https://example.com",
            urlString: "https://example.com",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        pasteService.paste(entry)

        XCTAssertEqual(pasteboard.string(forType: .string), "https://example.com")
    }

    // MARK: - Image

    func testPasteImage() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let entry = ClipboardEntry(
            contentType: .image,
            imageData: imageData,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        pasteService.paste(entry)

        XCTAssertNotNil(pasteboard.data(forType: .png))
    }

    // MARK: - Rich text

    func testPasteRichTextIncludesPlainFallback() {
        let rtfData = "{\\rtf1 Hello}".data(using: .utf8)!
        let entry = ClipboardEntry(
            contentType: .richText,
            plainText: "Hello",
            richTextData: rtfData,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        pasteService.paste(entry)

        XCTAssertNotNil(pasteboard.data(forType: .rtf), "RTF data should be on pasteboard")
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello", "Plain text fallback should be present")
    }

    // MARK: - File URLs

    func testPasteFileURLs() {
        let paths = ["/tmp/test.txt"]
        let entry = ClipboardEntry(
            contentType: .fileURL,
            plainText: "/tmp/test.txt",
            filePaths: paths,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        pasteService.paste(entry)

        let pastedString = pasteboard.string(forType: .string)
        XCTAssertEqual(pastedString, "/tmp/test.txt")
    }

    // MARK: - Self-capture prevention

    func testPasteUpdatesMonitorChangeCount() {
        let beforeCount = pasteboard.changeCount
        let entry = ClipboardEntry(
            contentType: .plainText,
            plainText: "test",
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
        pasteService.paste(entry)

        XCTAssertGreaterThan(pasteboard.changeCount, beforeCount)
    }
}
