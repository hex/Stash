// ABOUTME: Frosted popover backing — AppKit vibrancy under a scrim that guarantees contrast.
// ABOUTME: Falls back to a solid fill when the system asks for reduced transparency.

import SwiftUI
import AppKit

/// Behind-window vibrancy samples the desktop, so text contrast would otherwise depend
/// on whatever the popover happens to sit over — unreadable against a busy or dark
/// backdrop. The scrim fixes the floor while leaving the blur visible through it.
struct PopoverBackground: View {
    let appearance: AppearanceOption

    @State private var reduceTransparency = NSWorkspace.shared
        .accessibilityDisplayShouldReduceTransparency

    /// Enough to keep text legible over any desktop while the blur still reads as frost.
    private static let scrimOpacity = 0.85

    var body: some View {
        ZStack {
            if !reduceTransparency {
                VisualEffect(material: .popover, appearance: appearance)
            }
            scrim.opacity(reduceTransparency ? 1 : Self.scrimOpacity)
        }
        .task {
            // The setting can change while the app runs, and a stale read would leave
            // a transparent popover for someone who asked for an opaque one.
            let notifications = NotificationCenter.default.notifications(
                named: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
            for await _ in notifications {
                reduceTransparency = NSWorkspace.shared
                    .accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    private var scrim: Color {
        switch appearance {
        case .light: return Self.light
        case .dark:  return Self.dark
        case .auto:
            return Color(NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(red: 0.106, green: 0.115, blue: 0.149, alpha: 1)
                    : NSColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1)
            }))
        }
    }

    private static let dark = Color(red: 0.106, green: 0.115, blue: 0.149)  // #1B1D26
    private static let light = Color(red: 0.965, green: 0.969, blue: 0.976) // #F6F7F9
}

/// `preferredColorScheme` steers SwiftUI's own rendering but leaves an `NSView`'s
/// appearance untouched, so the material has to be told the theme directly or a
/// forced light/dark setting would leave it matching the system instead.
private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let appearance: AppearanceOption

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = nsAppearance
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = nsAppearance
    }

    private var nsAppearance: NSAppearance? {
        switch appearance {
        case .auto:  return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        }
    }
}
