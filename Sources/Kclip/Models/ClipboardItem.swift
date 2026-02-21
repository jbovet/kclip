// ClipboardItem.swift
// Kclip – Open-source keyboard-first clipboard manager
// Model representing a single clipboard history entry

import Foundation

/// A single entry in the clipboard history.
///
/// Stores the original text content, when it was copied, and whether the user
/// has pinned it to prevent automatic eviction.
struct ClipboardItem: Identifiable, Codable, Equatable, Hashable {

    /// Stable unique identifier for list diffing and removal.
    let id: UUID

    /// The full text content copied to the clipboard.
    let content: String

    /// When this item was added to the history.
    let timestamp: Date

    /// Whether the user has pinned this item.
    ///
    /// Pinned items float to the top of the list and are never removed
    /// by the history size limit or `clearUnpinned()`.
    var isPinned: Bool

    /// The number of lines in the content.
    var lineCount: Int {
        content.components(separatedBy: .newlines).count
    }

    /// A single-line summary capped at 80 characters, used in compact views.
    ///
    /// Takes the first non-empty line of the content and truncates to 80 chars.
    var shortPreview: String {
        let trimmed = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? content
        return String(trimmed.prefix(80))
    }

    /// A best-guess classification of the content, used to pick a display icon.
    var contentType: ContentType {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return .url }
        if Self.looksLikeEmail(trimmed) { return .email }
        if lineCount > 1 { return .multiline }
        return .text
    }

    /// The kind of text stored in a ``ClipboardItem``.
    enum ContentType {
        /// Plain single-line text.
        case text
        /// A URL beginning with `http://` or `https://`.
        case url
        /// An email address (contains `@` and `.`, no spaces).
        case email
        /// Text that spans multiple lines.
        case multiline

        /// The SF Symbol name that represents this content type.
        var systemImage: String {
            switch self {
            case .text:      return "doc.plaintext"
            case .url:       return "link"
            case .email:     return "envelope"
            case .multiline: return "text.alignleft"
            }
        }
    }

    /// Creates a new clipboard item with the given text, a fresh UUID, and the current timestamp.
    /// - Parameter content: The full text that was copied.
    init(content: String) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.isPinned = false
    }

    // MARK: - Email Heuristic

    /// Returns `true` when `text` looks like a single email address.
    ///
    /// Requires at least one character before `@`, at least one character between
    /// `@` and the last `.`, and at least one character after the last `.`.
    /// Also rejects strings that contain whitespace or multiple `@` signs.
    private static func looksLikeEmail(_ text: String) -> Bool {
        // Quick rejections
        guard !text.contains(" "), !text.isEmpty else { return false }

        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        // Must have exactly one @ → two parts
        guard parts.count == 2 else { return false }

        let local  = parts[0]   // before @
        let domain = parts[1]   // after @

        guard !local.isEmpty, !domain.isEmpty else { return false }

        // Domain must contain at least one dot with something after it
        guard let dotIndex = domain.lastIndex(of: ".") else { return false }
        let afterDot = domain[domain.index(after: dotIndex)...]
        let beforeDot = domain[domain.startIndex..<dotIndex]
        guard !afterDot.isEmpty, !beforeDot.isEmpty else { return false }

        return true
    }
}
