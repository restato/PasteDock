import AppKit
import ApplicationServices
import ClipboardCore
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var lastOperationMessage: String?
    @Published var permissionReminder = PermissionReminderState()
    @Published var accessibilityGuidePresented = false
    @Published var accessibilityDiagnostics = AccessibilityDiagnostics()
    @Published var showAccessibilityHintBanner = false
    @Published var setupChecks: [SetupCheckItem] = []
    @Published var logFilePath: String = ""

    @Published private(set) var settings: Settings
    let appDisplayName: String

    private let store: any HistoryStore
    private let toastService: OperationToastService
    private let reminderTracker: PermissionReminderTracker
    private let frontmostTracker: FrontmostAppTracker
    private let shortcutService: GlobalShortcutService
    private let pasteService: PasteActionService
    private let capturePipeline: CapturePipeline
    private let runtimeLogger: RuntimeLogger
    private let sourceAppNameResolver: SourceAppNameResolver
    private let sourceAppIconResolver: SourceAppIconResolver
    private let sourceTimeFormatter: DateFormatter
    private let settingsStore: SettingsStore
    private let quickEntryStatusResolver = QuickEntryStatusResolver()

    private var monitorService: ClipboardMonitorService?
    private var quickPickerModel: QuickPickerPanelModel?
    private var barPopoverController: BarPopoverController?
    private var targetAppBeforePicker: TargetAppSnapshot?

    private var toastPollingTimer: Timer?
    private var setupCheckPollingTimer: Timer?
    private var toastClearTask: Task<Void, Never>?
    private var lastAccessibilityPromptAt: Date?
    private let accessibilityPromptCooldown: TimeInterval = 120
    private var confirmedMissingFileEntryIDs = Set<UUID>()

    init() {
        let settingsStore = SettingsStore()
        let loadedSettings = settingsStore.load()
        appDisplayName = AppCoordinator.resolveAppDisplayName()
        self.settingsStore = settingsStore
        settings = loadedSettings

        toastService = OperationToastService()
        reminderTracker = PermissionReminderTracker()
        frontmostTracker = FrontmostAppTracker()
        shortcutService = GlobalShortcutService()

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.justdoit.pastedock"
        let paths: AppSupportPaths
        do {
            paths = try AppSupportPaths.make(bundleIdentifier: bundleIdentifier)
        } catch {
            let fallbackRoot = FileManager.default.temporaryDirectory.appendingPathComponent("pastedock", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallbackRoot, withIntermediateDirectories: true)
            paths = AppSupportPaths(
                root: fallbackRoot,
                databaseURL: fallbackRoot.appendingPathComponent("history.sqlite"),
                textPayloadDir: fallbackRoot.appendingPathComponent("texts", isDirectory: true),
                imagePayloadDir: fallbackRoot.appendingPathComponent("images", isDirectory: true),
                filePayloadDir: fallbackRoot.appendingPathComponent("files", isDirectory: true)
            )
            try? FileManager.default.createDirectory(at: paths.textPayloadDir, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: paths.imagePayloadDir, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: paths.filePayloadDir, withIntermediateDirectories: true)
        }

        do {
            store = try GRDBHistoryStore(databaseURL: paths.databaseURL)
        } catch {
            store = InMemoryHistoryStore()
        }

        let runtimeLogURL = paths.root.appendingPathComponent("logs/runtime.log")
        runtimeLogger = RuntimeLogger(fileURL: runtimeLogURL)
        sourceAppNameResolver = SourceAppNameResolver()
        sourceAppIconResolver = SourceAppIconResolver()
        sourceTimeFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter
        }()

        let privacy = DefaultPrivacyPolicyService(excludedBundleIds: loadedSettings.excludedBundleIds)
        let logService = LocalLogService(directoryURL: paths.root.appendingPathComponent("logs", isDirectory: true))

        capturePipeline = CapturePipeline(
            store: store,
            privacyPolicy: privacy,
            logService: logService,
            toastService: toastService
        )

        let restorer = SystemClipboardRestorer()
        let autoPaster = SystemAutoPaster(appTracker: frontmostTracker)

        pasteService = PasteActionService(
            store: store,
            restorer: restorer,
            autoPaster: autoPaster,
            settings: loadedSettings,
            reminderTracker: reminderTracker,
            toastService: toastService
        )

        monitorService = ClipboardMonitorService(
            payloadWriter: ClipboardPayloadWriter(paths: paths),
            frontmostSnapshotProvider: { [weak self] in
                self?.frontmostTracker.snapshot()
            },
            onCapturedInput: { [weak self] input in
                guard let self else { return }
                let decision = await self.capturePipeline.process(input, settings: self.settings)
                await self.runtimeLogger.log("capture kind=\(input.kind.rawValue) result=\(self.describeCaptureDecision(decision)) source=\(input.capturedAtFrontmostBundleId ?? "-")")
            }
        )

        configureQuickPicker()
        refreshSetupChecks()
        startServices()
        logFilePath = runtimeLogURL.path
        let bundlePath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first ?? ""
        let isBundled = bundlePath.hasSuffix(".app")
        let signingMode = AppCoordinator.detectSigningMode(bundlePath: bundlePath)
        Task {
            await runtimeLogger.log(
                "app_started bundle=\(bundleIdentifier) bundle_path=\(bundlePath) executable_path=\(executablePath) is_bundled=\(isBundled) signing_mode=\(signingMode) db=\(paths.databaseURL.path)"
            )
        }
    }

    func bindStatusBarButton(_ button: NSStatusBarButton?) {
        barPopoverController?.bindStatusBarButton(button)
    }

    func openQuickPicker() {
        openBarPanel(tab: .quick, focusSearch: true)
    }

    func openBarPanel(tab: BarPanelTab, focusSearch: Bool) {
        if tab == .quick {
            if barPopoverController?.isPresented != true {
                targetAppBeforePicker = frontmostTracker.snapshot()
                quickPickerModel?.query = ""
            }
        }

        if tab == .quick {
            quickPickerModel?.refresh()
        }
        barPopoverController?.present(tab: tab, focusSearch: focusSearch)

        Task {
            await runtimeLogger.log(
                "bar_panel_opened tab=\(tab.rawValue) focus_search=\(focusSearch) presented=\(barPopoverController?.isPresented == true)"
            )
        }
    }

    func toggleBarPanelFromStatusItemClick() {
        openBarPanel(tab: .quick, focusSearch: false)
    }

    func performSetupAction(_ action: SetupCheckAction) {
        Task { await runtimeLogger.log("setup_action \(action)") }
        switch action {
        case .openAccessibilitySettings:
            if AXIsProcessTrusted() {
                lastOperationMessage = "Accessibility is already enabled."
                Task { await runtimeLogger.log("accessibility_already_enabled") }
            }
            if openSystemSettings([
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.SystemSettings"
            ]) {
                lastOperationMessage = "Opened Accessibility settings."
            }
        case .openAccessibilityGuide:
            startAccessibilityGuide()
        case .openLoginItemSettings:
            _ = openSystemSettings([
                "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
                "x-apple.systempreferences:com.apple.settings.UsersGroups.extension?LoginItems",
                "x-apple.systempreferences:com.apple.SystemSettings"
            ])
        case .openAppSettingsPermissions:
            _ = openSystemSettings([
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.SystemSettings"
            ])
        }
    }

    func startAccessibilityGuide() {
        refreshAccessibilityDiagnostics()
        accessibilityGuidePresented = true
    }

    func closeAccessibilityGuide() {
        accessibilityGuidePresented = false
    }

    func refreshAccessibilityDiagnostics() {
        accessibilityDiagnostics = makePermissionHealthService().accessibilityDiagnostics(
            bundleId: Bundle.main.bundleIdentifier,
            appPath: Bundle.main.bundleURL.path,
            isBundled: Bundle.main.bundleURL.path.hasSuffix(".app")
        )
        if accessibilityDiagnostics.isTrusted {
            showAccessibilityHintBanner = false
        }
        refreshSetupChecks()
    }

    func requestAccessibilityPrompt(force: Bool = false) {
        requestAccessibilityPromptIfNeeded(force: force)
    }

    func revealRunningAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func copyRunningAppPath() {
        let path = Bundle.main.bundleURL.path
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        lastOperationMessage = "Copied app path."
    }

    var quickPickerShortcutPreset: QuickPickerShortcutPreset {
        QuickPickerShortcutPreset.fromSettingsValue(settings.quickPickerShortcut)
    }

    func updateQuickPickerShortcut(_ preset: QuickPickerShortcutPreset) {
        let currentPreset = quickPickerShortcutPreset
        guard currentPreset != preset else { return }

        settings.quickPickerShortcut = preset.settingsValue

        do {
            try registerShortcut(preset)
            settingsStore.save(settings)
            lastOperationMessage = "Shortcut updated: \(preset.displayName)"
            Task { await runtimeLogger.log("hotkey_updated shortcut=\(preset.displayName)") }
        } catch {
            settings.quickPickerShortcut = currentPreset.settingsValue
            do {
                try registerShortcut(currentPreset)
            } catch {
                Task { await runtimeLogger.log("hotkey_restore_failed error=\(error.localizedDescription)") }
            }
            lastOperationMessage = "Failed to register \(preset.displayName)"
            Task {
                await runtimeLogger.log(
                    "hotkey_update_failed shortcut=\(preset.displayName) error=\(error.localizedDescription)"
                )
            }
        }
    }

    func updateMaxItems(_ value: Int) {
        let clamped = SettingsStore.clampMaxItems(value)
        guard settings.maxItems != clamped else { return }

        settings.maxItems = clamped
        settings.quickPickerResultLimit = clamped
        settingsStore.save(settings)

        do {
            let retentionOutcome = try store.enforceLimits(maxItems: settings.maxItems, maxBytes: settings.maxBytes)
            if retentionOutcome.deletedCount > 0 {
                quickPickerModel?.refresh()
                lastOperationMessage = "Saved item limit \(clamped). Removed \(retentionOutcome.deletedCount) old item(s)."
            } else {
                lastOperationMessage = "Saved item limit \(clamped)."
            }
            Task {
                await runtimeLogger.log(
                    "settings_updated max_items=\(clamped) deleted=\(retentionOutcome.deletedCount)"
                )
            }
        } catch {
            lastOperationMessage = "Saved item limit \(clamped). Cleanup failed."
            Task {
                await runtimeLogger.log(
                    "settings_update_failed max_items=\(clamped) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func startServices() {
        monitorService?.start(intervalMs: settings.monitoringIntervalMs)
        Task { await runtimeLogger.log("clipboard_monitor_started interval_ms=\(settings.monitoringIntervalMs)") }

        do {
            let preset = quickPickerShortcutPreset
            try registerShortcut(preset)
            settings.quickPickerShortcut = preset.settingsValue
            settingsStore.save(settings)
            Task { await runtimeLogger.log("hotkey_registered shortcut=\(preset.displayName)") }
        } catch {
            lastOperationMessage = "Failed to register \(quickPickerShortcutPreset.displayName)"
            Task { await runtimeLogger.log("hotkey_register_failed error=\(error.localizedDescription)") }
        }

        toastPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                if let toast = await self.toastService.dequeue() {
                    await MainActor.run {
                        self.showToast(toast)
                    }
                }
            }
        }

        setupCheckPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshSetupChecks()
            }
        }
    }

    private func registerShortcut(_ preset: QuickPickerShortcutPreset) throws {
        try shortcutService.register(preset) { [weak self] in
            Task { @MainActor in
                self?.openBarPanel(tab: .quick, focusSearch: true)
            }
        }
    }

    private func configureQuickPicker() {
        let model = QuickPickerPanelModel(
            entryProvider: { [weak self] query in
                guard let self else { return [] }
                let items = (try? self.store.search(query: query, limit: self.settings.quickPickerResultLimit)) ?? []
                return items.map(self.makeQuickPickerEntry)
            },
            onExecuteIndex: { [weak self] index in
                self?.handleSelectIndex(index)
            },
            onExecuteTop: { [weak self] in
                self?.handleSelectIndex(0)
            },
            onDeleteSelection: { [weak self] id in
                self?.deleteEntry(id)
            },
            onClose: { [weak self] in
                self?.barPopoverController?.dismiss()
            }
        )

        quickPickerModel = model
        barPopoverController = BarPopoverController(model: model, coordinator: self)
    }

    private func makeQuickPickerEntry(for item: ClipboardItem) -> QuickPickerEntry {
        let sourcePresentation = makeSourcePresentation(for: item)
        return QuickPickerEntry.from(item: item, sourcePresentation: sourcePresentation)
    }

    private func makeSourcePresentation(for item: ClipboardItem) -> SourcePresentation {
        let resolvedAppName = sourceAppNameResolver.resolve(bundleId: item.sourceBundleId)
        return SourcePresentation(
            appName: resolvedAppName ?? "Unknown app",
            timeText: sourceTimeFormatter.string(from: item.createdAt),
            isKnownSource: resolvedAppName != nil
        )
    }

    func resolveSourceAppIcon(bundleId: String?) -> NSImage? {
        sourceAppIconResolver.resolve(bundleId: bundleId)
    }

    private func handleSelectIndex(_ index: Int) {
        guard let quickPickerModel else { return }
        guard quickPickerModel.entries.indices.contains(index) else { return }

        let entry = quickPickerModel.entries[index]
        guard shouldProceedWithExecution(for: entry) else {
            return
        }

        let id = entry.id
        barPopoverController?.dismiss()

        Task {
            let result = await pasteService.restoreAndPaste(id: id, targetApp: targetAppBeforePicker)
            permissionReminder = await pasteService.reminderState()
            await runtimeLogger.log("paste_selected index=\(index) result=\(describePasteResult(result)) target=\(targetAppBeforePicker?.bundleId ?? "-")")
            switch result {
            case .pasted:
                showAccessibilityHintBanner = false
                lastOperationMessage = "Pasted."
            case .restoredOnly(.permissionNeeded):
                showAccessibilityHintBanner = true
                lastOperationMessage = "Auto paste blocked. Item restored to clipboard. Press Cmd+V, and enable Accessibility for \(appDisplayName)."
            case .restoredOnly:
                showAccessibilityHintBanner = false
                lastOperationMessage = "Item restored to clipboard. Press Cmd+V."
            case .failed:
                showAccessibilityHintBanner = false
                lastOperationMessage = "Restore failed."
            }
            targetAppBeforePicker = nil
        }
    }

    private func shouldProceedWithExecution(for entry: QuickPickerEntry) -> Bool {
        guard entry.kind == .file else {
            return true
        }
        guard !confirmedMissingFileEntryIDs.contains(entry.id) else {
            return true
        }
        guard quickEntryStatusResolver.resolve(for: entry).isMissing else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Missing file detected"
        alert.informativeText = "This clipboard item references a missing file. Continue anyway?"
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            confirmedMissingFileEntryIDs.insert(entry.id)
            Task { await runtimeLogger.log("missing_file_confirmed id=\(entry.id.uuidString)") }
            return true
        }

        Task { await runtimeLogger.log("missing_file_execution_cancelled id=\(entry.id.uuidString)") }
        return false
    }

    private func deleteEntry(_ id: UUID) {
        try? store.delete(id: id)
        quickPickerModel?.refresh()
        Task { await runtimeLogger.log("entry_deleted id=\(id.uuidString)") }
    }

    private func showToast(_ toast: OperationToast) {
        lastOperationMessage = toast.message
        Task { await runtimeLogger.log("toast \(toast.style.rawValue) \(toast.message)") }

        toastClearTask?.cancel()
        toastClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(500, toast.durationMs)) * 1_000_000)
            if self.lastOperationMessage == toast.message {
                self.lastOperationMessage = nil
            }
        }
    }

    private func refreshSetupChecks() {
        let healthService = makePermissionHealthService()
        setupChecks = healthService.setupChecks()
        accessibilityDiagnostics = healthService.accessibilityDiagnostics(
            bundleId: Bundle.main.bundleIdentifier,
            appPath: Bundle.main.bundleURL.path,
            isBundled: Bundle.main.bundleURL.path.hasSuffix(".app")
        )
        if accessibilityDiagnostics.isTrusted {
            showAccessibilityHintBanner = false
        }
    }

    private func requestAccessibilityPromptIfNeeded(force: Bool = false) {
        if AXIsProcessTrusted() {
            refreshSetupChecks()
            Task { await runtimeLogger.log("accessibility_prompt_skipped already_trusted=true") }
            lastOperationMessage = "Accessibility is already enabled."
            return
        }

        let now = Date()
        if
            !force,
            let last = lastAccessibilityPromptAt,
            now.timeIntervalSince(last) < accessibilityPromptCooldown
        {
            Task { await runtimeLogger.log("accessibility_prompt_skipped reason=cooldown") }
            lastOperationMessage = "Prompt cooldown active. Use Request Again in guide if needed."
            return
        }

        lastAccessibilityPromptAt = now
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        lastOperationMessage = "Enable Accessibility for \(appDisplayName), then return and re-check."
        Task { await runtimeLogger.log("accessibility_prompt_requested force=\(force)") }
        refreshSetupChecks()
    }

    @discardableResult
    private func openSystemSettings(_ rawURLs: [String]) -> Bool {
        for rawURL in rawURLs {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                Task { await runtimeLogger.log("open_system_settings success url=\(rawURL)") }
                return true
            }
        }
        lastOperationMessage = "Failed to open System Settings"
        Task { await runtimeLogger.log("open_system_settings failed") }
        return false
    }

    func openLogFile() {
        let url = URL(fileURLWithPath: logFilePath)
        NSWorkspace.shared.open(url)
    }

    func revealLogFileInFinder() {
        let url = URL(fileURLWithPath: logFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func makePermissionHealthService() -> PermissionHealthService {
        PermissionHealthService(
            accessibilityProvider: RealAccessibilityProvider(),
            loginItemProvider: RealLoginItemProvider(),
            sparkleProvider: RealSparkleProvider(),
            actionOpener: NoopSettingsActionOpener()
        )
    }

    private func describeCaptureDecision(_ decision: CaptureDecision) -> String {
        switch decision {
        case .saved:
            return "saved"
        case let .skipped(reason):
            return "skipped:\(reason)"
        case let .failed(reason):
            return "failed:\(reason)"
        }
    }

    private func describePasteResult(_ result: PasteResult) -> String {
        switch result {
        case .pasted:
            return "pasted"
        case let .restoredOnly(reason):
            return "restored_only:\(reason)"
        case let .failed(reason):
            return "failed:\(reason)"
        }
    }

    private static func resolveAppDisplayName() -> String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
            return displayName
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return "PasteDock"
    }

    private static func detectSigningMode(bundlePath: String) -> String {
        guard FileManager.default.fileExists(atPath: "/usr/bin/codesign") else {
            return "unknown"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", bundlePath]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "unknown"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return "unknown"
        }

        if output.contains("Signature=adhoc") {
            return "adhoc"
        }

        if let teamLine = output.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) {
            let team = teamLine.replacingOccurrences(of: "TeamIdentifier=", with: "")
            if team == "not set" || team.isEmpty {
                return "unsigned_or_unknown"
            }
            return "certificate:\(team)"
        }

        return "signed_or_unknown"
    }
}

private struct RealAccessibilityProvider: AccessibilityPermissionProviding {
    func isTrusted() -> Bool { AXIsProcessTrusted() }
}

private struct RealLoginItemProvider: LoginItemCapabilityProviding {
    func canManageLoginItem() -> Bool { true }
}

private struct RealSparkleProvider: SparkleChannelProviding {
    func hasValidUpdateChannel() -> Bool { true }
}

private struct NoopSettingsActionOpener: SettingsActionOpening {
    func open(action _: SetupCheckAction) {}
}
