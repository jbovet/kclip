// HotkeyOptionTests.swift
// Kclip – Open-source keyboard-first clipboard manager
// Unit tests for HotkeyOption persistence, lookup, and predefined options.

import XCTest
import Carbon.HIToolbox
@testable import Kclip

final class HotkeyOptionTests: XCTestCase {

    private static let testSuiteName = "cc.kclip.hotkeyTests"
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: Self.testSuiteName)!
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - allOptions

    func testAllOptions_hasExpectedCount() {
        XCTAssertEqual(HotkeyOption.allOptions.count, 5)
    }

    func testAllOptions_defaultIsFirst() {
        XCTAssertEqual(HotkeyOption.defaultOption, HotkeyOption.allOptions[0])
    }

    func testAllOptions_labelsAreUnique() {
        let labels = HotkeyOption.allOptions.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "Hotkey labels must be unique")
    }

    // MARK: - find

    func testFind_existingOption() {
        let option = HotkeyOption.find(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        XCTAssertNotNil(option)
        XCTAssertEqual(option?.label, "⌘⇧V")
    }

    func testFind_nonExistentOption_returnsNil() {
        let option = HotkeyOption.find(keyCode: 999, modifiers: 999)
        XCTAssertNil(option)
    }

    func testFind_allPredefinedOptions() {
        for expected in HotkeyOption.allOptions {
            let found = HotkeyOption.find(keyCode: expected.keyCode, modifiers: expected.modifiers)
            XCTAssertEqual(found, expected, "Should find option \(expected.label)")
        }
    }

    // MARK: - save / load

    func testLoad_noSavedData_returnsDefault() {
        let loaded = HotkeyOption.load()
        XCTAssertEqual(loaded, HotkeyOption.defaultOption)
    }

    func testSaveAndLoad_roundTrip() {
        let option = HotkeyOption.allOptions[2] // ⌃⇧V
        option.save()
        let loaded = HotkeyOption.load()
        XCTAssertEqual(loaded, option)
    }

    func testLoad_invalidSavedData_returnsDefault() {
        // Save key code / modifiers that don't match any predefined option
        UserDefaults.standard.set(9999, forKey: "cc.kclip.hotkeyKeyCode")
        UserDefaults.standard.set(9999, forKey: "cc.kclip.hotkeyModifiers")
        let loaded = HotkeyOption.load()
        XCTAssertEqual(loaded, HotkeyOption.defaultOption)
        // Clean up
        UserDefaults.standard.removeObject(forKey: "cc.kclip.hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "cc.kclip.hotkeyModifiers")
    }

    // MARK: - Equatable

    func testEquatable_sameValues() {
        let a = HotkeyOption(label: "⌘⇧V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
        let b = HotkeyOption(label: "⌘⇧V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(a, b)
    }

    func testEquatable_differentValues() {
        let a = HotkeyOption.allOptions[0]
        let b = HotkeyOption.allOptions[1]
        XCTAssertNotEqual(a, b)
    }
}
