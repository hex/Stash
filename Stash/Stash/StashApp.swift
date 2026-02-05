// ABOUTME: Main app entry point with MenuBarExtra scene.
// ABOUTME: Configures SwiftData container and wires up services.

import SwiftUI
import SwiftData

@main
struct StashApp: App {
    @State private var appController = AppController()

    var body: some Scene {
        MenuBarExtra("Stash", systemImage: "clipboard") {
            MenuBarView(
                storage: appController.storage,
                preferences: appController.preferences,
                onPaste: { entry in appController.paste(entry) },
                onOpenPanel: { appController.togglePanel() }
            )
        }
        .menuBarExtraStyle(.menu)

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
            try? self.storage.save(
                contentType: contentType,
                plainText: plainText,
                urlString: urlString,
                filePaths: filePaths,
                imageData: imageData,
                richTextData: richTextData,
                sourceAppBundleID: bundleID,
                sourceAppName: appName
            )
        }

        let controller = PanelController(storage: storage) { [weak self] entry in
            self?.paste(entry)
        }
        self.panelController = controller

        hotkeyManager.onHotkey = { [weak self] in
            self?.togglePanel()
        }

        monitor.start()
        requestAccessibilityIfNeeded()
        hotkeyManager.start()
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
}
