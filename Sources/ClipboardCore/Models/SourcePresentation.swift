import Foundation

public struct SourcePresentation: Equatable, Sendable {
    public let appName: String
    public let timeText: String
    public let isKnownSource: Bool

    public init(appName: String, timeText: String, isKnownSource: Bool) {
        self.appName = appName
        self.timeText = timeText
        self.isKnownSource = isKnownSource
    }
}
