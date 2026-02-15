import AppKit
import SwiftUI

@main
struct PasteDockApp: App {
    @NSApplicationDelegateAdaptor(PasteDockAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class PasteDockAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "PasteDock"

        coordinator.bindStatusBarButton(button)
        updateStatusIcon()
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        _ = sender
        coordinator.toggleBarPanelFromStatusItemClick()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.image = StatusBarIconFactory.makeIcon()
        button.toolTip = "PasteDock (Capture On)"
    }
}
