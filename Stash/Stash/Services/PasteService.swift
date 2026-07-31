// ABOUTME: Writes a clipboard entry back to NSPasteboard for pasting.
// ABOUTME: Handles all content types and prevents self-capture via monitor notification.

import AppKit

@MainActor
final class PasteService {
    private let pasteboard: NSPasteboard
    private let monitor: ClipboardMonitor
    private let storage: StorageManager

    init(pasteboard: NSPasteboard = .general, monitor: ClipboardMonitor, storage: StorageManager) {
        self.pasteboard = pasteboard
        self.monitor = monitor
        self.storage = storage
    }

    /// Returns false when the entry's payload could no longer be loaded, which happens
    /// if the row was pruned between the last refresh and this click. Callers must not
    /// report success in that case.
    @discardableResult
    func paste(_ entry: ClipboardItem) -> Bool {
        pasteboard.clearContents()
        var pasted = true

        switch entry.contentType {
        case .plainText:
            pasteboard.setString(entry.plainText ?? "", forType: .string)

        case .url:
            let urlString = entry.urlString ?? entry.plainText ?? ""
            pasteboard.setString(urlString, forType: .string)

        case .image:
            if let data = try? storage.imageData(for: entry.id) {
                pasteboard.setData(data, forType: .png)
            } else {
                pasted = false
            }

        case .richText:
            let item = NSPasteboardItem()
            let rtfData = try? storage.richTextData(for: entry.id)
            if let rtfData {
                item.setData(rtfData, forType: .rtf)
            }
            if let text = entry.plainText {
                item.setString(text, forType: .string)
            }
            // The plain-text fallback still lands even when the formatted bytes are
            // unavailable, so that counts as a paste — degraded, but not a failure.
            pasted = rtfData != nil || entry.plainText != nil
            pasteboard.writeObjects([item])

        case .fileURL:
            if let paths = entry.filePaths {
                let urls = paths.compactMap { URL(fileURLWithPath: $0) as NSURL }
                pasteboard.writeObjects(urls)
            }
            if let text = entry.plainText {
                pasteboard.setString(text, forType: .string)
            }
        }

        monitor.markOwnChangeCount(pasteboard.changeCount)
        return pasted
    }
}
