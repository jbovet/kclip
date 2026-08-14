// AccessibilityStatusTests.swift
// KclipTests

import XCTest
@testable import Kclip

/// Tests for the Accessibility-permission status wording, including the
/// restart-nudge that appears after a denied→granted transition.
final class AccessibilityStatusTests: XCTestCase {

    func testMessage_notGranted_ignoresSessionFlag() {
        let expected = "Not granted — items are copied but not auto-pasted."
        XCTAssertEqual(AccessibilityStatus.message(granted: false, grantedThisSession: false), expected)
        // When not granted, the session flag must not change the message.
        XCTAssertEqual(AccessibilityStatus.message(granted: false, grantedThisSession: true), expected)
    }

    func testMessage_grantedAtLaunch_noRestartNudge() {
        let message = AccessibilityStatus.message(granted: true, grantedThisSession: false)
        XCTAssertEqual(message, "Granted — Kclip can paste into other apps.")
        XCTAssertFalse(message.lowercased().contains("restart"))
    }

    func testMessage_grantedThisSession_nudgesRestart() {
        let message = AccessibilityStatus.message(granted: true, grantedThisSession: true)
        XCTAssertTrue(message.lowercased().contains("restart"),
                      "a denied→granted transition should hint at a restart: \(message)")
    }
}
