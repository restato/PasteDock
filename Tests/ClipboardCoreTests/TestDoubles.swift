import ClipboardCore
import Foundation

final class TestClock: Clock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

struct StubPrivacyPolicy: PrivacyPolicyChecking {
    let excludedBundleIds: Set<String>
    let hasSensitivePattern: Bool

    func isExcluded(bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return excludedBundleIds.contains(bundleId)
    }

    func containsSensitiveContent(_ text: String) -> Bool {
        hasSensitivePattern
    }
}

final class StubRestorer: ClipboardRestoring, @unchecked Sendable {
    var shouldThrow = false
    var errorToThrow: Error?

    func restore(item: ClipboardItem) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        if shouldThrow {
            throw NSError(domain: "StubRestorer", code: 1)
        }
    }
}

final class StubAutoPaster: AutoPastePerforming, @unchecked Sendable {
    var canPaste = true
    var shouldThrow = false

    func canAutoPaste() -> Bool {
        canPaste
    }

    func performAutoPaste(targetApp _: TargetAppSnapshot?) throws {
        if shouldThrow {
            throw NSError(domain: "StubAutoPaster", code: 2)
        }
    }
}

struct StubAccessibilityProvider: AccessibilityPermissionProviding {
    let trusted: Bool

    func isTrusted() -> Bool {
        trusted
    }
}

struct StubLoginItemProvider: LoginItemCapabilityProviding {
    let supported: Bool

    func canManageLoginItem() -> Bool {
        supported
    }
}

struct StubSparkleProvider: SparkleChannelProviding {
    let validChannel: Bool

    func hasValidUpdateChannel() -> Bool {
        validChannel
    }
}

final class StubActionOpener: SettingsActionOpening, @unchecked Sendable {
    private(set) var openedActions: [SetupCheckAction] = []

    func open(action: SetupCheckAction) {
        openedActions.append(action)
    }
}
