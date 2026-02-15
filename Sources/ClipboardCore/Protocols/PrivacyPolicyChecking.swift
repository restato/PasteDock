import Foundation

public protocol PrivacyPolicyChecking: Sendable {
    func isExcluded(bundleId: String?) -> Bool
    func containsSensitiveContent(_ text: String) -> Bool
}
