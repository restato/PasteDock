import ClipboardCore
import Foundation
import Testing

@Test
func setupCheckViewModelReflectsActionRequirement() {
    let required = SetupCheckViewModel(
        checks: [
            SetupCheckItem(title: "Accessibility", status: .actionRequired, action: .openAccessibilityGuide)
        ]
    )
    #expect(required.title == "Setup Check")
    #expect(required.hasActionRequired)

    let ready = SetupCheckViewModel(
        checks: [
            SetupCheckItem(title: "Login Item", status: .ready, action: nil)
        ]
    )
    #expect(ready.hasActionRequired == false)
}

@Test
func fixedClockReturnsConfiguredDate() {
    let now = Date(timeIntervalSince1970: 1234)
    let clock = FixedClock(now: now)

    #expect(clock.now == now)
}

@Test
func systemClockReturnsCurrentTime() {
    let before = Date()
    let now = SystemClock().now
    let after = Date()

    #expect(now >= before)
    #expect(now <= after)
}

@Test
func targetAppSnapshotStoresValues() {
    let snapshot = TargetAppSnapshot(bundleId: "com.test.app", processIdentifier: 42)

    #expect(snapshot.bundleId == "com.test.app")
    #expect(snapshot.processIdentifier == 42)
}
