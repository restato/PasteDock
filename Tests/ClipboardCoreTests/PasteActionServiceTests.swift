import ClipboardCore
import Foundation
import Testing

@Test
func restoreAndPasteFallsBackWhenPermissionMissing() async throws {
    let store = InMemoryHistoryStore()
    let item = ClipboardItem(
        kind: .text,
        previewText: "hello",
        contentHash: "hash",
        byteSize: 5,
        sourceBundleId: "com.test",
        payloadPath: "text.txt"
    )
    try store.save(item: item)

    let restorer = StubRestorer()
    let autoPaster = StubAutoPaster()
    autoPaster.canPaste = false
    let tracker = PermissionReminderTracker()

    let service = PasteActionService(
        store: store,
        restorer: restorer,
        autoPaster: autoPaster,
        settings: Settings(autoPasteEnabled: true),
        reminderTracker: tracker
    )

    let result = await service.restoreAndPaste(id: item.id)
    #expect(result == .restoredOnly(.permissionNeeded))
}

@Test
func restoreAndPasteSucceedsWhenPermissionGranted() async throws {
    let store = InMemoryHistoryStore()
    let item = ClipboardItem(
        kind: .text,
        previewText: "hello",
        contentHash: "hash2",
        byteSize: 5,
        sourceBundleId: "com.test",
        payloadPath: "text.txt"
    )
    try store.save(item: item)

    let service = PasteActionService(
        store: store,
        restorer: StubRestorer(),
        autoPaster: StubAutoPaster(),
        settings: Settings(autoPasteEnabled: true),
        reminderTracker: PermissionReminderTracker()
    )

    let result = await service.restoreAndPaste(id: item.id)
    #expect(result == .pasted)
}

@Test
func permissionReminderBannerTurnsOnAfterThreeConsecutiveFailures() async throws {
    let store = InMemoryHistoryStore()
    let item = ClipboardItem(
        kind: .text,
        previewText: "hello",
        contentHash: "hash3",
        byteSize: 5,
        sourceBundleId: "com.test",
        payloadPath: "text.txt"
    )
    try store.save(item: item)

    let autoPaster = StubAutoPaster()
    autoPaster.canPaste = false
    let tracker = PermissionReminderTracker()

    let service = PasteActionService(
        store: store,
        restorer: StubRestorer(),
        autoPaster: autoPaster,
        settings: Settings(autoPasteEnabled: true),
        reminderTracker: tracker
    )

    _ = await service.restoreAndPaste(id: item.id)
    _ = await service.restoreAndPaste(id: item.id)
    _ = await service.restoreAndPaste(id: item.id)

    let reminder = await service.reminderState()
    #expect(reminder.shouldShowBanner)
    #expect(reminder.consecutiveCount == 3)
    #expect(reminder.reason == "permission_needed")
}

@Test
func permissionReminderStaysOffWhenSettingDisabled() async throws {
    let store = InMemoryHistoryStore()
    let item = ClipboardItem(
        kind: .text,
        previewText: "hello",
        contentHash: "hash4",
        byteSize: 5,
        sourceBundleId: "com.test",
        payloadPath: "text.txt"
    )
    try store.save(item: item)

    let autoPaster = StubAutoPaster()
    autoPaster.canPaste = false
    let tracker = PermissionReminderTracker()

    let service = PasteActionService(
        store: store,
        restorer: StubRestorer(),
        autoPaster: autoPaster,
        settings: Settings(autoPasteEnabled: true, permissionReminderEnabled: false),
        reminderTracker: tracker
    )

    _ = await service.restoreAndPaste(id: item.id)
    _ = await service.restoreAndPaste(id: item.id)
    _ = await service.restoreAndPaste(id: item.id)

    let reminder = await service.reminderState()
    #expect(reminder.shouldShowBanner == false)
    #expect(reminder.consecutiveCount == 0)
}
