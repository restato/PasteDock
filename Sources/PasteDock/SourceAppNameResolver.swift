import AppKit
import Foundation

@MainActor
final class SourceAppNameResolver {
    private var cache: [String: String?] = [:]

    func resolve(bundleId: String?) -> String? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        if let cached = cache[bundleId] {
            return cached
        }

        if
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
            let localizedName = running.localizedName,
            !localizedName.isEmpty
        {
            cache[bundleId] = localizedName
            return localizedName
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            cache[bundleId] = nil
            return nil
        }

        let bundle = Bundle(url: appURL)
        let localizedName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent

        let trimmed = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? nil : trimmed
        cache[bundleId] = resolved
        return resolved
    }
}
