// ABOUTME: Value-type snapshot of a clipboard entry for display and re-paste.
// ABOUTME: Excludes image and rich-text payloads; those are fetched on demand by id.

import Foundation
import SwiftData

/// Carries only what a row renders. Payload bytes stay out of it: SwiftUI retains
/// successive generations of whatever lands in `@State`, so an image carried here
/// costs one copy per live generation. Payloads load on demand from StorageManager.
struct ClipboardItem: Identifiable, Sendable {
    let id: PersistentIdentifier
    let timestamp: Date
    let contentType: ContentType
    let plainText: String?
    let urlString: String?
    let filePaths: [String]?
    let sourceAppName: String?
    let isPinned: Bool
}
