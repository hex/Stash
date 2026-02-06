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
                print("Stash: save failed: \(error)")
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
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.wantsLayer = true
        self.statusItem = item
        updateStatusIcon()

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

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        if monitor.isPaused {
            button.image = Self.pausedIcon()
        } else {
            button.image = NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "Stash clipboard history"
            )
        }
    }

    nonisolated static func pausedIcon() -> NSImage {
        let base = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "Stash - paused"
        )!
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.move(to: NSPoint(x: rect.width * 0.15, y: rect.height * 0.85))
            path.line(to: NSPoint(x: rect.width * 0.85, y: rect.height * 0.15))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func animateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let fillImage = NSImage(
            systemSymbolName: "clipboard.fill",
            accessibilityDescription: nil
        )

        let fadeIn = CATransition()
        fadeIn.type = .fade
        fadeIn.duration = 0.15
        button.layer?.add(fadeIn, forKey: "fillIn")
        button.image = fillImage

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            let fadeOut = CATransition()
            fadeOut.type = .fade
            fadeOut.duration = 0.15
            button.layer?.add(fadeOut, forKey: "fillOut")
            self?.updateStatusIcon()
        }
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
        if popover?.isShown == true {
            popover?.performClose(nil)
            DispatchQueue.main.async {
                self.panelController?.toggle()
            }
        } else {
            panelController?.toggle()
        }
    }

    func setPaused(_ isPaused: Bool) {
        preferences.isPaused = isPaused
        monitor.isPaused = isPaused
        updateStatusIcon()
    }
}
