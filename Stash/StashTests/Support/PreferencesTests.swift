// ABOUTME: Tests for Preferences defaults, value clamping, and excluded apps management.
// ABOUTME: Uses a custom UserDefaults suite for test isolation.

import XCTest
@testable import Stash

final class PreferencesTests: XCTestCase {

    private var prefs: Preferences!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.hexul.Stash.tests.\(UUID().uuidString)")!
        prefs = Preferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "")
        prefs = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultHistoryLimit() {
        XCTAssertEqual(prefs.historyLimit, 500)
    }

    func testDefaultPollingInterval() {
        XCTAssertEqual(prefs.pollingInterval, 0.5)
    }

    func testDefaultExcludedApps() {
        XCTAssertTrue(prefs.excludedBundleIDs.isEmpty)
    }

    func testDefaultIsPaused() {
        XCTAssertFalse(prefs.isPaused)
    }

    // MARK: - Clamping

    func testHistoryLimitClampedToMinimum() {
        prefs.historyLimit = 5
        XCTAssertEqual(prefs.historyLimit, 10)
    }

    func testHistoryLimitClampedToMaximum() {
        prefs.historyLimit = 100_000
        XCTAssertEqual(prefs.historyLimit, 10_000)
    }

    func testHistoryLimitAcceptsValidValue() {
        prefs.historyLimit = 200
        XCTAssertEqual(prefs.historyLimit, 200)
    }

    func testPollingIntervalClampedToMinimum() {
        prefs.pollingInterval = 0.01
        XCTAssertEqual(prefs.pollingInterval, 0.1, accuracy: 0.001)
    }

    func testPollingIntervalClampedToMaximum() {
        prefs.pollingInterval = 20.0
        XCTAssertEqual(prefs.pollingInterval, 5.0, accuracy: 0.001)
    }

    // MARK: - Excluded apps

    func testAddExcludedApp() {
        prefs.excludedBundleIDs.insert("com.example.app")
        XCTAssertTrue(prefs.excludedBundleIDs.contains("com.example.app"))
    }

    func testRemoveExcludedApp() {
        prefs.excludedBundleIDs.insert("com.example.app")
        prefs.excludedBundleIDs.remove("com.example.app")
        XCTAssertFalse(prefs.excludedBundleIDs.contains("com.example.app"))
    }

    // MARK: - Persistence

    func testHistoryLimitPersists() {
        prefs.historyLimit = 300
        let prefs2 = Preferences(defaults: defaults)
        XCTAssertEqual(prefs2.historyLimit, 300)
    }

    func testIsPausedPersists() {
        prefs.isPaused = true
        let prefs2 = Preferences(defaults: defaults)
        XCTAssertTrue(prefs2.isPaused)
    }

    func testExcludedAppsPersist() {
        prefs.excludedBundleIDs = ["com.a", "com.b"]
        let prefs2 = Preferences(defaults: defaults)
        XCTAssertEqual(prefs2.excludedBundleIDs, ["com.a", "com.b"])
    }
}
