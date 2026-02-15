import AppKit
import ClipboardCore
import Foundation

@MainActor
final class ClipboardMonitorService {
    private let pasteboard: NSPasteboard
    private let payloadWriter: ClipboardPayloadWriter
    private let frontmostSnapshotProvider: () -> TargetAppSnapshot?
    private let onCapturedInput: @Sendable (CaptureInput) async -> Void

    private var timer: Timer?
    private var lastChangeCount: Int

    init(
        pasteboard: NSPasteboard = .general,
        payloadWriter: ClipboardPayloadWriter,
        frontmostSnapshotProvider: @escaping () -> TargetAppSnapshot?,
        onCapturedInput: @escaping @Sendable (CaptureInput) async -> Void
    ) {
        self.pasteboard = pasteboard
        self.payloadWriter = payloadWriter
        self.frontmostSnapshotProvider = frontmostSnapshotProvider
        self.onCapturedInput = onCapturedInput
        self.lastChangeCount = pasteboard.changeCount
    }

    func start(intervalMs: Int) {
        stop()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: Double(max(50, intervalMs)) / 1000.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = pasteboard.changeCount

        let sourceBundleId = frontmostSnapshotProvider()?.bundleId

        if let filePaths = payloadWriter.readFilePaths(from: pasteboard), !filePaths.isEmpty {
            do {
                let path = try payloadWriter.writeFilePayload(filePaths)
                let input = CaptureInput(
                    kind: .file,
                    filePaths: filePaths,
                    payloadPath: path,
                    sourceBundleId: sourceBundleId,
                    capturedAtFrontmostBundleId: sourceBundleId
                )
                let handler = onCapturedInput
                Task { await handler(input) }
            } catch {
                // Ignore write failure in monitor; pipeline and logs handle capture-level failures.
            }
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            do {
                let path = try payloadWriter.writeText(text)
                let input = CaptureInput(
                    kind: .text,
                    text: text,
                    payloadPath: path,
                    sourceBundleId: sourceBundleId,
                    capturedAtFrontmostBundleId: sourceBundleId
                )
                let handler = onCapturedInput
                Task { await handler(input) }
            } catch {
                // Ignore write failure in monitor; pipeline and logs handle capture-level failures.
            }
            return
        }

        if let imageData = payloadWriter.readImageData(from: pasteboard), !imageData.isEmpty {
            do {
                let path = try payloadWriter.writeImage(imageData)
                let input = CaptureInput(
                    kind: .image,
                    imageBytes: imageData,
                    payloadPath: path,
                    sourceBundleId: sourceBundleId,
                    capturedAtFrontmostBundleId: sourceBundleId
                )
                let handler = onCapturedInput
                Task { await handler(input) }
            } catch {
                // Ignore write failure in monitor; pipeline and logs handle capture-level failures.
            }
        }
    }
}
