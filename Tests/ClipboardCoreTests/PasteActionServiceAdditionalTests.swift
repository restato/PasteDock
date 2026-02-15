import ClipboardCore
import Foundation
import Testing

@Test
func restoreReturnsItemNotFoundWhenMissing() async {
    let service = PasteActionService(
        store: InMemoryHistoryStore(),
        restorer: StubRestorer(),
        autoPaster: StubAutoPaster(),
        settings: Settings(showOperationToasts: true),
        reminderTracker: PermissionReminderTracker(),
        toastService: OperationToastService()
    )

    let result = await service.restore(id: UUID())
    #expect(result == .failed(.itemNotFound))
}

@Test
func restoreReturnsRestoreFailedWhenRestorerThrows() async throws {
    let store = InMemoryHistoryStore()
    let item = makePasteItem(hash: "restore-throw")
    try store.save(item: item)

    let restorer = StubRestorer()
    restorer.shouldThrow = true

    let service = PasteActionService(
        store: store,
        restorer: restorer,
        autoPaster: StubAutoPaster(),
        settings: Settings(showOperationToasts: true),
        reminderTracker: PermissionReminderTracker(),
        toastService: OperationToastService()
    )

    let result = await service.restore(id: item.id)

    switch result {
    case let .failed(.restoreFailed(message)):
        #expect(message.isEmpty == false)
    default:
        Issue.record("expected restoreFailed")
    }
}

@Test
func restoreResetsReminderTrackerOnSuccess() async throws {
    let store = InMemoryHistoryStore()
    let item = makePasteItem(hash: "restore-success")
    try store.save(item: item)

    let tracker = PermissionReminderTracker()
    await tracker.recordFailure(reason: "permission_needed")

    let service = PasteActionService(
        store: store,
        restorer: StubRestorer(),
        autoPaster: StubAutoPaster(),
        settings: Settings(showOperationToasts: true),
        reminderTracker: tracker,
        toastService: OperationToastService()
    )

    let result = await service.restore(id: item.id)
    #expect(result == .restoredOnly(.autoPasteDisabled))

    let reminder = await tracker.currentState()
    #expect(reminder == PermissionReminderState())
}

@Test
func restoreAndPasteReturnsItemNotFoundWhenMissing() async {
    let service = PasteActionService(
        store: InMemoryHistoryStore(),
        restorer: StubRestorer(),
        autoPaster: StubAutoPaster(),
        settings: Settings(autoPasteEnabled: true),
        reminderTracker: PermissionReminderTracker(),
        toastService: OperationToastService()
    )

    let result = await service.restoreAndPaste(id: UUID())
    #expect(result == .failed(.itemNotFound))
}

@Test
func restoreAndPasteReturnsRestoredOnlyWhenAutoPasteDisabled() async throws {
    let store = InMemoryHistoryStore()
    let item = makePasteItem(hash: "auto-disabled")
    try store.save(item: item)

    let service = PasteActionService(
        store: store,
        restorer: StubRestorer(),
        autoPaster: StubAutoPaster(),
        settings: Settings(autoPasteEnabled: false),
        reminderTracker: PermissionReminderTracker(),
        toastService: OperationToastService()
    )

    let result = await service.restoreAndPaste(id: item.id)
    #expect(result == .restoredOnly(.autoPasteDisabled))
}

@Test
func restoreAndPasteReturnsPasteFailedAndTracksReminder() async throws {
    let store = InMemoryHistoryStore()
    let item = makePasteItem(hash: "paste-failed")
    try store.save(item: item)

    let autoPaster = StubAutoPaster()
    autoPaster.shouldThrow = true
    let tracker = PermissionReminderTracker()

    let service = PasteActionService(
        store: store,
        restorer: StubRestorer(),
        autoPaster: autoPaster,
        settings: Settings(autoPasteEnabled: true, permissionReminderEnabled: true),
        reminderTracker: tracker,
        toastService: OperationToastService()
    )

    let result = await service.restoreAndPaste(id: item.id)
    switch result {
    case let .restoredOnly(.pasteFailed(message)):
        #expect(message.isEmpty == false)
    default:
        Issue.record("expected pasteFailed")
    }

    let reminder = await service.reminderState()
    #expect(reminder.reason == "paste_failed")
    #expect(reminder.consecutiveCount == 1)
}

@Test
func restoreAndPasteReturnsRestoreFailedWhenStoreThrows() async {
    let service = PasteActionService(
        store: ThrowingHistoryStore(error: PasteServiceError.storeFailed),
        restorer: StubRestorer(),
        autoPaster: StubAutoPaster(),
        settings: Settings(autoPasteEnabled: true),
        reminderTracker: PermissionReminderTracker(),
        toastService: OperationToastService()
    )

    let result = await service.restoreAndPaste(id: UUID())
    switch result {
    case let .failed(.restoreFailed(message)):
        #expect(message.isEmpty == false)
    default:
        Issue.record("expected restoreFailed from store error")
    }
}

@Test
func restoreAndPasteReportsMissingFileReasonAndToast() async throws {
    let store = InMemoryHistoryStore()
    let item = makePasteItem(hash: "missing-file")
    try store.save(item: item)

    let restorer = StubRestorer()
    restorer.errorToThrow = ClipboardRestoreError.fileMissing(path: "/tmp/missing.txt")
    let toastService = OperationToastService()

    let service = PasteActionService(
        store: store,
        restorer: restorer,
        autoPaster: StubAutoPaster(),
        settings: Settings(autoPasteEnabled: true, showOperationToasts: true),
        reminderTracker: PermissionReminderTracker(),
        toastService: toastService
    )

    let result = await service.restoreAndPaste(id: item.id)
    #expect(result == .failed(.restoreFailed("file_missing")))
    #expect(await toastService.dequeue() == OperationToast(message: "Restore failed (file missing)", style: .error))
}

@Test
func restoreAndPasteForwardsTargetAppSnapshot() async throws {
    let store = InMemoryHistoryStore()
    let item = makePasteItem(hash: "target-app")
    try store.save(item: item)

    let autoPaster = CapturingAutoPaster()
    let service = PasteActionService(
        store: store,
        restorer: StubRestorer(),
        autoPaster: autoPaster,
        settings: Settings(autoPasteEnabled: true),
        reminderTracker: PermissionReminderTracker(),
        toastService: OperationToastService()
    )

    let target = TargetAppSnapshot(bundleId: "com.target.app", processIdentifier: 123)
    let result = await service.restoreAndPaste(id: item.id, targetApp: target)

    #expect(result == .pasted)
    #expect(autoPaster.lastTargetApp == target)
}

@Test
func restoreSkipsToastWhenOperationToastsAreDisabled() async {
    let toastService = OperationToastService()
    let service = PasteActionService(
        store: InMemoryHistoryStore(),
        restorer: StubRestorer(),
        autoPaster: StubAutoPaster(),
        settings: Settings(showOperationToasts: false),
        reminderTracker: PermissionReminderTracker(),
        toastService: toastService
    )

    _ = await service.restore(id: UUID())
    #expect(await toastService.pendingCount() == 0)
}

private enum PasteServiceError: Error {
    case storeFailed
}

private final class ThrowingHistoryStore: HistoryStore, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func save(item _: ClipboardItem) throws {}

    func item(id _: UUID) throws -> ClipboardItem? {
        throw error
    }

    func search(query _: String, limit _: Int) throws -> [ClipboardItem] { [] }

    func pin(id _: UUID, value _: Bool) throws {}

    func delete(id _: UUID) throws {}

    func clearAll() throws {}

    func lastContentHash() throws -> String? { nil }

    func enforceLimits(maxItems _: Int, maxBytes _: Int64) throws -> RetentionOutcome {
        RetentionOutcome(deletedCount: 0, deletedBytes: 0)
    }
}

private final class CapturingAutoPaster: AutoPastePerforming, @unchecked Sendable {
    var lastTargetApp: TargetAppSnapshot?

    func canAutoPaste() -> Bool {
        true
    }

    func performAutoPaste(targetApp: TargetAppSnapshot?) throws {
        lastTargetApp = targetApp
    }
}

private func makePasteItem(hash: String) -> ClipboardItem {
    ClipboardItem(
        kind: .text,
        previewText: "value-\(hash)",
        contentHash: hash,
        byteSize: 5,
        sourceBundleId: "com.test",
        payloadPath: "payload-\(hash).txt"
    )
}
