import Foundation

public actor PermissionReminderTracker {
    private var state = PermissionReminderState()

    public init() {}

    public func recordFailure(reason: String) {
        if state.reason == reason {
            let nextCount = state.consecutiveCount + 1
            state = PermissionReminderState(
                reason: reason,
                consecutiveCount: nextCount,
                shouldShowBanner: nextCount >= 3
            )
            return
        }

        state = PermissionReminderState(reason: reason, consecutiveCount: 1, shouldShowBanner: false)
    }

    public func reset() {
        state = PermissionReminderState()
    }

    public func currentState() -> PermissionReminderState {
        state
    }
}

public struct PasteActionService: Sendable {
    private let store: HistoryStore
    private let restorer: ClipboardRestoring
    private let autoPaster: AutoPastePerforming
    private let settings: Settings
    private let reminderTracker: PermissionReminderTracker
    private let toastService: OperationToastService?

    public init(
        store: HistoryStore,
        restorer: ClipboardRestoring,
        autoPaster: AutoPastePerforming,
        settings: Settings,
        reminderTracker: PermissionReminderTracker,
        toastService: OperationToastService? = nil
    ) {
        self.store = store
        self.restorer = restorer
        self.autoPaster = autoPaster
        self.settings = settings
        self.reminderTracker = reminderTracker
        self.toastService = toastService
    }

    public func restore(id: UUID) async -> PasteResult {
        do {
            guard let item = try store.item(id: id) else {
                await enqueueToast(OperationToast(message: "Restore failed", style: .error))
                return .failed(.itemNotFound)
            }
            try restorer.restore(item: item)
            await reminderTracker.reset()
            await enqueueToast(OperationToast(message: "Restored", style: .info))
            return .restoredOnly(.autoPasteDisabled)
        } catch {
            await enqueueToast(OperationToast(message: Self.restoreFailureToastMessage(for: error), style: .error))
            return .failed(.restoreFailed(Self.restoreFailureMessage(for: error)))
        }
    }

    public func restoreAndPaste(id: UUID) async -> PasteResult {
        await restoreAndPaste(id: id, targetApp: nil)
    }

    public func restoreAndPaste(id: UUID, targetApp: TargetAppSnapshot?) async -> PasteResult {
        do {
            guard let item = try store.item(id: id) else {
                await enqueueToast(OperationToast(message: "Restore failed", style: .error))
                return .failed(.itemNotFound)
            }

            try restorer.restore(item: item)

            guard settings.autoPasteEnabled else {
                await reminderTracker.reset()
                await enqueueToast(OperationToast(message: "Restored only", style: .info))
                return .restoredOnly(.autoPasteDisabled)
            }

            guard autoPaster.canAutoPaste() else {
                if settings.permissionReminderEnabled {
                    await reminderTracker.recordFailure(reason: "permission_needed")
                }
                await enqueueToast(OperationToast(message: "Restored only (permission needed)", style: .warning))
                return .restoredOnly(.permissionNeeded)
            }

            do {
                try autoPaster.performAutoPaste(targetApp: targetApp)
                await reminderTracker.reset()
                await enqueueToast(OperationToast(message: "Pasted", style: .success))
                return .pasted
            } catch {
                if settings.permissionReminderEnabled {
                    await reminderTracker.recordFailure(reason: "paste_failed")
                }
                await enqueueToast(OperationToast(message: "Restored only", style: .warning))
                return .restoredOnly(.pasteFailed(error.localizedDescription))
            }
        } catch {
            await enqueueToast(OperationToast(message: Self.restoreFailureToastMessage(for: error), style: .error))
            return .failed(.restoreFailed(Self.restoreFailureMessage(for: error)))
        }
    }

    public func reminderState() async -> PermissionReminderState {
        guard settings.permissionReminderEnabled else {
            return PermissionReminderState()
        }
        return await reminderTracker.currentState()
    }

    private func enqueueToast(_ toast: OperationToast) async {
        guard settings.showOperationToasts else { return }
        await toastService?.enqueue(toast)
    }

    private static func restoreFailureMessage(for error: Error) -> String {
        if case .fileMissing = error as? ClipboardRestoreError {
            return "file_missing"
        }
        return error.localizedDescription
    }

    private static func restoreFailureToastMessage(for error: Error) -> String {
        if case .fileMissing = error as? ClipboardRestoreError {
            return "Restore failed (file missing)"
        }
        return "Restore failed"
    }
}
