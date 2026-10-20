import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipStore()
    private var monitor: ClipboardMonitor!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotKey: HotKey?
    private var notch: NotchController?
    private var screenshots: ScreenshotWatcher?
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
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

        hotKey = HotKey { [weak self] in self?.togglePopover() }
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
