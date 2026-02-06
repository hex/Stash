// ABOUTME: UserDefaults-backed app preferences with value clamping.
// ABOUTME: Observable for SwiftUI bindings, injectable UserDefaults for testing.

import Foundation

@Observable
final class Preferences {
    private let defaults: UserDefaults

    private enum Keys {
        static let historyLimit = "historyLimit"
        static let pollingInterval = "pollingInterval"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let isPaused = "isPaused"
        static let retentionDays = "retentionDays"
        static let clearOnQuit = "clearOnQuit"
    }

    private enum Limits {
        static let historyMin = 10
        static let historyMax = 10_000
        static let historyDefault = 500
        static let pollingMin = 0.1
        static let pollingMax = 5.0
        static let pollingDefault = 0.5
    }

    var historyLimit: Int {
        get {
            access(keyPath: \.historyLimit)
            let stored = defaults.integer(forKey: Keys.historyLimit)
            if stored == 0 { return Limits.historyDefault }
            return min(max(stored, Limits.historyMin), Limits.historyMax)
        }
        set {
            withMutation(keyPath: \.historyLimit) {
                defaults.set(min(max(newValue, Limits.historyMin), Limits.historyMax), forKey: Keys.historyLimit)
            }
        }
    }

    var pollingInterval: TimeInterval {
        get {
            access(keyPath: \.pollingInterval)
            let stored = defaults.double(forKey: Keys.pollingInterval)
            if stored == 0 { return Limits.pollingDefault }
            return min(max(stored, Limits.pollingMin), Limits.pollingMax)
        }
        set {
            withMutation(keyPath: \.pollingInterval) {
                defaults.set(min(max(newValue, Limits.pollingMin), Limits.pollingMax), forKey: Keys.pollingInterval)
            }
        }
    }

    var excludedBundleIDs: Set<String> {
        get {
            access(keyPath: \.excludedBundleIDs)
            return Set(defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? [])
        }
        set {
            withMutation(keyPath: \.excludedBundleIDs) {
                defaults.set(Array(newValue).sorted(), forKey: Keys.excludedBundleIDs)
            }
        }
    }

    var isPaused: Bool {
        get {
            access(keyPath: \.isPaused)
            return defaults.bool(forKey: Keys.isPaused)
        }
        set {
            withMutation(keyPath: \.isPaused) {
                defaults.set(newValue, forKey: Keys.isPaused)
            }
        }
    }

    /// Days to retain entries. 0 means forever.
    var retentionDays: Int {
        get {
            access(keyPath: \.retentionDays)
            return defaults.integer(forKey: Keys.retentionDays)
        }
        set {
            withMutation(keyPath: \.retentionDays) {
                defaults.set(newValue, forKey: Keys.retentionDays)
            }
        }
    }

    var clearOnQuit: Bool {
        get {
            access(keyPath: \.clearOnQuit)
            return defaults.bool(forKey: Keys.clearOnQuit)
        }
        set {
            withMutation(keyPath: \.clearOnQuit) {
                defaults.set(newValue, forKey: Keys.clearOnQuit)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
