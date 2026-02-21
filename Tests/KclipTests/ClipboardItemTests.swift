// ClipboardItemTests.swift
// Kclip – Open-source keyboard-first clipboard manager
// Unit tests for ClipboardItem computed properties and Codable conformance.

import XCTest
@testable import Kclip

final class ClipboardItemTests: XCTestCase {

    // MARK: - ContentType Detection

    func testContentTypeURL_http() {
        let item = ClipboardItem(content: "http://example.com")
        XCTAssertEqual(item.contentType, .url)
    }

    func testContentTypeURL_https() {
        let item = ClipboardItem(content: "https://github.com/josebovet/kclip")
        XCTAssertEqual(item.contentType, .url)
    }

    func testContentTypeEmail() {
        let item = ClipboardItem(content: "user@example.com")
        XCTAssertEqual(item.contentType, .email)
    }

    func testContentTypeEmail_rejectsSpaces() {
        let item = ClipboardItem(content: "not an email @ example.com")
        XCTAssertNotEqual(item.contentType, .email)
    }

    func testContentTypeMultiline() {
        let item = ClipboardItem(content: "line one\nline two")
        XCTAssertEqual(item.contentType, .multiline)
    }

    func testContentTypePlainText() {
        let item = ClipboardItem(content: "just some text")
        XCTAssertEqual(item.contentType, .text)
    }

    // MARK: - lineCount

    func testLineCount_singleLine() {
        let item = ClipboardItem(content: "hello")
        XCTAssertEqual(item.lineCount, 1)
    }

    func testLineCount_multipleLines() {
        let item = ClipboardItem(content: "line one\nline two\nline three")
        XCTAssertEqual(item.lineCount, 3)
    }

    // MARK: - shortPreview

    func testShortPreviewTruncatesAt80Chars() {
        let longString = String(repeating: "a", count: 120)
        let item = ClipboardItem(content: longString)
        XCTAssertEqual(item.shortPreview.count, 80)
    }

    func testShortPreviewTakesFirstNonEmptyLine() {
        let item = ClipboardItem(content: "\n\nfirst real line\nsecond line")
        XCTAssertEqual(item.shortPreview, "first real line")
    }

    func testShortPreviewSingleLine() {
        let item = ClipboardItem(content: "hello")
        XCTAssertEqual(item.shortPreview, "hello")
    }

    // MARK: - systemImage

    func testSystemImage_text() {
        let item = ClipboardItem(content: "plain text")
        XCTAssertEqual(item.contentType.systemImage, "doc.plaintext")
    }

    func testSystemImage_url() {
        let item = ClipboardItem(content: "https://example.com")
        XCTAssertEqual(item.contentType.systemImage, "link")
    }

    func testSystemImage_email() {
        let item = ClipboardItem(content: "user@example.com")
        XCTAssertEqual(item.contentType.systemImage, "envelope")
    }

    func testSystemImage_multiline() {
        let item = ClipboardItem(content: "line1\nline2")
        XCTAssertEqual(item.contentType.systemImage, "text.alignleft")
    }

    // MARK: - shortPreview edge cases

    func testShortPreview_allEmptyLines_fallsBackToContent() {
        let item = ClipboardItem(content: "   ")
        // All lines are blank-ish → falls back to content
        XCTAssertFalse(item.shortPreview.isEmpty)
    }

    func testShortPreview_exactlyAtLimit() {
        let content = String(repeating: "x", count: 80)
        let item = ClipboardItem(content: content)
        XCTAssertEqual(item.shortPreview, content)
    }

    // MARK: - Email heuristics edge cases

    func testEmail_rejectsEmpty() {
        let item = ClipboardItem(content: "")
        XCTAssertNotEqual(item.contentType, .email)
    }

    func testEmail_rejectsNoAtSign() {
        let item = ClipboardItem(content: "notanemail.com")
        XCTAssertNotEqual(item.contentType, .email)
    }

    func testEmail_rejectsMultipleAtSigns() {
        let item = ClipboardItem(content: "a@@b.com")
        XCTAssertNotEqual(item.contentType, .email)
    }

    func testEmail_rejectsNoDotInDomain() {
        let item = ClipboardItem(content: "a@localhost")
        XCTAssertNotEqual(item.contentType, .email)
    }

    func testEmail_rejectsNothingAfterDot() {
        let item = ClipboardItem(content: "a@b.")
        XCTAssertNotEqual(item.contentType, .email)
    }

    func testEmail_rejectsNothingBeforeAt() {
        let item = ClipboardItem(content: "@example.com")
        XCTAssertNotEqual(item.contentType, .email)
    }

    func testEmail_rejectsNothingBeforeDot() {
        let item = ClipboardItem(content: "a@.com")
        XCTAssertNotEqual(item.contentType, .email)
    }

    // MARK: - lineCount edge cases

    func testLineCount_emptyString() {
        let item = ClipboardItem(content: "")
        XCTAssertEqual(item.lineCount, 1)
    }

    func testLineCount_trailingNewline() {
        let item = ClipboardItem(content: "hello\n")
        XCTAssertEqual(item.lineCount, 2)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = ClipboardItem(content: "round trip test")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.isPinned, original.isPinned)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       original.timestamp.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testCodableRoundTrip_preservesPinnedState() throws {
        var item = ClipboardItem(content: "pinned roundtrip")
        item.isPinned = true
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
        XCTAssertTrue(decoded.isPinned)
    }

    // MARK: - Init defaults

    func testInit_isPinnedFalseByDefault() {
        let item = ClipboardItem(content: "test")
        XCTAssertFalse(item.isPinned)
    }

    func testInit_generatesUniqueIDs() {
        let a = ClipboardItem(content: "same")
        let b = ClipboardItem(content: "same")
        XCTAssertNotEqual(a.id, b.id)
    }
}
