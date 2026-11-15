import AppKit

/// Line-art bulb drawn as a template image so it follows the menu bar's light and dark look.
enum BulbIcon {
    private static let height: CGFloat = 18
    private static let lineWidth: CGFloat = 1.4

    private static let width: CGFloat = 24
    private static let center = NSPoint(x: 12, y: 10.4)

    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor.black.setStroke()
            path().stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Bulb"
        return image
    }

    /// A bulb with five short rays above it.
    static func path() -> NSBezierPath {
        let path = bulb(centerX: center.x, centerY: center.y, radiusX: 4.6, radiusY: 4.6, neck: 2.2)
        for degrees in stride(from: 0.0, through: 180.0, by: 45.0) {
            let angle = degrees * .pi / 180
            path.move(to: NSPoint(x: center.x + 6.6 * cos(angle), y: center.y + 6.6 * sin(angle)))
            path.line(to: NSPoint(x: center.x + 8.6 * cos(angle), y: center.y + 8.6 * sin(angle)))
        }
        return path
    }

    /// Globe open at the bottom, a neck, and two base lines.
    private static func bulb(centerX: CGFloat, centerY: CGFloat, radiusX: CGFloat, radiusY: CGFloat, neck: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let start = -50.0 * .pi / 180
        let end = 230.0 * .pi / 180
        let neckTop = centerY - radiusY * sin(50.0 * .pi / 180) - 1.2
        path.move(to: NSPoint(x: centerX + neck, y: neckTop))
        let samples = 48
        for index in 0...samples {
            let angle = start + (end - start) * Double(index) / Double(samples)
            path.line(to: NSPoint(x: centerX + radiusX * cos(angle), y: centerY + radiusY * sin(angle)))
        }
        path.line(to: NSPoint(x: centerX - neck, y: neckTop))
        path.move(to: NSPoint(x: centerX - neck, y: neckTop - 1.9))
        path.line(to: NSPoint(x: centerX + neck, y: neckTop - 1.9))
        path.move(to: NSPoint(x: centerX - neck + 1, y: neckTop - 3.8))
        path.line(to: NSPoint(x: centerX + neck - 1, y: neckTop - 3.8))
        return path
    }
}
