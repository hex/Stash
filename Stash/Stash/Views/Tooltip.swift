// ABOUTME: Hover tooltip for popover controls, drawn in SwiftUI rather than by AppKit.
// ABOUTME: `.help()` is silent here because the app stays inactive while the popover is open.

import SwiftUI

/// AppKit suppresses `NSView` tooltips while the owning app is inactive, and Stash
/// deliberately never activates when its popover opens — activating would pull focus
/// away from whatever the user is about to paste into. This draws the tooltip itself
/// so the behaviour no longer depends on activation.
private struct TooltipModifier: ViewModifier {
    let text: String
    let edge: VerticalEdge
    let anchor: HorizontalAlignment

    @State private var isHovered = false
    @State private var isVisible = false
    @State private var labelHeight: CGFloat = 0

    private var alignment: Alignment {
        Alignment(horizontal: anchor, vertical: edge == .top ? .top : .bottom)
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                if !hovering { isVisible = false }
            }
            .task(id: isHovered) {
                guard isHovered else { return }
                // Matches the system's own dwell before a tooltip appears, so a pointer
                // crossing the toolbar doesn't flash every label on the way past.
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                isVisible = true
            }
            .overlay(alignment: alignment) {
                if isVisible {
                    label
                        .fixedSize()
                        // Measured rather than guessed: the label's height follows the
                        // user's text size, so a hardcoded offset would drift.
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            labelHeight = $0
                        }
                        .offset(y: edge == .top ? -(labelHeight + 6) : labelHeight + 6)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isVisible)
            .zIndex(isVisible ? 1 : 0)
            // `.help()` set an accessibility hint as well as a tooltip. Carrying it here
            // keeps `.tooltip()` a full replacement rather than only the visible half.
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            )
    }
}

extension View {
    /// Shows `text` on hover. Use instead of `.help()` inside the popover.
    ///
    /// `anchor` keeps the label inside the popover: a centred label on an edge control
    /// overflows and gets clipped, so edge controls anchor to their own leading or
    /// trailing edge instead.
    func tooltip(
        _ text: String,
        edge: VerticalEdge = .top,
        anchor: HorizontalAlignment = .center
    ) -> some View {
        modifier(TooltipModifier(text: text, edge: edge, anchor: anchor))
    }
}
