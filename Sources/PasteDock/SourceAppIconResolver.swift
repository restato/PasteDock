import AppKit
import Foundation

@MainActor
final class SourceAppIconResolver {
    private enum CacheEntry {
        case missing
        case icon(NSImage)
    }

    private let appURLProvider: (String) -> URL?
    private let iconProvider: (String) -> NSImage
    private let iconSize: NSSize
    private var cache: [String: CacheEntry] = [:]

    init(
        appURLProvider: @escaping (String) -> URL? = { bundleId in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        },
        iconProvider: @escaping (String) -> NSImage = { appPath in
            NSWorkspace.shared.icon(forFile: appPath)
        },
        iconSize: NSSize = NSSize(width: 16, height: 16)
    ) {
        self.appURLProvider = appURLProvider
        self.iconProvider = iconProvider
        self.iconSize = iconSize
    }

    func resolve(bundleId: String?) -> NSImage? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        if let cached = cache[bundleId] {
            switch cached {
            case .missing:
                return nil
            case let .icon(icon):
                return icon
            }
        }

        guard let appURL = appURLProvider(bundleId) else {
            cache[bundleId] = .missing
            return nil
        }

        let fetchedIcon = iconProvider(appURL.path)
        let icon = (fetchedIcon.copy() as? NSImage) ?? fetchedIcon
        icon.size = iconSize
        cache[bundleId] = .icon(icon)
        return icon
    }
}
