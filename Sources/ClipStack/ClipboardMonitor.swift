import AppKit
import Foundation

/// Polls NSPasteboard.changeCount (there is no public change notification on macOS).
final class ClipboardMonitor {
    private let store: ClipStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private let pasteboard = NSPasteboard.general
    private var settingsObserver: NSObjectProtocol?

    /// Set by Paster right before it writes to the pasteboard so we don't re-record our own paste.
    var ignoreNextChange = false

    /// Cap on stored RTF/HTML so giant formatted documents don't bloat history.json.
    private let richLimit = 512 * 1024

    init(store: ClipStore) {
        self.store = store
        lastChangeCount = pasteboard.changeCount
        settingsObserver = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Settings.pollInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
        timer?.tolerance = Settings.pollInterval / 5
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func restart() { if timer != nil { start() } }

    private func check() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if ignoreNextChange { ignoreNextChange = false; return }

        // Respect password managers / "transient" marks.
        let types = pasteboard.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) ||
           types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) {
            return
        }

        // 1. Files from Finder
        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            store.addFiles(urls)
            return
        }

        // 2. Text (plain + optional rich representations)
        if let str = pasteboard.string(forType: .string) {
            var rtf: Data?
            var html: String?
            if Settings.captureRichText {
                if let d = pasteboard.data(forType: .rtf), d.count <= richLimit { rtf = d }
                if let h = pasteboard.string(forType: .html), h.utf8.count <= richLimit { html = h }
            }
            store.addText(str, rtf: rtf, html: html)
            return
        }

        // 3. Images
        if let img = NSImage(pasteboard: pasteboard) {
            store.addImage(img)
        }
    }
}
