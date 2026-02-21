// ClipboardRowView.swift
// Kclip – Open-source keyboard-first clipboard manager
// A single row in the clipboard list: badge, icon, text preview, timestamp.

import SwiftUI

/// A single row in the clipboard history list.
///
/// Displays a numbered badge, content-type icon, text preview, relative timestamp,
/// and a pin indicator. Visual selection state is driven by `isSelected`.
struct ClipboardRowView: View {

    /// The clipboard item this row represents.
    let item: ClipboardItem
    /// 0-based position in the list, used to render the badge label.
    let index: Int
    /// Whether this row is currently selected (highlighted).
    let isSelected: Bool
    /// When `false` the badge area is left blank (used for items beyond ``ClipboardStore/maxItems``).
    let showBadge: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            // Number badge (1–9) or pin icon
            badge

            // Content type icon
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            // Text preview
            VStack(alignment: .leading, spacing: 2) {
                Text(item.shortPreview)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                if item.lineCount > 1 {
                    Text("\(item.lineCount) lines")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Timestamp
            Text(item.timestamp, format: .relative(presentation: .named))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Pin indicator
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint(isSelected ? "Press Return to paste" : "")
    }

    // MARK: - Accessibility

    private var rowAccessibilityLabel: String {
        var parts: [String] = []
        if showBadge { parts.append("Item \(index + 1)") }
        if item.isPinned { parts.append("pinned") }
        parts.append(item.shortPreview)
        if item.lineCount > 1 { parts.append("\(item.lineCount) lines") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Subviews

    private var badge: some View {
        Group {
            if showBadge {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(width: 18, height: 18)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.9)
                            : Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .foregroundStyle(isSelected ? .white : .secondary)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ClipboardRowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 4) {
            ClipboardRowView(
                item: ClipboardItem(content: "Hello, World!"),
                index: 0,
                isSelected: true,
                showBadge: true
            )
            ClipboardRowView(
                item: ClipboardItem(content: "https://github.com/example/kclip"),
                index: 1,
                isSelected: false,
                showBadge: true
            )
            ClipboardRowView(
                item: ClipboardItem(content: "line one\nline two\nline three"),
                index: 2,
                isSelected: false,
                showBadge: true
            )
        }
        .padding()
        .frame(width: 580)
        .background(.ultraThinMaterial)
    }
}
#endif
