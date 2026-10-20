import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon RegisterEventHotKey — work without Accessibility permission.
/// One Carbon event handler dispatches to any number of registered `HotKey`s.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeyCenter.shared.handlers[id.id]?()
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    fileprivate func allocateID() -> UInt32 { defer { nextID += 1 }; return nextID }

    fileprivate func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister(id: id)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x434C5350) /* "CLSP" */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref } else { NSLog("ClipStack: hotkey \(id) registration failed (\(status))") }
    }

    fileprivate func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }
}

/// A single binding. `binding` is re-read (and the key re-registered) whenever Settings change,
/// so recorder changes in Preferences take effect immediately. Return nil to leave it unbound.
final class HotKey {
    private let id = HotKeyCenter.shared.allocateID()
    private let binding: () -> (keyCode: UInt32, carbonModifiers: UInt32)?
    private let handler: () -> Void
    private var observer: NSObjectProtocol?

    init(binding: @escaping () -> (keyCode: UInt32, carbonModifiers: UInt32)?, handler: @escaping () -> Void) {
        self.binding = binding
        self.handler = handler
        register()
        observer = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.register()
        }
    }

    private func register() {
        guard let b = binding() else { HotKeyCenter.shared.unregister(id: id); return }
        HotKeyCenter.shared.register(id: id, keyCode: b.keyCode, modifiers: b.carbonModifiers, handler: handler)
    }

    deinit { HotKeyCenter.shared.unregister(id: id) }
}
