import Foundation

public enum RestoredOnlyReason: Equatable, Sendable {
    case autoPasteDisabled
    case permissionNeeded
    case pasteFailed(String)
}

public enum PasteFailureReason: Equatable, Sendable {
    case itemNotFound
    case restoreFailed(String)
}

public enum PasteResult: Equatable, Sendable {
    case pasted
    case restoredOnly(RestoredOnlyReason)
    case failed(PasteFailureReason)
}
