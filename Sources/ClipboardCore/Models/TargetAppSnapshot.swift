import Foundation

public struct TargetAppSnapshot: Equatable, Sendable {
    public let bundleId: String?
    public let processIdentifier: Int32

    public init(bundleId: String?, processIdentifier: Int32) {
        self.bundleId = bundleId
        self.processIdentifier = processIdentifier
    }
}
