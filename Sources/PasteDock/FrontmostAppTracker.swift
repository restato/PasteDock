import AppKit
import ClipboardCore
import Foundation

struct FrontmostAppTracker {
    func snapshot() -> TargetAppSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return TargetAppSnapshot(bundleId: app.bundleIdentifier, processIdentifier: app.processIdentifier)
    }

    func activate(_ target: TargetAppSnapshot?) {
        guard let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard let app = NSRunningApplication(processIdentifier: target.processIdentifier) else { return }
        app.activate(options: [])
    }
}
