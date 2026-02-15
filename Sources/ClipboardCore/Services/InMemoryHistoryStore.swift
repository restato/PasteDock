import Foundation

public final class InMemoryHistoryStore: HistoryStore, @unchecked Sendable {
    private var items: [ClipboardItem] = []
    private let lock = NSLock()

    public init() {}

    public func save(item: ClipboardItem) throws {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    public func item(id: UUID) throws -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return items.first(where: { $0.id == id })
    }

    public func search(query: String, limit: Int) throws -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }

        let sorted = items.sorted(by: { $0.createdAt > $1.createdAt })
        if query.isEmpty {
            return Array(sorted.prefix(max(0, limit)))
        }

        let lowered = query.lowercased()
        return Array(
            sorted
                .filter { $0.previewText.lowercased().contains(lowered) }
                .prefix(max(0, limit))
        )
    }

    public func pin(id: UUID, value: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned = value
    }

    public func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll(where: { $0.id == id })
    }

    public func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
    }

    public func lastContentHash() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return items.last?.contentHash
    }

    public func enforceLimits(maxItems: Int, maxBytes: Int64) throws -> RetentionOutcome {
        lock.lock()
        defer { lock.unlock() }

        var deletedCount = 0
        var deletedBytes: Int64 = 0

        func currentTotalBytes() -> Int64 {
            items.reduce(0) { $0 + $1.byteSize }
        }

        while items.count > maxItems || currentTotalBytes() > maxBytes {
            let sortedByAge = items.enumerated().sorted { $0.element.createdAt < $1.element.createdAt }
            guard let removable = sortedByAge.first(where: { !$0.element.isPinned }) else { break }
            let removed = items.remove(at: removable.offset)
            deletedCount += 1
            deletedBytes += removed.byteSize
        }

        return RetentionOutcome(deletedCount: deletedCount, deletedBytes: deletedBytes)
    }

    public func allItems() -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        return items.sorted(by: { $0.createdAt > $1.createdAt })
    }
}
