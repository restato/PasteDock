import ClipboardCore
import Foundation
import Testing

@Test
func localLogServiceWritesJsonLineToActiveFile() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let service = LocalLogService(directoryURL: tempDir, maxFileBytes: 10_000, maxFiles: 2)
    await service.log(
        LogEntry(
            event: "capture",
            result: "saved",
            reason: "ok",
            bundleId: "com.test",
            itemKind: "text",
            itemSize: 10,
            durationMs: 1,
            timestamp: Date(timeIntervalSince1970: 1)
        )
    )

    let activeURL = tempDir.appendingPathComponent("clipboard.log")
    let content = try String(contentsOf: activeURL)

    #expect(content.contains("\"event\":\"capture\""))
    #expect(content.contains("\n"))
}

@Test
func localLogServiceHandlesDirectoryCreationFailureSilently() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("x".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let service = LocalLogService(directoryURL: fileURL)
    await service.log(LogEntry(event: "capture", result: "saved"))

    #expect(FileManager.default.fileExists(atPath: fileURL.path))
}

@Test
func localLogServiceRotationWithSingleFileKeepsNoBackups() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let service = LocalLogService(directoryURL: tempDir, maxFileBytes: 1, maxFiles: 1)

    await service.log(LogEntry(event: "capture", result: String(repeating: "a", count: 32)))
    await service.log(LogEntry(event: "capture", result: String(repeating: "b", count: 32)))

    let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
    #expect(files.contains("clipboard.log"))
    #expect(files.contains("clipboard.log.1") == false)
}

@Test
func localLogServiceRotationShiftsExistingBackups() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let service = LocalLogService(directoryURL: tempDir, maxFileBytes: 1, maxFiles: 3)

    let backup1 = tempDir.appendingPathComponent("clipboard.log.1")
    let backup2 = tempDir.appendingPathComponent("clipboard.log.2")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    try Data("backup1".utf8).write(to: backup1)
    try Data("backup2".utf8).write(to: backup2)

    await service.log(LogEntry(event: "capture", result: String(repeating: "x", count: 20)))
    await service.log(LogEntry(event: "capture", result: String(repeating: "y", count: 20)))

    let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
    #expect(files.contains("clipboard.log"))
    #expect(files.contains("clipboard.log.1"))
    #expect(files.contains("clipboard.log.2"))
}
