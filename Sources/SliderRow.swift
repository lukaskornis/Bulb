import AppKit

/// A menu row with an icon and a slider. Menu items with custom views draw their own padding.
final class SliderRow: NSView {
    let slider: NSSlider
    var onChange: ((Float) -> Void)?

    init(symbol: String, tooltip: String, value: Float, enabled: Bool) {
        slider = NSSlider(value: Double(value), minValue: 0, maxValue: 1, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
        toolTip = tooltip

        let icon = NSImageView(frame: NSRect(x: 16, y: 6, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        icon.contentTintColor = enabled ? .labelColor : .tertiaryLabelColor

        slider.frame = NSRect(x: 42, y: 5, width: 192, height: 20)
        slider.isContinuous = true
        slider.isEnabled = enabled
        slider.target = self
        slider.action = #selector(sliderMoved)

        addSubview(icon)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func sliderMoved() {
        onChange?(slider.floatValue)
    }
}
