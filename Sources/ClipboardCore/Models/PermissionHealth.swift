import Foundation

public enum SetupCheckStatus: String, Sendable {
    case ready = "Ready"
    case actionRequired = "Action Required"
}

public enum SetupCheckAction: Sendable, Equatable {
    case openAccessibilitySettings
    case openAccessibilityGuide
    case openLoginItemSettings
    case openAppSettingsPermissions
}

public struct SetupCheckItem: Equatable, Sendable {
    public let title: String
    public let status: SetupCheckStatus
    public let action: SetupCheckAction?

    public init(title: String, status: SetupCheckStatus, action: SetupCheckAction?) {
        self.title = title
        self.status = status
        self.action = action
    }
}

public enum AccessibilityGuideStep: String, CaseIterable, Sendable {
    case verifyAppIdentity
    case openSystemSettings
    case addAppIfMissing
    case enableToggle
    case recheckPermission
}

public struct AccessibilityDiagnostics: Equatable, Sendable {
    public let isTrusted: Bool
    public let bundleId: String
    public let appPath: String
    public let isBundled: Bool
    public let lastCheckedAt: Date
    public let guidanceReason: String?

    public init(
        isTrusted: Bool = false,
        bundleId: String = "",
        appPath: String = "",
        isBundled: Bool = false,
        lastCheckedAt: Date = Date(),
        guidanceReason: String? = nil
    ) {
        self.isTrusted = isTrusted
        self.bundleId = bundleId
        self.appPath = appPath
        self.isBundled = isBundled
        self.lastCheckedAt = lastCheckedAt
        self.guidanceReason = guidanceReason
    }
}

public struct PermissionReminderState: Equatable, Sendable {
    public let reason: String?
    public let consecutiveCount: Int
    public let shouldShowBanner: Bool

    public init(reason: String? = nil, consecutiveCount: Int = 0, shouldShowBanner: Bool = false) {
        self.reason = reason
        self.consecutiveCount = consecutiveCount
        self.shouldShowBanner = shouldShowBanner
    }
}
