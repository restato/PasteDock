import ClipboardCore
import Foundation
import Testing

@Test
func localLogServiceRotatesWithinMaxFileCount() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let service = LocalLogService(
        directoryURL: tempDir,
        maxFileBytes: 200,
        maxFiles: 3
    )

    for index in 0..<40 {
        await service.log(
            LogEntry(
                event: "capture",
                result: "saved",
                reason: "entry_\(index)_\(String(repeating: "x", count: 30))",
                bundleId: "com.test",
                itemKind: "text",
                itemSize: 100,
                durationMs: 1,
                timestamp: Date()
            )
        )
    }

    let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
    let logFiles = files.filter { $0.hasPrefix("clipboard.log") }
    #expect(logFiles.count <= 3)
}
