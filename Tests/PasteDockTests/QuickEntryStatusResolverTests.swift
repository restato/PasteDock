@testable import PasteDock
import ClipboardCore
import Foundation
import Testing

@Test
func quickEntryStatusResolverMarksTextAsReadyWhenPayloadExists() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("quick-entry-status-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let payloadURL = tempDir.appendingPathComponent("text.txt")
    try Data("hello".utf8).write(to: payloadURL)

    let entry = QuickPickerEntry(
        id: UUID(),
        displayText: "hello",
        isPinned: false,
        kind: .text,
        payloadPath: payloadURL.path
    )

    let resolver = QuickEntryStatusResolver()
    #expect(resolver.resolve(for: entry) == .ready)
}

@Test
func quickEntryStatusResolverMarksImageAsMissingWithoutPayload() {
    let entry = QuickPickerEntry(
        id: UUID(),
        displayText: "[Image]",
        isPinned: false,
        kind: .image,
        payloadPath: nil
    )

    let resolver = QuickEntryStatusResolver()
    #expect(resolver.resolve(for: entry) == .missing)
}

@Test
func quickEntryStatusResolverMarksFileAsMissingWhenAnyReferencedPathIsMissing() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("quick-entry-status-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let existingFileURL = tempDir.appendingPathComponent("exists.txt")
    try Data("ok".utf8).write(to: existingFileURL)
    let missingFileURL = tempDir.appendingPathComponent("missing.txt")

    let payloadURL = tempDir.appendingPathComponent("files.json")
    let payload = FileClipboardPayload(paths: [existingFileURL.path, missingFileURL.path])
    let payloadData = try JSONEncoder().encode(payload)
    try payloadData.write(to: payloadURL)

    let entry = QuickPickerEntry(
        id: UUID(),
        displayText: "[File] mixed",
        isPinned: false,
        kind: .file,
        payloadPath: payloadURL.path
    )

    let resolver = QuickEntryStatusResolver()
    #expect(resolver.resolve(for: entry) == .missing)
}

@Test
func quickEntryStatusResolverMarksFileAsReadyWhenAllReferencedPathsExist() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("quick-entry-status-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileAURL = tempDir.appendingPathComponent("a.txt")
    let fileBURL = tempDir.appendingPathComponent("b.txt")
    try Data("a".utf8).write(to: fileAURL)
    try Data("b".utf8).write(to: fileBURL)

    let payloadURL = tempDir.appendingPathComponent("files.json")
    let payload = FileClipboardPayload(paths: [fileAURL.path, fileBURL.path])
    let payloadData = try JSONEncoder().encode(payload)
    try payloadData.write(to: payloadURL)

    let entry = QuickPickerEntry(
        id: UUID(),
        displayText: "[Files 2] a +1",
        isPinned: false,
        kind: .file,
        payloadPath: payloadURL.path
    )

    let resolver = QuickEntryStatusResolver()
    #expect(resolver.resolve(for: entry) == .ready)
}
