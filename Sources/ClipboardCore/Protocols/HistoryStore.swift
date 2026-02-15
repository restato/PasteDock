import Foundation

public struct RetentionOutcome: Equatable, Sendable {
    public let deletedCount: Int
    public let deletedBytes: Int64

    public init(deletedCount: Int, deletedBytes: Int64) {
        self.deletedCount = deletedCount
        self.deletedBytes = deletedBytes
    }
}

public protocol HistoryStore: Sendable {
    func save(item: ClipboardItem) throws
    func item(id: UUID) throws -> ClipboardItem?
    func search(query: String, limit: Int) throws -> [ClipboardItem]
    func pin(id: UUID, value: Bool) throws
    func delete(id: UUID) throws
    func clearAll() throws
    func lastContentHash() throws -> String?
    func enforceLimits(maxItems: Int, maxBytes: Int64) throws -> RetentionOutcome
}
