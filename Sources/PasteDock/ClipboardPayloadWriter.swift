import AppKit
import ClipboardCore
import Foundation

final class ClipboardPayloadWriter {
    private let paths: AppSupportPaths

    init(paths: AppSupportPaths) {
        self.paths = paths
    }

    func writeText(_ text: String) throws -> String {
        let url = paths.textPayloadDir.appendingPathComponent("\(UUID().uuidString).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func writeImage(_ data: Data) throws -> String {
        let url = paths.imagePayloadDir.appendingPathComponent("\(UUID().uuidString).png")
        try data.write(to: url, options: [.atomic])
        return url.path
    }

    func writeFilePayload(_ filePaths: [String]) throws -> String {
        let payload = FileClipboardPayload(paths: filePaths)
        let data = try JSONEncoder().encode(payload)
        let url = paths.filePayloadDir.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic])
        return url.path
    }

    func readImageData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }

        guard let tiff = pasteboard.data(forType: .tiff), let image = NSImage(data: tiff) else {
            return nil
        }

        guard
            let tiffData = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiffData),
            let png = rep.representation(using: .png, properties: [:])
        else {
            return nil
        }

        return png
    }

    func readFilePaths(from pasteboard: NSPasteboard) -> [String]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }

        var seen = Set<String>()
        var uniquePaths: [String] = []
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                uniquePaths.append(path)
            }
        }

        return uniquePaths.isEmpty ? nil : uniquePaths
    }
}
