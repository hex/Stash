// ABOUTME: Menu bar dropdown content showing recent clipboard entries and controls.
// ABOUTME: Provides quick access to pause, settings, and quit actions.

import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Text("Stash")
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
