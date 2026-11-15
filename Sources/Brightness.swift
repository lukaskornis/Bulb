import AppKit
import IOKit

typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ length: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ length: UInt32) -> IOReturn

/// DDC/CI over the Apple Silicon display pipe. VCP 0x10 is luminance.
enum DDC {
    struct ExternalService {
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32
        let service: IOAVService
    }

    private static let chipAddress: UInt32 = 0x37
    private static let hostAddress: UInt8 = 0x51
    private static let displayAddress: UInt8 = 0x6E
    private static let luminance: UInt8 = 0x10
    private static let replyDelayMicroseconds: useconds_t = 40_000

    static func readBrightness(_ service: IOAVService) -> (current: UInt16, max: UInt16)? {
        for _ in 0..<3 {
            var request: [UInt8] = [0x82, 0x01, luminance, 0]
            request[3] = checksum(request.dropLast())
            guard IOAVServiceWriteI2C(service, chipAddress, UInt32(hostAddress), &request, UInt32(request.count)) == kIOReturnSuccess else { continue }
            usleep(replyDelayMicroseconds)

            var reply = [UInt8](repeating: 0, count: 12)
            guard IOAVServiceReadI2C(service, chipAddress, UInt32(hostAddress), &reply, UInt32(reply.count)) == kIOReturnSuccess else { continue }
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == luminance else { continue }

            let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            guard max > 0 else { continue }
            return (min(current, max), max)
        }
        return nil
    }

    @discardableResult
    static func writeBrightness(_ service: IOAVService, _ value: UInt16) -> Bool {
        var packet: [UInt8] = [0x84, 0x03, luminance, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = checksum(packet.dropLast())
        return IOAVServiceWriteI2C(service, chipAddress, UInt32(hostAddress), &packet, UInt32(packet.count)) == kIOReturnSuccess
    }

    private static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(displayAddress ^ hostAddress, ^)
    }

    /// Each external DCPAVServiceProxy follows its framebuffer's DisplayAttributes in registry order,
    /// which is how the service gets paired with an EDID identity.
    static func externalServices() -> [ExternalService] {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var services: [ExternalService] = []
        var lastAttributes: [String: Any] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let attributes = property(entry, "DisplayAttributes") as? [String: Any],
               let product = attributes["ProductAttributes"] as? [String: Any] {
                lastAttributes = product
                continue
            }
            guard IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0,
                  property(entry, "Location") as? String == "External",
                  let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            services.append(ExternalService(
                vendor: (lastAttributes["LegacyManufacturerID"] as? NSNumber)?.uint32Value ?? 0,
                model: (lastAttributes["ProductID"] as? NSNumber)?.uint32Value ?? 0,
                serial: (lastAttributes["SerialNumber"] as? NSNumber)?.uint32Value ?? 0,
                service: service))
        }
        return services
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// The built-in panel, through the private DisplayServices framework.
enum BuiltInBrightness {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getter: Getter? = symbol("DisplayServicesGetBrightness")
    private static let setter: Setter? = symbol("DisplayServicesSetBrightness")

    static func get(_ id: CGDirectDisplayID) -> Float? {
        guard let getter else { return nil }
        var value: Float = 0
        return getter(id, &value) == 0 ? value : nil
    }

    static func set(_ id: CGDirectDisplayID, _ value: Float) {
        _ = setter?(id, value)
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

final class Screen {
    enum Control {
        case builtIn
        case ddc(IOAVService, max: UInt16)
        case none
    }

    let id: CGDirectDisplayID
    let name: String
    let control: Control
    private(set) var brightness: Float
    var onBrightnessChange: ((Float) -> Void)?

    var isBuiltIn: Bool { if case .builtIn = control { return true } else { return false } }
    var isControllable: Bool { if case .none = control { return false } else { return true } }

    private static let ddcQueue = DispatchQueue(label: "bulb.ddc")
    private var pendingDDCValue: UInt16?
    private var isWritingDDC = false

    init(id: CGDirectDisplayID, name: String, control: Control, brightness: Float) {
        self.id = id
        self.name = name
        self.control = control
        self.brightness = brightness
    }

    func set(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        brightness = clamped
        onBrightnessChange?(clamped)
        switch control {
        case .builtIn:
            BuiltInBrightness.set(id, clamped)
        case .ddc(_, let max):
            pendingDDCValue = UInt16((clamped * Float(max)).rounded())
            flushDDC()
        case .none:
            break
        }
    }

    /// Picks up changes made elsewhere: the system's own keys, or the monitor's buttons.
    func reload() {
        switch control {
        case .builtIn:
            guard let value = BuiltInBrightness.get(id) else { return }
            brightness = value
            onBrightnessChange?(value)
        case .ddc(let service, _):
            Screen.ddcQueue.async {
                guard let reading = DDC.readBrightness(service) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isWritingDDC else { return }
                    self.brightness = Float(reading.current) / Float(reading.max)
                    self.onBrightnessChange?(self.brightness)
                }
            }
        case .none:
            break
        }
    }

    /// Monitors drop DDC writes when flooded, so a slider drag only ever sends the latest value.
    private func flushDDC() {
        guard !isWritingDDC, let value = pendingDDCValue, case .ddc(let service, _) = control else { return }
        pendingDDCValue = nil
        isWritingDDC = true
        Screen.ddcQueue.async {
            DDC.writeBrightness(service, value)
            DispatchQueue.main.async { [weak self] in
                self?.isWritingDDC = false
                self?.flushDDC()
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

enum ScreenCatalog {
    /// Screens ordered left to right as arranged. DDC reads are slow, so the work runs off the main thread.
    static func load(completion: @escaping ([Screen]) -> Void) {
        let found = NSScreen.screens
            .sorted { $0.frame.minX < $1.frame.minX }
            .map { (id: $0.displayID, name: $0.localizedName) }

        let externalCount = found.filter { CGDisplayIsBuiltin($0.id) == 0 }.count

        DispatchQueue.global(qos: .userInitiated).async {
            var unmatched = DDC.externalServices()
            var screens: [Screen] = []
            for (id, name) in found {
                if CGDisplayIsBuiltin(id) != 0 {
                    screens.append(Screen(id: id, name: name, control: .builtIn, brightness: BuiltInBrightness.get(id) ?? 1))
                    continue
                }
                guard let index = matchIndex(for: id, in: unmatched, externalCount: externalCount),
                      let reading = DDC.readBrightness(unmatched[index].service) else {
                    screens.append(Screen(id: id, name: name, control: .none, brightness: 1))
                    continue
                }
                let service = unmatched.remove(at: index).service
                screens.append(Screen(id: id, name: name, control: .ddc(service, max: reading.max),
                                      brightness: Float(reading.current) / Float(reading.max)))
            }
            DispatchQueue.main.async { completion(screens) }
        }
    }

    private static func matchIndex(for id: CGDirectDisplayID, in services: [DDC.ExternalService], externalCount: Int) -> Int? {
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)
        if let exact = services.firstIndex(where: {
            $0.vendor == vendor && $0.model == model && (serial == 0 || $0.serial == 0 || $0.serial == serial)
        }) {
            return exact
        }
        return services.count == 1 && externalCount == 1 ? 0 : nil
    }
}
