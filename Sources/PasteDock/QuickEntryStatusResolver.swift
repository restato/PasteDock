import ClipboardCore
import Foundation

enum QuickEntryStatus: Equatable {
    case ready
    case missing

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .missing:
            return "Missing"
        }
    }

    var isMissing: Bool {
        self == .missing
    }
}

struct QuickEntryStatusResolver {
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, decoder: JSONDecoder = JSONDecoder()) {
        self.fileManager = fileManager
        self.decoder = decoder
    }

    func resolve(for entry: QuickPickerEntry) -> QuickEntryStatus {
        switch entry.kind {
        case .text, .image:
            guard hasPayload(at: entry.payloadPath) else {
                return .missing
            }
            return .ready

        case .file:
            guard
                let payloadPath = entry.payloadPath,
                !payloadPath.isEmpty,
                let payloadData = try? Data(contentsOf: URL(fileURLWithPath: payloadPath)),
                let payload = try? decoder.decode(FileClipboardPayload.self, from: payloadData),
                !payload.paths.isEmpty
            else {
                return .missing
            }

            return payload.paths.allSatisfy { path in
                fileManager.fileExists(atPath: path)
            } ? .ready : .missing
        }
    }

    private func hasPayload(at payloadPath: String?) -> Bool {
        guard let payloadPath, !payloadPath.isEmpty else {
            return false
        }
        return fileManager.fileExists(atPath: payloadPath)
    }
}
