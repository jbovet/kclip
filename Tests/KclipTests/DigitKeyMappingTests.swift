// DigitKeyMappingTests.swift
// KclipTests

import XCTest
@testable import Kclip

/// Tests for the paste-by-number key mapping and the "shortcut vs. search text"
/// gating that governs the digit keys in the clipboard popup.
final class DigitKeyMappingTests: XCTestCase {

    // MARK: - Key codes (hardware virtual key codes, layout-independent)

    /// Top-row digit key codes in display order: 1 2 3 4 5 6 7 8 9 0.
    private let topRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    /// Numpad digit key codes in display order: 1 2 3 4 5 6 7 8 9 0.
    private let numpad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92, 82]

    // MARK: - Unmodified digits, search inactive → paste items 1…10

    func testUnmodified_searchInactive_topRowMapsToItems1Through10() {
        for (offset, keyCode) in topRow.enumerated() {
            let expected = offset + 1  // 1…10 (last key "0" → 10)
            XCTAssertEqual(
                DigitKeyMapping.unmodifiedPasteIndex(keyCode: keyCode, searchActive: false),
                expected,
                "top-row key code \(keyCode) should map to item \(expected)"
            )
        }
    }

    func testUnmodified_searchInactive_numpadMapsToItems1Through10() {
        for (offset, keyCode) in numpad.enumerated() {
            let expected = offset + 1
            XCTAssertEqual(
                DigitKeyMapping.unmodifiedPasteIndex(keyCode: keyCode, searchActive: false),
                expected,
                "numpad key code \(keyCode) should map to item \(expected)"
            )
        }
    }

    // MARK: - Regression: digits must be typeable while searching

    /// The bug this guards against: digit keys were consumed as paste shortcuts
    /// even during search, making queries like "utf8" or "python3" impossible.
    func testUnmodified_searchActive_topRowReturnsNil() {
        for keyCode in topRow {
            XCTAssertNil(
                DigitKeyMapping.unmodifiedPasteIndex(keyCode: keyCode, searchActive: true),
                "key code \(keyCode) must forward to the search field while searching"
            )
        }
    }

    func testUnmodified_searchActive_numpadReturnsNil() {
        for keyCode in numpad {
            XCTAssertNil(
                DigitKeyMapping.unmodifiedPasteIndex(keyCode: keyCode, searchActive: true)
            )
        }
    }

    // MARK: - Non-digit keys are never treated as paste shortcuts

    func testUnmodified_nonDigitKeyReturnsNil() {
        // 0 (kVK_ANSI_A), 49 (space), 36 (return) are not digit keys.
        for keyCode: UInt16 in [0, 49, 36, 51, 126, 125] {
            XCTAssertNil(
                DigitKeyMapping.unmodifiedPasteIndex(keyCode: keyCode, searchActive: false),
                "non-digit key code \(keyCode) must not map to a paste index"
            )
        }
    }

    // MARK: - ⌘-digits → items 11…15, active regardless of search state

    func testCommand_topRow1Through5MapsToItems11Through15() {
        let cmdKeys = Array(topRow.prefix(5))  // 1 2 3 4 5
        for (offset, keyCode) in cmdKeys.enumerated() {
            let expected = offset + 11  // 11…15
            XCTAssertEqual(
                DigitKeyMapping.commandPasteIndex(keyCode: keyCode),
                expected,
                "⌘ + key code \(keyCode) should map to item \(expected)"
            )
        }
    }

    func testCommand_digits6Through0ReturnNil() {
        // Only ⌘1–⌘5 are bound; ⌘6…⌘0 are not.
        for keyCode in topRow.suffix(from: 5) {  // 6 7 8 9 0
            XCTAssertNil(
                DigitKeyMapping.commandPasteIndex(keyCode: keyCode),
                "⌘ + key code \(keyCode) should not be a paste shortcut"
            )
        }
    }

    func testCommand_numpadReturnsNil() {
        for keyCode in numpad {
            XCTAssertNil(DigitKeyMapping.commandPasteIndex(keyCode: keyCode))
        }
    }

    // MARK: - Table integrity

    func testUnmodifiedTable_coversTenTopRowAndTenNumpadKeys() {
        XCTAssertEqual(DigitKeyMapping.unmodified.count, 20)
        // Values span exactly 1…10.
        XCTAssertEqual(Set(DigitKeyMapping.unmodified.values), Set(1...10))
    }

    func testCommandTable_coversFiveKeys() {
        XCTAssertEqual(DigitKeyMapping.command.count, 5)
        XCTAssertEqual(Set(DigitKeyMapping.command.values), Set(11...15))
    }
}
