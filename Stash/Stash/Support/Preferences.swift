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
        static let appearance = "appearance"
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

    /// Theme override: "auto" follows system, "light", or "dark".
    var appearance: AppearanceOption {
        get {
            access(keyPath: \.appearance)
            let raw = defaults.string(forKey: Keys.appearance) ?? AppearanceOption.auto.rawValue
            return AppearanceOption(rawValue: raw) ?? .auto
        }
        set {
            withMutation(keyPath: \.appearance) {
                defaults.set(newValue.rawValue, forKey: Keys.appearance)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}

enum AppearanceOption: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }
}
