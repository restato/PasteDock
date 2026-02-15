@testable import PasteDock
import ClipboardCore
import Foundation
import Testing

@Test
func settingsStoreNormalizesLoadedSettings() throws {
    let suiteName = "settings-store-load-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var raw = Settings()
    raw.maxItems = 1
    raw.quickPickerShortcut = "Cmd+Shift+Z"
    defaults.set(try JSONEncoder().encode(raw), forKey: "settings.v1.test")

    let store = SettingsStore(defaults: defaults, storageKey: "settings.v1.test")
    let loaded = store.load()

    #expect(loaded.maxItems == SettingsStore.maxItemsRange.lowerBound)
    #expect(loaded.quickPickerResultLimit == loaded.maxItems)
    #expect(loaded.quickPickerShortcut == QuickPickerShortcutPreset.cmdShiftV.settingsValue)
}

@Test
func settingsStoreNormalizesSavedSettings() {
    let suiteName = "settings-store-save-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create isolated UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var raw = Settings()
    raw.maxItems = 9_999
    raw.quickPickerShortcut = "Invalid"

    let store = SettingsStore(defaults: defaults, storageKey: "settings.v1.test")
    store.save(raw)
    let loaded = store.load()

    #expect(loaded.maxItems == SettingsStore.maxItemsRange.upperBound)
    #expect(loaded.quickPickerResultLimit == loaded.maxItems)
    #expect(loaded.quickPickerShortcut == QuickPickerShortcutPreset.cmdShiftV.settingsValue)
}

@Test
func quickPickerShortcutPresetFallsBackToDefaultForUnknownValues() {
    #expect(QuickPickerShortcutPreset.fromSettingsValue("Cmd+Shift+K") == .cmdShiftK)
    #expect(QuickPickerShortcutPreset.fromSettingsValue("Unknown") == .cmdShiftV)
}
