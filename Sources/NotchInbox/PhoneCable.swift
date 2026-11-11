import Foundation

/// Which USB devices count as a phone plugged in by cable. Kept apart from the watcher so it
/// can be checked anywhere.
enum PhoneCable {
    static let appleVendor = 0x05AC

    /// Makers whose USB devices are (nearly) always phones.
    static let phoneVendors: Set<Int> = [
        0x18D1, // Google (Pixel)
        0x2717, // Xiaomi
        0x2A70, // OnePlus
        0x22B8, // Motorola
        0x12D1, // Huawei
        0x22D9, // OPPO
        0x2D95, // vivo
        0x0FCE, // Sony Mobile
        0x1004, // LG
        0x0BB4, // HTC
        0x19D2, // ZTE
        0x2B0E, // Nothing / Realme
    ]

    /// An iPhone, or an Android phone. (A Samsung SSD has Samsung's vendor ID too, so for
    /// makers of other things as well, the name has to say phone.)
    static func isPhone(name: String?, vendor: Int?) -> Bool {
        let lower = (name ?? "").lowercased()
        if lower.contains("iphone") { return true }
        if vendor == appleVendor { return false } // iPads, keyboards, adapters
        if let vendor = vendor, phoneVendors.contains(vendor) { return true }
        return ["android", "galaxy", "pixel", "phone"].contains { lower.contains($0) }
    }

    /// The name to show: "iPhone", "Pixel 8", or just "Phone".
    static func displayName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased().contains("android") {
            return "Phone"
        }
        return trimmed.replacingOccurrences(of: "_", with: " ")
    }

    /// How fast the cable is, from USB's speed number: "USB 2 (480 Mb/s)".
    static func speedName(_ speed: Int?) -> String? {
        switch speed {
        case 0?: return "USB 1 (1.5 Mb/s)"
        case 1?: return "USB 1 (12 Mb/s)"
        case 2?: return "USB 2 (480 Mb/s)"
        case 3?: return "USB 3 (5 Gb/s)"
        case 4?: return "USB 3 (10 Gb/s)"
        case 5?: return "USB 3 (20 Gb/s)"
        default: return nil
        }
    }

    /// Where libimobiledevice's `ideviceinfo` usually is, if you've installed it (with
    /// Homebrew). It's the only way to ask an iPhone for its battery level over the cable.
    static let batteryToolPaths = ["/opt/homebrew/bin/ideviceinfo", "/usr/local/bin/ideviceinfo"]

    /// Reads what `ideviceinfo -q com.apple.mobile.battery` prints: "BatteryCurrentCapacity: 87"
    /// and "BatteryIsCharging: true".
    static func battery(fromToolOutput output: String) -> PhoneDetails.Battery? {
        var level: Int?
        var charging = false
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "BatteryCurrentCapacity": level = Int(parts[1])
            case "BatteryIsCharging": charging = parts[1].lowercased() == "true"
            default: break
            }
        }
        guard let percent = level, (0...100).contains(percent) else { return nil }
        return PhoneDetails.Battery(percent: percent, charging: charging)
    }
}

/// What the Mac can tell about the phone on the cable.
struct PhoneDetails: Equatable {
    struct Battery: Equatable {
        var percent: Int
        var charging: Bool

        /// "87%, charging".
        var text: String { "\(percent)%" + (charging ? ", charging" : "") }
    }

    /// "iPhone", "Pixel 8".
    var name: String
    /// "Apple Inc.", "Google".
    var maker: String = ""
    /// "USB 2 (480 Mb/s)".
    var speed: String?
    /// Only known for an iPhone, with libimobiledevice installed and the phone trusting this Mac.
    var battery: Battery?
}
