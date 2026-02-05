// ABOUTME: SwiftData model representing a single clipboard history entry.
// ABOUTME: Stores content, metadata, source app info, and a content hash for dedup.

import Foundation
import SwiftData
import CryptoKit

@Model
final class ClipboardEntry {
    var timestamp: Date
    var contentTypeRaw: String
    var plainText: String?
    var urlString: String?
    var filePathsJSON: String?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var isPinned: Bool
    var contentHash: String

    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var richTextData: Data?

    var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .plainText }
        set { contentTypeRaw = newValue.rawValue }
    }

    var filePaths: [String]? {
        get {
            guard let json = filePathsJSON else { return nil }
            return try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        }
        set {
            guard let paths = newValue else { filePathsJSON = nil; return }
            filePathsJSON = String(data: try! JSONEncoder().encode(paths), encoding: .utf8)
        }
    }

    init(
        contentType: ContentType,
        plainText: String? = nil,
        urlString: String? = nil,
        filePaths: [String]? = nil,
        imageData: Data? = nil,
        richTextData: Data? = nil,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        self.timestamp = Date()
        self.contentTypeRaw = contentType.rawValue
        self.plainText = plainText
        self.urlString = urlString
        self.imageData = imageData
        self.richTextData = richTextData
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.isPinned = false

        if let paths = filePaths {
            self.filePathsJSON = String(data: try! JSONEncoder().encode(paths), encoding: .utf8)
        } else {
            self.filePathsJSON = nil
        }

        self.contentHash = Self.computeHash(
            contentType: contentType,
            plainText: plainText,
            imageData: imageData,
            richTextData: richTextData
        )
    }

    static func computeHash(
        contentType: ContentType,
        plainText: String?,
        imageData: Data?,
        richTextData: Data?
    ) -> String {
        var data = Data()

        switch contentType {
        case .image:
            if let imageData { data.append(imageData) }
        case .richText:
            if let richTextData { data.append(richTextData) }
            else if let text = plainText { data.append(Data(text.utf8)) }
        default:
            if let text = plainText { data.append(Data(text.utf8)) }
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
