import ClipboardCore
import Foundation
import Testing

@Test
func captureFailsForInvalidTextInputAndEmitsFailureToast() async {
    let store = PipelineStoreDouble()
    let toastService = OperationToastService()
    let (logService, logDir) = makeLogService()
    defer { try? FileManager.default.removeItem(at: logDir) }

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
        logService: logService,
        toastService: toastService,
        clock: FixedClock(now: Date(timeIntervalSince1970: 100))
    )

    let input = CaptureInput(kind: .text, text: nil, payloadPath: "invalid.txt", sourceBundleId: "com.test")
    let result = await pipeline.process(input, settings: Settings(showOperationToasts: true))

    #expect(result == .failed(.invalidInput))
    #expect(await toastService.dequeue() == OperationToast(message: "Capture failed", style: .error))
}

@Test
func captureFailsForMissingImageBytes() async {
    let store = PipelineStoreDouble()

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
        clock: FixedClock(now: Date(timeIntervalSince1970: 100))
    )

    let input = CaptureInput(kind: .image, imageBytes: nil, payloadPath: "missing-image.bin", sourceBundleId: "com.test")
    let result = await pipeline.process(input, settings: Settings(showOperationToasts: false))

    #expect(result == .failed(.invalidInput))
}

@Test
func captureProcessesImageInputAndFormatsPreview() async {
    let store = PipelineStoreDouble()

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
    )

    let input = CaptureInput(
        kind: .image,
        imageBytes: Data(repeating: 0xAB, count: 512),
        payloadPath: "image.bin",
        sourceBundleId: "com.images"
    )

    let result = await pipeline.process(input, settings: Settings(showOperationToasts: false))

    guard case let .saved(item) = result else {
        Issue.record("expected image capture to be saved")
        return
    }

    #expect(item.kind == .image)
    #expect(item.previewText == "[Image] 1 KB")
    #expect(item.byteSize == 512)
}

@Test
func captureProcessesSingleFileInputAndFormatsPreview() async {
    let store = PipelineStoreDouble()

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
    )

    let filePath = "/Users/test/Documents/report.pdf"
    let input = CaptureInput(
        kind: .file,
        filePaths: [filePath],
        payloadPath: "manifest.json",
        sourceBundleId: "com.finder"
    )

    let result = await pipeline.process(input, settings: Settings(showOperationToasts: false))

    guard case let .saved(item) = result else {
        Issue.record("expected file capture to be saved")
        return
    }

    let encodedManifest = try? JSONEncoder().encode(FileClipboardPayload(paths: [filePath]))
    let expectedSize = Int64(encodedManifest?.count ?? -1)
    #expect(item.kind == .file)
    #expect(item.previewText == "[File] report.pdf")
    #expect(item.byteSize == expectedSize)
}

@Test
func captureProcessesMultipleFilesInputAndFormatsPreview() async {
    let store = PipelineStoreDouble()

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
    )

    let input = CaptureInput(
        kind: .file,
        filePaths: [
            "/Users/test/Documents/plan.md",
            "/Users/test/Documents/screenshot.png",
            "/Users/test/Documents/todo.txt"
        ],
        payloadPath: "manifest-multi.json",
        sourceBundleId: "com.finder"
    )

    let result = await pipeline.process(input, settings: Settings(showOperationToasts: false))

    guard case let .saved(item) = result else {
        Issue.record("expected multiple file capture to be saved")
        return
    }

    #expect(item.previewText == "[Files 3] plan.md +2")
}

@Test
func captureSkipsDuplicateFilesByNormalizedPathHash() async {
    let store = InMemoryHistoryStore()

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
    )

    let first = CaptureInput(
        kind: .file,
        filePaths: ["/tmp/../tmp/a.txt", "/tmp/b.txt"],
        payloadPath: "files-a.json",
        sourceBundleId: "com.finder"
    )
    let second = CaptureInput(
        kind: .file,
        filePaths: ["/tmp/b.txt", "/tmp/a.txt"],
        payloadPath: "files-b.json",
        sourceBundleId: "com.finder"
    )

    let firstResult = await pipeline.process(first, settings: Settings(showOperationToasts: false))
    let secondResult = await pipeline.process(second, settings: Settings(showOperationToasts: false))

    if case .saved = firstResult {
        #expect(Bool(true))
    } else {
        Issue.record("expected first file capture to save")
    }
    #expect(secondResult == .skipped(.duplicate))
}

@Test
func captureFailsForMissingFilePaths() async {
    let store = PipelineStoreDouble()

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
    )

    let input = CaptureInput(kind: .file, filePaths: nil, payloadPath: "files.json", sourceBundleId: "com.finder")
    let result = await pipeline.process(input, settings: Settings(showOperationToasts: false))

    #expect(result == .failed(.invalidInput))
}

@Test
func captureAllowsSensitiveTextWhenPrivacyFilterDisabledAndTruncatesPreview() async {
    let store = PipelineStoreDouble()
    let longText = String(repeating: "a", count: 140)

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: true),
    )

    let input = CaptureInput(kind: .text, text: "\n\(longText)\n", payloadPath: "long.txt", sourceBundleId: "com.safe")
    let result = await pipeline.process(input, settings: Settings(privacyFilterEnabled: false, showOperationToasts: false))

    guard case let .saved(item) = result else {
        Issue.record("expected long text capture to be saved")
        return
    }

    #expect(item.previewText.hasSuffix("..."))
    #expect(item.previewText.count == 120)
}

@Test
func captureEmitsRetentionToastWhenHistoryIsTrimmed() async {
    let store = PipelineStoreDouble()
    store.enforceOutcome = RetentionOutcome(deletedCount: 2, deletedBytes: 12)
    let toastService = OperationToastService()
    let (logService, logDir) = makeLogService()
    defer { try? FileManager.default.removeItem(at: logDir) }

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
        logService: logService,
        toastService: toastService,
        clock: FixedClock(now: Date(timeIntervalSince1970: 100))
    )

    let input = CaptureInput(kind: .text, text: "trim candidate", payloadPath: "trim.txt", sourceBundleId: "com.test")
    let result = await pipeline.process(input, settings: Settings(showOperationToasts: true))

    guard case .saved = result else {
        Issue.record("expected capture to be saved")
        return
    }

    #expect(await toastService.dequeue() == OperationToast(message: "History trimmed", style: .info))
}

@Test
func captureConvertsStoreErrorsToStoreWriteFailed() async {
    let store = PipelineStoreDouble()
    store.saveError = PipelineError.boom
    let toastService = OperationToastService()
    let (logService, logDir) = makeLogService()
    defer { try? FileManager.default.removeItem(at: logDir) }

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
        logService: logService,
        toastService: toastService,
        clock: FixedClock(now: Date(timeIntervalSince1970: 100))
    )

    let input = CaptureInput(kind: .text, text: "value", payloadPath: "value.txt", sourceBundleId: "com.test")
    let result = await pipeline.process(input, settings: Settings(showOperationToasts: true))

    switch result {
    case let .failed(.storeWriteFailed(message)):
        #expect(message.isEmpty == false)
    default:
        Issue.record("expected storeWriteFailed")
    }

    #expect(await toastService.dequeue() == OperationToast(message: "Capture failed", style: .error))
}

@Test
func captureUsesFrontmostBundleIdWhenSaving() async {
    let store = PipelineStoreDouble()

    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
    )

    let input = CaptureInput(
        kind: .text,
        text: "frontmost source",
        payloadPath: "frontmost.txt",
        sourceBundleId: "com.source",
        capturedAtFrontmostBundleId: "com.frontmost"
    )

    let result = await pipeline.process(input, settings: Settings(showOperationToasts: false))

    guard case let .saved(item) = result else {
        Issue.record("expected capture to be saved")
        return
    }

    #expect(item.sourceBundleId == "com.frontmost")
}

private enum PipelineError: Error {
    case boom
}

private final class PipelineStoreDouble: HistoryStore, @unchecked Sendable {
    var savedItems: [ClipboardItem] = []
    var lastHash: String?
    var saveError: Error?
    var lastHashError: Error?
    var enforceOutcome = RetentionOutcome(deletedCount: 0, deletedBytes: 0)
    var enforceError: Error?

    func save(item: ClipboardItem) throws {
        if let saveError {
            throw saveError
        }
        savedItems.append(item)
    }

    func item(id: UUID) throws -> ClipboardItem? {
        savedItems.first { $0.id == id }
    }

    func search(query: String, limit: Int) throws -> [ClipboardItem] {
        Array(savedItems.prefix(max(0, limit)))
    }

    func pin(id: UUID, value: Bool) throws {
        if let index = savedItems.firstIndex(where: { $0.id == id }) {
            savedItems[index].isPinned = value
        }
    }

    func delete(id: UUID) throws {
        savedItems.removeAll { $0.id == id }
    }

    func clearAll() throws {
        savedItems.removeAll()
    }

    func lastContentHash() throws -> String? {
        if let lastHashError {
            throw lastHashError
        }
        return lastHash
    }

    func enforceLimits(maxItems _: Int, maxBytes _: Int64) throws -> RetentionOutcome {
        if let enforceError {
            throw enforceError
        }
        return enforceOutcome
    }
}

private func makeLogService() -> (LocalLogService, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let service = LocalLogService(directoryURL: directory, maxFileBytes: 4_096, maxFiles: 2)
    return (service, directory)
}
