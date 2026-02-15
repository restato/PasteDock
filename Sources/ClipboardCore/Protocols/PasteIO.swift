import Foundation

public enum ClipboardRestoreError: Error, Equatable, Sendable {
    case payloadReadFailed
    case invalidFilePayload
    case fileMissing(path: String)
    case pasteboardWriteFailed
}

public protocol ClipboardRestoring: Sendable {
    func restore(item: ClipboardItem) throws
}

public protocol AutoPastePerforming: Sendable {
    func canAutoPaste() -> Bool
    func performAutoPaste(targetApp: TargetAppSnapshot?) throws
}
