// ABOUTME: Identifies the real format of captured image bytes.
// ABOUTME: Clipboard images arrive as PNG, TIFF, or whatever an image file on disk held.

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat {
    /// The pasteboard type matching the bytes themselves.
    ///
    /// `ClipboardMonitor.extractImageData` falls back to TIFF when the pasteboard carries
    /// no PNG, and reads whole image files off disk for the formats it recognises, so the
    /// bytes have to be asked rather than assumed. Undecodable data falls back to PNG,
    /// which at worst reproduces what a consumer would have received anyway.
    static func pasteboardType(of data: Data) -> NSPasteboard.PasteboardType {
        guard let type = contentType(of: data) else { return .png }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .tiff) { return .tiff }
        return NSPasteboard.PasteboardType(type.identifier)
    }

    /// The filename extension matching the bytes, for writing a preview file that
    /// Finder and Preview will open with the right handler.
    static func fileExtension(of data: Data) -> String {
        contentType(of: data)?.preferredFilenameExtension ?? "png"
    }

    private static func contentType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String? else {
            return nil
        }
        return UTType(identifier)
    }
}
