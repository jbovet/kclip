// ClipboardStoreTests.swift
// Kclip – Open-source keyboard-first clipboard manager
// Unit tests for ClipboardStore: deduplication, pinning, trimming, undo, and persistence.

import XCTest
@testable import Kclip

final class ClipboardStoreTests: XCTestCase {

    /// Isolated UserDefaults suite so tests never read/write the user's real data.
    private static let testSuiteName = "cc.kclip.tests"
    private var testDefaults: UserDefaults!
    private var store: ClipboardStore!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: Self.testSuiteName)!
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        store = ClipboardStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        testDefaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Add

    func testAddItem() {
        store.add(ClipboardItem(content: "hello"))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].content, "hello")
    }

    func testAddMultipleItems_newestFirst() {
        store.add(ClipboardItem(content: "first"))
        store.add(ClipboardItem(content: "second"))
        XCTAssertEqual(store.items[0].content, "second")
        XCTAssertEqual(store.items[1].content, "first")
    }

    // MARK: - Deduplication

    func testDeduplication_keepsSingleCopy() {
        store.add(ClipboardItem(content: "dup"))
        store.add(ClipboardItem(content: "dup"))
        XCTAssertEqual(store.items.count, 1)
    }

    func testDeduplication_floatsToTop() {
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.add(ClipboardItem(content: "A"))   // re-add A
        XCTAssertEqual(store.items[0].content, "A")
        XCTAssertEqual(store.items[1].content, "B")
        XCTAssertEqual(store.items.count, 2)
    }

    func testDeduplication_isCaseSensitive() {
        store.add(ClipboardItem(content: "hello"))
        store.add(ClipboardItem(content: "Hello"))
        XCTAssertEqual(store.items.count, 2)
    }

    // MARK: - Max Items

    func testMaxItemsLimit_unpinnedOnly() {
        for i in 1...20 {
            store.add(ClipboardItem(content: "item \(i)"))
        }
        let unpinned = store.items.filter { !$0.isPinned }
        XCTAssertLessThanOrEqual(unpinned.count, store.maxItems)
    }

    func testMaxItemsLimit_pinnedNotCounted() {
        let pinned = ClipboardItem(content: "pinned")
        store.add(pinned)
        store.togglePin(id: pinned.id)

        for i in 1...store.maxItems {
            store.add(ClipboardItem(content: "item \(i)"))
        }

        let pinnedItems   = store.items.filter { $0.isPinned }
        let unpinnedItems = store.items.filter { !$0.isPinned }

        XCTAssertEqual(pinnedItems.count, 1)
        XCTAssertEqual(unpinnedItems.count, store.maxItems)
    }

    func testMaxItems_instanceProperty() {
        store.maxItems = 5
        XCTAssertEqual(store.maxItems, 5)
        // Verify it persists through a new store using the same defaults
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertEqual(store2.maxItems, 5)
    }

    func testTrimToLimit() {
        for i in 1...15 {
            store.add(ClipboardItem(content: "item \(i)"))
        }
        store.maxItems = 5
        store.trimToLimit()
        let unpinned = store.items.filter { !$0.isPinned }
        XCTAssertEqual(unpinned.count, 5)
    }

    // MARK: - Remove

    func testRemoveById() {
        let item = ClipboardItem(content: "to remove")
        store.add(item)
        store.remove(id: item.id)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRemoveById_nonExistentId_doesNotPushUndo() {
        store.add(ClipboardItem(content: "keep"))
        let fakeID = UUID()
        store.remove(id: fakeID)
        // Undo stack should be empty since nothing was actually removed
        XCTAssertFalse(store.canUndo)
    }

    func testRemoveAtIndex() {
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.remove(at: 0)
        XCTAssertEqual(store.items.count, 1)
    }

    func testRemoveAtInvalidIndex_doesNotCrash() {
        store.remove(at: 99)  // should be a no-op
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Undo

    func testUndo_restoresDeletedItem() {
        let item = ClipboardItem(content: "undoable")
        store.add(item)
        store.remove(id: item.id)
        XCTAssertTrue(store.items.isEmpty)

        let didUndo = store.undo()
        XCTAssertTrue(didUndo)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].content, "undoable")
    }

    func testUndo_emptyStack_returnsFalse() {
        XCTAssertFalse(store.undo())
    }

    func testUndo_afterClearUnpinned() {
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.clearUnpinned()
        XCTAssertTrue(store.items.isEmpty)

        let didUndo = store.undo()
        XCTAssertTrue(didUndo)
        XCTAssertEqual(store.items.count, 2)
    }

    // MARK: - Pin / Unpin

    func testTogglePin_pinnedItemFloatsToTop() {
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        let idA = store.items.first(where: { $0.content == "A" })!.id
        store.togglePin(id: idA)
        XCTAssertTrue(store.items[0].isPinned)
        XCTAssertEqual(store.items[0].content, "A")
    }

    func testTogglePin_unpin() {
        let item = ClipboardItem(content: "toggled")
        store.add(item)
        store.togglePin(id: item.id)
        XCTAssertTrue(store.items[0].isPinned)
        store.togglePin(id: item.id)
        XCTAssertFalse(store.items[0].isPinned)
    }

    /// Regression: unpinning must re-apply the history limit. Previously the
    /// unpinned set could grow past `maxItems` until the next `add()`.
    func testTogglePin_unpinRespectsMaxItems() {
        store.maxItems = 3
        let pinned = ClipboardItem(content: "P")
        store.add(pinned)
        store.togglePin(id: pinned.id)             // P is pinned, above the limit
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.add(ClipboardItem(content: "C"))     // 3 unpinned — at the limit
        XCTAssertEqual(store.items.filter { !$0.isPinned }.count, 3)

        store.togglePin(id: pinned.id)             // unpin P → would be 4 unpinned
        XCTAssertEqual(store.items.filter { !$0.isPinned }.count, 3,
                       "unpinning must not leave more than maxItems unpinned")
        XCTAssertEqual(store.items.filter { $0.isPinned }.count, 0)
        // The just-unpinned item is kept (floats to top); the oldest is evicted.
        XCTAssertTrue(store.items.contains { $0.content == "P" })
        XCTAssertFalse(store.items.contains { $0.content == "A" })
    }

    // MARK: - Clear Unpinned

    func testClearUnpinned_removeOnlyUnpinned() {
        let pinned = ClipboardItem(content: "keep me")
        store.add(pinned)
        store.togglePin(id: pinned.id)
        store.add(ClipboardItem(content: "remove me"))

        store.clearUnpinned()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].content, "keep me")
    }

    func testClearUnpinned_emptyStore() {
        store.clearUnpinned()   // should not crash on empty store
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Undo depth cap

    func testUndo_depthCappedAt10() {
        // Add and remove 12 items to push 12 undo snapshots
        for i in 1...12 {
            let item = ClipboardItem(content: "item \(i)")
            store.add(item)
            store.remove(id: item.id)
        }

        // Should be able to undo exactly 10 times (max depth)
        var undoCount = 0
        while store.undo() {
            undoCount += 1
        }
        XCTAssertEqual(undoCount, 10, "Undo stack should be capped at 10")
    }

    func testUndo_multipleUndosInSequence() {
        let a = ClipboardItem(content: "A")
        let b = ClipboardItem(content: "B")
        store.add(a)
        store.add(b)

        store.remove(id: b.id)  // undo snapshot 1
        store.remove(id: a.id)  // undo snapshot 2

        XCTAssertTrue(store.items.isEmpty)

        // First undo restores state before removing A
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].content, "A")

        // Second undo restores state before removing B
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items.count, 2)
    }

    // MARK: - Remove at index pushes undo

    func testRemoveAtIndex_pushesUndo() {
        store.add(ClipboardItem(content: "A"))
        store.remove(at: 0)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].content, "A")
    }

    func testRemoveAtInvalidIndex_doesNotPushUndo() {
        store.add(ClipboardItem(content: "keep"))
        store.remove(at: 99)
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - Toggle pin on nonexistent ID

    func testTogglePin_nonexistentID_noOp() {
        store.add(ClipboardItem(content: "A"))
        let fakeID = UUID()
        store.togglePin(id: fakeID)
        // Nothing should change
        XCTAssertFalse(store.items[0].isPinned)
    }

    // MARK: - Deduplication does not remove pinned

    func testDeduplication_doesNotRemovePinned() {
        let item = ClipboardItem(content: "pinnable")
        store.add(item)
        store.togglePin(id: item.id)
        // Adding same content again should not remove the pinned copy
        store.add(ClipboardItem(content: "pinnable"))
        let pinned = store.items.filter(\.isPinned)
        XCTAssertEqual(pinned.count, 1)
        XCTAssertEqual(pinned[0].content, "pinnable")
        // Should have the pinned one + the new unpinned one
        XCTAssertEqual(store.items.count, 2)
    }

    // MARK: - TrimToLimit when under limit

    func testTrimToLimit_underLimit_noChange() {
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.maxItems = 10
        store.trimToLimit()
        XCTAssertEqual(store.items.count, 2)
    }

    // MARK: - Max items default

    func testMaxItems_defaultIs15() {
        XCTAssertEqual(store.maxItems, 15)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        store.add(ClipboardItem(content: "persist me"))

        // A new store instance using the same defaults should load the saved data
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertEqual(store2.items.count, 1)
        XCTAssertEqual(store2.items[0].content, "persist me")
    }

    func testPersistencePreservesPinnedState() {
        let item = ClipboardItem(content: "pinned persist")
        store.add(item)
        store.togglePin(id: item.id)

        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertTrue(store2.items[0].isPinned)
    }

    // MARK: - Memory-only mode

    func testMemoryOnly_defaultIsFalse() {
        XCTAssertFalse(store.memoryOnly)
    }

    func testMemoryOnly_whenEnabled_doesNotPersist() {
        store.memoryOnly = true
        store.add(ClipboardItem(content: "ephemeral"))
        // Item is present in the current session…
        XCTAssertEqual(store.items.count, 1)
        // …but a fresh store (a "relaunch") starts empty.
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertTrue(store2.items.isEmpty)
    }

    func testMemoryOnly_enabling_clearsAlreadyPersistedHistory() {
        // The persistence key used by ClipboardStore.save().
        let historyKey = "cc.kclip.history"

        store.add(ClipboardItem(content: "on disk"))       // persisted (default mode)
        // Sanity: it really was written to disk (guards against a stale key literal).
        XCTAssertNotNil(testDefaults.data(forKey: historyKey))

        store.memoryOnly = true                            // should wipe the on-disk copy

        // The raw blob is gone from UserDefaults — asserted directly rather than
        // via a fresh store, whose load() would skip anyway while memory-only is on.
        XCTAssertNil(testDefaults.data(forKey: historyKey))
    }

    func testMemoryOnly_disabling_persistsCurrentItems() {
        store.memoryOnly = true
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.memoryOnly = false                           // resume persistence, write now

        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertEqual(store2.items.count, 2)
        XCTAssertEqual(Set(store2.items.map(\.content)), ["A", "B"])
    }

    func testMemoryOnly_settingPersistsAcrossStores() {
        store.memoryOnly = true
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertTrue(store2.memoryOnly)
    }

    // MARK: - Clear on quit

    func testClearOnQuit_defaultIsFalse() {
        XCTAssertFalse(store.clearOnQuit)
    }

    func testClearOnQuit_settingPersistsAcrossStores() {
        store.clearOnQuit = true
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertTrue(store2.clearOnQuit)
    }

    func testClearOnQuitIfNeeded_whenDisabled_keepsEverything() {
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.clearOnQuitIfNeeded()   // disabled → no-op
        XCTAssertEqual(store.items.count, 2)
    }

    func testClearOnQuitIfNeeded_whenEnabled_removesUnpinnedKeepsPinned() {
        let pinned = ClipboardItem(content: "keep me")
        store.add(pinned)
        store.togglePin(id: pinned.id)
        store.add(ClipboardItem(content: "drop me"))

        store.clearOnQuit = true
        store.clearOnQuitIfNeeded()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].content, "keep me")
        XCTAssertTrue(store.items[0].isPinned)
    }

    func testClearOnQuitIfNeeded_whenEnabled_persistsClearedState() {
        store.add(ClipboardItem(content: "drop me"))
        store.clearOnQuit = true
        store.clearOnQuitIfNeeded()

        // A relaunch sees the cleared history.
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertTrue(store2.items.isEmpty)
    }

    /// A crash / force-quit skips clearOnQuitIfNeeded(); unpinned history must
    /// still not survive, because it is never written while the option is on.
    func testClearOnQuit_enabled_unpinnedNeverPersisted_evenWithoutQuitHook() {
        store.clearOnQuit = true
        let pinned = ClipboardItem(content: "keep me")
        store.add(pinned)
        store.togglePin(id: pinned.id)
        store.add(ClipboardItem(content: "secret"))
        XCTAssertEqual(store.items.count, 2, "current session still has both")

        // Simulated crash: no clearOnQuitIfNeeded() call before "relaunch".
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertEqual(store2.items.map(\.content), ["keep me"])
    }

    func testClearOnQuit_enabling_scrubsUnpinnedAlreadyOnDisk() {
        store.add(ClipboardItem(content: "on disk"))
        store.clearOnQuit = true
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertTrue(store2.items.isEmpty)
    }

    func testClearOnQuit_disabling_persistsCurrentItems() {
        store.clearOnQuit = true
        store.add(ClipboardItem(content: "A"))
        store.clearOnQuit = false
        let store2 = ClipboardStore(defaults: testDefaults)
        XCTAssertEqual(store2.items.map(\.content), ["A"])
    }

    // MARK: - Undo keeps later changes

    func testUndo_keepsItemsAddedAfterDelete() {
        let a = ClipboardItem(content: "A")
        store.add(a)
        store.remove(id: a.id)
        store.add(ClipboardItem(content: "B"))   // copied after the delete

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items.map(\.content), ["B", "A"],
                       "undo must keep B, and the newer B must stay above the restored A")
    }

    /// Items copied after the delete must stay above the restored item, even
    /// when the restored item had neighbours (anchor-based placement).
    func testUndo_restoresBetweenNeighbours_belowNewerCopies() {
        let a = ClipboardItem(content: "A")
        let b = ClipboardItem(content: "B")
        let c = ClipboardItem(content: "C")
        store.add(a); store.add(b); store.add(c)   // [C, B, A]
        store.remove(id: b.id)                      // [C, A]
        store.add(ClipboardItem(content: "D"))     // [D, C, A]
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items.map(\.content), ["D", "C", "B", "A"])
    }

    /// With correct ordering, the next copy evicts the oldest item — not the
    /// item copied after the delete.
    func testUndo_thenAdd_evictsOldestNotNewest() {
        store.maxItems = 2
        let a = ClipboardItem(content: "A")
        store.add(a)
        store.remove(id: a.id)
        store.add(ClipboardItem(content: "B"))      // [B]
        XCTAssertTrue(store.undo())                  // [B, A]
        store.add(ClipboardItem(content: "C"))      // over the limit → drop the oldest (A)
        XCTAssertEqual(store.items.map(\.content), ["C", "B"])
    }

    /// If every restored item would be trimmed straight away, undo reports
    /// nothing restored and leaves history exactly as it was.
    func testUndo_restoredItemImmediatelyTrimmed_isNoOp() {
        store.maxItems = 2
        let a = ClipboardItem(content: "A")
        store.add(a)
        store.add(ClipboardItem(content: "B"))      // [B, A]
        store.remove(id: a.id)                       // [B]
        store.add(ClipboardItem(content: "C"))      // [C, B]
        XCTAssertFalse(store.undo(), "A is the oldest and would be trimmed at once")
        XCTAssertEqual(store.items.map(\.content), ["C", "B"])
    }

    func testUndo_reappliesMaxItems() {
        store.maxItems = 3
        store.add(ClipboardItem(content: "A"))
        store.add(ClipboardItem(content: "B"))
        store.add(ClipboardItem(content: "C"))
        store.clearUnpinned()
        store.add(ClipboardItem(content: "D"))
        store.add(ClipboardItem(content: "E"))

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items.map(\.content), ["E", "D", "C"],
                       "undo must not leave more than maxItems unpinned")

        let reloaded = ClipboardStore(defaults: testDefaults)
        XCTAssertEqual(reloaded.items.count, 3, "the trimmed state is what gets persisted")
    }

    /// An entry that restores nothing is skipped so ⌘Z still restores the
    /// previous deletion instead of silently doing nothing.
    func testUndo_skipsEntryThatRestoresNothing() {
        let foo = ClipboardItem(content: "foo")
        let bar = ClipboardItem(content: "bar")
        store.add(bar)
        store.add(foo)
        store.remove(id: bar.id)                     // entry 1: bar
        store.remove(id: foo.id)                     // entry 2: foo
        store.add(ClipboardItem(content: "foo"))    // foo copied again

        XCTAssertTrue(store.undo(), "skips the foo entry and restores bar")
        XCTAssertEqual(store.items.map(\.content), ["foo", "bar"])
        XCTAssertFalse(store.canUndo)
    }

    func testUndo_keepsPinChangesMadeAfterDelete() {
        let a = ClipboardItem(content: "A")
        let b = ClipboardItem(content: "B")
        store.add(a)
        store.add(b)
        store.remove(id: a.id)
        store.togglePin(id: b.id)

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items.map(\.content), ["B", "A"])
        XCTAssertTrue(store.items[0].isPinned, "pin made after the delete survives undo")
        XCTAssertFalse(store.items[1].isPinned)
    }

    func testUndo_restoresOriginalPosition() {
        let a = ClipboardItem(content: "A")
        let b = ClipboardItem(content: "B")
        let c = ClipboardItem(content: "C")
        store.add(a); store.add(b); store.add(c)   // [C, B, A]
        store.remove(id: b.id)                      // [C, A]
        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.items.map(\.content), ["C", "B", "A"])
    }

    func testUndo_doesNotDuplicateContentCopiedAgain() {
        let a = ClipboardItem(content: "A")
        store.add(a)
        store.remove(id: a.id)
        store.add(ClipboardItem(content: "A"))     // same text copied again

        XCTAssertFalse(store.undo(), "nothing new to restore")
        XCTAssertEqual(store.items.map(\.content), ["A"])
        XCTAssertFalse(store.canUndo, "the no-op entry is consumed")
    }

    func testUndo_clearUnpinned_keepsPinnedOnTop() {
        let p = ClipboardItem(content: "P")
        store.add(p)
        store.togglePin(id: p.id)
        store.add(ClipboardItem(content: "X"))
        store.add(ClipboardItem(content: "Y"))
        store.clearUnpinned()
        store.add(ClipboardItem(content: "Z"))

        XCTAssertTrue(store.undo())
        XCTAssertTrue(store.items[0].isPinned)
        XCTAssertEqual(store.items.map(\.content), ["P", "Z", "Y", "X"],
                       "pinned first, then newest-first with Z (copied after the clear) on top")
    }

    func testClearOnQuit_load_scrubsUnpinnedLeftOnDisk() {
        let historyKey = "cc.kclip.history"
        // Simulate an older build that crashed: unpinned item on disk while the
        // flag is on (written directly, since the current setter scrubs on enable).
        let leftover = try! JSONEncoder().encode([ClipboardItem(content: "secret")])
        testDefaults.set(leftover, forKey: historyKey)
        testDefaults.set(true, forKey: "cc.kclip.clearOnQuit")

        let relaunched = ClipboardStore(defaults: testDefaults)
        XCTAssertTrue(relaunched.items.isEmpty)
        let onDisk = try! JSONDecoder().decode([ClipboardItem].self,
                                               from: testDefaults.data(forKey: historyKey)!)
        XCTAssertTrue(onDisk.isEmpty, "load() must rewrite storage, not just filter in memory")
    }
}
