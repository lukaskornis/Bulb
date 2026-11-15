import AppKit

/// A small on-screen bar on each screen whose brightness just changed.
final class BrightnessHUD {
    private var panels: [CGDirectDisplayID: HUDPanel] = [:]

    func show(_ value: Float, on screen: NSScreen) {
        let panel = panels[screen.displayID] ?? HUDPanel()
        panels[screen.displayID] = panel
        panel.show(value, on: screen)
    }
}

private final class HUDPanel {
    private let panel: NSPanel
    private let bar = SegmentBar()
    private var hideWork: DispatchWorkItem?

    private static let size = NSSize(width: 230, height: 40)
    private static let bottomOffset: CGFloat = 80
    private static let visibleSeconds = 1.2

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .hudWindow
        background.state = .active
        background.maskImage = Self.roundedMask(size: Self.size, radius: Self.size.height / 2)

        let icon = NSImageView(frame: NSRect(x: 14, y: 10, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness")
        icon.contentTintColor = .labelColor

        bar.frame = NSRect(x: 44, y: 15, width: Self.size.width - 62, height: 10)

        background.addSubview(icon)
        background.addSubview(bar)
        panel.contentView = background
    }

    func show(_ value: Float, on screen: NSScreen) {
        bar.value = CGFloat(value)
        let frame = screen.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + Self.bottomOffset))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; self?.panel.animator().alphaValue = 0 },
                                                 completionHandler: { self?.panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds, execute: work)
    }

    private static func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
    }
}

/// Sixteen segments, like the system's brightness steps; a partial segment shows fine steps.
private final class SegmentBar: NSView {
    var value: CGFloat = 0 { didSet { needsDisplay = true } }

    private static let segments = 16
    private static let gap: CGFloat = 2

    override func draw(_ dirtyRect: NSRect) {
        let width = (bounds.width - Self.gap * CGFloat(Self.segments - 1)) / CGFloat(Self.segments)
        let filled = value * CGFloat(Self.segments)
        for index in 0..<Self.segments {
            let rect = NSRect(x: CGFloat(index) * (width + Self.gap), y: 0, width: width, height: bounds.height)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()

            let fill = min(max(filled - CGFloat(index), 0), 1)
            guard fill > 0 else { continue }
            NSColor.labelColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: 0, width: width * fill, height: bounds.height),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
