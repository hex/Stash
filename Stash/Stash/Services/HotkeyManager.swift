// ABOUTME: Registers global and local NSEvent monitors for the clipboard panel hotkey.
// ABOUTME: Default hotkey is Cmd+Shift+V; fires a callback to toggle panel visibility.

import AppKit

@MainActor
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    /// Key code for 'V' on macOS
    private static let defaultKeyCode: UInt16 = 0x09
    private static let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotkey(event) == true {
                self?.onHotkey?()
                return nil // consume the event
            }
            return event
        }
    }

    func stop() {
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if isHotkey(event) {
            onHotkey?()
        }
    }

    private func isHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == Self.defaultKeyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == Self.defaultModifiers
    }
}
