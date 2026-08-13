// SelectionMath.swift
// Kclip – Open-source keyboard-first clipboard manager
// Pure index arithmetic for the clipboard list selection.
// Extracted from `ClipboardPopupView` so the selection rules are unit-testable.

import Foundation

/// Stateless helpers that keep the popup's `selectedIndex` valid as the list
/// changes underneath it (navigation, deletion).
enum SelectionMath {

    /// Moves `index` by `delta`, wrapping around both ends of a list of `count`
    /// items (↑ past the top lands on the bottom, and vice-versa).
    ///
    /// Robust to any `delta`, including magnitudes larger than `count`.
    ///
    /// - Parameters:
    ///   - index: The current 0-based selection.
    ///   - delta: Signed step (e.g. `-1` for ↑, `+1` for ↓).
    ///   - count: Number of items in the list.
    /// - Returns: The new index in `0..<count`, or `0` when the list is empty.
    static func wrapped(_ index: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let m = (index + delta) % count
        return m < 0 ? m + count : m
    }

    /// Clamps a selection index after the list has shrunk (e.g. following a
    /// delete) so it never points past the end.
    ///
    /// When the removed item was the last row, selection moves up to the new
    /// last row; otherwise it stays in place (now pointing at the item that
    /// slid into the gap). Returns `0` for an empty list.
    ///
    /// - Parameters:
    ///   - index: The selection index *before* accounting for the removal.
    ///   - newCount: The item count *after* the removal.
    /// - Returns: A valid index in `0..<newCount`, or `0` when the list is empty.
    static func clampedAfterRemoval(_ index: Int, newCount: Int) -> Int {
        guard newCount > 0 else { return 0 }
        return min(max(index, 0), newCount - 1)
    }
}
