import Foundation

public struct FileClipboardPayload: Codable, Equatable, Sendable {
    public let paths: [String]

    public init(paths: [String]) {
        self.paths = paths
    }
}
