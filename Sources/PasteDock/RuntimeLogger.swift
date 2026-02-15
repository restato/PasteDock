import Foundation

actor RuntimeLogger {
    private let fileURL: URL
    private let dateFormatter: ISO8601DateFormatter

    init(fileURL: URL) {
        self.fileURL = fileURL
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    func log(_ message: String) {
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }

        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Intentionally ignore logging failures.
        }
    }
}
