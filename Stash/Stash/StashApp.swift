// ABOUTME: Main app entry point with custom NSStatusItem for animated menu bar icon.
// ABOUTME: Configures SwiftData container and wires up services.

import SwiftUI
import SwiftData

@main
struct StashApp: App {
    @State private var appController = AppController()

    var body: some Scene {
        // Empty scene — settings window is managed by AppController directly
        // because LSUIElement apps can't use the Settings scene (no app menu)
        Settings { EmptyView() }
    }
}

/// Coordinates all services and manages the app lifecycle.
@MainActor
@Observable
final class AppController {
    let storage: StorageManager
    let preferences: Preferences
    private let monitor: ClipboardMonitor
    private let pasteService: PasteService
    private let updater: UpdaterController
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init() {
        self.preferences = Preferences()
        self.storage = StorageManager()
        self.monitor = ClipboardMonitor()
        self.pasteService = PasteService(monitor: monitor)
        self.updater = UpdaterController()

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

        DispatchQueue.main.async { [self] in
            self.setupStatusItem()
            self.monitor.start()
            self.deleteExpiredEntries()
            self.observeTermination()
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

        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let button = self.statusItem?.button,
                  let window = event.window, window == button.window else { return event }
            let locationInButton = button.convert(event.locationInWindow, from: nil)
            if button.bounds.contains(locationInButton) {
                DispatchQueue.main.async { self.setPaused(!self.monitor.isPaused) }
                return nil
            }
            return event
        }

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 340, height: 400)
        pop.behavior = .applicationDefined
        pop.contentViewController = NSHostingController(
            rootView: MenuBarView(
                storage: storage,
                preferences: preferences,
                onPaste: { [weak self] entry in self?.paste(entry) },
                onPauseChanged: { [weak self] isPaused in self?.setPaused(isPaused) },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                }
            )
        )
        pop.setValue(true, forKeyPath: "shouldHideAnchor")
        self.popover = pop
    }

    @objc private func statusItemClicked() {
        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            addClickMonitors()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeClickMonitors()
    }

    private func addClickMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closePopover() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let popover = self.popover, popover.isShown else { return event }
            // If the click is inside the popover window, let it through
            if let popoverWindow = popover.contentViewController?.view.window,
               event.window == popoverWindow {
                return event
            }
            DispatchQueue.main.async { self.closePopover() }
            return event
        }
    }

    private func removeClickMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
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

    func paste(_ entry: ClipboardEntry) {
        pasteService.paste(entry)
        animateStatusIcon()
    }

    func setPaused(_ isPaused: Bool) {
        preferences.isPaused = isPaused
        monitor.isPaused = isPaused
        updateStatusIcon()
    }

    func syncExcludedApps() {
        monitor.excludedBundleIDs = preferences.excludedBundleIDs
    }

    private func deleteExpiredEntries() {
        let days = preferences.retentionDays
        guard days > 0 else { return }
        let count = (try? storage.deleteExpired(olderThanDays: days)) ?? 0
        if count > 0 {
            print("Stash: deleted \(count) expired entries (older than \(days) days)")
        }
    }

    private func observeTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.preferences.clearOnQuit else { return }
            try? self.storage.deleteAll()
        }
    }

    func openSettings() {
        popover?.performClose(nil)

        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            preferences: preferences,
            onExcludedAppsChanged: { [weak self] in
                self?.syncExcludedApps()
            },
            onClearHistory: { [weak self] in
                try? self?.storage.deleteAll()
            },
            onCheckForUpdates: { [weak self] in
                self?.updater.checkForUpdates()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stash Settings"
        window.contentViewController = NSHostingController(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        self.settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
