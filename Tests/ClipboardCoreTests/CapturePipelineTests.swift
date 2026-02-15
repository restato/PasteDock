import ClipboardCore
import Foundation
import Testing

@Test
func captureSkipsExcludedApp() async {
    let store = InMemoryHistoryStore()
    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: ["com.blocked"], hasSensitivePattern: false)
    )

    let input = CaptureInput(kind: .text, text: "hello", payloadPath: "text.txt", sourceBundleId: "com.blocked")
    let result = await pipeline.process(input, settings: Settings())

    #expect(result == .skipped(.excludedApp))
}

@Test
func captureSkipsSensitiveText() async {
    let store = InMemoryHistoryStore()
    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: true)
    )

    let input = CaptureInput(kind: .text, text: "password=abc", payloadPath: "text.txt", sourceBundleId: "com.safe")
    let result = await pipeline.process(input, settings: Settings())

    #expect(result == .skipped(.sensitiveContent))
}

@Test
func captureSkipsDuplicateConsecutiveItem() async {
    let store = InMemoryHistoryStore()
    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false)
    )

    let input = CaptureInput(kind: .text, text: "same text", payloadPath: "text.txt", sourceBundleId: "com.safe")
    let first = await pipeline.process(input, settings: Settings())
    let second = await pipeline.process(input, settings: Settings())

    if case .saved = first {
        #expect(Bool(true))
    } else {
        Issue.record("expected first capture to save")
    }

    #expect(second == .skipped(.duplicate))
}

@Test
func captureDoesNotEnqueueToastWhenDisabled() async {
    let store = InMemoryHistoryStore()
    let toastService = OperationToastService()
    let pipeline = CapturePipeline(
        store: store,
        privacyPolicy: StubPrivacyPolicy(excludedBundleIds: [], hasSensitivePattern: false),
        toastService: toastService
    )

    let input = CaptureInput(kind: .text, text: "hello", payloadPath: "text.txt", sourceBundleId: "com.safe")
    _ = await pipeline.process(input, settings: Settings(showOperationToasts: false))

    let toastCount = await toastService.pendingCount()
    #expect(toastCount == 0)
}
