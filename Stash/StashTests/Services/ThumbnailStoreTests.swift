// ABOUTME: Tests for ThumbnailStore decoding, dimension labels, and cache eviction.
// ABOUTME: Uses real encoded PNGs so the ImageIO paths actually run.

import XCTest
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AppKit
import SwiftData
@testable import Stash

@MainActor
final class ThumbnailStoreTests: XCTestCase {

    /// A real encoded PNG. The rest of the suite's 4-byte fixtures are not decodable
    /// images, so any thumbnail or dimension logic silently no-ops on them.
    private func makePNG(width: Int, height: Int) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = UInt8(i % 251)
            pixels[i + 1] = UInt8((i / 3) % 251)
            pixels[i + 2] = UInt8((i / 7) % 251)
            pixels[i + 3] = 255
        }

        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func makeIdentifiers(_ count: Int) throws -> [PersistentIdentifier] {
        let crypto = CryptoService(keychainService: "com.hexul.Stash.tests.\(UUID().uuidString)")
        defer { crypto.deleteKey() }
        let storage = StorageManager(inMemory: true, crypto: crypto)
        storage.historyLimit = count + 1

        for index in 0..<count {
            try storage.save(
                contentType: .plainText,
                plainText: "entry-\(index)",
                sourceAppBundleID: nil,
                sourceAppName: nil
            )
        }
        return try storage.fetchAll().map(\.id)
    }

    func testMakeReturnsThumbnailAndDimensionLabel() async throws {
        let png = try makePNG(width: 64, height: 32)
        let id = try await makeIdentifiers(1)[0]
        let store = ThumbnailStore()

        let made = await store.make(for: id, from: png)

        let thumbnail = try XCTUnwrap(made)
        XCTAssertEqual(thumbnail.label, "64×32 image")
        XCTAssertGreaterThan(thumbnail.image.size.width, 0)
    }

    func testCachedReturnsEntryAfterMake() async throws {
        let png = try makePNG(width: 32, height: 32)
        let id = try await makeIdentifiers(1)[0]
        let store = ThumbnailStore()

        let before = await store.cached(id)
        XCTAssertNil(before)

        _ = await store.make(for: id, from: png)

        let after = await store.cached(id)
        XCTAssertEqual(after?.label, "32×32 image")
    }

    func testEvictsOldestBeyondCapacity() async throws {
        let png = try makePNG(width: 16, height: 16)
        let ids = try await makeIdentifiers(21)
        let store = ThumbnailStore()

        for id in ids {
            _ = await store.make(for: id, from: png)
        }

        let evicted = await store.cached(ids[0])
        XCTAssertNil(evicted, "Oldest entry should be evicted at capacity")
        for id in ids.dropFirst() {
            let survivor = await store.cached(id)
            XCTAssertNotNil(survivor)
        }
    }

    func testMakeReturnsNilForGarbageData() async throws {
        let id = try await makeIdentifiers(1)[0]
        let store = ThumbnailStore()

        let made = await store.make(for: id, from: Data([0xDE, 0xAD, 0xBE, 0xEF]))

        XCTAssertNil(made)
    }
}
