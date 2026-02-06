# Discoveries & Notes

## Environment
- macOS 26.2, Xcode 26.2, Swift 6.2.3 (arm64)
- XcodeGen 2.44.1 available at /opt/homebrew/bin - usable for project generation
- beads issue tracker initialized with STASH prefix

## macOS Clipboard API Findings
- NSPasteboard has no change notification - must poll via Timer checking `changeCount`
- Password manager detection: check for `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` UTIs on pasteboard items
- Additional privacy markers: `de.petermaurer.TransientPasteboardType`, `com.agilebits.onepassword`
- macOS 15.4+ introduced `NSPasteboard.accessBehavior` for paste privacy alerts, but NOT enforced as of macOS 26.2

## SwiftUI/AppKit Findings
- MenuBarExtra (macOS 13+) is the modern menu bar app API - supports `.window` style for popovers
- NSPanel subclass is required for proper Spotlight-like floating behavior (pure SwiftUI can't do `nonActivatingPanel` + `hidesOnDeactivate`)
- `LSUIElement = true` in Info.plist hides app from Dock and App Switcher
- SMAppService.mainApp (macOS 13+) is the modern launch-at-login API

## Global Hotkey Options (no external deps)
- `NSEvent.addGlobalMonitorForEvents` - works but cannot consume the event (Cmd+Shift+V may also trigger in focused app)
- Carbon `RegisterEventHotKey` - legacy, reported issues on macOS 15+
- CGEventTap - modern alternative but requires Accessibility permissions
- Decision: start with NSEvent monitors, upgrade to CGEventTap if conflicts arise

## SwiftData Notes
- `@Attribute(.externalStorage)` auto-offloads blobs >128KB to external files
- External storage fields cannot be used in SwiftData predicates
- Store `contentTypeRaw` as String rather than enum for reliable predicate support
- `ModelConfiguration(isStoredInMemoryOnly: true)` gives fast, isolated test containers (~100ms for 65 tests)

## Swift 6 Strict Concurrency + XCTest (Key Finding)
- XCTest `setUp()`/`tearDown()` are NOT @MainActor-isolated even when the test class is marked @MainActor
- This causes "sending X risks causing data races" errors when creating @MainActor objects in setUp
- Workaround: `@preconcurrency import AppKit` in test files to treat non-Sendable AppKit types as Sendable
- Alternative: `nonisolated(unsafe)` on test properties holding non-Sendable types
- Extract pure logic as `nonisolated static func` on @MainActor classes for easy testability
- NSPasteboard is not Sendable; use named pasteboards for test isolation + `releaseGlobally()` in tearDown

## @MainActor + System Callback Closures (Runtime Bug)
- `NSEvent.addGlobalMonitorForEvents` callbacks fire on a background thread, NOT the main thread
- `Timer.scheduledTimer(withTimeInterval:repeats:block:)` block is `@Sendable`, cannot directly call `@MainActor` methods
- If the callback captures a `@MainActor`-isolated `self`, calling methods on it silently fails at runtime
- Fix: use `DispatchQueue.main.async` inside ALL system callbacks that need to reach @MainActor code
- Same pattern needed for NSEvent monitors, Timer callbacks, and any closure-based system API
- Static constants on @MainActor classes must be marked `nonisolated static` to be accessible from non-isolated callbacks

## One-Way Data Binding Between UI and Services
- Setting `monitor.isPaused = preferences.isPaused` in init is a one-time copy, not a live binding
- If a SwiftUI Toggle writes to `preferences.isPaused`, the `monitor.isPaused` stays stale
- Fix: use a callback pattern (`onPauseChanged`) that updates BOTH preferences and the service
- UserDefaults persists state across launches, so stale flags survive app restarts

## NSEvent Global Monitor + Accessibility
- `NSEvent.addGlobalMonitorForEvents` requires Accessibility permission to function
- Without permission, the monitor is created but silently receives zero events (no error thrown)
- Use `AXIsProcessTrustedWithOptions` with prompt option to request access on launch
- Avoid `kAXTrustedCheckOptionPrompt` directly (not concurrency-safe); use string literal `"AXTrustedCheckOptionPrompt" as CFString`
- User must restart the app after granting Accessibility access

## SwiftUI MenuBarExtra (.menu style)
- `@State` properties in menu views are NOT re-evaluated on each menu open - they stay stale
- Compute derived data directly in `body` or use `onAppear` (though onAppear is unreliable for menus)
- Computing `let entries = (try? storage.fetchAll()) ?? []` in body works because SwiftUI re-evaluates body on each menu display

## macOS Unified Logging Privacy Redaction
- `NSLog()` and `os_log` messages containing `%@` format specifiers are redacted as `<private>` in `log stream` output
- This happens unless the process is attached to a debugger (Xcode)
- `print()` goes to stdout only, not the unified logging system at all — invisible to `log stream`
- Workaround for CLI debugging: write to a temp file (e.g. `/tmp/app-debug.log`) instead
- Alternative: use `os_log` with `%{public}s` format specifiers for non-sensitive debug data

## XcodeGen Behavior
- `xcodegen generate` must be re-run after adding/removing any Swift files
- Entitlements: XcodeGen may normalize/strip entries (empty `<dict/>` is correct for non-sandboxed)
- The .xcodeproj should be regenerated, not manually edited

