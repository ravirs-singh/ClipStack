import AppKit
import Carbon.HIToolbox

/// Writes an item back to the pasteboard and optionally simulates ⌘V in the frontmost app.
enum Paster {
    /// - plain: strip formatting (text items only) and write just the string.
    /// - override: replacement text (from a smart action); implies plain.
    static func copy(_ item: ClipItem, monitor: ClipboardMonitor, plain: Bool = false, override: String? = nil) {
        let pb = NSPasteboard.general
        monitor.ignoreNextChange = true
        pb.clearContents()

        if let override {
            pb.setString(override, forType: .string)
            return
        }

        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
            if !plain {
                if let rtf = item.rtf { pb.setData(rtf, forType: .rtf) }
                if let html = item.html { pb.setString(html, forType: .html) }
            }
        case .image:
            if let img = item.image { pb.writeObjects([img]) }
        case .files:
            pb.writeObjects(item.fileURLs as [NSURL])
        }
    }

    /// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).
    static func paste(_ item: ClipItem, monitor: ClipboardMonitor, plain: Bool = false, override: String? = nil) {
        copy(item, monitor: monitor, plain: plain, override: override)
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }
        // Give the previous app a moment to regain focus after our panel closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vKey = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Copy or paste according to the user's auto-paste preference.
    static func use(_ item: ClipItem, monitor: ClipboardMonitor, plain: Bool = false, override: String? = nil) {
        if Settings.autoPaste {
            paste(item, monitor: monitor, plain: plain, override: override)
        } else {
            copy(item, monitor: monitor, plain: plain, override: override)
        }
    }

    static func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}
