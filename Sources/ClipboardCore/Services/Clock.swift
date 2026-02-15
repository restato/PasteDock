import Foundation

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }
}

public struct FixedClock: Clock {
    public var now: Date

    public init(now: Date) {
        self.now = now
    }
}
