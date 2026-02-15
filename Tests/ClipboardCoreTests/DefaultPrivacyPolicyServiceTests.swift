import ClipboardCore
import Testing

@Test
func defaultPrivacyPolicyRecognizesExcludedBundleIds() {
    let policy = DefaultPrivacyPolicyService(excludedBundleIds: ["com.blocked.app"])

    #expect(policy.isExcluded(bundleId: "com.blocked.app"))
    #expect(policy.isExcluded(bundleId: "com.safe.app") == false)
    #expect(policy.isExcluded(bundleId: nil) == false)
}

@Test
func defaultPrivacyPolicyDetectsSensitivePatterns() {
    let policy = DefaultPrivacyPolicyService(excludedBundleIds: [])

    #expect(policy.containsSensitiveContent("ssn 123-45-6789"))
    #expect(policy.containsSensitiveContent("card 4111 1111 1111 1111"))
    #expect(policy.containsSensitiveContent("password = hunter2"))
    #expect(policy.containsSensitiveContent("api-key: secret-value"))
    #expect(policy.containsSensitiveContent("normal clipboard text") == false)
}
