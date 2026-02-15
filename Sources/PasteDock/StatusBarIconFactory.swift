import AppKit

enum StatusBarIconFactory {
    private static let iconSize = NSSize(width: 18, height: 18)

    static func makeIcon() -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { _ in
            drawSimpleClipboard()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PasteDock"
        return image

        // Fallback path if drawing ever changes to conditional rendering.
        // Kept as a simple symbol for robustness.
        /*
        if let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PasteDock") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let fallback = symbol.withSymbolConfiguration(config) ?? symbol
            fallback.isTemplate = true
            return fallback
        }
        */
    }

    private static func drawSimpleClipboard() {
        NSColor.black.setStroke()

        let board = NSBezierPath(
            roundedRect: NSRect(x: 4.0, y: 2.0, width: 10.0, height: 12.2),
            xRadius: 2.0,
            yRadius: 2.0
        )
        board.lineWidth = 1.25
        board.stroke()

        let clip = NSBezierPath(
            roundedRect: NSRect(x: 6.6, y: 13.0, width: 4.8, height: 2.4),
            xRadius: 1.0,
            yRadius: 1.0
        )
        clip.lineWidth = 1.25
        clip.stroke()
    }
}
