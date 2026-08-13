// DigitKeyMapping.swift
// Kclip – Open-source keyboard-first clipboard manager
// Pure, stateless mapping from number-key key codes to clipboard item positions.
// Extracted from `KeyEventBridge` so the "shortcut vs. search text" decision is testable.

import Foundation

/// Maps physical number-key key codes to clipboard item positions for the
/// paste-by-number shortcuts, and decides whether a key press should act as a
/// paste shortcut or fall through to the search field as text.
///
/// The key codes are hardware virtual key codes (the same values reported by
/// `NSEvent.keyCode`), so the mapping is layout-independent.
enum DigitKeyMapping {

    /// Top-row and numpad number keys → items 1…10 (`0` maps to item 10).
    ///
    /// Top-row codes (18–29) and numpad codes (82–92) do not overlap, so they
    /// share one table safely.
    static let unmodified: [UInt16: Int] = [
        // Top row: 1 2 3 4 5 6 7 8 9 0
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10,
        // Numpad: 1 2 3 4 5 6 7 8 9 0
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 10,
    ]

    /// Top-row number keys → items 11…15, used with the ⌘ modifier.
    static let command: [UInt16: Int] = [18: 11, 19: 12, 20: 13, 21: 14, 23: 15]

    /// The clipboard item to paste for an *unmodified* digit key, or `nil` when
    /// the key should instead be typed into the search field.
    ///
    /// Digits act as paste shortcuts only while the search field is inactive
    /// (empty and no preview open). Once the user is typing a query, digits are
    /// text — so queries like `"utf8"` or `"python3"` work as expected.
    ///
    /// - Parameters:
    ///   - keyCode: The hardware key code from `NSEvent.keyCode`.
    ///   - searchActive: `true` when the search field has content or a preview is open.
    /// - Returns: The 1-based item position (1…10), or `nil` to forward the key as text.
    static func unmodifiedPasteIndex(keyCode: UInt16, searchActive: Bool) -> Int? {
        guard !searchActive else { return nil }
        return unmodified[keyCode]
    }

    /// The clipboard item to paste for a ⌘-modified digit key (items 11…15), or `nil`.
    ///
    /// ⌘-digit shortcuts stay active during search, mirroring the other
    /// ⌘-modified shortcuts (⌘Delete, ⌘P, ⌘Z).
    ///
    /// - Parameter keyCode: The hardware key code from `NSEvent.keyCode`.
    /// - Returns: The 1-based item position (11…15), or `nil` if the key is not a ⌘-digit.
    static func commandPasteIndex(keyCode: UInt16) -> Int? {
        command[keyCode]
    }
}
