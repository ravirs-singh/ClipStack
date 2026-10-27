import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipStore()
    private var monitor: ClipboardMonitor!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotKey: HotKey?
    private var notch: NotchController?
    private var screenshots: ScreenshotWatcher?
    private var capture: ScreenshotCapture?
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        // An earlier build could unload macOS's volume/brightness overlay; make sure it's back.
        let restore = Process(); restore.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        restore.arguments = ["bootstrap", "gui/\(getuid())", "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist"]
        restore.standardOutput = FileHandle.nullDevice; restore.standardError = FileHandle.nullDevice
        try? restore.run()
        quitOtherInstances()

        monitor = ClipboardMonitor(store: store)
        monitor.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipStack")
            button.action = #selector(statusClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        screenshots = ScreenshotWatcher(store: store)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = HistoryViewController(
            store: store, monitor: monitor, screenshots: screenshots!, dismiss: { [weak self] in self?.closePopover() })

        hotKey = HotKey(binding: { (Settings.hotKeyCode, Settings.hotKeyCarbonModifiers) },
                        handler: { [weak self] in self?.togglePopover() })
        capture = ScreenshotCapture(watcher: screenshots!)
        notch = NotchController(store: store, monitor: monitor, openHistory: { [weak self] in self?.showPopover() })
    }

    /// A freshly launched build replaces any ClipStack already running (handy after rebuilds).
    private func quitOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.terminate()
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show History  \(Settings.hotKeyDescription)", action: #selector(togglePopover), keyEquivalent: "")
        menu.addItem(.separator())
        for kind in CaptureKind.allCases {
            let mi = NSMenuItem(title: kind.title, action: #selector(captureTapped(_:)), keyEquivalent: "")
            mi.representedObject = kind.rawValue
            if let b = Settings.captureHotKey(kind), Settings.captureEnabled {
                mi.toolTip = KeyNames.describe(keyCode: UInt16(b.keyCode), modifiers: b.modifiers)
            }
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.items.forEach { $0.target = self }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ClipStack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // so left-click goes back to the popover
    }

    @objc private func openPreferences() { PreferencesWindowController.shared.show() }

    @objc private func captureTapped(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = CaptureKind(rawValue: raw) else { return }
        // Let the menu close before the crosshair appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.capture?.capture(kind) }
    }

    @objc func togglePopover() {
        if popover.isShown { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        if popover.isShown { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
        // Hand focus back so a simulated ⌘V lands in the app the user was using.
        previousApp?.activate()
    }
}
