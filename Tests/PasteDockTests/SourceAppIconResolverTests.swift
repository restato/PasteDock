@testable import PasteDock
import AppKit
import Foundation
import Testing

@Test
func sourceAppIconResolverReturnsNilWhenBundleIdIsMissing() async {
    await MainActor.run {
        var appURLLookups = 0
        let resolver = SourceAppIconResolver(
            appURLProvider: { _ in
                appURLLookups += 1
                return nil
            },
            iconProvider: { _ in NSImage(size: NSSize(width: 32, height: 32)) }
        )

        #expect(resolver.resolve(bundleId: nil) == nil)
        #expect(resolver.resolve(bundleId: "") == nil)
        #expect(appURLLookups == 0)
    }
}

@Test
func sourceAppIconResolverCachesMissingBundleIdLookups() async {
    await MainActor.run {
        var appURLLookups = 0
        let resolver = SourceAppIconResolver(
            appURLProvider: { _ in
                appURLLookups += 1
                return nil
            },
            iconProvider: { _ in NSImage(size: NSSize(width: 32, height: 32)) }
        )

        #expect(resolver.resolve(bundleId: "com.example.missing") == nil)
        #expect(resolver.resolve(bundleId: "com.example.missing") == nil)
        #expect(appURLLookups == 1)
    }
}

@Test
func sourceAppIconResolverCachesResolvedIconsAndNormalizesSize() async {
    await MainActor.run {
        let appURL = URL(fileURLWithPath: "/Applications/FakeApp.app")
        var appURLLookups = 0
        var iconPaths: [String] = []
        let resolver = SourceAppIconResolver(
            appURLProvider: { bundleId in
                appURLLookups += 1
                return bundleId == "com.example.fake" ? appURL : nil
            },
            iconProvider: { path in
                iconPaths.append(path)
                return NSImage(size: NSSize(width: 64, height: 64))
            },
            iconSize: NSSize(width: 16, height: 16)
        )

        let first = resolver.resolve(bundleId: "com.example.fake")
        let second = resolver.resolve(bundleId: "com.example.fake")

        #expect(appURLLookups == 1)
        #expect(iconPaths == [appURL.path])
        #expect(first?.size == NSSize(width: 16, height: 16))
        if let first, let second {
            #expect(first === second)
        }
    }
}
