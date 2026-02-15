import Foundation

public enum CaptureSkipReason: Equatable, Sendable {
    case excludedApp
    case sensitiveContent
    case duplicate
}

public enum CaptureFailureReason: Equatable, Sendable {
    case invalidInput
    case storeWriteFailed(String)
    case retentionFailed(String)
}

public enum CaptureDecision: Equatable, Sendable {
    case saved(ClipboardItem)
    case skipped(CaptureSkipReason)
    case failed(CaptureFailureReason)
}

public struct CaptureInput: Equatable, Sendable {
    public let kind: ClipboardItemKind
    public let text: String?
    public let imageBytes: Data?
    public let filePaths: [String]?
    public let payloadPath: String
    public let sourceBundleId: String?
    public let capturedAtFrontmostBundleId: String?

    public init(
        kind: ClipboardItemKind,
        text: String? = nil,
        imageBytes: Data? = nil,
        filePaths: [String]? = nil,
        payloadPath: String,
        sourceBundleId: String?,
        capturedAtFrontmostBundleId: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.imageBytes = imageBytes
        self.filePaths = filePaths
        self.payloadPath = payloadPath
        self.sourceBundleId = sourceBundleId
        self.capturedAtFrontmostBundleId = capturedAtFrontmostBundleId
    }
}
