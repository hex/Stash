// ABOUTME: Polls NSPasteboard.general for changes and extracts clipboard content.
// ABOUTME: Filters out privacy-marked and excluded-app content before firing callbacks.

import AppKit
import Foundation
import os.log

private let monitorLog = Logger(subsystem: "com.hexul.Stash", category: "monitor")

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

    private var tickCount = 0

    func start() {
        monitorLog.warning("ClipboardMonitor starting, initial changeCount=\(self.lastChangeCount)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tickCount += 1
                if self.tickCount <= 3 {
                    monitorLog.warning("Timer tick #\(self.tickCount), changeCount=\(NSPasteboard.general.changeCount)")
                }
                self.checkForChanges()
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

        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let pid = Self.sourceWindowOwnerPID(from: windowList, ownBundleID: ownBundleID, ownPID: ownPID) {
            let app = NSRunningApplication(processIdentifier: pid)
            if let app, app.activationPolicy == .regular || app.activationPolicy == .accessory {
                return app
            }
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

    // MARK: - Static source window detection (testable)

    /// Finds the PID of the app owning the topmost normal window in a window list.
    /// Skips windows that are too small, at non-zero layers, or owned by this app.
    nonisolated static func sourceWindowOwnerPID(
        from windowList: [[String: Any]],
        ownBundleID: String?,
        ownPID: pid_t? = nil
    ) -> pid_t? {
        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Int,
                  let height = bounds["Height"] as? Int,
                  width > 50, height > 50 else {
                continue
            }
            if let ownPID, pid == ownPID { continue }
            return pid
        }
        return nil
    }

    // MARK: - Private

    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        monitorLog.warning("clipboard changed \(self.lastChangeCount) -> \(currentCount), isPaused=\(self.isPaused)")
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
        let imageData = extractImageData(from: pasteboard, item: item)
        let richTextData = item.data(forType: .rtf)

        let plainTextHasContent = plainText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasUsableContent = plainTextHasContent
            || imageData != nil
            || richTextData != nil
            || (filePaths?.isEmpty == false)
        guard hasUsableContent else { return }

        var displayBundleID = sourceBundleID
        var displayAppName = source?.localizedName

        if contentType == .image, let writer = detectWriterApp(filePaths: filePaths) {
            displayAppName = writer.name
            if let bundleID = writer.bundleID { displayBundleID = bundleID }
        }

        onClipboardChange?(
            contentType, plainText, urlString, filePaths,
            imageData, richTextData,
            displayBundleID, displayAppName
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

    private func extractImageData(from pasteboard: NSPasteboard, item: NSPasteboardItem) -> Data? {
        if let data = item.data(forType: .png) ?? item.data(forType: .tiff) {
            return data
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return data
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiffData = image.tiffRepresentation {
            return tiffData
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL],
           let url = urls.first,
           Self.isLikelyImageFile(url),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return nil
    }

    /// Identifies the writing app from file paths in `~/Library/Application Support/<AppName>/`.
    /// Used to override topmost-window attribution for screenshot tools (CleanShot, Shottr, etc.)
    /// that write to the pasteboard from background helper processes.
    private func detectWriterApp(filePaths: [String]?) -> (name: String, bundleID: String?)? {
        guard let paths = filePaths else { return nil }
        let marker = "/Library/Application Support/"

        for path in paths {
            guard let range = path.range(of: marker) else { continue }
            let after = path[range.upperBound...]
            guard let slashIndex = after.firstIndex(of: "/") else { continue }
            let appDir = String(after[..<slashIndex])
            if appDir.isEmpty { continue }

            for app in NSWorkspace.shared.runningApplications {
                guard let name = app.localizedName else { continue }
                if name == appDir || name.hasPrefix(appDir) || appDir.hasPrefix(name) {
                    return (name, app.bundleIdentifier)
                }
            }

            return (appDir, nil)
        }
        return nil
    }

    nonisolated static func isLikelyImageFile(_ url: URL) -> Bool {
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "tiff", "tif", "webp", "heic", "heif", "bmp", "avif"
        ]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
}
