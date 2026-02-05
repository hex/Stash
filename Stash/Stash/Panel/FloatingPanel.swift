// ABOUTME: NSPanel subclass that provides a non-activating, floating window.
// ABOUTME: Styled like Spotlight: translucent, always on top, dismisses on deactivate.

import AppKit

final class FloatingPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = true

        // Allow the panel to become key for keyboard input
        becomesKeyOnlyIfNeeded = false
    }

    // Allow the panel to receive keyboard events
    override var canBecomeKey: Bool { true }
}
