// ClipboardStore.swift
// Kclip – Open-source keyboard-first clipboard manager
// Observable store that holds, deduplicates, and persists clipboard history

import Foundation
import Combine

/// Observable store that owns the clipboard history.
///
/// Responsibilities:
/// - Deduplicates entries by exact content match (case-sensitive).
/// - Keeps all pinned items plus up to ``maxItems`` unpinned items.
/// - Persists the history to `UserDefaults` as JSON on every mutation.
class ClipboardStore: ObservableObject {

    // MARK: - Configuration

    /// Available choices for the maximum number of unpinned items.
    static let maxItemsOptions = [10, 15, 25, 50]

    /// UserDefaults key for the configurable history size.
    private static let maxItemsKey = "cc.kclip.maxItems"

    /// Maximum number of *unpinned* items kept in history.
    /// Pinned items are always preserved regardless of this limit.
    /// Defaults to 15 and can be changed from the status-bar right-click menu.
    var maxItems: Int {
        get {
            let stored = defaults.integer(forKey: Self.maxItemsKey)
            return stored > 0 ? stored : 15
        }
        set {
            defaults.set(newValue, forKey: Self.maxItemsKey)
        }
    }

    private let storageKey = "cc.kclip.history"

    /// The `UserDefaults` suite used for persistence.
    /// Injectable for test isolation.
    private let defaults: UserDefaults

    /// Maximum number of undo snapshots kept in memory.
    private static let maxUndoDepth = 10

    // MARK: - Published State

    /// The full ordered history: pinned items first, then unpinned newest-first.
    @Published var items: [ClipboardItem] = []

    // MARK: - Undo Stack

    /// Stack of previous `items` snapshots for undo support.
    /// Each `remove` / `clearUnpinned` pushes the pre-mutation state here.
    private var undoStack: [[ClipboardItem]] = []

    /// `true` when there is at least one undoable action.
    var canUndo: Bool { !undoStack.isEmpty }

    // MARK: - Init

    /// Creates a store backed by the given `UserDefaults` suite.
    /// - Parameter defaults: The defaults suite for persistence. Pass a custom
    ///   `UserDefaults(suiteName:)` in tests to isolate from the user's real data.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Public API

    /// Adds an item to the top of the unpinned history.
    ///
    /// If an unpinned entry with the same content already exists it is removed
    /// before re-inserting so the new copy floats to the top.
    /// Pinned items with matching content are left untouched.
    ///
    /// - Parameter item: The clipboard item to add.
    func add(_ item: ClipboardItem) {
        // Remove any existing unpinned entry with the same text (re-insert at top)
        items.removeAll { !$0.isPinned && $0.content == item.content }

        // Insert at the top of unpinned items (after pinned ones)
        let pinnedCount = items.filter(\.isPinned).count
        items.insert(item, at: pinnedCount)

        // Trim history: keep all pinned + up to maxItems unpinned
        let unpinned = items.filter { !$0.isPinned }
        let pinned   = items.filter { $0.isPinned }
        if unpinned.count > maxItems {
            items = pinned + Array(unpinned.prefix(maxItems))
        }

        save()
    }

    /// Removes the item at the given index. Pushes an undo snapshot.
    /// - Parameter index: A valid index within `items`; out-of-range values are ignored.
    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        pushUndo()
        items.remove(at: index)
        save()
    }

    /// Removes the item with the given identifier. Pushes an undo snapshot.
    /// - Parameter id: The `UUID` of the item to remove.
    func remove(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        pushUndo()
        items.removeAll { $0.id == id }
        save()
    }

    /// Restores the most recent undo snapshot, reverting the last delete.
    /// - Returns: `true` if an undo was performed, `false` if the stack was empty.
    @discardableResult
    func undo() -> Bool {
        guard let snapshot = undoStack.popLast() else { return false }
        items = snapshot
        save()
        return true
    }

    /// Toggles the pinned state of an item and re-sorts so pinned items stay on top.
    /// - Parameter id: The `UUID` of the item to pin or unpin.
    func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned.toggle()
        // Re-sort: pinned items float to top
        let pinned   = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        items = pinned + unpinned
        save()
    }

    /// Enforces the current `maxItems` limit, trimming excess unpinned items.
    /// Call after changing ``maxItems`` to apply the new limit immediately.
    func trimToLimit() {
        let pinned   = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        if unpinned.count > maxItems {
            items = pinned + Array(unpinned.prefix(maxItems))
            save()
        }
    }

    /// Removes all unpinned items from history. Pinned items are preserved. Pushes an undo snapshot.
    func clearUnpinned() {
        pushUndo()
        items.removeAll { !$0.isPinned }
        save()
    }

    // MARK: - Undo Helpers

    /// Saves the current `items` array before a destructive operation.
    private func pushUndo() {
        undoStack.append(items)
        // Cap the stack so memory usage stays bounded
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst(undoStack.count - Self.maxUndoDepth)
        }
    }

    // MARK: - Persistence (UserDefaults)

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data  = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        items = saved
    }
}
