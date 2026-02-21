/// ClipboardSearch.swift
/// Kclip
///
/// Pure, stateless search utility for filtering clipboard items.
/// Extracted from `ClipboardPopupView` for testability and reuse.

import Foundation

/// A namespace for clipboard search logic.
///
/// Use ``filter(_:query:)`` to match a list of ``ClipboardItem``s against a
/// user-supplied query string.  All sanitization (trimming, tokenising) is
/// handled internally so call-sites stay simple.
enum ClipboardSearch {

    // MARK: - Public API

    /// Returns the subset of `items` that matches every token in `query`.
    ///
    /// **Sanitization rules applied to `query`:**
    /// - Leading/trailing whitespace and newlines are stripped.
    /// - The remainder is split on any run of whitespace/newlines into tokens.
    /// - A blank or whitespace-only query produces *no* tokens → all items are returned.
    ///
    /// **Matching rule:**
    /// Every token must appear somewhere in `item.content`
    /// (case-insensitive, locale-aware).  This means a query like `"func bar"`
    /// finds items containing *both* `"func"` and `"bar"` anywhere, not
    /// necessarily adjacent.
    ///
    /// - Parameters:
    ///   - items: The source array of clipboard items to filter.
    ///   - query: The raw search string entered by the user.
    /// - Returns: A filtered array preserving the original order of `items`.
    static func filter(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return items }
        return items.filter { item in
            tokens.allSatisfy { item.content.localizedCaseInsensitiveContains($0) }
        }
    }

    // MARK: - Private helpers

    /// Trims `query` and splits it into non-empty tokens on whitespace/newlines.
    private static func tokenize(_ query: String) -> [String] {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
}
