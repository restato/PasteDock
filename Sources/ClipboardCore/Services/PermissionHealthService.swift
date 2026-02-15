import Foundation

public struct PermissionHealthService: Sendable {
    private let accessibilityProvider: AccessibilityPermissionProviding
    private let loginItemProvider: LoginItemCapabilityProviding
    private let sparkleProvider: SparkleChannelProviding
    private let actionOpener: SettingsActionOpening

    public init(
        accessibilityProvider: AccessibilityPermissionProviding,
        loginItemProvider: LoginItemCapabilityProviding,
        sparkleProvider: SparkleChannelProviding,
        actionOpener: SettingsActionOpening
    ) {
        self.accessibilityProvider = accessibilityProvider
        self.loginItemProvider = loginItemProvider
        self.sparkleProvider = sparkleProvider
        self.actionOpener = actionOpener
    }

    public func setupChecks() -> [SetupCheckItem] {
        let accessibilityTrusted = accessibilityProvider.isTrusted()
        return [
            SetupCheckItem(
                title: "Accessibility",
                status: accessibilityTrusted ? .ready : .actionRequired,
                action: .openAccessibilityGuide
            ),
            SetupCheckItem(
                title: "Login Item",
                status: loginItemProvider.canManageLoginItem() ? .ready : .actionRequired,
                action: loginItemProvider.canManageLoginItem() ? nil : .openLoginItemSettings
            ),
            SetupCheckItem(
                title: "Sparkle Update Channel",
                status: sparkleProvider.hasValidUpdateChannel() ? .ready : .actionRequired,
                action: sparkleProvider.hasValidUpdateChannel() ? nil : .openAppSettingsPermissions
            )
        ]
    }

    public func accessibilityDiagnostics(
        bundleId: String?,
        appPath: String?,
        isBundled: Bool,
        now: Date = Date()
    ) -> AccessibilityDiagnostics {
        let trusted = accessibilityProvider.isTrusted()
        let normalizedBundleId: String
        if let bundleId, !bundleId.isEmpty {
            normalizedBundleId = bundleId
        } else {
            normalizedBundleId = "com.justdoit.pastedock"
        }

        let normalizedAppPath: String
        if let appPath, !appPath.isEmpty {
            normalizedAppPath = appPath
        } else {
            normalizedAppPath = "(unknown)"
        }
        let guidanceReason: String?

        if trusted {
            guidanceReason = nil
        } else if !isBundled {
            guidanceReason = "Run the app from a .app bundle, then re-check Accessibility."
        } else {
            guidanceReason = "Enable this app in System Settings > Privacy & Security > Accessibility."
        }

        return AccessibilityDiagnostics(
            isTrusted: trusted,
            bundleId: normalizedBundleId,
            appPath: normalizedAppPath,
            isBundled: isBundled,
            lastCheckedAt: now,
            guidanceReason: guidanceReason
        )
    }

    public func performAction(for item: SetupCheckItem) {
        guard let action = item.action else { return }
        actionOpener.open(action: action)
    }
}
