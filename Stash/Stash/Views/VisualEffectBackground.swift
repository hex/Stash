// ABOUTME: Frosted popover backing — AppKit vibrancy under a scrim that guarantees contrast.
// ABOUTME: Falls back to a solid fill when the system asks for reduced transparency.

import SwiftUI
import AppKit

/// Behind-window vibrancy samples the desktop, so text contrast would otherwise depend
/// on whatever the popover happens to sit over — unreadable against a busy or dark
/// backdrop. The scrim fixes the floor while leaving the blur visible through it.
struct PopoverBackground: View {
    let appearance: AppearanceOption

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Enough to keep text legible over any desktop while the blur still reads as frost.
    private static let scrimOpacity = 0.85

    var body: some View {
        ZStack {
            if !reduceTransparency {
                VisualEffect(material: .popover, appearance: appearance)
            }
            scrim.opacity(reduceTransparency ? 1 : Self.scrimOpacity)
        }
    }

    private var scrim: Color {
        switch appearance {
        case .light: return Color(Self.light)
        case .dark:  return Color(Self.dark)
        case .auto:
            return Color(NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? Self.dark
                    : Self.light
            }))
        }
    }

    private static let dark = NSColor(red: 0.106, green: 0.115, blue: 0.149, alpha: 1)  // #1B1D26
    private static let light = NSColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1) // #F6F7F9
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let appearance: AppearanceOption

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appearance.nsAppearance
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = appearance.nsAppearance
    }
}
