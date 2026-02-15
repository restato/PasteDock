import Carbon
import Foundation

enum GlobalShortcutError: Error {
    case installHandlerFailed(OSStatus)
    case registerHotKeyFailed(OSStatus)
}

enum QuickPickerShortcutPreset: String, CaseIterable, Identifiable {
    case cmdShiftV = "Cmd+Shift+V"
    case cmdShiftJ = "Cmd+Shift+J"
    case cmdShiftK = "Cmd+Shift+K"
    case cmdShiftSpace = "Cmd+Shift+Space"

    var id: String { rawValue }
    var displayName: String { rawValue }
    var settingsValue: String { rawValue }
    var modifierFlags: UInt32 { UInt32(cmdKey | shiftKey) }

    var keyCode: UInt32 {
        switch self {
        case .cmdShiftV:
            return UInt32(kVK_ANSI_V)
        case .cmdShiftJ:
            return UInt32(kVK_ANSI_J)
        case .cmdShiftK:
            return UInt32(kVK_ANSI_K)
        case .cmdShiftSpace:
            return UInt32(kVK_Space)
        }
    }

    static func fromSettingsValue(_ value: String) -> QuickPickerShortcutPreset {
        QuickPickerShortcutPreset(rawValue: value) ?? .cmdShiftV
    }
}

final class GlobalShortcutService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    deinit {
        unregister()
    }

    func register(_ preset: QuickPickerShortcutPreset, onTrigger: @escaping () -> Void) throws {
        unregister()
        self.onTrigger = onTrigger

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let shortcutService = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
                shortcutService.onTrigger?()
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw GlobalShortcutError.installHandlerFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4A444954), id: 1)
        let registerStatus = RegisterEventHotKey(
            preset.keyCode,
            preset.modifierFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw GlobalShortcutError.registerHotKeyFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        onTrigger = nil
    }
}
