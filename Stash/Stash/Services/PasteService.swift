// ABOUTME: Writes a clipboard entry back to NSPasteboard for pasting.
// ABOUTME: Handles all content types and prevents self-capture via monitor notification.

import AppKit

@MainActor
final class PasteService {
    private let pasteboard: NSPasteboard
    private let monitor: ClipboardMonitor

    init(pasteboard: NSPasteboard = .general, monitor: ClipboardMonitor) {
        self.pasteboard = pasteboard
        self.monitor = monitor
    }

    func paste(_ entry: ClipboardEntry) {
        pasteboard.clearContents()

        switch entry.contentType {
        case .plainText:
            pasteboard.setString(entry.plainText ?? "", forType: .string)

        case .url:
            let urlString = entry.urlString ?? entry.plainText ?? ""
            pasteboard.setString(urlString, forType: .string)

        case .image:
            if let data = entry.imageData {
                pasteboard.setData(data, forType: .png)
            }

        case .richText:
            let item = NSPasteboardItem()
            if let rtfData = entry.richTextData {
                item.setData(rtfData, forType: .rtf)
            }
            if let text = entry.plainText {
                item.setString(text, forType: .string)
            }
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
    }
}
