import CryptoKit
import Foundation

public struct CapturePipeline: Sendable {
    private let store: HistoryStore
    private let privacyPolicy: PrivacyPolicyChecking
    private let logService: LocalLogService?
    private let toastService: OperationToastService?
    private let clock: Clock

    public init(
        store: HistoryStore,
        privacyPolicy: PrivacyPolicyChecking,
        logService: LocalLogService? = nil,
        toastService: OperationToastService? = nil,
        clock: Clock = SystemClock()
    ) {
        self.store = store
        self.privacyPolicy = privacyPolicy
        self.logService = logService
        self.toastService = toastService
        self.clock = clock
    }

    public func process(_ input: CaptureInput, settings: Settings) async -> CaptureDecision {
        let start = clock.now

        let capturedBundleId = input.capturedAtFrontmostBundleId ?? input.sourceBundleId
        if privacyPolicy.isExcluded(bundleId: capturedBundleId) {
            await emitSkip(reason: .excludedApp, input: input, start: start, showToasts: settings.showOperationToasts)
            return .skipped(.excludedApp)
        }

        let contentHashData: Data
        let payloadByteSize: Int64
        let previewText: String

        switch input.kind {
        case .text:
            guard let text = input.text, !text.isEmpty else {
                await emitFailure(reason: .invalidInput, input: input, start: start, showToasts: settings.showOperationToasts)
                return .failed(.invalidInput)
            }
            if settings.privacyFilterEnabled && privacyPolicy.containsSensitiveContent(text) {
                await emitSkip(reason: .sensitiveContent, input: input, start: start, showToasts: settings.showOperationToasts)
                return .skipped(.sensitiveContent)
            }
            let textData = Data(text.utf8)
            contentHashData = textData
            payloadByteSize = Int64(textData.count)
            previewText = Self.oneLineText(text)

        case .image:
            guard let imageBytes = input.imageBytes, !imageBytes.isEmpty else {
                await emitFailure(reason: .invalidInput, input: input, start: start, showToasts: settings.showOperationToasts)
                return .failed(.invalidInput)
            }
            contentHashData = imageBytes
            payloadByteSize = Int64(imageBytes.count)
            let kb = max(1, imageBytes.count / 1024)
            previewText = "[Image] \(kb) KB"

        case .file:
            let filePaths = Self.sanitizedFilePaths(input.filePaths)
            guard !filePaths.isEmpty else {
                await emitFailure(reason: .invalidInput, input: input, start: start, showToasts: settings.showOperationToasts)
                return .failed(.invalidInput)
            }

            let normalizedPaths = Self.normalizedPathsForHash(filePaths)
            guard !normalizedPaths.isEmpty else {
                await emitFailure(reason: .invalidInput, input: input, start: start, showToasts: settings.showOperationToasts)
                return .failed(.invalidInput)
            }

            guard let manifestData = try? JSONEncoder().encode(FileClipboardPayload(paths: filePaths)) else {
                await emitFailure(reason: .invalidInput, input: input, start: start, showToasts: settings.showOperationToasts)
                return .failed(.invalidInput)
            }

            contentHashData = Data(Self.normalizedPathsHashSeed(normalizedPaths).utf8)
            payloadByteSize = Int64(manifestData.count)
            previewText = Self.filePreviewText(for: filePaths)
        }

        let hash = Self.hash(contentHashData)

        do {
            if try store.lastContentHash() == hash {
                await emitSkip(reason: .duplicate, input: input, start: start, showToasts: settings.showOperationToasts)
                return .skipped(.duplicate)
            }

            let item = ClipboardItem(
                kind: input.kind,
                previewText: previewText,
                contentHash: hash,
                byteSize: payloadByteSize,
                sourceBundleId: capturedBundleId,
                payloadPath: input.payloadPath
            )

            try store.save(item: item)
            let retentionOutcome = try store.enforceLimits(maxItems: settings.maxItems, maxBytes: settings.maxBytes)

            if retentionOutcome.deletedCount > 0 && settings.showOperationToasts {
                await toastService?.enqueue(OperationToast(message: "History trimmed", style: .info))
            }
            if retentionOutcome.deletedCount > 0 {
                await logService?.log(
                    LogEntry(
                        event: "retention",
                        result: "trimmed",
                        reason: "limits_exceeded",
                        bundleId: capturedBundleId,
                        itemKind: input.kind.rawValue,
                        itemSize: payloadByteSize,
                        durationMs: Self.durationMs(from: start, to: clock.now),
                        timestamp: clock.now
                    )
                )
            }

            await logService?.log(
                LogEntry(
                    event: "capture",
                    result: "saved",
                    bundleId: capturedBundleId,
                    itemKind: input.kind.rawValue,
                    itemSize: payloadByteSize,
                    durationMs: Self.durationMs(from: start, to: clock.now),
                    timestamp: clock.now
                )
            )
            return .saved(item)
        } catch {
            let reason = CaptureFailureReason.storeWriteFailed(error.localizedDescription)
            await emitFailure(reason: reason, input: input, start: start, showToasts: settings.showOperationToasts)
            return .failed(reason)
        }
    }

    private func emitSkip(reason: CaptureSkipReason, input: CaptureInput, start: Date, showToasts: Bool) async {
        let message: String
        switch reason {
        case .excludedApp:
            message = "Skipped excluded app"
        case .sensitiveContent:
            message = "Skipped sensitive content"
        case .duplicate:
            message = "Skipped duplicate"
        }

        if showToasts {
            await toastService?.enqueue(OperationToast(message: message, style: .info))
        }
        await logService?.log(
            LogEntry(
                event: "capture",
                result: "skipped",
                reason: String(describing: reason),
                bundleId: input.capturedAtFrontmostBundleId ?? input.sourceBundleId,
                itemKind: input.kind.rawValue,
                durationMs: Self.durationMs(from: start, to: clock.now),
                timestamp: clock.now
            )
        )
    }

    private func emitFailure(reason: CaptureFailureReason, input: CaptureInput, start: Date, showToasts: Bool) async {
        if showToasts {
            await toastService?.enqueue(OperationToast(message: "Capture failed", style: .error))
        }
        await logService?.log(
            LogEntry(
                event: "capture",
                result: "failed",
                reason: String(describing: reason),
                bundleId: input.capturedAtFrontmostBundleId ?? input.sourceBundleId,
                itemKind: input.kind.rawValue,
                durationMs: Self.durationMs(from: start, to: clock.now),
                timestamp: clock.now
            )
        )
    }

    private static func oneLineText(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.count <= 120 {
            return singleLine
        }
        return String(singleLine.prefix(117)) + "..."
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sanitizedFilePaths(_ paths: [String]?) -> [String] {
        guard let paths else { return [] }
        return paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedPathsForHash(_ paths: [String]) -> [String] {
        paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .sorted()
    }

    private static func normalizedPathsHashSeed(_ paths: [String]) -> String {
        paths.joined(separator: "\n")
    }

    private static func filePreviewText(for paths: [String]) -> String {
        let firstName = URL(fileURLWithPath: paths[0]).lastPathComponent
        if paths.count == 1 {
            return "[File] \(firstName)"
        }
        return "[Files \(paths.count)] \(firstName) +\(paths.count - 1)"
    }

    private static func durationMs(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1000).rounded())
    }
}
