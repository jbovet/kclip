// ClipboardSearchTests.swift
// KclipTests

import XCTest
@testable import Kclip

final class ClipboardSearchTests: XCTestCase {

    // MARK: - Fixtures

    /// A small, fixed set of items used across all tests.
    private let items: [ClipboardItem] = [
        ClipboardItem(content: "Hello World"),
        ClipboardItem(content: "func fooBar()"),
        ClipboardItem(content: "https://example.com"),
        ClipboardItem(content: "swift async await"),
        ClipboardItem(content: "Kclip rocks"),
    ]

    // MARK: - Blank / whitespace queries → return everything

    func testEmptyQueryReturnsAll() {
        let result = ClipboardSearch.filter(items, query: "")
        XCTAssertEqual(result.count, items.count)
    }

    /// Regression: old code used `guard !searchText.isEmpty` so a pure-space
    /// query passed the guard and produced zero results.
    func testWhitespaceOnlyQueryReturnsAll() {
        let result = ClipboardSearch.filter(items, query: "   ")
        XCTAssertEqual(result.count, items.count)
    }

    /// Regression: leading/trailing spaces must be ignored.
    func testLeadingTrailingSpacesIgnored() {
        let result = ClipboardSearch.filter(items, query: "  hello  ")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "Hello World")
    }

    // MARK: - Single-token matching

    func testSingleTokenMatch() {
        let result = ClipboardSearch.filter(items, query: "swift")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "swift async await")
    }

    func testSingleTokenNoMatch() {
        let result = ClipboardSearch.filter(items, query: "python")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Multi-token AND matching (new capability)

    /// "func bar" should find items that contain BOTH "func" AND "bar" anywhere.
    func testMultiTokenMatch() {
        let result = ClipboardSearch.filter(items, query: "func bar")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "func fooBar()")
    }

    /// Only one token matches → no results.
    func testMultiTokenPartialMatch_returnsEmpty() {
        let result = ClipboardSearch.filter(items, query: "func python")
        XCTAssertTrue(result.isEmpty)
    }

    /// Multiple spaces between tokens must be treated as a single separator.
    func testMultipleSpacesBetweenTokens() {
        let result = ClipboardSearch.filter(items, query: "async   await")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "swift async await")
    }

    // MARK: - Case insensitivity

    func testCaseInsensitive() {
        let result = ClipboardSearch.filter(items, query: "KCLIP")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "Kclip rocks")
    }

    // MARK: - Newline treated as delimiter

    func testNewlineInQueryTreatedAsDelimiter() {
        // A query with an embedded newline should split into two tokens.
        let result = ClipboardSearch.filter(items, query: "async\nawait")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "swift async await")
    }
}
