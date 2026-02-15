import Foundation

public struct LogEntry: Codable, Equatable, Sendable {
    public let event: String
    public let result: String
    public let reason: String?
    public let bundleId: String?
    public let itemKind: String?
    public let itemSize: Int64?
    public let durationMs: Int?
    public let timestamp: Date

    public init(
        event: String,
        result: String,
        reason: String? = nil,
        bundleId: String? = nil,
        itemKind: String? = nil,
        itemSize: Int64? = nil,
        durationMs: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.event = event
        self.result = result
        self.reason = reason
        self.bundleId = bundleId
        self.itemKind = itemKind
        self.itemSize = itemSize
        self.durationMs = durationMs
        self.timestamp = timestamp
    }
}

public actor LocalLogService {
    private let directoryURL: URL
    private let baseFileName: String
    private let maxFileBytes: UInt64
    private let maxFiles: Int
    private let encoder: JSONEncoder

    public init(
        directoryURL: URL,
        baseFileName: String = "clipboard.log",
        maxFileBytes: UInt64 = 10 * 1024 * 1024,
        maxFiles: Int = 3
    ) {
        self.directoryURL = directoryURL
        self.baseFileName = baseFileName
        self.maxFileBytes = maxFileBytes
        self.maxFiles = max(1, maxFiles)
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func log(_ entry: LogEntry) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try rotateIfNeeded()

            let fileURL = activeFileURL()
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            let encoded = try encoder.encode(entry)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(encoded)
            handle.write(Data([0x0A]))
        } catch {
            // Keep logging failures silent to avoid recursive failures.
        }
    }

    private func activeFileURL() -> URL {
        directoryURL.appendingPathComponent(baseFileName)
    }

    private func rotateIfNeeded() throws {
        let fileURL = activeFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as! NSNumber).uint64Value

        guard size >= maxFileBytes else { return }

        let backupCount = maxFiles - 1
        guard backupCount > 0 else {
            try FileManager.default.removeItem(at: fileURL)
            return
        }

        let oldestBackup = directoryURL.appendingPathComponent("\(baseFileName).\(backupCount)")
        if FileManager.default.fileExists(atPath: oldestBackup.path) {
            try FileManager.default.removeItem(at: oldestBackup)
        }

        if backupCount > 1 {
            for index in stride(from: backupCount - 1, through: 1, by: -1) {
                let old = directoryURL.appendingPathComponent("\(baseFileName).\(index)")
                let next = directoryURL.appendingPathComponent("\(baseFileName).\(index + 1)")
                if FileManager.default.fileExists(atPath: old.path) {
                    try FileManager.default.moveItem(at: old, to: next)
                }
            }
        }

        let firstBackup = directoryURL.appendingPathComponent("\(baseFileName).1")
        try? FileManager.default.removeItem(at: firstBackup)
        try FileManager.default.moveItem(at: fileURL, to: firstBackup)
    }
}
