// ABOUTME: Menu bar popover — Native + Quiet design, system fonts, system accent, no themed colors.
// ABOUTME: Inherits the user's macOS preferences (light/dark, accent, contrast) without override.

import SwiftUI
import SwiftData

struct MenuBarView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardEntry) -> Void
    let onPauseChanged: (Bool) -> Void
    let onOpenSettings: () -> Void

    @State private var copiedEntryID: PersistentIdentifier?
    @State private var hoveredEntryID: PersistentIdentifier?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var isScrolling = false
    @State private var entries: [ClipboardEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else {
                entryList(entries)
            }

            Divider()

            bottomToolbar
        }
        .frame(width: 380, height: 400)
        .background(
            Color(NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(red: 0.106, green: 0.115, blue: 0.149, alpha: 1) // #1B1D26
                    : NSColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1) // #F6F7F9
            }))
        )
        .preferredColorScheme(preferences.appearance == .auto ? nil
                              : (preferences.appearance == .dark ? .dark : .light))
        .task(id: storage.changeCount) {
            entries = (try? storage.fetchAll()) ?? []
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Spacer()

            Toggle(preferences.isPaused ? "Paused" : "Recording", isOn: Binding(
                get: { !preferences.isPaused },
                set: { onPauseChanged(!$0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption)
            .foregroundStyle(.secondary)
            .tint(.blue)
            .help(preferences.isPaused ? "Paused — toggle to resume" : "Recording — toggle to pause")

            Button {
                confirmAndQuit()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.34, blue: 0.34))
            }
            .buttonStyle(.plain)
            .help("Quit Stash")
            .contextMenu {
                Button("Clear All History", role: .destructive) {
                    confirmAndClear()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No clipboard history")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Copy something to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Entry list

    private func entryList(_ entries: [ClipboardEntry]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let displayed = Array(entries.prefix(10))
                ForEach(Array(displayed.enumerated()), id: \.element.persistentModelID) { index, entry in
                    EntryRowView(
                        entry: entry,
                        isTopmost: index == 0,
                        isHovered: hoveredEntryID == entry.persistentModelID,
                        isCopied: copiedEntryID == entry.persistentModelID,
                        action: actionFor(entry)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { copyEntry(entry) }
                    .onHover { hovering in
                        hoveredEntryID = hovering ? entry.persistentModelID : nil
                    }
                    .contextMenu {
                        Button("Copy") { copyEntry(entry) }
                        Button(entry.isPinned ? "Unpin" : "Pin") {
                            try? storage.togglePin(entryWithID: entry.persistentModelID)
                        }
                        if let action = actionFor(entry) {
                            Button(action.label) { action.perform() }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            try? storage.delete(entryWithID: entry.persistentModelID)
                        }
                    }

                    if index < displayed.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geo in
            scrollOffset = geo.contentOffset.y
            contentHeight = geo.contentSize.height
            viewportHeight = geo.bounds.height
        }
        .onScrollPhaseChange { _, newPhase in
            isScrolling = newPhase != .idle
        }
        .overlay(alignment: .topTrailing) {
            customScrollIndicator
        }
    }

    @ViewBuilder
    private var customScrollIndicator: some View {
        let needsScroll = contentHeight > viewportHeight + 1
        let viewportRatio = min(max(viewportHeight / max(contentHeight, 1), 0.1), 1.0)
        let indicatorHeight = max(viewportHeight * viewportRatio, 24)
        let trackRange = max(viewportHeight - indicatorHeight, 0)
        let scrollableRange = max(contentHeight - viewportHeight, 1)
        let progress = min(max(scrollOffset / scrollableRange, 0), 1)
        let yOffset = progress * trackRange

        Capsule()
            .fill(.primary.opacity(0.30))
            .frame(width: 3, height: indicatorHeight)
            .padding(.trailing, 3)
            .offset(y: yOffset)
            .opacity(needsScroll && isScrolling ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: isScrolling)
            .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func copyEntry(_ entry: ClipboardEntry) {
        onPaste(entry)
        withAnimation(.easeIn(duration: 0.15)) {
            copiedEntryID = entry.persistentModelID
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                copiedEntryID = nil
            }
        }
    }

    private func actionFor(_ entry: ClipboardEntry) -> EntryRowView.Action? {
        switch entry.contentType {
        case .image:
            guard let data = entry.imageData else { return nil }
            return EntryRowView.Action(label: "Preview", systemImage: "eye") {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("stash-preview.png")
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        case .fileURL:
            guard let path = entry.filePaths?.first,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return EntryRowView.Action(label: "Preview", systemImage: "eye") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        case .url:
            guard let urlString = entry.urlString,
                  let url = URL(string: urlString) else { return nil }
            return EntryRowView.Action(label: "Open", systemImage: "arrow.up.right.square") {
                NSWorkspace.shared.open(url)
            }
        default:
            return nil
        }
    }

    // MARK: - Modal confirmations (NSAlert bypasses SwiftUI dialog wedging in popovers)

    private func confirmAndQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Stash?"
        alert.addButton(withTitle: "Quit").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            if preferences.clearOnQuit {
                try? storage.deleteAll()
            }
            NSApp.terminate(nil)
        }
    }

    private func confirmAndClear() {
        let alert = NSAlert()
        alert.messageText = "Clear All History?"
        alert.informativeText = "This will permanently delete every entry, including pinned items."
        alert.addButton(withTitle: "Clear All").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            try? storage.deleteAll()
        }
    }
}
