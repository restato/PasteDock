import AppKit
import CoreGraphics
import Foundation

enum IconGenerationError: Error, CustomStringConvertible {
    case invalidArguments
    case sourceImageLoadFailed(String)
    case sourceImageDecodeFailed(String)
    case squareCropFailed
    case bitmapContextCreateFailed
    case outputEncodeFailed(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Usage: swift scripts/generate-app-icon.swift <source.png> <iconset-dir> <menuBarTemplate.png>"
        case let .sourceImageLoadFailed(path):
            return "Failed to load source image: \(path)"
        case let .sourceImageDecodeFailed(path):
            return "Failed to decode source image into bitmap: \(path)"
        case .squareCropFailed:
            return "Failed to crop source image into a centered square"
        case .bitmapContextCreateFailed:
            return "Failed to create bitmap context"
        case let .outputEncodeFailed(path):
            return "Failed to encode PNG output: \(path)"
        }
    }
}

private let iconsetEntries: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

private let menuBarTemplateSize = 36

private func loadSourceImage(_ url: URL) throws -> CGImage {
    guard let nsImage = NSImage(contentsOf: url) else {
        throw IconGenerationError.sourceImageLoadFailed(url.path)
    }

    if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return cgImage
    }

    guard
        let data = try? Data(contentsOf: url),
        let rep = NSBitmapImageRep(data: data),
        let cgImage = rep.cgImage
    else {
        throw IconGenerationError.sourceImageDecodeFailed(url.path)
    }
    return cgImage
}

private func croppedSquare(from image: CGImage) throws -> CGImage {
    let width = image.width
    let height = image.height
    let side = min(width, height)
    let originX = (width - side) / 2
    let originY = (height - side) / 2
    let cropRect = CGRect(x: originX, y: originY, width: side, height: side)

    guard let cropped = image.cropping(to: cropRect) else {
        throw IconGenerationError.squareCropFailed
    }
    return cropped
}

private func makeContext(size: Int) throws -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw IconGenerationError.bitmapContextCreateFailed
    }
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    return context
}

private func resizedImage(from square: CGImage, size: Int, inset: Int = 0) throws -> CGImage {
    let context = try makeContext(size: size)
    let drawRect = CGRect(
        x: inset,
        y: inset,
        width: size - (inset * 2),
        height: size - (inset * 2)
    )
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.draw(square, in: drawRect)

    guard let image = context.makeImage() else {
        throw IconGenerationError.bitmapContextCreateFailed
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.outputEncodeFailed(url.path)
    }
    try data.write(to: url)
}

private func makeMenuBarTemplate(from square: CGImage) throws -> CGImage {
    let padding = max(2, Int(round(Double(menuBarTemplateSize) * 0.12)))
    let resized = try resizedImage(from: square, size: menuBarTemplateSize, inset: padding)

    let context = try makeContext(size: menuBarTemplateSize)
    context.clear(CGRect(x: 0, y: 0, width: menuBarTemplateSize, height: menuBarTemplateSize))
    context.draw(resized, in: CGRect(x: 0, y: 0, width: menuBarTemplateSize, height: menuBarTemplateSize))

    guard let data = context.data else {
        throw IconGenerationError.bitmapContextCreateFailed
    }

    let bytesPerRow = context.bytesPerRow
    let pixelCount = menuBarTemplateSize * menuBarTemplateSize
    let pointer = data.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

    for y in 0 ..< menuBarTemplateSize {
        for x in 0 ..< menuBarTemplateSize {
            let offset = (y * bytesPerRow) + (x * 4)
            let red = Double(pointer[offset])
            let green = Double(pointer[offset + 1])
            let blue = Double(pointer[offset + 2])
            let alpha = Double(pointer[offset + 3])

            if alpha == 0 {
                continue
            }

            // Convert to template alpha:
            // - preserve existing alpha
            // - suppress bright/white backgrounds
            let luma = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            let inverted = max(0.0, min(255.0, (255.0 - luma) * 1.2))
            let templateAlpha = UInt8(max(0.0, min(255.0, (alpha / 255.0) * inverted)))

            pointer[offset] = 0
            pointer[offset + 1] = 0
            pointer[offset + 2] = 0
            pointer[offset + 3] = templateAlpha
        }
    }

    guard let output = context.makeImage() else {
        throw IconGenerationError.bitmapContextCreateFailed
    }
    return output
}

private func run() throws {
    guard CommandLine.arguments.count == 4 else {
        throw IconGenerationError.invalidArguments
    }

    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let iconsetDir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let menuBarTemplateURL = URL(fileURLWithPath: CommandLine.arguments[3])

    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        throw IconGenerationError.sourceImageLoadFailed(sourceURL.path)
    }

    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: menuBarTemplateURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let sourceImage = try loadSourceImage(sourceURL)
    let square = try croppedSquare(from: sourceImage)

    for (size, fileName) in iconsetEntries {
        let outputImage = try resizedImage(from: square, size: size)
        let outputURL = iconsetDir.appendingPathComponent(fileName)
        try writePNG(outputImage, to: outputURL)
    }

    let menuTemplate = try makeMenuBarTemplate(from: square)
    try writePNG(menuTemplate, to: menuBarTemplateURL)

    print("Generated iconset at \(iconsetDir.path)")
    print("Generated menu bar template at \(menuBarTemplateURL.path)")
}

do {
    try run()
} catch {
    if let known = error as? IconGenerationError {
        fputs("generate-app-icon error: \(known.description)\n", stderr)
    } else {
        fputs("generate-app-icon error: \(error.localizedDescription)\n", stderr)
    }
    exit(1)
}
