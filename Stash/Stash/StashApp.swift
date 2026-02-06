// ABOUTME: Main app entry point with custom NSStatusItem for animated menu bar icon.
// ABOUTME: Configures SwiftData container and wires up services.

import SwiftUI
import SwiftData

@main
struct StashApp: App {
    @State private var appController = AppController()

    var body: some Scene {
        Settings {
            SettingsView(preferences: appController.preferences)
        }
    }
}

/// Coordinates all services and manages the app lifecycle.
@MainActor
@Observable
final class AppController {
    let storage: StorageManager
    let preferences: Preferences
    private let monitor: ClipboardMonitor
    private let hotkeyManager: HotkeyManager
    private let pasteService: PasteService
    private var panelController: PanelController?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var started = false

    init() {
        self.preferences = Preferences()
        self.storage = StorageManager()
        self.monitor = ClipboardMonitor()
        self.hotkeyManager = HotkeyManager()
        self.pasteService = PasteService(monitor: monitor)

        storage.historyLimit = preferences.historyLimit
        monitor.excludedBundleIDs = preferences.excludedBundleIDs
        monitor.isPaused = preferences.isPaused

        monitor.onClipboardChange = { [weak self] contentType, plainText, urlString, filePaths, imageData, richTextData, bundleID, appName in
            guard let self else { return }
            do {
                try self.storage.save(
                    contentType: contentType,
                    plainText: plainText,
                    urlString: urlString,
                    filePaths: filePaths,
                    imageData: imageData,
                    richTextData: richTextData,
                    sourceAppBundleID: bundleID,
                    sourceAppName: appName
                )
                self.animateStatusIcon()
            } catch {
                debugLog("save FAILED: \(error)")
            }
        }

        let controller = PanelController(storage: storage) { [weak self] entry in
            self?.paste(entry)
        }
        self.panelController = controller

        hotkeyManager.onHotkey = { [weak self] in
            self?.togglePanel()
        }

        DispatchQueue.main.async { [self] in
            self.setupStatusItem()
            self.startServices()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "Stash clipboard history"
        )
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.wantsLayer = true
        self.statusItem = item

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 360)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(
            rootView: MenuBarView(
                storage: storage,
                preferences: preferences,
                onPaste: { [weak self] entry in self?.paste(entry) },
                onOpenPanel: { [weak self] in self?.togglePanel() },
                onPauseChanged: { [weak self] isPaused in self?.setPaused(isPaused) }
            )
        )
        self.popover = pop
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private var isAnimating = false

    private func animateStatusIcon() {
        guard let button = statusItem?.button, !isAnimating,
              let originalImage = button.image else { return }
        isAnimating = true

        let size = originalImage.size
        guard let outline = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size.height, weight: .regular)),
              let fill = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size.height, weight: .regular)) else {
            isAnimating = false
            return
        }

        let frameCount = 10
        let frameDuration = 0.035

        // Fill in: clip rect grows from bottom to top
        for i in 0...frameCount {
            let fraction = CGFloat(i) / CGFloat(frameCount)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * frameDuration) {
                button.image = Self.compositeImage(outline: outline, fill: fill, fillFraction: fraction, size: size)
            }
        }

        // Hold filled, then drain back down
        let holdDelay = Double(frameCount) * frameDuration + 0.6
        for i in 0...frameCount {
            let fraction = 1.0 - CGFloat(i) / CGFloat(frameCount)
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay + Double(i) * frameDuration) { [weak self] in
                button.image = Self.compositeImage(outline: outline, fill: fill, fillFraction: fraction, size: size)
                if i == frameCount {
                    self?.isAnimating = false
                }
            }
        }
    }

    private static func compositeImage(
        outline: NSImage,
        fill: NSImage,
        fillFraction: CGFloat,
        size: NSSize
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            outline.draw(in: rect)

            if fillFraction > 0 {
                let clipHeight = rect.height * fillFraction
                let clipRect = NSRect(x: 0, y: 0, width: rect.width, height: clipHeight)
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: clipRect).addClip()
                fill.draw(in: rect)
                NSGraphicsContext.current?.restoreGraphicsState()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Services

    private func startServices() {
        guard !started else { return }
        started = true
        monitor.start()
        hotkeyManager.start()
        requestAccessibilityIfNeeded()
    }

    private nonisolated func requestAccessibilityIfNeeded() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let trusted = AXIsProcessTrustedWithOptions(
            [key: true] as CFDictionary
        )
        if !trusted {
            print("Stash: Accessibility access required for global hotkey (Cmd+Shift+V)")
        }
    }

    func paste(_ entry: ClipboardEntry) {
        pasteService.paste(entry)
    }

    func togglePanel() {
        panelController?.toggle()
    }

    func setPaused(_ isPaused: Bool) {
        preferences.isPaused = isPaused
        monitor.isPaused = isPaused
    }
}
