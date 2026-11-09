import Combine
import Foundation
import IOKit

/// Watches for a phone plugged into this Mac by USB cable, using macOS's own notices when a
/// USB device comes or goes (no polling). Wireless connections don't count.
final class PhoneCableWatcher: ObservableObject {
    static let shared = PhoneCableWatcher()

    /// The phone plugged in now ("iPhone", "Pixel 8"), or nil.
    @Published private(set) var phone: String?

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

        var found: String?
        var device = IOIteratorNext(iterator)
        while device != 0 {
            if found == nil {
                let name = (PhoneCableWatcher.property(device, "USB Product Name") ?? PhoneCableWatcher.property(device, "kUSBProductString")) as? String
                let vendor = (PhoneCableWatcher.property(device, "idVendor") as? NSNumber)?.intValue
                if PhoneCable.isPhone(name: name, vendor: vendor) {
                    found = PhoneCable.displayName(name)
                }
            }
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
        if phone != found {
            phone = found
        }
    }

    private static func property(_ device: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(device, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
