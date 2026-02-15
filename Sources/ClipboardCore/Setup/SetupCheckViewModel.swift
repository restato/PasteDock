import Foundation

public struct SetupCheckViewModel: Sendable {
    public let title: String
    public let checks: [SetupCheckItem]

    public init(checks: [SetupCheckItem]) {
        self.title = "Setup Check"
        self.checks = checks
    }

    public var hasActionRequired: Bool {
        checks.contains(where: { $0.status == .actionRequired })
    }
}
