// ClipboardPopupView.swift
// Kclip – Open-source keyboard-first clipboard manager
// The main Spotlight-style popup: search bar + scrollable clipboard list.
//
// Keyboard controls:
//   ↑ / ↓       → move selection
//   1 – 0       → instantly paste items 1–10
//   ⌘1 – ⌘5    → instantly paste items 11–15
//   Return      → paste selected item
//   ⌘Del        → delete selected item
//   ⌘P          → pin / unpin selected item
//   Space       → preview full content of selected item (when search is empty)
//   ⌥Return    → paste selected item as plain text
//   Escape      → dismiss (or close preview if open)
//   Type text   → filter the list

import SwiftUI
import AppKit

// MARK: - Main Popup View

/// The Spotlight-style clipboard history panel (580 × variable pt).
///
/// Shows a search bar and a scrollable list of ``ClipboardItem`` entries.
/// Keyboard shortcuts:
/// - `↑ / ↓` — move selection
/// - `1–0` — instant-paste items 1–10
/// - `⌘1–⌘5` — instant-paste items 11–15
/// - `Return` — paste selected item
/// - `⌘Delete` — delete selected item
/// - `⌘P` — pin / unpin selected item
/// - `Space` — preview full content of selected item (when search field is empty)
/// - `Escape` — close preview overlay, or dismiss panel
/// - Typing — filters the list in real time
struct ClipboardPopupView: View {

    // MARK: - Dependencies

    @ObservedObject var store: ClipboardStore
    /// Shared bridge whose closures are kept current by `BridgeUpdater` and whose
    /// `NSEvent` monitor is owned by `FloatingPanelController` (installed in `show()`).
    var bridge: KeyEventBridge
    /// Called with the item to paste. The caller is responsible for hiding the panel.
    var onPaste: (ClipboardItem) -> Void
    /// Called with the item to paste as plain text (⌘⌥⇧V in target app).
    var onPastePlainText: (ClipboardItem) -> Void
    /// Called when the panel should be dismissed without pasting.
    var onDismiss: () -> Void
    /// Called when the user clicks the power button to quit the app.
    var onQuit: () -> Void

    // MARK: - State

    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool
    /// Transient status message shown in the footer (e.g. "Copied to clipboard").
    /// Cleared automatically after 1.2 s.
    @State private var bannerMessage: String? = nil
    /// Item currently shown in the full-content preview overlay. `nil` = overlay hidden.
    @State private var previewItem: ClipboardItem? = nil

    // MARK: - Timing Constants

    /// Duration (seconds) the "Copied to clipboard" banner stays visible before clearing.
    private static let bannerDisplayDuration: TimeInterval = 1.2

    // MARK: - Derived

    /// `true` when the search field contains no non-whitespace characters.
    ///
    /// Whitespace-only text (e.g. an accidental Space that reached the TextField
    /// before the key monitor was reinstalled) is treated the same as truly empty.
    /// Used to gate the Del / P / Space keyboard shortcuts.
    private var searchIsEmpty: Bool { searchText.allSatisfy { $0.isWhitespace } }

    /// The subset of `store.items` matching the current search query.
    ///
    /// Delegates to ``ClipboardSearch/filter(_:query:)`` which trims whitespace,
    /// splits into tokens, and requires ALL tokens to appear in the item's content.
    /// A blank or whitespace-only query returns the full list.
    var filteredItems: [ClipboardItem] {
        ClipboardSearch.filter(store.items, query: searchText)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Main list UI
            VStack(spacing: 0) {
                searchBar
                Divider().opacity(0.5)
                itemsList
                Divider().opacity(0.3)
                footer
            }

            // Full-content preview overlay (shown when Space is pressed)
            if let item = previewItem {
                ItemPreviewView(item: item) {
                    // Paste from preview
                    previewItem = nil
                    onPaste(item)
                } onDismiss: {
                    closePreview()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
            }
        }
        .frame(width: 580)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.15), value: previewItem == nil)
        .onAppear {
            selectedIndex = 0
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipClipPanelWillShow)) { _ in
            searchText = ""
            selectedIndex = 0
            previewItem = nil
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipClipPanelEscapePressed)) { _ in
            // Escape closes the preview first; second Escape dismisses the panel
            if previewItem != nil {
                closePreview()
            } else {
                onDismiss()
            }
        }
        // Shown when paste() fires but there is no previous app to paste into
        .onReceive(NotificationCenter.default.publisher(for: .clipClipCopiedOnly)) { _ in
            bannerMessage = "Copied to clipboard"
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerDisplayDuration) {
                bannerMessage = nil
            }
        }
        // BridgeUpdater keeps KeyEventBridge closures current on every SwiftUI render.
        // The actual NSEvent monitor is owned by FloatingPanelController (show/hide),
        // so it can never be silently removed by SwiftUI view-hierarchy changes.
        .background(BridgeUpdater(
            bridge:   bridge,
            onUp:     { moveSelection(-1) },
            onDown:   { moveSelection(+1) },
            onReturn: { pasteSelected() },
            onOptionReturn: { pastePlainTextSelected() },
            onEscape: {
                if previewItem != nil {
                    closePreview()
                } else {
                    onDismiss()
                }
            },
            onDelete: { deleteSelected() },
            onPin:    { pinSelected() },
            onSpace:  { previewSelected() },
            onUndo:   { undoDelete() },
            onDigit:  { digit in pasteByNumber(digit) },
            // Closure — not Bool — so the bridge always reads the live @State value
            // at the moment the key event fires, regardless of render timing.
            // Only Space still needs this gate; ⌘Delete / ⌘P work even during search.
            isSearchActive: { !searchIsEmpty || previewItem != nil }
        ))
        .onChange(of: searchText) { _ in selectedIndex = 0 }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search clipboard history…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
                .onSubmit { pasteSelected() }

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // Maximum height of the scrollable list area.
    // Fits ~8 rows (≈ 44 pt each + 2 pt spacing + 12 pt outer padding) before scrolling starts.
    private static let maxListHeight: CGFloat = 380

    private var itemsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    if filteredItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, item in
                            ClipboardRowView(
                                item: item,
                                index: idx,
                                isSelected: idx == selectedIndex,
                                showBadge: idx < store.maxItems
                            )
                            // Tag each row so ScrollViewReader can scroll to it
                            .id(idx)
                            .contentShape(Rectangle())
                            .onTapGesture { onPaste(item) }
                            .onHover { hovering in if hovering { selectedIndex = idx } }
                            .contextMenu {
                                Button("Paste")   { onPaste(item) }
                                Button("Paste as Plain Text") { onPastePlainText(item) }
                                Button("Preview") { withAnimation { previewItem = item } }
                                Button(item.isPinned ? "Unpin" : "Pin") {
                                    store.togglePin(id: item.id)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    store.remove(id: item.id)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            // Keep selected row visible when navigating with ↑/↓
            .onChange(of: selectedIndex) { newIdx in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
        // Cap the list at maxListHeight so NSHostingView.fittingSize reports the right
        // natural height. The panel is resized to fittingSize on every show(), so it
        // shrinks when there are few items and stays at the cap when there are many.
        .frame(maxHeight: Self.maxListHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "Nothing copied yet" : "No matches for \"\(searchText)\"")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            keyHint(key: "↑↓", label: "nav")
            keyHint(key: "⏎",  label: "paste")
            keyHint(key: "⌥⏎", label: "plain")
            keyHint(key: "⌘⌫", label: "del")
            keyHint(key: "⌘Z", label: "undo")
            keyHint(key: "⌘P", label: "pin")
            keyHint(key: "⎵",  label: "preview")
            Spacer()
            // Shows a transient banner (e.g. "Copied to clipboard") or item count
            Group {
                if let message = bannerMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(filteredItems.count) item\(filteredItems.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: bannerMessage)

            Button(action: confirmClearAll) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.items.isEmpty ? .tertiary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty)
            .help("Clear all history")
            .accessibilityLabel("Clear all history")

            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Kclip")
            .accessibilityLabel("Quit Kclip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func keyHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func confirmClearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This will remove all \(store.items.filter { !$0.isPinned }.count) unpinned items. Pinned items will be kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        // Sheet the alert onto the floating panel so it appears above it
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    store.clearUnpinned()
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                store.clearUnpinned()
            }
        }
    }

    /// Removes the currently selected item. Works during search; no-op when preview is open.
    private func deleteSelected() {
        guard previewItem == nil,
              let item = filteredItems[safe: selectedIndex] else { return }
        let prevCount = filteredItems.count
        store.remove(id: item.id)
        // Keep index in bounds after removal
        if selectedIndex >= prevCount - 1 {
            selectedIndex = max(0, prevCount - 2)
        }
    }

    /// Toggles the pin state of the currently selected item. Works during search; no-op when preview is open.
    private func pinSelected() {
        guard previewItem == nil,
              let item = filteredItems[safe: selectedIndex] else { return }
        store.togglePin(id: item.id)
    }

    /// Opens the full-content preview overlay for the currently selected item.
    private func previewSelected() {
        guard searchIsEmpty,
              let item = filteredItems[safe: selectedIndex] else { return }
        withAnimation { previewItem = item }
    }

    /// Closes the preview overlay and restores selection to the previewed item's
    /// position in the list. Always call this instead of clearing `previewItem` inline
    /// so that `selectedIndex` is never left at 0 after a Space → Escape cycle.
    private func closePreview() {
        // Re-locate the previewed item in the current list before clearing state,
        // so selectedIndex tracks the item even if pinning reordered it.
        if let current = previewItem,
           let idx = filteredItems.firstIndex(where: { $0.id == current.id }) {
            selectedIndex = idx
        }
        withAnimation { previewItem = nil }
        isSearchFocused = true
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func pasteSelected() {
        guard let item = filteredItems[safe: selectedIndex] else { return }
        onPaste(item)
    }

    /// Pastes the currently selected item as plain text (⌥Return).
    private func pastePlainTextSelected() {
        guard let item = filteredItems[safe: selectedIndex] else { return }
        onPastePlainText(item)
    }

    /// Undoes the last delete and shows a transient "Item restored" banner.
    private func undoDelete() {
        if store.undo() {
            bannerMessage = "Item restored"
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerDisplayDuration) {
                if bannerMessage == "Item restored" { bannerMessage = nil }
            }
        }
    }

    private func pasteByNumber(_ digit: Int) {
        // digit is 1-based (1=first item)
        let idx = digit - 1
        guard let item = filteredItems[safe: idx] else { return }
        selectedIndex = idx
        onPaste(item)
    }
}

// MARK: - Item Preview Overlay

/// Full-content overlay shown when the user presses Space on a list item.
///
/// Displays the complete text with a scrollable ``TextEditor``-style view,
/// a character count, the item's timestamp, and quick Paste / Close actions.
private struct ItemPreviewView: View {
    let item: ClipboardItem
    /// Called when the user chooses to paste from this overlay.
    var onPaste: () -> Void
    /// Called when the user dismisses the overlay without pasting.
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 10) {
                Image(systemName: item.contentType.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Full Content")
                        .font(.system(size: 12, weight: .semibold))
                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(item.content.count) chars")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close preview")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.4)

            // Scrollable full text — .textSelection(.enabled) lets users select & copy
            ScrollView(.vertical, showsIndicators: true) {
                Text(item.content)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            Divider().opacity(0.3)

            // Footer
            HStack {
                Text("⏎ paste  ·  Esc close")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Paste", action: onPaste)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .padding(10)
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
    }
}

// MARK: - BridgeUpdater (NSViewRepresentable)
// A zero-footprint NSViewRepresentable whose sole job is to push fresh action closures
// into KeyEventBridge on every SwiftUI render cycle.
//
// The NSEvent monitor itself lives in FloatingPanelController (show / hide), completely
// decoupled from the SwiftUI view hierarchy. This eliminates the class of bugs where
// viewDidMoveToWindow removes the monitor whenever SwiftUI touches the ZStack or focus.

private struct BridgeUpdater: NSViewRepresentable {
    let bridge: KeyEventBridge
    var onUp:           () -> Void
    var onDown:         () -> Void
    var onReturn:       () -> Void
    var onOptionReturn: () -> Void
    var onEscape:       () -> Void
    var onDelete:       () -> Void
    var onPin:          () -> Void
    var onSpace:        () -> Void
    var onUndo:         () -> Void
    var onDigit:        (Int) -> Void
    /// Closure — not Bool — so KeyEventBridge reads live @State at event time.
    var isSearchActive: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        pushToBridge()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        pushToBridge()
    }

    private func pushToBridge() {
        bridge.onUp           = onUp
        bridge.onDown         = onDown
        bridge.onReturn       = onReturn
        bridge.onOptionReturn = onOptionReturn
        bridge.onEscape       = onEscape
        bridge.onDelete       = onDelete
        bridge.onPin          = onPin
        bridge.onSpace        = onSpace
        bridge.onUndo         = onUndo
        bridge.onDigit        = onDigit
        bridge.isSearchActive = isSearchActive
    }
}

// MARK: - Safe subscript helper

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
