import Foundation

struct AppSupportPaths {
    let root: URL
    let databaseURL: URL
    let textPayloadDir: URL
    let imagePayloadDir: URL
    let filePayloadDir: URL

    static func make(bundleIdentifier: String) throws -> AppSupportPaths {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let safeName = bundleIdentifier.replacingOccurrences(of: ".", with: "-")
        let root = appSupport.appendingPathComponent(safeName, isDirectory: true)
        let textPayloadDir = root.appendingPathComponent("texts", isDirectory: true)
        let imagePayloadDir = root.appendingPathComponent("images", isDirectory: true)
        let filePayloadDir = root.appendingPathComponent("files", isDirectory: true)
        let databaseURL = root.appendingPathComponent("history.sqlite", isDirectory: false)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textPayloadDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagePayloadDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filePayloadDir, withIntermediateDirectories: true)

        return AppSupportPaths(
            root: root,
            databaseURL: databaseURL,
            textPayloadDir: textPayloadDir,
            imagePayloadDir: imagePayloadDir,
            filePayloadDir: filePayloadDir
        )
    }
}
