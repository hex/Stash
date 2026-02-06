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

## MenuBarExtra .menu Style Does NOT Re-evaluate Body (Critical)
- `.menu` style `MenuBarExtra` converts its SwiftUI body to `NSMenu` items ONCE at startup
- Subsequent opens of the menu reuse the cached NSMenu — the body is NOT re-evaluated
- `@Observable` property changes do NOT trigger re-rendering of `.menu` style content
- This means `fetchAll()` in the body only runs once, showing stale data forever
- Fix: switch to `.window` style, which hosts a live SwiftUI view that participates in normal observation/rendering
- `.window` style combined with an observable `changeCount` property on the data store gives real-time updates

## NSStatusBarButton Icon Animation
- SF Symbol animations (`.symbolEffect`, `.contentTransition`) do NOT work on MenuBarExtra labels — they render as static NSStatusBarButton images
- For animated menu bar icons, must own the `NSStatusItem` directly (drop MenuBarExtra for the icon)
- Frame-by-frame compositing works: draw outline + clipped fill with `NSBezierPath.addClip()` growing from bottom
- MUST use `image.isTemplate = true` on composite images for correct light/dark mode rendering
- MUST match the original `button.image.size` for composites — using `button.bounds.size` causes the icon to grow (bounds includes padding)
- Use `NSImage(size:flipped:drawingHandler:)` for compositing (lockFocus is deprecated)
- Guard with `isAnimating` flag to prevent overlapping animations from rapid copies

## macOS Unified Logging Privacy Redaction
- `NSLog()` and `os_log` messages containing `%@` format specifiers are redacted as `<private>` in `log stream` output
- This happens unless the process is attached to a debugger (Xcode)
- `print()` goes to stdout only, not the unified logging system at all — invisible to `log stream`
- Workaround for CLI debugging: write to a temp file (e.g. `/tmp/app-debug.log`) instead
- Alternative: use `os_log` with `%{public}s` format specifiers for non-sensitive debug data

## NSPopover + FloatingPanel hidesOnDeactivate Race
- LSUIElement apps have fragile "active" state — closing an NSPopover can deactivate the app
- If a FloatingPanel has `hidesOnDeactivate = true`, opening it from a popover button fails silently
- The panel shows momentarily, then the app deactivation hides it immediately
- Fix: close the popover first, then show the panel on the next run loop tick via `DispatchQueue.main.async`
- The Cmd+Shift+V hotkey path doesn't hit this because the app isn't "active" to begin with

## @Observable + Computed Properties (Critical)
- `@Observable` macro ONLY auto-instruments stored properties with observation tracking
- Computed properties (even on `@Observable` classes) are invisible to the observation system
- SwiftUI views reading computed properties get NO re-render when values change
- Fix: manually call `access(keyPath:)` in getters and `withMutation(keyPath:)` in setters
- This applies to any `@Observable` class with computed properties backed by external storage (UserDefaults, Keychain, etc.)
- Symptom: Toggle/Binding visually snaps back because SwiftUI never sees the mutation

## NSStatusItem Click Handling (Fragile)
- `sendAction(on: [.leftMouseUp, .rightMouseUp])` BREAKS NSStatusBarButton click handling entirely
- After setting it, the action handler never fires — even after removing the call in later builds
- Ghost status bar icons: `pkill -x` kills the process but macOS may leave the icon visible
- User clicks a dead/ghost icon that doesn't respond; real icon may be elsewhere in the bar
- Fast kill-and-relaunch cycles can produce multiple ghost icons
- `NSApp.currentEvent?.clickCount` unreliable for NSStatusBarButton double-click detection
- `print()` goes to stdout only, not `log stream` — use file logging for debug (e.g. `/tmp/stash-debug.log`)
- Debugging: add startup log to `/tmp/` file to verify setup, then check if clicks produce log entries

## SwiftData Encryption Options
- SwiftData/Core Data have NO built-in local encryption (`@Attribute(.allowsCloudEncryption)` is iCloud-only)
- SQLCipher is incompatible with SwiftData — no hook to swap the underlying SQLite store in `ModelConfiguration`
- All Apple Silicon Macs encrypt internal storage at hardware level; FileVault ties decryption to login password
- CryptoKit field-level encryption works for non-searched fields (imageData, richTextData) but breaks `#Predicate` search on plainText
- Store CryptoKit symmetric key in Keychain (Secure Enclave backed); Keychain itself is NOT for bulk data
- `NSFileProtection` exists on macOS Apple Silicon but fragile with SQLite (WAL files, self-healing recreates files)
- Competitors: Maccy/Alfred/CopyClip don't encrypt; Raycast claims "local encrypted database"; Paste uses iCloud encryption
- Most practical approach: privacy markers (already done) + app exclusions (done) + optional auto-expiry + CryptoKit for blob fields

## SwiftUI Settings Scene Broken for LSUIElement Apps
- SwiftUI `Settings` scene relies on the app menu's "Settings..." item to trigger `showSettingsWindow:` action
- LSUIElement apps have NO app menu and NO Dock icon — the Settings scene exists but is completely unreachable
- `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` also fails — the action responder is never registered without the app menu
- `NSApp.activate(ignoringOtherApps: true)` before `sendAction` doesn't help either
- Fix: bypass Settings scene entirely, manage an NSWindow + NSHostingController manually
- Use `isReleasedWhenClosed = false` to reuse the window, `NSApp.activate(ignoringOtherApps: true)` to bring to front

## Excluded Apps Don't Sync at Runtime (Bug)
- `monitor.excludedBundleIDs = preferences.excludedBundleIDs` in AppController.init is a one-time copy
- Editing excluded apps in Settings has no effect until app restart
- Same pattern as the isPaused bug — needs callback pattern to sync both preferences AND monitor

## macOS App Resolution APIs
- `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` — bundle ID to .app URL (even non-running)
- `NSWorkspace.shared.icon(forFile: url.path)` — get app icon from path
- `FileManager.default.displayName(atPath: url.path)` — get display name (strips .app extension)
- `NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }` — running GUI apps
- `NSOpenPanel` + `UTType.applicationBundle` — browse for .app bundles (`import UniformTypeIdentifiers`)

## NSPopover Customization
- Hide the arrow: `pop.setValue(true, forKeyPath: "shouldHideAnchor")` — private but stable since macOS 10.10
- Popover's vibrancy comes from an `NSVisualEffectView` in `_NSPopoverFrame` — covers both arrow and content
- Adding a SwiftUI `.background(material)` creates a SECOND layer that won't match the arrow
- For solid background: use `Color(.windowBackgroundColor)` on the SwiftUI content
- ScrollView indicators clip against popover's rounded corners; fix with `.contentMargins(.vertical, 6, for: .scrollIndicators)`

## SwiftUI ShapeStyle Shorthand Pitfall
- `.foregroundStyle(.accentColor)` fails to compile — `ShapeStyle` has no `.accentColor` member
- Must use `Color.accentColor` explicitly: `.foregroundStyle(Color.accentColor)`
- System colors like `.red`, `.blue` work as shorthand because they're defined on both `Color` and `ShapeStyle`
- `.accentColor` is only defined on `Color`, so the shorthand dot syntax doesn't resolve

## SwiftData Field-Level Encryption Pattern
- SwiftData has NO full-DB encryption option; SQLCipher is incompatible (no hook to swap SQLite engine)
- Field-level encryption with CryptoKit AES-256-GCM works: encrypt before `context.insert()`, decrypt after `context.fetch()`
- CRITICAL: Cannot decrypt in-place on the same ModelContext used for writes — `context.save()` would persist decrypted values back
- Solution: `fetchAll()` uses a fresh `ModelContext(container)` for reads; entries are decrypted in this disposable context
- The disposable context is retained by the fetched entries (they reference their context); released when entries are replaced
- Keychain key storage: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` ties key to device + login session
- Migration from unencrypted to encrypted: `(try? crypto.decrypt(value)) ?? value` — invalid ciphertext falls back to plaintext
- Content hash for dedup must be computed from PLAINTEXT before encryption (hash stays unencrypted in DB)

## Time Machine Exclusion for SwiftData Stores
- `URLResourceValues.isExcludedFromBackup = true` excludes files/dirs from Time Machine
- Must set on the parent directory of the `.store` file to cover WAL and SHM files too
- `ModelConfiguration` exposes `url` for the store path; use `deletingLastPathComponent()` for the directory
- `URL.setResourceValues` mutates, so needs `var` binding (not `let`)
- Only apply to on-disk stores — skip for `isStoredInMemoryOnly: true` test containers

## XcodeGen Behavior
- `xcodegen generate` must be re-run after adding/removing any Swift files
- Entitlements: XcodeGen may normalize/strip entries (empty `<dict/>` is correct for non-sandboxed)
- The .xcodeproj should be regenerated, not manually edited

