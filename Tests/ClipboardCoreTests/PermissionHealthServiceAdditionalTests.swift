import ClipboardCore
import Foundation
import Testing

@Test
func setupChecksAssignActionsForUnreadyProviders() {
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: false),
        loginItemProvider: StubLoginItemProvider(supported: false),
        sparkleProvider: StubSparkleProvider(validChannel: true),
        actionOpener: StubActionOpener()
    )

    let checks = service.setupChecks()

    #expect(checks[1].status == .actionRequired)
    #expect(checks[1].action == .openLoginItemSettings)
    #expect(checks[2].status == .ready)
    #expect(checks[2].action == nil)
}

@Test
func accessibilityDiagnosticsFallsBackForMissingIdentityAndUnbundledApp() {
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: false),
        loginItemProvider: StubLoginItemProvider(supported: true),
        sparkleProvider: StubSparkleProvider(validChannel: true),
        actionOpener: StubActionOpener()
    )

    let diagnostics = service.accessibilityDiagnostics(
        bundleId: nil,
        appPath: "",
        isBundled: false,
        now: Date(timeIntervalSince1970: 42)
    )

    #expect(diagnostics.bundleId == "com.justdoit.pastedock")
    #expect(diagnostics.appPath == "(unknown)")
    #expect(diagnostics.guidanceReason == "Run the app from a .app bundle, then re-check Accessibility.")
}

@Test
func accessibilityDiagnosticsOmitsGuidanceWhenTrusted() {
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: true),
        loginItemProvider: StubLoginItemProvider(supported: true),
        sparkleProvider: StubSparkleProvider(validChannel: true),
        actionOpener: StubActionOpener()
    )

    let diagnostics = service.accessibilityDiagnostics(bundleId: nil, appPath: nil, isBundled: true)
    #expect(diagnostics.guidanceReason == nil)
}

@Test
func performActionDoesNothingWhenActionIsMissing() {
    let opener = StubActionOpener()
    let service = PermissionHealthService(
        accessibilityProvider: StubAccessibilityProvider(trusted: true),
        loginItemProvider: StubLoginItemProvider(supported: true),
        sparkleProvider: StubSparkleProvider(validChannel: true),
        actionOpener: opener
    )

    service.performAction(for: SetupCheckItem(title: "ready", status: .ready, action: nil))
    #expect(opener.openedActions.isEmpty)
}
