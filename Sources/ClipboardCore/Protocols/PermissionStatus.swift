import Foundation

public protocol AccessibilityPermissionProviding: Sendable {
    func isTrusted() -> Bool
}

public protocol LoginItemCapabilityProviding: Sendable {
    func canManageLoginItem() -> Bool
}

public protocol SparkleChannelProviding: Sendable {
    func hasValidUpdateChannel() -> Bool
}

public protocol SettingsActionOpening: Sendable {
    func open(action: SetupCheckAction)
}
