import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// UserDefaults-backed app settings. Post `Settings.changed` after writes so live components can react.
enum Settings {
    static let changed = Notification.Name("ClipStackSettingsChanged")
    private static let d = UserDefaults.standard

    static var maxItems: Int {
        get { let v = d.integer(forKey: "maxItems"); return v == 0 ? 200 : v }
        set { d.set(newValue, forKey: "maxItems"); notify() }
    }

    static var pollInterval: Double {
        get { let v = d.double(forKey: "pollInterval"); return v == 0 ? 0.5 : v }
        set { d.set(newValue, forKey: "pollInterval"); notify() }
    }

    static var autoPaste: Bool {
        get { d.object(forKey: "autoPaste") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoPaste"); notify() }
    }

    /// Keep rich text (RTF/HTML) alongside plain text.
    static var captureRichText: Bool {
        get { d.object(forKey: "captureRichText") as? Bool ?? true }
        set { d.set(newValue, forKey: "captureRichText"); notify() }
    }

    /// Dynamic-Island-style notch UI.
    static var notchEnabled: Bool {
        get { d.object(forKey: "notchEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "notchEnabled"); notify() }
    }

    /// Briefly expand the notch to show what was just copied.
    static var notchToasts: Bool {
        get { d.object(forKey: "notchToasts") as? Bool ?? true }
        set { d.set(newValue, forKey: "notchToasts"); notify() }
    }

    // MARK: Screenshots

    static var screenshotsEnabled: Bool {
        get { d.object(forKey: "screenshotsEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "screenshotsEnabled"); notify() }
    }
    static var screenshotOCR: Bool {
        get { d.object(forKey: "screenshotOCR") as? Bool ?? true }
        set { d.set(newValue, forKey: "screenshotOCR"); notify() }
    }
    static var screenshotOrganize: Bool {
        get { d.object(forKey: "screenshotOrganize") as? Bool ?? false }
        set { d.set(newValue, forKey: "screenshotOrganize"); notify() }
    }
    static var screenshotFolder: URL {
        get {
            if let p = d.string(forKey: "screenshotFolder") { return URL(fileURLWithPath: p) }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")
        }
        set { d.set(newValue.path, forKey: "screenshotFolder"); notify() }
    }

    // MARK: Hotkey (default ⌘⇧V)

    static var hotKeyCode: UInt32 {
        get { d.object(forKey: "hotKeyCode") as? UInt32 ?? UInt32(kVK_ANSI_V) }
        set { d.set(newValue, forKey: "hotKeyCode"); notify() }
    }

    /// Stored as NSEvent.ModifierFlags raw value.
    static var hotKeyModifiers: NSEvent.ModifierFlags {
        get {
            if let raw = d.object(forKey: "hotKeyMods") as? UInt { return NSEvent.ModifierFlags(rawValue: raw) }
            return [.command, .shift]
        }
        set { d.set(newValue.rawValue, forKey: "hotKeyMods"); notify() }
    }

    static var hotKeyCarbonModifiers: UInt32 {
        var m: UInt32 = 0
        let f = hotKeyModifiers
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift)   { m |= UInt32(shiftKey) }
        if f.contains(.option)  { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static var hotKeyDescription: String {
        KeyNames.describe(keyCode: UInt16(hotKeyCode), modifiers: hotKeyModifiers)
    }

    // MARK: Launch at login (requires running from a .app bundle)

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("ClipStack: launch-at-login failed: \(error)")
            }
        }
    }

    private static func notify() {
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// Human-readable key names for the hotkey recorder.
enum KeyNames {
    static func describe(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + name(for: keyCode)
    }

    static func name(for keyCode: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let n = special[Int(keyCode)] { return n }

        // Translate via the current keyboard layout.
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        var dead: UInt32 = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                  &dead, 4, &len, &chars)
        }
        guard status == noErr, len > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: len).uppercased()
    }
}
