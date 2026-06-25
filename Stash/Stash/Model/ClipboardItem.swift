// ABOUTME: Value-type snapshot of a clipboard entry for display and re-paste.
// ABOUTME: Carries decrypted content detached from SwiftData so views never retain a ModelContext.

import Foundation
import SwiftData

struct ClipboardItem: Identifiable, Sendable {
    let id: PersistentIdentifier
    let timestamp: Date
    let contentType: ContentType
    let plainText: String?
    let urlString: String?
    let filePaths: [String]?
    let imageData: Data?
    let richTextData: Data?
    let sourceAppName: String?
    let isPinned: Bool

    /// Projects a managed entry into a detached snapshot.
    /// The caller is responsible for decrypting the entry's fields first.
    init(_ entry: ClipboardEntry) {
        self.id = entry.persistentModelID
        self.timestamp = entry.timestamp
        self.contentType = entry.contentType
        self.plainText = entry.plainText
        self.urlString = entry.urlString
        self.filePaths = entry.filePaths
        self.imageData = entry.imageData
        self.richTextData = entry.richTextData
        self.sourceAppName = entry.sourceAppName
        self.isPinned = entry.isPinned
    }
}
