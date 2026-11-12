import AppKit

/// Takes over the volume and brightness keys, so the notch can act on them and macOS's own
/// pop-up doesn't show as well. This is the one part of the notch's volume and brightness
/// that needs Accessibility permission: macOS only lets a trusted app stand between the
/// keyboard and everything else. Only those keys are looked at; every other key goes
/// straight past, unseen.
final class MediaKeyTap {
    /// A volume or brightness key was pressed or let go (`fine` is Shift and Option held,
    /// for quarter steps). Return true if it was dealt with, and macOS shouldn't see it.
    var handle: ((MediaKey.Press, Bool) -> Bool)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { port != nil }

    /// Starts listening. False if macOS won't allow it (Accessibility isn't granted).
    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        // Only "system-defined" events (type 14), which is how these keys arrive.
        let mask = CGEventMask(1) << 14
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let made = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: mediaKeyTapCallback, userInfo: info) else {
            return false
        }
        let loop = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, made, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), loop, .commonModes)
        CGEvent.tapEnable(tap: made, enable: true)
        port = made
        source = loop
        return true
    }

    func stop() {
        if let port = port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        port = nil
        source = nil
    }

    /// One event from macOS. Returns true to swallow it.
    fileprivate func received(type: CGEventType, event: CGEvent) -> Bool {
        // macOS switches a tap off if it's ever slow to answer: switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return false
        }
        guard type.rawValue == 14, let pressed = NSEvent(cgEvent: event), pressed.type == .systemDefined,
              let press = MediaKey.press(subtype: Int(pressed.subtype.rawValue), data1: pressed.data1) else { return false }
        let fine = pressed.modifierFlags.contains(.shift) && pressed.modifierFlags.contains(.option)
        return handle?(press, fine) ?? false
    }
}

/// What macOS calls with each event. It runs on the main thread, where the tap was added.
private func mediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info = info else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue()
    return tap.received(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
