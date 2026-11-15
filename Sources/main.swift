import AppKit
import ServiceManagement

/// A menu row with an icon and a slider. Menu items with custom views draw their own padding.
private final class SliderRow: NSView {
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let keyTap = BrightnessKeyTap()
    private let hud = BrightnessHUD()
    private var screens: [Screen] = []
    private var allRow: SliderRow?
    private var reloadWork: DispatchWorkItem?

    private static let step: Float = 1.0 / 16
    private static let fineStep: Float = 1.0 / 64
    private static let screenChangeSettleSeconds = 1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "Bulb")
        menu.delegate = self
        statusItem.menu = menu

        keyTap.handler = { [weak self] press in self?.handleKey(press) ?? false }
        keyTap.start()
        if !keyTap.isRunning { requestAccessibility() }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleScreenReload()
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            // The trust list is written just after this notification fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.retryKeyTap() }
        }

        rebuildMenu()
        reloadScreens()
    }

    // MARK: Keys

    private func handleKey(_ press: BrightnessKeyTap.Press) -> Bool {
        let mouse = NSEvent.mouseLocation
        guard let nsScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let screen = screens.first(where: { $0.id == nsScreen.displayID }),
              !screen.isBuiltIn, screen.isControllable else { return false }
        guard press.isKeyDown else { return true }

        let step = press.isFine ? Self.fineStep : Self.step
        let snapped = (screen.brightness / step).rounded() + (press.isUp ? 1 : -1)
        screen.set(snapped * step)
        hud.show(screen.brightness, on: nsScreen)
        return true
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func retryKeyTap() {
        keyTap.start()
        rebuildMenu()
    }

    // MARK: Screens

    private func scheduleScreenReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadScreens() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.screenChangeSettleSeconds, execute: work)
    }

    private func reloadScreens() {
        ScreenCatalog.load { [weak self] screens in
            self?.screens = screens
            self?.rebuildMenu()
        }
    }

    private var averageBrightness: Float {
        let controllable = screens.filter(\.isControllable)
        guard !controllable.isEmpty else { return 1 }
        return controllable.map(\.brightness).reduce(0, +) / Float(controllable.count)
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        screens.forEach { $0.reload() }
        statusItem.menu?.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) })?.state = launchAtLoginState
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let all = SliderRow(symbol: "sun.max.fill", tooltip: "All screens", value: averageBrightness,
                            enabled: screens.contains(where: \.isControllable))
        all.onChange = { [weak self] value in self?.screens.filter(\.isControllable).forEach { $0.set(value) } }
        allRow = all
        menu.addItem(viewItem(all))
        menu.addItem(.separator())

        for screen in screens {
            let symbol = screen.isBuiltIn ? "laptopcomputer" : "display"
            let tooltip = screen.isControllable ? screen.name : "\(screen.name): no brightness control"
            let row = SliderRow(symbol: symbol, tooltip: tooltip, value: screen.brightness, enabled: screen.isControllable)
            row.onChange = { [weak screen] value in screen?.set(value) }
            screen.onBrightnessChange = { [weak self, weak row] value in
                row?.slider.floatValue = value
                if let self { self.allRow?.slider.floatValue = self.averageBrightness }
            }
            menu.addItem(viewItem(row))
        }
        menu.addItem(.separator())

        if !keyTap.isRunning {
            menu.addItem(withTitle: "Allow Brightness Keys…", action: #selector(openAccessibilitySettings), keyEquivalent: "").target = self
        }
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLoginState
        menu.addItem(login)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private var launchAtLoginState: NSControl.StateValue {
        SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Bulb: launch at login failed: \(error.localizedDescription)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
