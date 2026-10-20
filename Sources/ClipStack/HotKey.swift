import Carbon.HIToolbox
import Foundation

/// Global hotkey via Carbon RegisterEventHotKey — works without Accessibility permission.
/// Reads its binding from Settings and re-registers when settings change.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private var settingsObserver: NSObjectProtocol?

    init(handler: @escaping () -> Void) {
        self.handler = handler

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().handler()
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)

        register()
        settingsObserver = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.register()
        }
    }

    private func register() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5350) /* "CLSP" */, id: 1)
        let status = RegisterEventHotKey(Settings.hotKeyCode, Settings.hotKeyCarbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("ClipStack: hotkey registration failed (\(status))") }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
