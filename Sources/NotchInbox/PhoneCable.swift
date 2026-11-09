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
}
