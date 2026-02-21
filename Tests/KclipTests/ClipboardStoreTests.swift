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
}
