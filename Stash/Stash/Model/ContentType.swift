// ABOUTME: Content type classification for clipboard entries.
// ABOUTME: Detects the primary content type from pasteboard type arrays with defined priority.

import AppKit

enum ContentType: String, CaseIterable, Codable, Sendable {
    case plainText
    case richText
    case image
    case fileURL
    case url

    /// Detects the primary content type from a list of pasteboard types.
    /// Priority: image > fileURL > url > richText > plainText.
    /// Image is ahead of fileURL because screenshot tools (CleanShot, Shottr, macOS save-to-file)
    /// put BOTH the saved file path AND raw image bytes on the pasteboard — the user's intent is
    /// "I have an image," and the file path is an implementation detail of how it was captured.
    static func detect(from types: [NSPasteboard.PasteboardType]) -> ContentType? {
        let typeSet = Set(types)

        if typeSet.contains(.tiff) || typeSet.contains(.png) {
            return .image
        }

        if typeSet.contains(.fileURL) {
            return .fileURL
        }

        if typeSet.contains(.URL) {
            return .url
        }

        if typeSet.contains(.rtf) || typeSet.contains(.html) {
            return .richText
        }

        if typeSet.contains(.string) {
            return .plainText
        }

        return nil
    }
}
