import Foundation
@preconcurrency import GRDB

public final class GRDBHistoryStore: HistoryStore, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.makeMigrator().migrate(dbQueue)
    }

    public func save(item: ClipboardItem) throws {
        try dbQueue.write { db in
            var record = ClipboardItemRecord(item: item)
            try record.insert(db)
        }
    }

    public func item(id: UUID) throws -> ClipboardItem? {
        try dbQueue.read { db in
            let record = try ClipboardItemRecord.fetchOne(db, key: id.uuidString.lowercased())
            return record?.toItem()
        }
    }

    public func search(query: String, limit: Int) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            let safeLimit = max(0, limit)
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let records = try ClipboardItemRecord
                    .order(Column("created_at").desc)
                    .limit(safeLimit)
                    .fetchAll(db)
                return records.map { $0.toItem() }
            }

            let like = "%\(query.lowercased())%"
            let records = try ClipboardItemRecord
                .filter(sql: "lower(preview_text) LIKE ?", arguments: [like])
                .order(Column("created_at").desc)
                .limit(safeLimit)
                .fetchAll(db)
            return records.map { $0.toItem() }
        }
    }

    public func pin(id: UUID, value: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?",
                arguments: [value ? 1 : 0, id.uuidString.lowercased()]
            )
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            if let path: String = try String.fetchOne(
                db,
                sql: "SELECT payload_path FROM clipboard_items WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            ) {
                try? FileManager.default.removeItem(atPath: path)
            }
            try db.execute(
                sql: "DELETE FROM clipboard_items WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            )
        }
    }

    public func clearAll() throws {
        try dbQueue.write { db in
            let paths = try String.fetchAll(db, sql: "SELECT payload_path FROM clipboard_items")
            for path in paths {
                try? FileManager.default.removeItem(atPath: path)
            }
            try db.execute(sql: "DELETE FROM clipboard_items")
        }
    }

    public func lastContentHash() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT content_hash FROM clipboard_items ORDER BY created_at DESC LIMIT 1")
        }
    }

    public func enforceLimits(maxItems: Int, maxBytes: Int64) throws -> RetentionOutcome {
        try dbQueue.write { db in
            var deletedCount = 0
            var deletedBytes: Int64 = 0

            func stats() throws -> (count: Int, bytes: Int64) {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_items")!
                let bytes = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(byte_size), 0) FROM clipboard_items")!
                return (count, bytes)
            }

            while true {
                let current = try stats()
                if current.count <= maxItems, current.bytes <= maxBytes {
                    break
                }

                guard
                    let row = try Row.fetchOne(
                        db,
                        sql: "SELECT id, byte_size, payload_path FROM clipboard_items WHERE is_pinned = 0 ORDER BY created_at ASC LIMIT 1"
                    )
                else {
                    break
                }

                let id: String = row["id"]
                let byteSize: Int64 = row["byte_size"]
                let payloadPath: String = row["payload_path"]
                try db.execute(sql: "DELETE FROM clipboard_items WHERE id = ?", arguments: [id])
                try? FileManager.default.removeItem(atPath: payloadPath)
                deletedCount += 1
                deletedBytes += byteSize
            }

            return RetentionOutcome(deletedCount: deletedCount, deletedBytes: deletedBytes)
        }
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create_clipboard_items") { db in
            try db.create(table: "clipboard_items") { t in
                t.column("id", .text).primaryKey()
                t.column("created_at", .double).notNull()
                t.column("kind", .text).notNull()
                t.column("preview_text", .text).notNull()
                t.column("content_hash", .text).notNull()
                t.column("byte_size", .integer).notNull()
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("source_bundle_id", .text)
                t.column("payload_path", .text).notNull()
            }

            try db.create(index: "idx_clipboard_created_at", on: "clipboard_items", columns: ["created_at"])
            try db.create(index: "idx_clipboard_content_hash", on: "clipboard_items", columns: ["content_hash"])
        }
        return migrator
    }
}

private struct ClipboardItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clipboard_items"

    var id: String
    var createdAt: Double
    var kind: String
    var previewText: String
    var contentHash: String
    var byteSize: Int64
    var isPinned: Bool
    var sourceBundleId: String?
    var payloadPath: String

    enum Columns: String, ColumnExpression {
        case id
        case createdAt = "created_at"
        case kind
        case previewText = "preview_text"
        case contentHash = "content_hash"
        case byteSize = "byte_size"
        case isPinned = "is_pinned"
        case sourceBundleId = "source_bundle_id"
        case payloadPath = "payload_path"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case kind
        case previewText = "preview_text"
        case contentHash = "content_hash"
        case byteSize = "byte_size"
        case isPinned = "is_pinned"
        case sourceBundleId = "source_bundle_id"
        case payloadPath = "payload_path"
    }

    init(item: ClipboardItem) {
        id = item.id.uuidString.lowercased()
        createdAt = item.createdAt.timeIntervalSince1970
        kind = item.kind.rawValue
        previewText = item.previewText
        contentHash = item.contentHash
        byteSize = item.byteSize
        isPinned = item.isPinned
        sourceBundleId = item.sourceBundleId
        payloadPath = item.payloadPath
    }

    func toItem() -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: id) ?? UUID(),
            createdAt: Date(timeIntervalSince1970: createdAt),
            kind: ClipboardItemKind(rawValue: kind) ?? .text,
            previewText: previewText,
            contentHash: contentHash,
            byteSize: byteSize,
            isPinned: isPinned,
            sourceBundleId: sourceBundleId,
            payloadPath: payloadPath
        )
    }
}
