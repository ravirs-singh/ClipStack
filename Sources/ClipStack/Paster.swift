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
            if let src = item.sourceURL, item.sourceExists, let full = NSImage(contentsOf: src) {
                // File URL first so Finder/Slack get the file; image so editors get pixels.
                pb.writeObjects([src as NSURL, full] as [NSPasteboardWriting])
            } else if let img = item.image { pb.writeObjects([img]) }
        case .files:
            let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { NSSound.beep(); NSLog("ClipStack: file clip no longer exists on disk"); return }
            // One pasteboard item per file. For a single image, also carry the pixels so browsers,
            // Messages and chat composers (which ignore file references) accept the paste.
            var items: [NSPasteboardItem] = []
            for u in urls {
                let pi = NSPasteboardItem()
                pi.setString(u.absoluteString, forType: .fileURL)
                if urls.count == 1, let img = NSImage(contentsOf: u), let tiff = img.tiffRepresentation {
                    pi.setData(tiff, forType: .tiff)
                    if let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) { pi.setData(png, forType: .png) }
                }
                items.append(pi)
            }
            pb.writeObjects(items)
            // Legacy filenames list — some apps (and AppleScript-era code) still read only this.
            let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            pb.addTypes([legacy], owner: nil)
            pb.setPropertyList(urls.map(\.path), forType: legacy)
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
