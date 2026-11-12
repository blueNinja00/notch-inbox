import AppKit
import Combine
import CoreAudio

/// The Mac's output volume: read it, set it, and hear when it changes. This is the same
/// volume the keyboard's keys and Control Centre change, and it needs no permission.
final class VolumeControl {
    /// The volume, the mute switch or the output device changed.
    var onChange: (() -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var deviceListeners: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var started = false

    /// The "virtual main volume" ('vmvc'): one volume for the whole device, as the menu
    /// bar's slider uses, whatever channels the device really has.
    private static let virtualVolume: AudioObjectPropertySelector = 0x766D_7663

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func start() {
        guard !started else { return }
        started = true
        // A different output (headphones plugged in, say): follow it.
        var address = VolumeControl.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attach()
            self?.onChange?()
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block) == noErr {
            systemListener = block
        }
        attach()
    }

    func stop() {
        guard started else { return }
        started = false
        detach()
        if let block = systemListener {
            var address = VolumeControl.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
            systemListener = nil
        }
        device = AudioDeviceID(kAudioObjectUnknown)
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var address = VolumeControl.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var found = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &found)
        return status == noErr && found != AudioDeviceID(kAudioObjectUnknown) ? found : nil
    }

    /// Listens to the output device in use now.
    private func attach() {
        detach()
        guard let output = VolumeControl.defaultOutput() else {
            device = AudioDeviceID(kAudioObjectUnknown)
            return
        }
        device = output
        // Devices differ in which of these they announce, so listen for each one they have.
        var wanted = [VolumeControl.address(VolumeControl.virtualVolume), VolumeControl.address(kAudioDevicePropertyMute)]
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            wanted.append(VolumeControl.address(kAudioDevicePropertyVolumeScalar, element: element))
        }
        for candidate in wanted {
            var address = candidate
            guard AudioObjectHasProperty(output, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.onChange?()
            }
            if AudioObjectAddPropertyListenerBlock(output, &address, DispatchQueue.main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func detach() {
        for listener in deviceListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listener.block)
        }
        deviceListeners = []
    }

    private func float(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Float32? {
        var address = VolumeControl.address(selector, element: element)
        guard device != AudioDeviceID(kAudioObjectUnknown), AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func setFloat(_ value: Float32, _ selector: AudioObjectPropertySelector,
                          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = VolumeControl.address(selector, element: element)
        guard device != AudioDeviceID(kAudioObjectUnknown), AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var wanted = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &wanted) == noErr
    }

    private var isMuted: Bool {
        var address = VolumeControl.address(kAudioDevicePropertyMute)
        guard device != AudioDeviceID(kAudioObjectUnknown), AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    /// The volume now, or nil if this output has no volume of its own (some screens and
    /// audio interfaces don't).
    func read() -> LevelReading? {
        if let whole = float(VolumeControl.virtualVolume) ?? float(kAudioDevicePropertyVolumeScalar) {
            return LevelReading(kind: .volume, value: Double(whole), muted: isMuted)
        }
        let channels = [float(kAudioDevicePropertyVolumeScalar, element: 1), float(kAudioDevicePropertyVolumeScalar, element: 2)].compactMap { $0 }
        guard !channels.isEmpty else { return nil }
        let average = channels.reduce(0, +) / Float32(channels.count)
        return LevelReading(kind: .volume, value: Double(average), muted: isMuted)
    }

    /// Sets the volume. Returns false if this output's volume can't be set.
    @discardableResult
    func set(_ value: Double) -> Bool {
        let wanted = Float32(min(max(value, 0), 1))
        if setFloat(wanted, VolumeControl.virtualVolume) || setFloat(wanted, kAudioDevicePropertyVolumeScalar) {
            return true
        }
        let left = setFloat(wanted, kAudioDevicePropertyVolumeScalar, element: 1)
        let right = setFloat(wanted, kAudioDevicePropertyVolumeScalar, element: 2)
        return left || right
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        var address = VolumeControl.address(kAudioDevicePropertyMute)
        guard device != AudioDeviceID(kAudioObjectUnknown), AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

/// The built-in display's brightness. macOS has no public way to read or set it, so this
/// uses DisplayServices, a framework of macOS's own, found by name when the app starts.
/// If a future macOS drops it, brightness simply isn't shown; nothing else is affected.
final class BrightnessControl {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getter: Getter?
    private let setter: Setter?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle = handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getter = unsafeBitCast(symbol, to: Getter.self)
        } else {
            getter = nil
        }
        if let handle = handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
            setter = unsafeBitCast(symbol, to: Setter.self)
        } else {
            setter = nil
        }
    }

    /// The MacBook's own screen, if it's on (not shut, with a monitor plugged in).
    private static var builtIn: CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// The brightness now, or nil if there's no built-in screen to ask.
    func read() -> LevelReading? {
        guard let getter = getter, let display = BrightnessControl.builtIn else { return nil }
        var value: Float = 0
        guard getter(display, &value) == 0, value.isFinite else { return nil }
        return LevelReading(kind: .brightness, value: Double(value))
    }

    @discardableResult
    func set(_ value: Double) -> Bool {
        guard let setter = setter, let display = BrightnessControl.builtIn else { return false }
        return setter(display, Float(min(max(value, 0), 1))) == 0
    }
}

/// Keeps an eye on the volume and the brightness for the notch: publishes what they are,
/// says when a change is worth showing, and changes them when you drag a slider (or, with
/// the keys taken over, when you press one).
final class LevelsWatcher: ObservableObject {
    static let shared = LevelsWatcher()

    @Published private(set) var volume: LevelReading?
    @Published private(set) var brightness: LevelReading?

    /// A level changed in a way worth showing at the notch.
    var onShow: ((LevelReading) -> Void)?
    /// Whether a level is on show at the notch right now (set by the app): it then follows every change.
    var showing: LevelKind?

    private let sound = VolumeControl()
    private let screen = BrightnessControl()
    private var watch = LevelWatch()
    private var timer: Timer?
    private var keyMonitor: Any?
    private var quickUntil = Date.distantPast
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        sound.onChange = { [weak self] in
            self?.readVolume()
        }
        sound.start()
        readVolume()
        readBrightness()
        // Brightness has no way to say it changed, so it's looked at a few times a second:
        // a tiny question to macOS each time.
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.readBrightness()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Where macOS lets the app see the keys being pressed, the notch answers at once.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let press = MediaKey.press(subtype: Int(event.subtype.rawValue), data1: event.data1), press.down else { return }
            self?.sawKey(press.key)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sound.stop()
        sound.onChange = nil
        timer?.invalidate()
        timer = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        watch = LevelWatch()
        volume = nil
        brightness = nil
    }

    private func take(_ reading: LevelReading?, own: Bool = false, pressed: Bool = false) {
        guard let reading = reading else { return }
        let show = watch.take(reading, own: own, pressed: pressed, showing: showing == reading.kind)
        switch reading.kind {
        case .volume:
            if volume != reading { volume = reading }
        case .brightness:
            if brightness != reading { brightness = reading }
        }
        if show {
            onShow?(reading)
        }
    }

    private func readVolume(own: Bool = false, pressed: Bool = false) {
        let reading = sound.read()
        if reading == nil && volume != nil {
            volume = nil
        }
        take(reading, own: own, pressed: pressed)
    }

    private func readBrightness(own: Bool = false, pressed: Bool = false) {
        let reading = screen.read()
        if reading == nil && brightness != nil {
            brightness = nil
        }
        take(reading, own: own, pressed: pressed)
    }

    /// A key was pressed and macOS is dealing with it: look again as it takes effect.
    private func sawKey(_ key: MediaKey) {
        for delay in [0.03, 0.12, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isRunning else { return }
                if key.kind == .volume {
                    self.readVolume(pressed: delay == 0.03)
                } else {
                    self.readBrightness(pressed: delay == 0.03)
                }
            }
        }
    }

    // MARK: Changing them from the notch

    /// From the volume slider.
    func setVolume(_ value: Double) {
        guard sound.set(value) else { return }
        if value > 0, volume?.muted == true {
            sound.setMuted(false)
        }
        readVolume(own: true)
    }

    func toggleMute() {
        guard let now = volume, sound.setMuted(!now.muted) else { return }
        readVolume(own: true)
    }

    /// From the brightness slider.
    func setBrightness(_ value: Double) {
        guard screen.set(value) else { return }
        readBrightness(own: true)
    }

    /// With the keys taken over: does what the key does, and shows it. Returns false if
    /// there's nothing here to change, so the key should go on to macOS as usual.
    func press(_ key: MediaKey, fine: Bool) -> Bool {
        switch key.kind {
        case .volume:
            guard let now = sound.read(), let next = LevelWatch.after(key, from: now, fine: fine) else { return false }
            if key == .mute {
                guard sound.setMuted(next.muted) else { return false }
            } else {
                guard sound.set(next.value) else { return false }
                if now.muted {
                    sound.setMuted(false)
                }
            }
            readVolume(pressed: true)
            return true
        case .brightness:
            // With another screen plugged in, the keys may be meant for it: leave them to macOS.
            guard NSScreen.screens.count == 1, let now = screen.read(), let next = LevelWatch.after(key, from: now, fine: fine),
                  screen.set(next.value) else { return false }
            readBrightness(pressed: true)
            return true
        }
    }

    /// Whether the keys for this level can be taken over right now.
    func canChange(_ kind: LevelKind) -> Bool {
        switch kind {
        case .volume: return sound.read() != nil
        case .brightness: return NSScreen.screens.count == 1 && screen.read() != nil
        }
    }
}
