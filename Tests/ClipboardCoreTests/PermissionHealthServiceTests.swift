import ClipboardCore
import Foundation
import Testing

@Test
func setupChecksReflectProviderStates() {
    let opener = StubActionOpener()
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: false),
        loginItemProvider: StubLoginItemProvider(supported: true),
        sparkleProvider: StubSparkleProvider(validChannel: false),
        actionOpener: opener
    )

    let checks = service.setupChecks()

    #expect(checks.count == 3)
    #expect(checks[0].status == .actionRequired)
    #expect(checks[0].action == .openAccessibilityGuide)
    #expect(checks[1].status == .ready)
    #expect(checks[2].status == .actionRequired)
}

@Test
func performActionDelegatesToActionOpener() {
    let opener = StubActionOpener()
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: false),
        loginItemProvider: StubLoginItemProvider(supported: false),
        sparkleProvider: StubSparkleProvider(validChannel: false),
        actionOpener: opener
    )

    let check = SetupCheckItem(title: "Accessibility", status: .actionRequired, action: .openAccessibilitySettings)
    service.performAction(for: check)

    #expect(opener.openedActions.count == 1)
}

@Test
func accessibilityDiagnosticsReflectTrustAndBundleShape() {
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: false),
        loginItemProvider: StubLoginItemProvider(supported: true),
        sparkleProvider: StubSparkleProvider(validChannel: true),
        actionOpener: StubActionOpener()
    )

    let diagnostics = service.accessibilityDiagnostics(
        bundleId: "com.justdoit.pastedock",
        appPath: "/Applications/PasteDock.app",
        isBundled: true,
        now: Date(timeIntervalSince1970: 1_000)
    )

    #expect(diagnostics.isTrusted == false)
    #expect(diagnostics.bundleId == "com.justdoit.pastedock")
    #expect(diagnostics.appPath == "/Applications/PasteDock.app")
    #expect(diagnostics.isBundled == true)
    #expect(diagnostics.lastCheckedAt == Date(timeIntervalSince1970: 1_000))
    #expect(diagnostics.guidanceReason != nil)
}

@Test
func accessibilityCheckKeepsGuideActionWhenReady() {
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: true),
        loginItemProvider: StubLoginItemProvider(supported: true),
        sparkleProvider: StubSparkleProvider(validChannel: true),
        actionOpener: StubActionOpener()
    )

    let checks = service.setupChecks()

    #expect(checks[0].status == .ready)
    #expect(checks[0].action == .openAccessibilityGuide)
}
