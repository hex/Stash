// ABOUTME: Registers global and local NSEvent monitors for the clipboard panel hotkey.
// ABOUTME: Default hotkey is Cmd+Shift+V; fires a callback to toggle panel visibility.

import AppKit

@MainActor
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private nonisolated static let hotkeyCode: UInt16 = 0x09
    private nonisolated static let hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isHotkey(event) else { return }
            DispatchQueue.main.async {
                self?.onHotkey?()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isHotkey(event) else { return event }
            DispatchQueue.main.async {
                self?.onHotkey?()
            }
            return nil
        }
    }

    private nonisolated static func isHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == hotkeyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == hotkeyModifiers
    }
}
