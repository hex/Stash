// ABOUTME: Wraps Sparkle's SPUStandardUpdaterController for programmatic update checking.
// ABOUTME: Provides a simple interface for triggering updates and reading auto-check state.

@preconcurrency import Sparkle

@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
