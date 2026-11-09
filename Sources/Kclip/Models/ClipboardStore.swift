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

    /// UserDefaults key for the memory-only setting.
    private static let memoryOnlyKey = "cc.kclip.memoryOnly"

    /// When `true`, history is kept in memory for the current session only and
    /// is never written to disk. Defaults to `false` (history persists).
    ///
    /// Enabling it clears any already-persisted history and turns ``save()`` into
    /// a no-op; disabling it persists the current in-memory items immediately.
    var memoryOnly: Bool {
        get { defaults.bool(forKey: Self.memoryOnlyKey) }
        set {
            defaults.set(newValue, forKey: Self.memoryOnlyKey)
            if newValue {
                // Stop persisting and wipe anything already written to disk.
                defaults.removeObject(forKey: storageKey)
            } else {
                // Resume persistence: write the current session's items now.
                save()
            }
        }
    }

    /// UserDefaults key for the clear-on-quit setting.
    private static let clearOnQuitKey = "cc.kclip.clearOnQuit"

    /// When `true`, unpinned history does not survive Kclip quitting, so the
    /// next launch starts clean. Pinned items are kept. Defaults to `false`.
    ///
    /// While enabled, only pinned items are ever written to disk: unpinned
    /// history lives in memory, so a crash, force-quit, or kill (which skip
    /// `applicationWillTerminate`) cannot leave it behind. Toggling re-saves
    /// immediately: enabling scrubs unpinned items already on disk, disabling
    /// persists the current session's items.
    var clearOnQuit: Bool {
        get { defaults.bool(forKey: Self.clearOnQuitKey) }
        set {
            defaults.set(newValue, forKey: Self.clearOnQuitKey)
            save()
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

    /// An item removed by a delete / clear, plus where to put it back.
    private struct RemovedItem {
        let item: ClipboardItem
        /// The nearest item *below* it that survived the removal (`nil` if it
        /// was at the bottom). Undo re-inserts the item directly above this
        /// anchor, so items copied since the delete stay above it — unlike a
        /// raw index, which goes stale as soon as anything is added on top.
        let anchorID: UUID?
    }

    /// One undoable deletion, in original top-to-bottom order.
    private typealias UndoEntry = [RemovedItem]

    /// Stack of deletions for undo support. Each `remove` / `clearUnpinned`
    /// pushes only what it removed, so undo re-inserts those items without
    /// discarding anything added, pinned, or trimmed since (a full snapshot
    /// restore used to silently drop items copied after the delete).
    private var undoStack: [UndoEntry] = []

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
        // Capture the id first: the predicate must not read `items` while
        // removeAll(where:) is mutating it (exclusive-access violation).
        let id = items[index].id
        removeItems { $0.id == id }
    }

    /// Removes the item with the given identifier. Pushes an undo entry.
    /// - Parameter id: The `UUID` of the item to remove.
    func remove(id: UUID) {
        removeItems { $0.id == id }
    }

    /// Re-inserts the items removed by the most recent delete / clear.
    ///
    /// Items go back where they were relative to their neighbours, so anything
    /// copied, pinned, or reordered since the delete is kept and history stays
    /// newest-first. An unpinned item whose text was copied again meanwhile is
    /// not restored twice, and the ``maxItems`` limit is re-applied.
    ///
    /// An entry that would restore nothing visible (everything already back,
    /// or immediately trimmed by the limit) is skipped in favour of the next
    /// one, so each successful call visibly restores something.
    /// - Returns: `true` if at least one item was restored, `false` otherwise.
    @discardableResult
    func undo() -> Bool {
        while let entry = undoStack.popLast() {
            if restore(entry) {
                save()
                return true
            }
        }
        return false
    }

    /// Re-inserts one entry's items and re-applies the limit.
    /// - Returns: `true` if at least one restored item survived trimming.
    private func restore(_ entry: UndoEntry) -> Bool {
        let before = items
        var restoredIDs: Set<UUID> = []
        for removed in entry {
            let item = removed.item
            let alreadyPresent = items.contains {
                $0.id == item.id || (!item.isPinned && !$0.isPinned && $0.content == item.content)
            }
            guard !alreadyPresent else { continue }
            items.insert(item, at: insertionIndex(for: removed))
            restoredIDs.insert(item.id)
        }
        applyLimit()
        guard items.contains(where: { restoredIDs.contains($0.id) }) else {
            items = before   // nothing visible came back; leave history untouched
            return false
        }
        return true
    }

    /// Where to re-insert a removed item, keeping pinned items first.
    private func insertionIndex(for removed: RemovedItem) -> Int {
        let item = removed.item
        let pinnedCount = items.lazy.filter(\.isPinned).count
        // Directly above the anchor, if it still exists in the same group.
        if let anchorID = removed.anchorID,
           let anchor = items.firstIndex(where: { $0.id == anchorID }),
           items[anchor].isPinned == item.isPinned {
            return anchor
        }
        if item.isPinned {
            return pinnedCount                       // bottom of the pinned group
        }
        if removed.anchorID == nil {
            return items.count                       // it was the bottom item
        }
        // Anchor gone (deleted / pinned since): fall back to copy time so the
        // unpinned group stays newest-first.
        return items[pinnedCount...].firstIndex { $0.timestamp < item.timestamp } ?? items.count
    }

    /// Toggles the pinned state of an item and re-sorts so pinned items stay on top.
    /// - Parameter id: The `UUID` of the item to pin or unpin.
    func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned.toggle()
        // Re-sort: pinned items float to top.
        let pinned   = items.filter { $0.isPinned }
        var unpinned = items.filter { !$0.isPinned }
        // Unpinning grows the unpinned set and can push it over the limit — trim
        // the oldest so togglePin respects maxItems the same way add() does.
        if unpinned.count > maxItems {
            unpinned = Array(unpinned.prefix(maxItems))
        }
        items = pinned + unpinned
        save()
    }

    /// Enforces the current `maxItems` limit, trimming excess unpinned items.
    /// Call after changing ``maxItems`` to apply the new limit immediately.
    func trimToLimit() {
        if applyLimit() { save() }
    }

    /// Drops the oldest unpinned items beyond ``maxItems`` (no save).
    /// - Returns: `true` if anything was trimmed.
    @discardableResult
    private func applyLimit() -> Bool {
        let pinned   = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        guard unpinned.count > maxItems else { return false }
        items = pinned + Array(unpinned.prefix(maxItems))
        return true
    }

    /// Removes all unpinned items from history. Pinned items are preserved. Pushes an undo snapshot.
    func clearUnpinned() {
        removeItems { !$0.isPinned }
    }

    /// Called on app termination: if ``clearOnQuit`` is enabled, remove unpinned
    /// history (pinned items are kept) and persist, so the next launch starts
    /// clean. No undo snapshot is pushed since the app is shutting down.
    func clearOnQuitIfNeeded() {
        guard clearOnQuit else { return }
        items.removeAll { !$0.isPinned }
        save()
    }

    // MARK: - Undo Helpers

    /// Removes every item matching `predicate`, recording them (with their
    /// anchors) as one undo entry. No-op — and no undo entry — if nothing matches.
    private func removeItems(where predicate: (ClipboardItem) -> Bool) {
        // Walk bottom-up so each removed item knows the nearest survivor below it.
        var removed: UndoEntry = []
        var survivorBelow: UUID?
        for item in items.reversed() {
            if predicate(item) {
                removed.append(RemovedItem(item: item, anchorID: survivorBelow))
            } else {
                survivorBelow = item.id
            }
        }
        removed.reverse()   // back to top-to-bottom order
        guard !removed.isEmpty else { return }
        pushUndo(removed)
        items.removeAll(where: predicate)
        save()
    }

    /// Records a deletion so it can be undone.
    private func pushUndo(_ entry: UndoEntry) {
        undoStack.append(entry)
        // Cap the stack so memory usage stays bounded
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst(undoStack.count - Self.maxUndoDepth)
        }
    }

    // MARK: - Persistence (UserDefaults)

    private func save() {
        // In memory-only mode history is never written to disk.
        guard !memoryOnly else { return }
        // With clear-on-quit, unpinned history is never persisted (see clearOnQuit).
        let toPersist = clearOnQuit ? items.filter(\.isPinned) : items
        guard let data = try? JSONEncoder().encode(toPersist) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        // In memory-only mode we start each session empty.
        guard !memoryOnly else { return }
        guard
            let data  = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        guard clearOnQuit else {
            items = saved
            return
        }
        // Clear-on-quit: drop unpinned items left on disk (e.g. by an older build
        // that crashed before its quit hook ran) and scrub them from storage now,
        // rather than waiting for the next mutation to rewrite it.
        items = saved.filter(\.isPinned)
        if items.count != saved.count { save() }
    }
}
