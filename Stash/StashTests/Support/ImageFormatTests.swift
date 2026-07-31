// ABOUTME: Tests that captured image bytes are identified by their real format.
// ABOUTME: Encodes genuine PNG, TIFF and JPEG data rather than asserting on stub bytes.

import XCTest
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AppKit
@testable import Stash

final class ImageFormatTests: XCTestCase {

    private func encode(_ contentType: UTType) throws -> Data {
        let width = 8, height = 8, bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0x7F, count: bytesPerRow * height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, contentType.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testPNGBytesArePasteboardPNG() throws {
        XCTAssertEqual(ImageFormat.pasteboardType(of: try encode(.png)), .png)
    }

    /// The monitor falls back to TIFF whenever the pasteboard carries no PNG, so these
    /// bytes must not be handed to consumers labelled as PNG.
    func testTIFFBytesArePasteboardTIFF() throws {
        XCTAssertEqual(ImageFormat.pasteboardType(of: try encode(.tiff)), .tiff)
    }

    /// Image files read off disk can be any format the monitor recognises.
    func testJPEGBytesKeepTheirOwnType() throws {
        let type = ImageFormat.pasteboardType(of: try encode(.jpeg))
        XCTAssertEqual(type.rawValue, UTType.jpeg.identifier)
    }

    func testUndecodableBytesFallBackToPNG() {
        XCTAssertEqual(ImageFormat.pasteboardType(of: Data([0xDE, 0xAD, 0xBE, 0xEF])), .png)
    }

    func testFileExtensionMatchesTheBytes() throws {
        XCTAssertEqual(ImageFormat.fileExtension(of: try encode(.png)), "png")
        XCTAssertEqual(ImageFormat.fileExtension(of: try encode(.jpeg)), "jpeg")
        XCTAssertEqual(ImageFormat.fileExtension(of: Data([0x00, 0x01])), "png")
    }
}
