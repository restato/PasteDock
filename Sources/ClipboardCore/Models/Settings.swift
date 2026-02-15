import Foundation

public enum QuickPickerStyle: String, Codable, Sendable {
    case compactOneLine
}

public struct Settings: Equatable, Codable, Sendable {
    public var maxItems: Int
    public var maxBytes: Int64
    public var quickPickerShortcut: String
    public var autoPasteEnabled: Bool
    public var launchAtLogin: Bool
    public var excludedBundleIds: Set<String>
    public var privacyFilterEnabled: Bool
    public var showOperationToasts: Bool
    public var quickPickerStyle: QuickPickerStyle
    public var permissionReminderEnabled: Bool
    public var monitoringIntervalMs: Int
    public var quickPickerResultLimit: Int

    public init(
        maxItems: Int = 500,
        maxBytes: Int64 = 2 * 1024 * 1024 * 1024,
        quickPickerShortcut: String = "Cmd+Shift+V",
        autoPasteEnabled: Bool = true,
        launchAtLogin: Bool = true,
        excludedBundleIds: Set<String> = [],
        privacyFilterEnabled: Bool = true,
        showOperationToasts: Bool = true,
        quickPickerStyle: QuickPickerStyle = .compactOneLine,
        permissionReminderEnabled: Bool = true,
        monitoringIntervalMs: Int = 250,
        quickPickerResultLimit: Int = 500
    ) {
        self.maxItems = maxItems
        self.maxBytes = maxBytes
        self.quickPickerShortcut = quickPickerShortcut
        self.autoPasteEnabled = autoPasteEnabled
        self.launchAtLogin = launchAtLogin
        self.excludedBundleIds = excludedBundleIds
        self.privacyFilterEnabled = privacyFilterEnabled
        self.showOperationToasts = showOperationToasts
        self.quickPickerStyle = quickPickerStyle
        self.permissionReminderEnabled = permissionReminderEnabled
        self.monitoringIntervalMs = monitoringIntervalMs
        self.quickPickerResultLimit = quickPickerResultLimit
    }
}
