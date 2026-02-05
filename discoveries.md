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

## XcodeGen Behavior
- `xcodegen generate` must be re-run after adding/removing any Swift files
- Entitlements: XcodeGen may normalize/strip entries (empty `<dict/>` is correct for non-sandboxed)
- The .xcodeproj should be regenerated, not manually edited

