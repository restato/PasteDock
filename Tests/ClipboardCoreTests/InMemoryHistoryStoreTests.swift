import ClipboardCore
import Foundation
import Testing

@Test
func inMemoryHistoryStoreSupportsCrudSearchAndPin() throws {
    let store = InMemoryHistoryStore()

    let older = makeItem(
        createdAt: Date(timeIntervalSince1970: 1_000),
        previewText: "alpha entry",
        contentHash: "hash-alpha",
        byteSize: 10
    )
    let newer = makeItem(
        createdAt: Date(timeIntervalSince1970: 2_000),
        previewText: "beta entry",
        contentHash: "hash-beta",
        byteSize: 20
    )

    #expect(try store.lastContentHash() == nil)

    try store.save(item: older)
    try store.save(item: newer)

    #expect(try store.item(id: older.id)?.id == older.id)
    #expect(try store.item(id: UUID()) == nil)
    #expect(try store.lastContentHash() == newer.contentHash)

    let emptyQuery = try store.search(query: "", limit: 10)
    #expect(emptyQuery.map(\.id) == [newer.id, older.id])

    let filtered = try store.search(query: "ALPHA", limit: 10)
    #expect(filtered.map(\.id) == [older.id])

    #expect(try store.search(query: "", limit: -1).isEmpty)

    try store.pin(id: older.id, value: true)
    #expect(try store.item(id: older.id)?.isPinned == true)

    try store.pin(id: UUID(), value: true)

    let sortedAllBeforeDelete = store.allItems()
    #expect(sortedAllBeforeDelete.map(\.id) == [newer.id, older.id])

    try store.delete(id: older.id)
    #expect(try store.item(id: older.id) == nil)

    let all = store.allItems()
    #expect(all.map(\.id) == [newer.id])

    try store.clearAll()
    #expect(try store.search(query: "", limit: 10).isEmpty)
}

@Test
func inMemoryHistoryStoreEnforceLimitsRemovesOldestUnpinnedAndStopsWhenOnlyPinnedRemain() throws {
    let store = InMemoryHistoryStore()

    let pinnedOldest = makeItem(
        createdAt: Date(timeIntervalSince1970: 1_000),
        previewText: "pinned",
        contentHash: "hash-pinned",
        byteSize: 10,
        isPinned: true
    )
    let unpinnedOld = makeItem(
        createdAt: Date(timeIntervalSince1970: 1_100),
        previewText: "old",
        contentHash: "hash-old",
        byteSize: 20
    )
    let unpinnedNew = makeItem(
        createdAt: Date(timeIntervalSince1970: 1_200),
        previewText: "new",
        contentHash: "hash-new",
        byteSize: 30
    )

    try store.save(item: pinnedOldest)
    try store.save(item: unpinnedOld)
    try store.save(item: unpinnedNew)

    let firstOutcome = try store.enforceLimits(maxItems: 2, maxBytes: 1_000)
    #expect(firstOutcome == RetentionOutcome(deletedCount: 1, deletedBytes: 20))
    #expect(try store.item(id: unpinnedOld.id) == nil)

    let secondOutcome = try store.enforceLimits(maxItems: 0, maxBytes: 0)
    #expect(secondOutcome == RetentionOutcome(deletedCount: 1, deletedBytes: 30))
    #expect(try store.item(id: unpinnedNew.id) == nil)

    let thirdOutcome = try store.enforceLimits(maxItems: 0, maxBytes: 0)
    #expect(thirdOutcome == RetentionOutcome(deletedCount: 0, deletedBytes: 0))
    #expect(try store.item(id: pinnedOldest.id) != nil)
}

private func makeItem(
    id: UUID = UUID(),
    createdAt: Date,
    previewText: String,
    contentHash: String,
    byteSize: Int64,
    isPinned: Bool = false
) -> ClipboardItem {
    ClipboardItem(
        id: id,
        createdAt: createdAt,
        kind: .text,
        previewText: previewText,
        contentHash: contentHash,
        byteSize: byteSize,
        isPinned: isPinned,
        sourceBundleId: "com.test",
        payloadPath: "payload-\(id.uuidString)"
    )
}
