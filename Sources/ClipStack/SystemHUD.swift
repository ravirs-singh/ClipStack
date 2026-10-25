import AppKit
import CoreAudio
import AudioToolbox

/// Watches output volume, display brightness and Caps Lock so the notch can show a HUD when they change.
/// No key interception needed: volume uses a CoreAudio property listener, brightness is polled.
final class SystemHUD {
    static let changed = Notification.Name("ClipStackHUD")
    enum Kind { case volume, brightness, capsLock }
    struct Event { let kind: Kind; let level: Double; let on: Bool }   // level 0…1 (volume/brightness), on for caps lock

    private var lastVolume: Double = -1
    private var muted = false
    private var lastBrightness: Double = -1
    private var capsOn = false
    private var poll: Timer?
    private var flagsMonitor: Any?
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var settingsObserver: NSObjectProtocol?
    private var armed = false   // ignore the first readings so launch doesn't flash a HUD

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private var getBrightness: GetBrightness?

    init() {
        if let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
           let sym = dlsym(h, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(sym, to: GetBrightness.self)
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in self?.applyEnabled() }
        applyEnabled()
    }

    private func applyEnabled() {
        stop()
        guard Settings.hudEnabled else { return }
        armed = false
        setupVolume()
        poll = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.armed = true }
    }

    private func stop() {
        poll?.invalidate(); poll = nil
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if deviceID != kAudioObjectUnknown, let block = listenerBlock {
            var addr = Self.volumeAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
            var maddr = Self.muteAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &maddr, DispatchQueue.main, block)
        }
        listenerBlock = nil
    }

    // MARK: Volume (CoreAudio)

    private static var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    private func setupVolume() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var dev = AudioObjectID(kAudioObjectUnknown)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != kAudioObjectUnknown else { return }
        deviceID = dev
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
        listenerBlock = block
        var vaddr = Self.volumeAddress
        AudioObjectAddPropertyListenerBlock(dev, &vaddr, DispatchQueue.main, block)
        var maddr = Self.muteAddress
        AudioObjectAddPropertyListenerBlock(dev, &maddr, DispatchQueue.main, block)
        lastVolume = currentVolume()
        muted = isMuted()
    }

    private func currentVolume() -> Double {
        var addr = Self.volumeAddress
        var v: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &v) == noErr ? Double(v) : -1
    }

    private func isMuted() -> Bool {
        var addr = Self.muteAddress
        var m: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &m) == noErr && m == 1
    }

    private func volumeChanged() {
        let v = currentVolume(), m = isMuted()
        guard armed, abs(v - lastVolume) > 0.001 || m != muted else { lastVolume = v; muted = m; return }
        lastVolume = v; muted = m
        NotificationCenter.default.post(name: Self.changed, object: self, userInfo: ["event": Event(kind: .volume, level: m ? 0 : v, on: !m)])
    }

    // MARK: Brightness (polled)

    private func tick() {
        guard let get = getBrightness else { return }
        var b: Float = 0
        guard get(CGMainDisplayID(), &b) == 0 else { return }
        let v = Double(b)
        if lastBrightness < 0 { lastBrightness = v; return }
        guard armed, abs(v - lastBrightness) > 0.005 else { return }
        lastBrightness = v
        NotificationCenter.default.post(name: Self.changed, object: self, userInfo: ["event": Event(kind: .brightness, level: v, on: true)])
    }

    // MARK: Caps Lock

    private func flags(_ e: NSEvent) {
        let on = e.modifierFlags.contains(.capsLock)
        guard on != capsOn else { return }
        capsOn = on
        guard armed else { return }
        NotificationCenter.default.post(name: Self.changed, object: self, userInfo: ["event": Event(kind: .capsLock, level: on ? 1 : 0, on: on)])
    }
}
