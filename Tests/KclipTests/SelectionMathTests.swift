// SelectionMathTests.swift
// KclipTests

import XCTest
@testable import Kclip

/// Tests for the pure selection-index arithmetic used by the clipboard popup.
final class SelectionMathTests: XCTestCase {

    // MARK: - wrapped(_:delta:count:)

    func testWrapped_movesDownWithinBounds() {
        XCTAssertEqual(SelectionMath.wrapped(0, delta: 1, count: 5), 1)
        XCTAssertEqual(SelectionMath.wrapped(3, delta: 1, count: 5), 4)
    }

    func testWrapped_movesUpWithinBounds() {
        XCTAssertEqual(SelectionMath.wrapped(2, delta: -1, count: 5), 1)
    }

    func testWrapped_wrapsFromBottomToTop() {
        XCTAssertEqual(SelectionMath.wrapped(4, delta: 1, count: 5), 0)
    }

    func testWrapped_wrapsFromTopToBottom() {
        XCTAssertEqual(SelectionMath.wrapped(0, delta: -1, count: 5), 4)
    }

    func testWrapped_emptyListReturnsZero() {
        XCTAssertEqual(SelectionMath.wrapped(0, delta: 1, count: 0), 0)
        XCTAssertEqual(SelectionMath.wrapped(3, delta: -1, count: 0), 0)
    }

    func testWrapped_singleItemStaysAtZero() {
        XCTAssertEqual(SelectionMath.wrapped(0, delta: 1, count: 1), 0)
        XCTAssertEqual(SelectionMath.wrapped(0, delta: -1, count: 1), 0)
    }

    func testWrapped_handlesDeltaLargerThanCount() {
        // Robustness: magnitudes beyond the list size must still land in range.
        XCTAssertEqual(SelectionMath.wrapped(0, delta: 7, count: 5), 2)
        XCTAssertEqual(SelectionMath.wrapped(0, delta: -7, count: 5), 3)
    }

    // MARK: - clampedAfterRemoval(_:newCount:)

    /// Deleting a middle row: selection stays put, now pointing at the item
    /// that slid into the gap.
    func testClamped_middleRemoval_indexUnchanged() {
        // Was 5 items, selecting index 2; after removal 4 items remain.
        XCTAssertEqual(SelectionMath.clampedAfterRemoval(2, newCount: 4), 2)
    }

    /// Regression for the delete bug: removing the last row must move the
    /// selection up to the new last index rather than pointing off the end.
    func testClamped_lastRowRemoval_movesUp() {
        // Was 5 items, selecting the last (index 4); after removal 4 remain.
        XCTAssertEqual(SelectionMath.clampedAfterRemoval(4, newCount: 4), 3)
    }

    func testClamped_firstRowRemoval_staysAtZero() {
        XCTAssertEqual(SelectionMath.clampedAfterRemoval(0, newCount: 4), 0)
    }

    func testClamped_removingOnlyItem_returnsZero() {
        XCTAssertEqual(SelectionMath.clampedAfterRemoval(0, newCount: 0), 0)
    }

    func testClamped_neverReturnsNegative() {
        XCTAssertEqual(SelectionMath.clampedAfterRemoval(-3, newCount: 4), 0)
    }
}
