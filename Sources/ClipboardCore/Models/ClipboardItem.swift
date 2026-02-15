import Foundation

public enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
    case file
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let kind: ClipboardItemKind
    public let previewText: String
    public let contentHash: String
    public let byteSize: Int64
    public var isPinned: Bool
    public let sourceBundleId: String?
    public let payloadPath: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ClipboardItemKind,
        previewText: String,
        contentHash: String,
        byteSize: Int64,
        isPinned: Bool = false,
        sourceBundleId: String?,
        payloadPath: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.previewText = previewText
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.isPinned = isPinned
        self.sourceBundleId = sourceBundleId
        self.payloadPath = payloadPath
    }
}
