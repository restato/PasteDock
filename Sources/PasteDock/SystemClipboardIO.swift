import AppKit
import ApplicationServices
import ClipboardCore
import Foundation

enum AutoPasteIOError: Error {
    case pasteEventFailed
}

final class SystemClipboardRestorer: ClipboardRestoring {
    func restore(item: ClipboardItem) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            let textURL = URL(fileURLWithPath: item.payloadPath)
            guard let text = try? String(contentsOf: textURL, encoding: .utf8) else {
                throw ClipboardRestoreError.payloadReadFailed
            }
            guard pasteboard.setString(text, forType: .string) else {
                throw ClipboardRestoreError.pasteboardWriteFailed
            }

        case .image:
            let imageURL = URL(fileURLWithPath: item.payloadPath)
            let data: Data
            do {
                data = try Data(contentsOf: imageURL)
            } catch {
                throw ClipboardRestoreError.payloadReadFailed
            }
            if let image = NSImage(data: data) {
                guard pasteboard.writeObjects([image]) else {
                    throw ClipboardRestoreError.pasteboardWriteFailed
                }
            } else {
                guard pasteboard.setData(data, forType: .png) else {
                    throw ClipboardRestoreError.pasteboardWriteFailed
                }
            }

        case .file:
            let payload = try Self.readFilePayload(path: item.payloadPath)
            guard !payload.paths.isEmpty else {
                throw ClipboardRestoreError.invalidFilePayload
            }

            if let missing = payload.paths.first(where: { !FileManager.default.fileExists(atPath: $0) }) {
                throw ClipboardRestoreError.fileMissing(path: missing)
            }

            let fileURLs = payload.paths.map { NSURL(fileURLWithPath: $0) }
            guard pasteboard.writeObjects(fileURLs) else {
                throw ClipboardRestoreError.pasteboardWriteFailed
            }
        }
    }

    private static func readFilePayload(path: String) throws -> FileClipboardPayload {
        let payloadURL = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: payloadURL)
        } catch {
            throw ClipboardRestoreError.payloadReadFailed
        }

        do {
            return try JSONDecoder().decode(FileClipboardPayload.self, from: data)
        } catch {
            throw ClipboardRestoreError.invalidFilePayload
        }
    }
}

final class SystemAutoPaster: AutoPastePerforming {
    private let appTracker: FrontmostAppTracker

    init(appTracker: FrontmostAppTracker) {
        self.appTracker = appTracker
    }

    func canAutoPaste() -> Bool {
        AXIsProcessTrusted()
    }

    func performAutoPaste(targetApp: TargetAppSnapshot?) throws {
        appTracker.activate(targetApp)
        usleep(80_000)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw AutoPasteIOError.pasteEventFailed
        }
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            throw AutoPasteIOError.pasteEventFailed
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
