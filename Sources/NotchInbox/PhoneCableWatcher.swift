import Combine
import Foundation
import IOKit

/// Watches for a phone plugged into this Mac by USB cable, using macOS's own notices when a
/// USB device comes or goes (no polling). Wireless connections don't count.
final class PhoneCableWatcher: ObservableObject {
    static let shared = PhoneCableWatcher()

    /// The phone plugged in now ("iPhone", "Pixel 8"), or nil.
    @Published private(set) var phone: String?
    /// What the Mac can tell about it: its maker, how fast the cable is, and for an iPhone
    /// its battery, if libimobiledevice is installed.
    @Published private(set) var details: PhoneDetails?

    /// Asking for the battery happens off the main thread.
    private let batteryQueue = DispatchQueue(label: "NotchInbox.PhoneBattery", qos: .utility)
    private var batteryTimer: Timer?

    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let me = Unmanaged.passUnretained(self).toOpaque()
        let changed: IOServiceMatchingCallback = { context, iterator in
            guard let context = context else { return }
            let watcher = Unmanaged<PhoneCableWatcher>.fromOpaque(context).takeUnretainedValue()
            PhoneCableWatcher.drain(iterator)
            watcher.refresh()
        }
        // Each notice has to be emptied once to start it.
        if IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"),
                                            changed, me, &added) == KERN_SUCCESS {
            PhoneCableWatcher.drain(added)
        }
        if IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"),
                                            changed, me, &removed) == KERN_SUCCESS {
            PhoneCableWatcher.drain(removed)
        }
        refresh()
    }

    deinit {
        if added != 0 { IOObjectRelease(added) }
        if removed != 0 { IOObjectRelease(removed) }
        if let port = port { IONotificationPortDestroy(port) }
    }

    private static func drain(_ iterator: io_iterator_t) {
        var device = IOIteratorNext(iterator)
        while device != 0 {
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
    }

    /// Looks through the USB devices plugged in now for a phone.
    private func refresh() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var found: PhoneDetails?
        var device = IOIteratorNext(iterator)
        while device != 0 {
            if found == nil {
                let name = (PhoneCableWatcher.property(device, "USB Product Name") ?? PhoneCableWatcher.property(device, "kUSBProductString")) as? String
                let vendor = (PhoneCableWatcher.property(device, "idVendor") as? NSNumber)?.intValue
                if PhoneCable.isPhone(name: name, vendor: vendor) {
                    let maker = (PhoneCableWatcher.property(device, "USB Vendor Name") ?? PhoneCableWatcher.property(device, "kUSBVendorString")) as? String
                    let speed = (PhoneCableWatcher.property(device, "Device Speed") as? NSNumber)?.intValue
                    found = PhoneDetails(name: PhoneCable.displayName(name),
                                         maker: (maker ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                         speed: PhoneCable.speedName(speed))
                }
            }
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
        if phone != found?.name {
            phone = found?.name
        }
        // Keep a battery reading for the same phone; a different phone starts afresh.
        var next = found
        if next?.name == details?.name {
            next?.battery = details?.battery
        }
        if details != next {
            details = next
        }
        watchBattery(found != nil && (found?.name.lowercased().contains("iphone") ?? false))
    }

    // MARK: Battery (iPhone, with libimobiledevice)

    /// Where `ideviceinfo` is, if it's installed.
    static var batteryTool: String? {
        PhoneCable.batteryToolPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Asks an iPhone for its battery level now and every few minutes while it's plugged in.
    /// Only works if you've installed libimobiledevice and the phone trusts this Mac.
    private func watchBattery(_ on: Bool) {
        guard on, PhoneCableWatcher.batteryTool != nil else {
            batteryTimer?.invalidate()
            batteryTimer = nil
            return
        }
        guard batteryTimer == nil else { return }
        let timer = Timer(timeInterval: 180, repeats: true) { [weak self] _ in
            self?.readBattery()
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
        readBattery()
    }

    private func readBattery() {
        guard let tool = PhoneCableWatcher.batteryTool else { return }
        batteryQueue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = ["-q", "com.apple.mobile.battery"]
            let output = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            // It answers at once, or not at all (a phone that's locked and hasn't trusted this Mac).
            let deadline = Date().addingTimeInterval(8)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                return
            }
            let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
            let battery = PhoneCable.battery(fromToolOutput: String(decoding: data.prefix(4000), as: UTF8.self))
            DispatchQueue.main.async {
                guard let self = self, var current = self.details, current.battery != battery, battery != nil else { return }
                current.battery = battery
                self.details = current
            }
        }
    }

    private static func property(_ device: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(device, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
