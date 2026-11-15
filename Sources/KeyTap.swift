import AppKit

/// Listens for the keyboard's brightness keys. The handler decides whether the system still sees the key.
final class BrightnessKeyTap {
    struct Press {
        let isUp: Bool
        let isFine: Bool
        let isKeyDown: Bool
    }

    /// Return true to swallow the key so the system does not change the built-in screen.
    var handler: ((Press) -> Bool)?
    private(set) var isRunning = false
    private var tap: CFMachPort?

    private static let systemDefinedType: UInt32 = 14
    private static let auxControlButtonsSubtype: Int16 = 8
    private static let brightnessUpKey = 2
    private static let brightnessDownKey = 3
    private static let keyDownState = 0x0A

    func start() {
        guard !isRunning else { return }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let keyTap = Unmanaged<BrightnessKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
            return keyTap.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.systemDefinedType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlButtonsSubtype else { return Unmanaged.passUnretained(event) }

        let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
        guard keyCode == Self.brightnessUpKey || keyCode == Self.brightnessDownKey else { return Unmanaged.passUnretained(event) }

        let keyState = (nsEvent.data1 & 0xFF00) >> 8
        let press = Press(isUp: keyCode == Self.brightnessUpKey,
                          isFine: nsEvent.modifierFlags.contains([.shift, .option]),
                          isKeyDown: keyState == Self.keyDownState)
        return handler?(press) == true ? nil : Unmanaged.passUnretained(event)
    }
}
