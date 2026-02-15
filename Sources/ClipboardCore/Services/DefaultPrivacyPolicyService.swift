import Foundation

public struct DefaultPrivacyPolicyService: PrivacyPolicyChecking {
    public let excludedBundleIds: Set<String>

    private let sensitivePatterns: [NSRegularExpression]

    public init(excludedBundleIds: Set<String>) {
        self.excludedBundleIds = excludedBundleIds
        self.sensitivePatterns = [
            #"\b\d{3}-\d{2}-\d{4}\b"#,
            #"\b(?:\d[ -]*?){13,16}\b"#,
            #"(?i)password\s*[:=]\s*\S+"#,
            #"(?i)api[_-]?key\s*[:=]\s*\S+"#
        ].compactMap { pattern in
            try? NSRegularExpression(pattern: pattern)
        }
    }

    public func isExcluded(bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return excludedBundleIds.contains(bundleId)
    }

    public func containsSensitiveContent(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return sensitivePatterns.contains { pattern in
            pattern.firstMatch(in: text, range: range) != nil
        }
    }
}
