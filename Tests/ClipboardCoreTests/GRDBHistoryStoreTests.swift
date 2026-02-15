import ClipboardCore
import Foundation
import GRDB
import Testing

@Test
func grdbHistoryStoreSupportsCrudSearchPinDeleteAndClear() throws {
    let fixture = try GRDBFixture()
    defer { fixture.cleanup() }

    let firstPath = try fixture.makePayloadFile(name: "first.txt", contents: "one")
    let secondPath = try fixture.makePayloadFile(name: "second.txt", contents: "two")

    let first = ClipboardItem(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_000),
        kind: .text,
        previewText: "alpha text",
        contentHash: "hash-1",
        byteSize: 11,
        sourceBundleId: "com.a",
        payloadPath: firstPath
    )
    let second = ClipboardItem(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 2_000),
        kind: .text,
        previewText: "beta text",
        contentHash: "hash-2",
        byteSize: 22,
        sourceBundleId: "com.b",
        payloadPath: secondPath
    )

    try fixture.store.save(item: first)
    try fixture.store.save(item: second)

    #expect(try fixture.store.item(id: first.id)?.id == first.id)
    #expect(try fixture.store.item(id: UUID()) == nil)

    let all = try fixture.store.search(query: "", limit: 10)
    #expect(all.map(\.id) == [second.id, first.id])

    let filtered = try fixture.store.search(query: "BETA", limit: 10)
    #expect(filtered.map(\.id) == [second.id])

    #expect(try fixture.store.search(query: "", limit: -1).isEmpty)
    #expect(try fixture.store.search(query: "   ", limit: 1).count == 1)

    try fixture.store.pin(id: first.id, value: true)
    #expect(try fixture.store.item(id: first.id)?.isPinned == true)
    try fixture.store.pin(id: first.id, value: false)
    #expect(try fixture.store.item(id: first.id)?.isPinned == false)

    #expect(try fixture.store.lastContentHash() == second.contentHash)

    try fixture.store.delete(id: first.id)
    #expect(try fixture.store.item(id: first.id) == nil)
    #expect(FileManager.default.fileExists(atPath: firstPath) == false)

    try fixture.store.delete(id: UUID())

    try fixture.store.clearAll()
    #expect(try fixture.store.search(query: "", limit: 10).isEmpty)
    #expect(FileManager.default.fileExists(atPath: secondPath) == false)
}

@Test
func grdbHistoryStoreEnforceLimitsRemovesUnpinnedOldestAndStopsWhenOnlyPinnedRemain() throws {
    let fixture = try GRDBFixture()
    defer { fixture.cleanup() }

    let pinnedPath = try fixture.makePayloadFile(name: "pinned.txt", contents: "pinned")
    let oldPath = try fixture.makePayloadFile(name: "old.txt", contents: "old")
    let newPath = try fixture.makePayloadFile(name: "new.txt", contents: "new")

    let pinned = ClipboardItem(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_000),
        kind: .text,
        previewText: "pinned",
        contentHash: "hash-pinned",
        byteSize: 10,
        isPinned: true,
        sourceBundleId: "com.test",
        payloadPath: pinnedPath
    )
    let old = ClipboardItem(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_100),
        kind: .text,
        previewText: "old",
        contentHash: "hash-old",
        byteSize: 20,
        sourceBundleId: "com.test",
        payloadPath: oldPath
    )
    let newest = ClipboardItem(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_200),
        kind: .text,
        previewText: "new",
        contentHash: "hash-new",
        byteSize: 30,
        sourceBundleId: "com.test",
        payloadPath: newPath
    )

    try fixture.store.save(item: pinned)
    try fixture.store.save(item: old)
    try fixture.store.save(item: newest)

    let firstOutcome = try fixture.store.enforceLimits(maxItems: 2, maxBytes: 1_000)
    #expect(firstOutcome == RetentionOutcome(deletedCount: 1, deletedBytes: 20))
    #expect(try fixture.store.item(id: old.id) == nil)
    #expect(FileManager.default.fileExists(atPath: oldPath) == false)

    let secondOutcome = try fixture.store.enforceLimits(maxItems: 0, maxBytes: 0)
    #expect(secondOutcome == RetentionOutcome(deletedCount: 1, deletedBytes: 30))
    #expect(try fixture.store.item(id: newest.id) == nil)
    #expect(FileManager.default.fileExists(atPath: newPath) == false)

    let thirdOutcome = try fixture.store.enforceLimits(maxItems: 0, maxBytes: 0)
    #expect(thirdOutcome == RetentionOutcome(deletedCount: 0, deletedBytes: 0))
    #expect(try fixture.store.item(id: pinned.id) != nil)
}

@Test
func grdbHistoryStoreFallsBackForInvalidRowIdentifierAndKind() throws {
    let fixture = try GRDBFixture()
    defer { fixture.cleanup() }

    let payload = try fixture.makePayloadFile(name: "fallback.txt", contents: "fallback")
    let queue = try DatabaseQueue(path: fixture.databaseURL.path)
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO clipboard_items (
                id, created_at, kind, preview_text, content_hash, byte_size, is_pinned, source_bundle_id, payload_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                "not-a-uuid",
                1234.0,
                "unknown-kind",
                "fallback row",
                "fallback-hash",
                9,
                0,
                "com.test",
                payload
            ]
        )
    }

    let results = try fixture.store.search(query: "fallback", limit: 5)
    #expect(results.count == 1)
    #expect(results[0].kind == .text)
}

private struct GRDBFixture {
    let root: URL
    let databaseURL: URL
    let store: GRDBHistoryStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        databaseURL = root.appendingPathComponent("db/history.sqlite")
        store = try GRDBHistoryStore(databaseURL: databaseURL)
    }

    func makePayloadFile(name: String, contents: String) throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
