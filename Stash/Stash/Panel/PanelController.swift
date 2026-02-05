// ABOUTME: Manages the floating panel lifecycle: creation, positioning, and show/hide.
// ABOUTME: Hosts SwiftUI SearchView inside the NSPanel via NSHostingView.

import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: FloatingPanel?
    private let storage: StorageManager
    private let onSelect: (ClipboardEntry) -> Void

    var isVisible: Bool { panel?.isVisible ?? false }

    init(storage: StorageManager, onSelect: @escaping (ClipboardEntry) -> Void) {
        self.storage = storage
        self.onSelect = onSelect
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        positionPanel()
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let panelWidth: CGFloat = 640
        let panelHeight: CGFloat = 420

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [],
            backing: .buffered,
            defer: true
        )

        let searchView = SearchView(storage: storage) { [weak self] entry in
            self?.onSelect(entry)
            self?.hide()
        }

        let hostingView = NSHostingView(rootView: searchView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.contentView = hostingView

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - panelFrame.height - screenFrame.height * 0.2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
