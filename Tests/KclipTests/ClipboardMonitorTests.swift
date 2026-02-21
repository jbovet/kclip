// ClipboardMonitorTests.swift
// Kclip – Open-source keyboard-first clipboard manager
// Unit tests for ClipboardMonitor configuration and lifecycle.

import XCTest
@testable import Kclip

final class ClipboardMonitorTests: XCTestCase {

    // MARK: - Default exclusion list

    func testDefaultExcludedBundleIDs_containsOnePassword() {
        XCTAssertTrue(ClipboardMonitor.defaultExcludedBundleIDs.contains("com.1password.1password"))
    }

    func testDefaultExcludedBundleIDs_containsBitwarden() {
        XCTAssertTrue(ClipboardMonitor.defaultExcludedBundleIDs.contains("com.bitwarden.desktop"))
    }

    func testDefaultExcludedBundleIDs_containsLastPass() {
        XCTAssertTrue(ClipboardMonitor.defaultExcludedBundleIDs.contains("com.lastpass.LastPass"))
    }

    func testDefaultExcludedBundleIDs_containsKeePassXC() {
        XCTAssertTrue(ClipboardMonitor.defaultExcludedBundleIDs.contains("org.keepassxc.keepassxc"))
    }

    func testDefaultExcludedBundleIDs_containsApplePasswords() {
        XCTAssertTrue(ClipboardMonitor.defaultExcludedBundleIDs.contains("com.apple.Passwords"))
    }

    func testDefaultExcludedBundleIDs_hasExpectedCount() {
        // 11 known password managers (including Apple Passwords)
        XCTAssertEqual(ClipboardMonitor.defaultExcludedBundleIDs.count, 11)
    }

    // MARK: - Start / Stop lifecycle

    func testStart_setsOnNewItem() {
        let monitor = ClipboardMonitor()
        var called = false
        monitor.onNewItem = { _ in called = true }
        monitor.start()
        // Timer is running but hasn't fired yet (0.5s interval)
        monitor.stop()
        // Just verify start/stop don't crash
        XCTAssertFalse(called, "Timer shouldn't have fired immediately")
    }

    func testStop_beforeStart_doesNotCrash() {
        let monitor = ClipboardMonitor()
        monitor.stop() // No-op, should not crash
    }

    func testStart_calledTwice_isNoOp() {
        let monitor = ClipboardMonitor()
        monitor.start()
        monitor.start() // Second call is a no-op
        monitor.stop()
    }

    // MARK: - Initial state

    func testExcludedCount_startsAtZero() {
        let monitor = ClipboardMonitor()
        XCTAssertEqual(monitor.excludedCount, 0)
    }

    func testLastExcludedApp_startsNil() {
        let monitor = ClipboardMonitor()
        XCTAssertNil(monitor.lastExcludedApp)
    }
}
