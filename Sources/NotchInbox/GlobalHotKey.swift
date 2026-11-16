import AppKit
import Carbon.HIToolbox

/// One key that works in every app, even while another app is in front: the key that
/// opens the notch.
///
/// It's registered with macOS as a hot key, the way launchers do it. That needs no
/// Accessibility permission, because the app doesn't watch your typing: macOS tells it
/// when this one key is pressed, and about nothing else.
final class GlobalHotKey {
    /// What to do when it's pressed (on the main thread).
    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// "NIhk": marks the hot keys that are this app's.
    fileprivate static let signature: OSType = 0x4E49_686B

    deinit {
        unregister()
        if let handler = handler {
            RemoveEventHandler(handler)
        }
    }

    /// Makes `combo` the key (or none, for nil). Returns why it couldn't be, if it couldn't.
    @discardableResult
    func register(_ combo: KeyCombo?) -> String? {
        unregister()
        guard let combo = combo else { return nil }
        guard installHandler() else {
            return "\(combo.label) couldn't be set up to work from any app. Quitting and opening Notch Inbox again may help."
        }
        var made: EventHotKeyRef?
        let id = EventHotKeyID(signature: GlobalHotKey.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(combo.code), combo.carbonModifiers, id, GetEventDispatcherTarget(),
                                         OptionBits(kEventHotKeyExclusive), &made)
        guard status == noErr, let registered = made else {
            if status == OSStatus(eventHotKeyExistsErr) {
                return "Another app already uses \(combo.label), so it can't open the notch. Pick another key for it."
            }
            return "\(combo.label) couldn't be set up to work from any app (macOS said \(status)). Pick another key for it."
        }
        hotKey = registered
        return nil
    }

    func unregister() {
        if let hotKey = hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
    }

    /// Asks macOS to say when one of this app's hot keys is pressed. Once is enough.
    private func installHandler() -> Bool {
        if handler != nil {
            return true
        }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetEventDispatcherTarget(), globalHotKeyPressed, 1, &pressed, me, &handler)
        return status == noErr
    }

    fileprivate func pressed() {
        DispatchQueue.main.async { [weak self] in
            self?.onPress?()
        }
    }
}

/// macOS calls this when a hot key is pressed. It passes the press on if the key is this app's.
private func globalHotKeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, id.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().pressed()
    return noErr
}
