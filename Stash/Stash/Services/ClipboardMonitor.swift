// ABOUTME: Polls NSPasteboard.general for changes and extracts clipboard content.
// ABOUTME: Filters out privacy-marked and excluded-app content before firing callbacks.

import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    typealias ChangeHandler = (ContentType, String?, String?, [String]?, Data?, Data?, String?, String?) -> Void

    var onClipboardChange: ChangeHandler?
    var excludedBundleIDs: Set<String> = []
    var isPaused: Bool = false

    private var timer: Timer?
    private var lastChangeCount: Int
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkForChanges()
            }
        }
    }

    /// Finds the app owning the topmost on-screen window.
    /// Uses CGWindowList to detect non-activating panels (e.g. iTerm quake window)
    /// that don't register as frontmostApplication.
    private var topmostWindowOwner: NSRunningApplication? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return NSWorkspace.shared.frontmostApplication
        }

        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }
            let app = NSRunningApplication(processIdentifier: pid)
            // Skip our own windows and background processes
            if app?.bundleIdentifier == ownBundleID { continue }
            if app?.activationPolicy != .regular && app?.activationPolicy != .accessory { continue }
            return app
        }

        return NSWorkspace.shared.frontmostApplication
    }

    /// Called by PasteService to prevent self-capture after writing to the pasteboard
    func markOwnChangeCount(_ count: Int) {
        lastChangeCount = count
    }

    // MARK: - Static filtering (testable)

    nonisolated static func shouldSkip(
        types: [NSPasteboard.PasteboardType],
        excludedBundleIDs: Set<String>,
        frontmostBundleID: String? = nil
    ) -> Bool {
        // Check privacy markers
        let typeSet = Set(types)
        if !typeSet.isDisjoint(with: PasteboardConstants.concealedMarkers) {
            return true
        }

        // Check excluded apps
        if let bundleID = frontmostBundleID, excludedBundleIDs.contains(bundleID) {
            return true
        }

        return false
    }

    // MARK: - Private

    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard !isPaused else { return }

        guard let items = pasteboard.pasteboardItems, let item = items.first else { return }
        let types = item.types

        let source = topmostWindowOwner
        let sourceBundleID = source?.bundleIdentifier

        guard !Self.shouldSkip(
            types: types,
            excludedBundleIDs: excludedBundleIDs,
            frontmostBundleID: sourceBundleID
        ) else { return }

        guard let contentType = ContentType.detect(from: types) else { return }

        let plainText = item.string(forType: .string)
        let urlString = item.string(forType: .URL) ?? extractURL(from: plainText)
        let filePaths = extractFilePaths(from: pasteboard)
        let imageData = extractImageData(from: item)
        let richTextData = item.data(forType: .rtf)

        let appName = source?.localizedName

        onClipboardChange?(
            contentType, plainText, urlString, filePaths,
            imageData, richTextData,
            sourceBundleID, appName
        )
    }

    private func extractURL(from plainText: String?) -> String? {
        guard let text = plainText,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length == text.utf16.count else {
            return nil
        }
        return match.url?.absoluteString
    }

    private func extractFilePaths(from pasteboard: NSPasteboard) -> [String]? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            return nil
        }
        return urls.map(\.path)
    }

    private func extractImageData(from item: NSPasteboardItem) -> Data? {
        item.data(forType: .png) ?? item.data(forType: .tiff)
    }
}
