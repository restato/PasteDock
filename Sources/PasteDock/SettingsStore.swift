import ClipboardCore
import Foundation

struct SettingsStore {
    static let maxItemsRange = 10 ... 2000
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "settings.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> Settings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            return sanitized(Settings())
        }

        return sanitized(decoded)
    }

    func save(_ settings: Settings) {
        let normalized = sanitized(settings)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func clampMaxItems(_ value: Int) -> Int {
        min(maxItemsRange.upperBound, max(maxItemsRange.lowerBound, value))
    }

    private func sanitized(_ settings: Settings) -> Settings {
        var normalized = settings
        normalized.maxItems = Self.clampMaxItems(settings.maxItems)
        // Keep picker result size aligned with retained history size.
        normalized.quickPickerResultLimit = normalized.maxItems
        normalized.quickPickerShortcut = QuickPickerShortcutPreset
            .fromSettingsValue(settings.quickPickerShortcut)
            .settingsValue
        return normalized
    }
}
