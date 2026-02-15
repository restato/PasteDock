import Foundation

public enum ToastStyle: String, Sendable {
    case success
    case info
    case warning
    case error
}

public struct OperationToast: Equatable, Sendable {
    public let message: String
    public let style: ToastStyle
    public let durationMs: Int

    public init(message: String, style: ToastStyle, durationMs: Int = 2500) {
        self.message = message
        self.style = style
        self.durationMs = durationMs
    }
}
