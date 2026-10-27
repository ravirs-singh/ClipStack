import AppKit

enum CaptureKind: String, CaseIterable {
    case area, window, screen

    var title: String {
        switch self {
        case .area: return "Capture Area"
        case .window: return "Capture Window"
        case .screen: return "Capture Screen"
        }
    }

    /// Arguments for /usr/sbin/screencapture.
    var arguments: [String] {
        switch self {
        case .area: return ["-i", "-s"]     // interactive, selection only
        case .window: return ["-i", "-W"]   // interactive, start in window mode
        case .screen: return []             // whole screen, no interaction
        }
    }
}

/// Runs macOS's own capture engine (`screencapture`) so the file is written the instant the shot is taken —
/// no floating thumbnail delay — and hands it straight to the ScreenshotWatcher pipeline.
final class ScreenshotCapture {
    private let watcher: ScreenshotWatcher
    private var hotKeys: [HotKey] = []
    private var running = false

    init(watcher: ScreenshotWatcher) {
        self.watcher = watcher
        for kind in CaptureKind.allCases {
            hotKeys.append(HotKey(binding: {
                guard Settings.captureEnabled, let b = Settings.captureHotKey(kind) else { return nil }
                return (b.keyCode, Settings.carbonModifiers(b.modifiers))
            }, handler: { [weak self] in self?.capture(kind) }))
        }
    }

    func capture(_ kind: CaptureKind) {
        guard !running else { return }
        running = true
        let app = watcher.frontmostAppName()
        let dest = watcher.plannedDestination(appName: app)
        watcher.reserve(dest)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = kind.arguments + [dest.path]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.running = false
                if FileManager.default.fileExists(atPath: dest.path) {
                    self?.watcher.ingestNow(dest, appName: app)
                }
                // else: user pressed Esc — nothing written.
            }
        }
        do { try p.run() } catch {
            running = false
            NSLog("ClipStack: screencapture failed: \(error)")
        }
    }
}
