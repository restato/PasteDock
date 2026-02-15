import Foundation

public struct QuickPickerEntry: Equatable, Sendable {
    public let id: UUID
    public let displayText: String
    public let isPinned: Bool
    public let kind: ClipboardItemKind
    public let payloadPath: String?
    public let sourceBundleId: String?
    public let capturedAt: Date
    public let sourceAppName: String?
    public let sourceTimeText: String

    public init(
        id: UUID,
        displayText: String,
        isPinned: Bool,
        kind: ClipboardItemKind = .text,
        payloadPath: String? = nil,
        sourceBundleId: String? = nil,
        capturedAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceTimeText: String? = nil
    ) {
        self.id = id
        self.displayText = displayText
        self.isPinned = isPinned
        self.kind = kind
        self.payloadPath = payloadPath
        self.sourceBundleId = sourceBundleId
        self.capturedAt = capturedAt
        self.sourceAppName = sourceAppName
        self.sourceTimeText = sourceTimeText ?? capturedAt.formatted(date: .omitted, time: .shortened)
    }

    public static func from(item: ClipboardItem, sourcePresentation: SourcePresentation? = nil) -> QuickPickerEntry {
        let sourceAppName = sourcePresentation.flatMap { presentation in
            presentation.isKnownSource ? presentation.appName : nil
        }
        let sourceTimeText = sourcePresentation?.timeText ?? item.createdAt.formatted(date: .omitted, time: .shortened)

        if item.kind == .image || item.kind == .file {
            return QuickPickerEntry(
                id: item.id,
                displayText: item.previewText,
                isPinned: item.isPinned,
                kind: item.kind,
                payloadPath: item.payloadPath,
                sourceBundleId: item.sourceBundleId,
                capturedAt: item.createdAt,
                sourceAppName: sourceAppName,
                sourceTimeText: sourceTimeText
            )
        }

        let oneLine = item.previewText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickPickerEntry(
            id: item.id,
            displayText: oneLine,
            isPinned: item.isPinned,
            kind: .text,
            payloadPath: item.payloadPath,
            sourceBundleId: item.sourceBundleId,
            capturedAt: item.createdAt,
            sourceAppName: sourceAppName,
            sourceTimeText: sourceTimeText
        )
    }
}

public enum KeyModifier: Hashable, Sendable {
    case command
}

public struct KeyInput: Sendable {
    public let key: String
    public let modifiers: Set<KeyModifier>

    public init(key: String, modifiers: Set<KeyModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum QuickPickerCommand: Equatable, Sendable {
    case selectIndex(Int)
    case executeTopResult
    case deleteSelection
    case close
    case none
}

public struct QuickPickerKeyMapper {
    public init() {}

    public func command(for input: KeyInput) -> QuickPickerCommand {
        if input.modifiers.isEmpty, let number = Int(input.key), (1...9).contains(number) {
            return .selectIndex(number - 1)
        }

        if input.modifiers.isEmpty, input.key == "enter" {
            return .executeTopResult
        }

        if input.modifiers.contains(.command), input.key == "backspace" {
            return .deleteSelection
        }

        if input.modifiers.isEmpty, input.key == "escape" {
            return .close
        }

        return .none
    }
}
