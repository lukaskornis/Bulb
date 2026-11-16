import AppKit

// Draws the README screenshots offscreen: the real SliderRow and BulbIcon on a menu bar strip, with made-up screens.
// No window is shown and nothing on the real screen is captured. Run ./screenshots/render.sh.

private let canvasWidth: CGFloat = 330
private let barHeight: CGFloat = 26
private let menuWidth: CGFloat = 250
private let textRowHeight: CGFloat = 22
private let separatorHeight: CGFloat = 11
private let sliderRowHeight: CGFloat = 30
private let menuPadding: CGFloat = 5
private let scale: CGFloat = 2

private enum Item {
    case slider(symbol: String, value: Float)
    case separator
    case check(String, on: Bool, indent: Int)
    case command(String, key: String)

    var height: CGFloat {
        switch self {
        case .slider: sliderRowHeight
        case .separator: separatorHeight
        case .check, .command: textRowHeight
        }
    }
}

private let items: [Item] = [
    .slider(symbol: "sun.max.fill", value: 0.62),
    .separator,
    .slider(symbol: "laptopcomputer", value: 0.7),
    .slider(symbol: "display", value: 0.55),
    .separator,
    .check("Keys Change All Screens", on: true, indent: 0),
    .check("Keep Brightness Ratios", on: true, indent: 1),
    .separator,
    .check("Launch at Login", on: true, indent: 0),
    .command("Quit", key: "⌘Q"),
]

/// Calm backdrop, a slice of menu bar with the bulb highlighted, and the menu panel under it.
private final class Backdrop: NSView {
    let menuFrame: NSRect
    let iconFrame: NSRect
    let dark: Bool

    init(frame: NSRect, menuFrame: NSRect, iconFrame: NSRect, dark: Bool) {
        self.menuFrame = menuFrame
        self.iconFrame = iconFrame
        self.dark = dark
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let top = dark ? NSColor(srgbRed: 0.20, green: 0.19, blue: 0.18, alpha: 1) : NSColor(srgbRed: 0.93, green: 0.90, blue: 0.85, alpha: 1)
        let bottom = dark ? NSColor(srgbRed: 0.12, green: 0.11, blue: 0.10, alpha: 1) : NSColor(srgbRed: 0.84, green: 0.79, blue: 0.72, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: bounds, angle: 90)

        let bar = NSRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)
        (dark ? NSColor(white: 0, alpha: 0.35) : NSColor(white: 1, alpha: 0.5)).setFill()
        bar.fill()
        let highlight = iconFrame.insetBy(dx: -5, dy: -3)
        (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.1)).setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 5, yRadius: 5).fill()

        let panel = NSBezierPath(roundedRect: menuFrame, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: dark ? 0.5 : 0.22)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        (dark ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
        panel.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: dark ? 1 : 0, alpha: 0.12).setStroke()
        panel.lineWidth = 0.5
        panel.stroke()
    }
}

private func label(_ text: String, color: NSColor, at origin: NSPoint, alignRightTo right: CGFloat? = nil) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .menuFont(ofSize: 0)
    field.textColor = color
    field.sizeToFit()
    let x = right.map { $0 - field.frame.width } ?? origin.x
    field.setFrameOrigin(NSPoint(x: x, y: origin.y + (textRowHeight - field.frame.height) / 2))
    return field
}

private func render(dark: Bool, to path: String) throws {
    let menuHeight = items.reduce(menuPadding * 2) { $0 + $1.height }
    let canvas = NSSize(width: canvasWidth, height: barHeight + 6 + menuHeight + 34)
    let iconFrame = NSRect(x: 48, y: canvas.height - barHeight + 4, width: 24, height: 18)
    let menuFrame = NSRect(x: iconFrame.minX - 8, y: canvas.height - barHeight - 6 - menuHeight, width: menuWidth, height: menuHeight)

    let root = Backdrop(frame: NSRect(origin: .zero, size: canvas), menuFrame: menuFrame, iconFrame: iconFrame, dark: dark)
    root.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

    let icon = NSImageView(frame: iconFrame)
    icon.image = BulbIcon.image()
    icon.contentTintColor = .labelColor
    root.addSubview(icon)

    var y = menuFrame.maxY - menuPadding
    for item in items {
        y -= item.height
        switch item {
        case let .slider(symbol, value):
            let row = SliderRow(symbol: symbol, tooltip: "", value: value, enabled: true)
            row.setFrameOrigin(NSPoint(x: menuFrame.minX, y: y))
            root.addSubview(row)
        case .separator:
            let line = NSBox(frame: NSRect(x: menuFrame.minX + 10, y: y + separatorHeight / 2, width: menuWidth - 20, height: 1))
            line.boxType = .separator
            root.addSubview(line)
        case let .check(title, on, indent):
            let indentX = CGFloat(indent) * 14
            if on { root.addSubview(label("✓", color: .labelColor, at: NSPoint(x: menuFrame.minX + 12 + indentX, y: y))) }
            root.addSubview(label(title, color: .labelColor, at: NSPoint(x: menuFrame.minX + 28 + indentX, y: y)))
        case let .command(title, key):
            root.addSubview(label(title, color: .labelColor, at: NSPoint(x: menuFrame.minX + 28, y: y)))
            root.addSubview(label(key, color: .secondaryLabelColor, at: NSPoint(x: 0, y: y), alignRightTo: menuFrame.maxX - 14))
        }
    }

    let window = NSWindow(contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = root.appearance
    window.contentView = root
    root.layoutSubtreeIfNeeded()

    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        throw CocoaError(.fileWriteUnknown)
    }
    bitmap.size = canvas
    root.appearance?.performAsCurrentDrawingAppearance {
        root.cacheDisplay(in: root.bounds, to: bitmap)
    }
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: URL(fileURLWithPath: path))
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let directory = CommandLine.arguments[1]
try render(dark: false, to: "\(directory)/menu-light.png")
try render(dark: true, to: "\(directory)/menu-dark.png")
