// ABOUTME: Tests for ContentType enum and its pasteboard type detection logic.
// ABOUTME: Verifies detection priority: fileURL > image > url > richText > plainText.

import XCTest
import AppKit
@testable import Stash

final class ContentTypeTests: XCTestCase {

    // MARK: - Raw value round-tripping

    func testRawValueRoundTrip() {
        for type in ContentType.allCases {
            XCTAssertEqual(ContentType(rawValue: type.rawValue), type)
        }
    }

    // MARK: - Detection priority

    func testDetectsFileURL() {
        let types: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .string,
        ]
        XCTAssertEqual(ContentType.detect(from: types), .fileURL)
    }

    func testDetectsImage() {
        let types: [NSPasteboard.PasteboardType] = [
            .tiff,
            .string,
        ]
        XCTAssertEqual(ContentType.detect(from: types), .image)
    }

    func testDetectsPNG() {
        let types: [NSPasteboard.PasteboardType] = [
            .png,
        ]
        XCTAssertEqual(ContentType.detect(from: types), .image)
    }

    func testDetectsURL() {
        let types: [NSPasteboard.PasteboardType] = [
            .URL,
            .string,
        ]
        XCTAssertEqual(ContentType.detect(from: types), .url)
    }

    func testDetectsRichText() {
        let types: [NSPasteboard.PasteboardType] = [
            .rtf,
            .string,
        ]
        XCTAssertEqual(ContentType.detect(from: types), .richText)
    }

    func testDetectsHTML() {
        let types: [NSPasteboard.PasteboardType] = [
            .html,
            .string,
        ]
        XCTAssertEqual(ContentType.detect(from: types), .richText)
    }

    func testDetectsPlainText() {
        let types: [NSPasteboard.PasteboardType] = [
            .string,
        ]
        XCTAssertEqual(ContentType.detect(from: types), .plainText)
    }

    func testReturnsNilForEmpty() {
        XCTAssertNil(ContentType.detect(from: []))
    }

    func testReturnsNilForUnknownTypes() {
        let types: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("com.example.unknown"),
        ]
        XCTAssertNil(ContentType.detect(from: types))
    }

    // MARK: - Priority ordering

    func testFileURLTakesPriorityOverImage() {
        let types: [NSPasteboard.PasteboardType] = [.tiff, .fileURL]
        XCTAssertEqual(ContentType.detect(from: types), .fileURL)
    }

    func testImageTakesPriorityOverURL() {
        let types: [NSPasteboard.PasteboardType] = [.URL, .tiff]
        XCTAssertEqual(ContentType.detect(from: types), .image)
    }

    func testURLTakesPriorityOverRichText() {
        let types: [NSPasteboard.PasteboardType] = [.rtf, .URL, .string]
        XCTAssertEqual(ContentType.detect(from: types), .url)
    }

    func testRichTextTakesPriorityOverPlainText() {
        let types: [NSPasteboard.PasteboardType] = [.string, .rtf]
        XCTAssertEqual(ContentType.detect(from: types), .richText)
    }
}
