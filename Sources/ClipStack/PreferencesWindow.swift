import AppKit
import Carbon.HIToolbox

/// System Settings-style preferences: toolbar tabs with SF Symbols, grouped forms inside.
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let tabs = NSTabViewController()
    private var panes: [PreferencePane] = []

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ClipStack"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.titlebarAppearsTransparent = false
        super.init(window: window)

        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        panes = [GeneralPane(), CapturePane(), ScreenshotsPane(), NotchPane(), AgentsPane()]
        for pane in panes {
            let item = NSTabViewItem(viewController: pane)
            item.label = pane.paneTitle
            item.image = UI.symbol(pane.paneSymbol, size: 18, weight: .regular)
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        panes.forEach { $0.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Pane base: a simple grouped form

class PreferencePane: NSViewController {
    var paneTitle: String { "" }
    var paneSymbol: String { "gearshape" }

    private let grid = NSGridView()
    private var observer: NSObjectProtocol?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 380))
        grid.rowSpacing = 10
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
        ])
        build()
        if grid.numberOfColumns > 0 {
            grid.column(at: 0).xPlacement = .trailing
            grid.column(at: 0).width = 150
        }
        observer = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    override func viewWillAppear() { super.viewWillAppear(); refresh() }

    /// Subclasses add rows here.
    func build() {}
    func refresh() {}

    // Row helpers
    func row(_ label: String, _ control: NSView) {
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        l.font = .systemFont(ofSize: 13)
        grid.addRow(with: [l, control])
    }

    func row(_ control: NSView) { grid.addRow(with: [NSGridCell.emptyContentView, control]) }

    func note(_ text: String) {
        let t = NSTextField(wrappingLabelWithString: text)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .secondaryLabelColor
        t.preferredMaxLayoutWidth = 340
        grid.addRow(with: [NSGridCell.emptyContentView, t])
        grid.row(at: grid.numberOfRows - 1).topPadding = -6
    }

    func gap(_ h: CGFloat = 10) {
        grid.addRow(with: [NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        grid.row(at: grid.numberOfRows - 1).height = h
    }

    func checkbox(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: action)
        b.font = .systemFont(ofSize: 13)
        return b
    }

    func smallButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        return b
    }
}

// MARK: - General

final class GeneralPane: PreferencePane {
    override var paneTitle: String { "General" }
    override var paneSymbol: String { "gearshape" }

    private let recorder = HotKeyRecorderView()
    private let maxItemsField = NSTextField()
    private let maxItemsStepper = NSStepper()
    private let pollPopup = NSPopUpButton()
    private lazy var autoPasteCheck = checkbox("Paste into the frontmost app when an item is chosen", #selector(autoPasteChanged))
    private lazy var richCheck = checkbox("Keep rich text formatting (RTF / HTML)", #selector(richChanged))
    private lazy var loginCheck = checkbox("Launch ClipStack at login", #selector(loginChanged))
    private let axLabel = NSTextField(labelWithString: "")
    private let axDot = NSView()

    override func build() {
        recorder.onChange = { code, mods in Settings.hotKeyCode = UInt32(code); Settings.hotKeyModifiers = mods }
        let hk = NSStackView(views: [recorder, smallButton("Reset", #selector(resetHotKey))]); hk.spacing = 8
        row("Show history:", hk)

        gap()
        maxItemsField.alignment = .right
        maxItemsField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        maxItemsField.target = self; maxItemsField.action = #selector(maxItemsEdited)
        maxItemsStepper.minValue = 10; maxItemsStepper.maxValue = 5000; maxItemsStepper.increment = 10
        maxItemsStepper.target = self; maxItemsStepper.action = #selector(maxItemsStepped)
        let maxRow = NSStackView(views: [maxItemsField, maxItemsStepper, NSTextField(labelWithString: "items")]); maxRow.spacing = 4
        row("Keep up to:", maxRow)
        note("Pinned items don't count toward the limit.")

        for (title, v) in [("Fast (0.25 s)", 0.25), ("Normal (0.5 s)", 0.5), ("Relaxed (1 s)", 1.0), ("Lazy (2 s)", 2.0)] {
            pollPopup.addItem(withTitle: title); pollPopup.lastItem?.representedObject = v
        }
        pollPopup.target = self; pollPopup.action = #selector(pollChanged)
        row("Check clipboard:", pollPopup)
        row("Capture:", richCheck)

        gap()
        row("Auto-paste:", autoPasteCheck)
        axDot.wantsLayer = true; axDot.layer?.cornerRadius = 4
        axDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        axDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        axLabel.font = .systemFont(ofSize: 11); axLabel.textColor = .secondaryLabelColor
        let ax = NSStackView(views: [axDot, axLabel, smallButton("Open Accessibility Settings…", #selector(openAccessibility))]); ax.spacing = 8
        row(ax)

        gap()
        row("Startup:", loginCheck)
    }

    override func refresh() {
        recorder.setBinding(keyCode: UInt16(Settings.hotKeyCode), modifiers: Settings.hotKeyModifiers)
        maxItemsField.integerValue = Settings.maxItems
        maxItemsStepper.integerValue = Settings.maxItems
        pollPopup.selectItem(at: pollPopup.itemArray.firstIndex { ($0.representedObject as? Double) == Settings.pollInterval } ?? 1)
        autoPasteCheck.state = Settings.autoPaste ? .on : .off
        richCheck.state = Settings.captureRichText ? .on : .off
        loginCheck.state = Settings.launchAtLogin ? .on : .off
        loginCheck.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        let trusted = AXIsProcessTrusted()
        axDot.layer?.backgroundColor = (trusted ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        axLabel.stringValue = trusted ? "Accessibility access granted" : "Accessibility access needed for auto-paste"
    }

    @objc private func resetHotKey() { Settings.hotKeyCode = UInt32(kVK_ANSI_V); Settings.hotKeyModifiers = [.command, .shift] }
    @objc private func maxItemsEdited() { Settings.maxItems = max(10, maxItemsField.integerValue) }
    @objc private func maxItemsStepped() { Settings.maxItems = maxItemsStepper.integerValue }
    @objc private func pollChanged() { Settings.pollInterval = pollPopup.selectedItem?.representedObject as? Double ?? 0.5 }
    @objc private func autoPasteChanged() { Settings.autoPaste = autoPasteCheck.state == .on }
    @objc private func richChanged() { Settings.captureRichText = richCheck.state == .on }
    @objc private func loginChanged() { Settings.launchAtLogin = loginCheck.state == .on; refresh() }
    @objc private func openAccessibility() {
        Paster.promptForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Capture

final class CapturePane: PreferencePane {
    override var paneTitle: String { "Capture" }
    override var paneSymbol: String { "camera.viewfinder" }

    private lazy var enableCheck = checkbox("Enable ClipStack capture shortcuts", #selector(enableChanged))
    private var recorders: [CaptureKind: HotKeyRecorderView] = [:]

    override func build() {
        row("Shortcuts:", enableCheck)
        note("ClipStack runs the capture itself, so the file and history entry appear instantly — no floating-thumbnail delay.")
        gap(4)
        for kind in CaptureKind.allCases {
            let r = HotKeyRecorderView()
            r.onChange = { code, mods in Settings.setCaptureHotKey(kind, keyCode: UInt32(code), modifiers: mods) }
            recorders[kind] = r
            row(kind.title.replacingOccurrences(of: "Capture ", with: "") + ":", r)
        }
        gap()
        note("To use ⌘⇧3 / ⌘⇧4 / ⌘⇧5 here, first turn Apple's off under System Settings → Keyboard → Keyboard Shortcuts → Screenshots.")
        row(smallButton("Open Keyboard Shortcuts…", #selector(openShortcuts)))
    }

    override func refresh() {
        enableCheck.state = Settings.captureEnabled ? .on : .off
        for (kind, r) in recorders {
            if let b = Settings.captureHotKey(kind) { r.setBinding(keyCode: UInt16(b.keyCode), modifiers: b.modifiers) }
            r.isEnabled = Settings.captureEnabled
        }
    }

    @objc private func enableChanged() { Settings.captureEnabled = enableCheck.state == .on }
    @objc private func openShortcuts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Screenshots

final class ScreenshotsPane: PreferencePane {
    override var paneTitle: String { "Screenshots" }
    override var paneSymbol: String { "photo.on.rectangle" }

    private lazy var enableCheck = checkbox("Add new screenshots to history", #selector(changed))
    private lazy var ocrCheck = checkbox("Recognize text in screenshots", #selector(changed))
    private lazy var organizeCheck = checkbox("Move screenshots into monthly folders", #selector(changed))
    private let folderLabel = NSTextField(labelWithString: "")
    private lazy var folderButton = smallButton("Choose…", #selector(chooseFolder))

    override func build() {
        row("History:", enableCheck)
        row("Text:", ocrCheck)
        note("On-device OCR makes screenshot text searchable and lets you copy it.")
        gap()
        row("Organize:", organizeCheck)
        note("Named by date and the app that was in front, e.g. “2026-10-20 14.32.11 – Safari.png”.")
        folderLabel.font = .systemFont(ofSize: 12); folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        let f = NSStackView(views: [folderButton, folderLabel]); f.spacing = 8
        row("Folder:", f)
    }

    override func refresh() {
        enableCheck.state = Settings.screenshotsEnabled ? .on : .off
        ocrCheck.state = Settings.screenshotOCR ? .on : .off
        organizeCheck.state = Settings.screenshotOrganize ? .on : .off
        ocrCheck.isEnabled = Settings.screenshotsEnabled
        organizeCheck.isEnabled = Settings.screenshotsEnabled
        folderButton.isEnabled = Settings.screenshotsEnabled && Settings.screenshotOrganize
        folderLabel.stringValue = Settings.screenshotFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    @objc private func changed() {
        Settings.screenshotsEnabled = enableCheck.state == .on
        Settings.screenshotOCR = ocrCheck.state == .on
        Settings.screenshotOrganize = organizeCheck.state == .on
    }
    @objc private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = Settings.screenshotFolder
        if p.runModal() == .OK, let url = p.url { Settings.screenshotFolder = url }
    }
}

// MARK: - Notch

final class NotchPane: PreferencePane {
    override var paneTitle: String { "Notch" }
    override var paneSymbol: String { "macbook" }

    private lazy var enableCheck = checkbox("Show the interactive notch", #selector(changed))
    private lazy var toastCheck = checkbox("Flash what was just copied", #selector(changed))
    private lazy var shotCheck = checkbox("Drop down with actions after a screenshot", #selector(changed))
    private lazy var musicCheck = checkbox("Show Now Playing (Spotify, Apple Music, YouTube Music in Chrome)", #selector(changed))
    private lazy var calCheck = checkbox("Show next calendar event and today's reminders", #selector(changed))
    private lazy var weatherCheck = checkbox("Show the weather (uses your location)", #selector(changed))
    private lazy var hudCheck = checkbox("Show volume, brightness and Caps Lock changes in the notch", #selector(changed))
    private let glowPopup = NSPopUpButton()
    private lazy var pipCheck = checkbox("Show Pip, the eyes beside the notch", #selector(changed))

    override func build() {
        row("Notch:", enableCheck)
        note("Hover to see recent clips, click a chip to paste, drop files or text on it to copy. Macs without a notch get a small pill.")
        gap()
        row("Activity:", toastCheck)
        row(shotCheck)
        gap()
        row("Music:", musicCheck)
        row("Up Next:", calCheck)
        note("macOS will ask for Calendar and Reminders access the first time.")
        row("Weather:", weatherCheck)
        row("HUD:", hudCheck)
        note("Apple's own overlay still appears; this adds a matching indicator in the notch.")
        gap()
        for t in ["Off", "Subtle", "Vivid"] { glowPopup.addItem(withTitle: t) }
        glowPopup.target = self; glowPopup.action = #selector(glowChanged)
        row("Glow:", glowPopup)
        row("Mascot:", pipCheck)
        note("Pip blinks, follows your cursor, smiles when you copy, turns orange when an agent needs you, and bobs to your music.")
        note("Tints the island's edge with the album art colour, orange when an agent needs you, amber while a timer runs.")
        note("Album art on the left of the notch, audio bars on the right; hover for controls. macOS will ask once to allow ClipStack to control each player.")
        note("For YouTube Music / YouTube in Chrome, Brave, Edge or Arc: enable View ▸ Developer ▸ “Allow JavaScript from Apple Events” in the browser once.")
    }

    override func refresh() {
        enableCheck.state = Settings.notchEnabled ? .on : .off
        toastCheck.state = Settings.notchToasts ? .on : .off
        shotCheck.state = Settings.notchScreenshotToast ? .on : .off
        toastCheck.isEnabled = Settings.notchEnabled
        shotCheck.isEnabled = Settings.notchEnabled
        musicCheck.state = Settings.notchNowPlaying ? .on : .off
        musicCheck.isEnabled = Settings.notchEnabled
        calCheck.state = Settings.calendarEnabled ? .on : .off
        weatherCheck.state = Settings.weatherEnabled ? .on : .off
        hudCheck.state = Settings.hudEnabled ? .on : .off
        glowPopup.selectItem(at: Settings.notchGlow)
        pipCheck.state = Settings.notchMascot ? .on : .off
        pipCheck.isEnabled = Settings.notchEnabled
        [calCheck, weatherCheck, hudCheck, glowPopup].forEach { $0.isEnabled = Settings.notchEnabled }
    }

    @objc private func changed() {
        Settings.notchEnabled = enableCheck.state == .on
        Settings.notchToasts = toastCheck.state == .on
        Settings.notchScreenshotToast = shotCheck.state == .on
        Settings.notchNowPlaying = musicCheck.state == .on
        Settings.calendarEnabled = calCheck.state == .on
        Settings.weatherEnabled = weatherCheck.state == .on
        Settings.hudEnabled = hudCheck.state == .on
        Settings.notchMascot = pipCheck.state == .on
    }
    @objc private func glowChanged() { Settings.notchGlow = glowPopup.indexOfSelectedItem }
}

// MARK: - Agents

final class AgentsPane: PreferencePane {
    override var paneTitle: String { "Agents" }
    override var paneSymbol: String { "sparkles" }

    private lazy var enableCheck = checkbox("Show AI agent activity in the notch", #selector(changed))
    private let status = NSTextField(wrappingLabelWithString: "")
    private lazy var installButton = smallButton("Install Claude Code Hooks", #selector(install))
    private lazy var revealButton = smallButton("Show settings.json", #selector(reveal))

    override func build() {
        row("Agents:", enableCheck)
        note("Claude Code reports what it's doing through hooks. When it needs permission for a command, the notch glows orange and you can Allow or Deny right there — the agent waits for your answer.")
        gap()
        status.font = .systemFont(ofSize: 12); status.preferredMaxLayoutWidth = 340
        row("Claude Code:", status)
        let btns = NSStackView(views: [installButton, revealButton]); btns.spacing = 8
        row(btns)
        note("Adds hook entries to ~/.claude/settings.json (a backup is kept). Codex and Cursor support is planned.")
    }

    override func refresh() {
        enableCheck.state = Settings.agentsEnabled ? .on : .off
        let ok = AgentMonitor.hooksInstalled
        status.stringValue = ok ? "Hooks installed · listening on 127.0.0.1:\(AgentMonitor.port)" : "Hooks not installed"
        status.textColor = ok ? .systemGreen : .secondaryLabelColor
        installButton.title = ok ? "Reinstall Hooks" : "Install Claude Code Hooks"
    }

    @objc private func changed() { Settings.agentsEnabled = enableCheck.state == .on }
    @objc private func install() {
        do {
            try AgentMonitor.installHooks(); refresh()
            let a = NSAlert(); a.messageText = "Hooks installed"
            a.informativeText = "Claude Code will report to ClipStack from its next session. Restart any session that's already running."
            a.runModal()
        } catch {
            let a = NSAlert(); a.messageText = "Couldn't write hooks"; a.informativeText = error.localizedDescription; a.runModal()
        }
    }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([AgentMonitor.settingsURL]) }
}

// MARK: - Hotkey recorder

/// Click, then press a key combo (must include ⌘, ⌃ or ⌥). Esc cancels.
final class HotKeyRecorderView: NSView {
    var onChange: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }

    private var keyCode: UInt16 = 0
    private var modifiers: NSEvent.ModifierFlags = []
    private var recording = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }
    override var acceptsFirstResponder: Bool { true }

    func setBinding(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        startRecording()
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.recording else { return e }
            if e.keyCode == 53 { self.stopRecording(); return nil }  // Esc
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !mods.isDisjoint(with: [.command, .option, .control]) else { NSSound.beep(); return nil }
            self.keyCode = e.keyCode
            self.modifiers = mods
            self.onChange?(e.keyCode, mods)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }

    override func resignFirstResponder() -> Bool { stopRecording(); return true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text = recording ? "Type shortcut…" : KeyNames.describe(keyCode: keyCode, modifiers: modifiers)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
