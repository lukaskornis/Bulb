import AppKit
import os
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let hud = BrightnessHUD()
    private let group = ScreenGroup()
    private var allRow: SliderRow?
    private var reloadWork: DispatchWorkItem?

    private static let ownWriteTolerance: Float = 0.001
    private static let log = Logger(subsystem: "local.bulb", category: "keys")
    private static let screenChangeSettleSeconds = 1.0
    private static let keysChangeAllScreensKey = "keysChangeAllScreens"
    private static let keepRatiosKey = "keepRatios"

    private var keysChangeAllScreens: Bool {
        get { UserDefaults.standard.bool(forKey: Self.keysChangeAllScreensKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.keysChangeAllScreensKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.keysChangeAllScreensKey: true, Self.keepRatiosKey: false])
        group.keepsRatios = UserDefaults.standard.bool(forKey: Self.keepRatiosKey)

        statusItem.button?.image = BulbIcon.image()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleScreenReload()
        }

        rebuildMenu()
        reloadScreens()
    }

    // MARK: Keys

    /// macOS handles the brightness keys inside the keyboard driver, so no app ever sees them.
    /// Bulb reacts to the built-in screen's change instead and passes the step on to the others.
    private func builtInChangedElsewhere() {
        guard let builtIn = group.screens.first(where: \.isBuiltIn),
              let value = BuiltInBrightness.get(builtIn.id) else { return }
        let previous = builtIn.brightness
        // Bulb's own writes update the model first, so they arrive here already matching.
        guard abs(value - previous) > Self.ownWriteTolerance else { return }
        Self.log.info("Built-in changed \(previous, privacy: .public) -> \(value, privacy: .public)")

        builtIn.reload()
        guard keysChangeAllScreens else {
            group.captureRatios()
            return
        }
        group.follow(builtIn, delta: value - previous)
        showHUD(for: group.controllable.filter { !$0.isBuiltIn })
    }

    private func showHUD(for screens: [Screen]) {
        for nsScreen in NSScreen.screens {
            guard let screen = screens.first(where: { $0.id == nsScreen.displayID }) else { continue }
            hud.show(screen.brightness, on: nsScreen)
        }
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
            guard let self else { return }
            self.group.screens = screens
            if let builtIn = screens.first(where: \.isBuiltIn) {
                BuiltInBrightness.observeChanges(builtIn.id) { [weak self] in self?.builtInChangedElsewhere() }
            }
            self.rebuildMenu()
        }
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        group.screens.forEach { $0.reload() }
        menu.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) })?.state = launchAtLoginState
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let all = SliderRow(symbol: "sun.max.fill", tooltip: "All screens", value: group.level, enabled: !group.controllable.isEmpty)
        all.onChange = { [weak self] value in self?.group.setLevel(value) }
        allRow = all
        menu.addItem(viewItem(all))
        menu.addItem(.separator())

        for screen in group.screens {
            let symbol = screen.isBuiltIn ? "laptopcomputer" : "display"
            let tooltip = screen.isControllable ? screen.name : "\(screen.name): no brightness control"
            let row = SliderRow(symbol: symbol, tooltip: tooltip, value: screen.brightness, enabled: screen.isControllable)
            row.onChange = { [weak self, weak screen] value in
                screen?.set(value)
                self?.group.captureRatios()
            }
            screen.onBrightnessChange = { [weak self, weak row] value in
                row?.slider.floatValue = value
                if let self { self.allRow?.slider.floatValue = self.group.level }
            }
            menu.addItem(viewItem(row))
        }
        menu.addItem(.separator())

        let allScreens = NSMenuItem(title: "Keys Change All Screens", action: #selector(toggleKeysChangeAllScreens), keyEquivalent: "")
        allScreens.target = self
        allScreens.state = keysChangeAllScreens ? .on : .off
        menu.addItem(allScreens)
        if keysChangeAllScreens {
            let ratios = NSMenuItem(title: "Keep Brightness Ratios", action: #selector(toggleKeepRatios), keyEquivalent: "")
            ratios.target = self
            ratios.state = group.keepsRatios ? .on : .off
            ratios.indentationLevel = 1
            menu.addItem(ratios)
        }
        menu.addItem(.separator())

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

    @objc private func toggleKeysChangeAllScreens() {
        keysChangeAllScreens.toggle()
        rebuildMenu()
    }

    @objc private func toggleKeepRatios() {
        group.keepsRatios.toggle()
        UserDefaults.standard.set(group.keepsRatios, forKey: Self.keepRatiosKey)
        rebuildMenu()
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
