// ABOUTME: Main app entry point with MenuBarExtra scene.
// ABOUTME: Configures SwiftData container and wires up services.

import SwiftUI
import SwiftData

@main
struct StashApp: App {
    var body: some Scene {
        MenuBarExtra("Stash", systemImage: "clipboard") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
