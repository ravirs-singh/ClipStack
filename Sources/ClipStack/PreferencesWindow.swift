import AppKit
import Carbon.HIToolbox

/// Simple preferences window: hotkey recorder, history size, polling, capture, auto-paste, login item.
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let recorder = HotKeyRecorderView()
    private let maxItemsField = NSTextField()
    private let maxItemsStepper = NSStepper()
    private let pollPopup = NSPopUpButton()
    private let autoPasteCheck = NSButton(checkboxWithTitle: "Paste into the frontmost app when an item is chosen", target: nil, action: nil)
    private let richCheck = NSButton(checkboxWithTitle: "Keep rich text formatting (RTF / HTML)", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "Launch ClipStack at login", target: nil, action: nil)
    private let shotCheck = NSButton(checkboxWithTitle: "Capture new screenshots into history", target: nil, action: nil)
    private let shotOCRCheck = NSButton(checkboxWithTitle: "Recognize text in screenshots (searchable, on-device)", target: nil, action: nil)
    private let shotOrganizeCheck = NSButton(checkboxWithTitle: "Move screenshots into monthly folders, named by date and app", target: nil, action: nil)
    private let shotFolderButton = NSButton(title: "Choose Folder…", target: nil, action: nil)
    private let shotFolderLabel = NSTextField(labelWithString: "")
    private let notchCheck = NSButton(checkboxWithTitle: "Show interactive notch (hover to expand, drop to copy)", target: nil, action: nil)
    private let notchToastCheck = NSButton(checkboxWithTitle: "Flash the notch when something is copied", target: nil, action: nil)
    private let accessibilityLabel = NSTextField(wrappingLabelWithString: "")

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClipStack Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Hotkey
        recorder.onChange = { code, mods in
            Settings.hotKeyCode = UInt32(code)
            Settings.hotKeyModifiers = mods
        }
        let resetBtn = NSButton(title: "Reset", target: self, action: #selector(resetHotKey))
        resetBtn.controlSize = .small
        let hotkeyRow = NSStackView(views: [recorder, resetBtn])
        hotkeyRow.spacing = 8

        // Max items
        maxItemsField.alignment = .right
        maxItemsField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        maxItemsField.target = self; maxItemsField.action = #selector(maxItemsEdited)
        maxItemsStepper.minValue = 10; maxItemsStepper.maxValue = 5000; maxItemsStepper.increment = 10
        maxItemsStepper.target = self; maxItemsStepper.action = #selector(maxItemsStepped)
        let maxRow = NSStackView(views: [maxItemsField, maxItemsStepper, NSTextField(labelWithString: "items (pinned items don't count)")])
        maxRow.spacing = 4

        // Polling
        for (title, v) in [("Fast (0.25 s)", 0.25), ("Normal (0.5 s)", 0.5), ("Relaxed (1 s)", 1.0), ("Lazy (2 s)", 2.0)] {
            pollPopup.addItem(withTitle: title)
            pollPopup.lastItem?.representedObject = v
        }
        pollPopup.target = self; pollPopup.action = #selector(pollChanged)

        autoPasteCheck.target = self; autoPasteCheck.action = #selector(autoPasteChanged)
        richCheck.target = self; richCheck.action = #selector(richChanged)
        loginCheck.target = self; loginCheck.action = #selector(loginChanged)
        notchCheck.target = self; notchCheck.action = #selector(notchChanged)
        shotCheck.target = self; shotCheck.action = #selector(shotChanged)
        shotOCRCheck.target = self; shotOCRCheck.action = #selector(shotChanged)
        shotOrganizeCheck.target = self; shotOrganizeCheck.action = #selector(shotChanged)
        shotFolderButton.target = self; shotFolderButton.action = #selector(chooseFolder)
        shotFolderButton.controlSize = .small
        shotFolderLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        shotFolderLabel.textColor = .secondaryLabelColor
        shotFolderLabel.lineBreakMode = .byTruncatingMiddle
        let folderRow = NSStackView(views: [shotFolderButton, shotFolderLabel]); folderRow.spacing = 8
        notchToastCheck.target = self; notchToastCheck.action = #selector(notchToastChanged)

        accessibilityLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        accessibilityLabel.textColor = .secondaryLabelColor
        let axBtn = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibility))
        axBtn.controlSize = .small

        let grid = NSGridView(views: [
            [label("Show history:"), hotkeyRow],
            [label("Keep up to:"), maxRow],
            [label("Check clipboard:"), pollPopup],
            [label("Capture:"), richCheck],
            [label("Auto-paste:"), autoPasteCheck],
            [NSGridCell.emptyContentView, accessibilityLabel],
            [NSGridCell.emptyContentView, axBtn],
            [label("Screenshots:"), shotCheck],
            [NSGridCell.emptyContentView, shotOCRCheck],
            [NSGridCell.emptyContentView, shotOrganizeCheck],
            [NSGridCell.emptyContentView, folderRow],
            [label("Notch:"), notchCheck],
            [NSGridCell.emptyContentView, notchToastCheck],
            [label("Startup:"), loginCheck],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func refresh() {
        recorder.setBinding(keyCode: UInt16(Settings.hotKeyCode), modifiers: Settings.hotKeyModifiers)
        maxItemsField.integerValue = Settings.maxItems
        maxItemsStepper.integerValue = Settings.maxItems
        let idx = pollPopup.itemArray.firstIndex { ($0.representedObject as? Double) == Settings.pollInterval } ?? 1
        pollPopup.selectItem(at: idx)
        autoPasteCheck.state = Settings.autoPaste ? .on : .off
        richCheck.state = Settings.captureRichText ? .on : .off
        loginCheck.state = Settings.launchAtLogin ? .on : .off
        notchCheck.state = Settings.notchEnabled ? .on : .off
        shotCheck.state = Settings.screenshotsEnabled ? .on : .off
        shotOCRCheck.state = Settings.screenshotOCR ? .on : .off
        shotOrganizeCheck.state = Settings.screenshotOrganize ? .on : .off
        shotOCRCheck.isEnabled = Settings.screenshotsEnabled
        shotOrganizeCheck.isEnabled = Settings.screenshotsEnabled
        shotFolderButton.isEnabled = Settings.screenshotsEnabled && Settings.screenshotOrganize
        shotFolderLabel.stringValue = Settings.screenshotFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        notchToastCheck.state = Settings.notchToasts ? .on : .off
        notchToastCheck.isEnabled = Settings.notchEnabled
        loginCheck.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        loginCheck.toolTip = loginCheck.isEnabled ? nil : "Available when running from ClipStack.app"
        accessibilityLabel.stringValue = AXIsProcessTrusted()
            ? "Accessibility access is granted — auto-paste will work."
            : "Auto-paste needs Accessibility access for ClipStack."
    }

    // MARK: Actions

    @objc private func resetHotKey() {
        Settings.hotKeyCode = UInt32(kVK_ANSI_V)
        Settings.hotKeyModifiers = [.command, .shift]
        refresh()
    }
    @objc private func maxItemsEdited() { Settings.maxItems = max(10, maxItemsField.integerValue); refresh() }
    @objc private func maxItemsStepped() { Settings.maxItems = maxItemsStepper.integerValue; refresh() }
    @objc private func pollChanged() { Settings.pollInterval = pollPopup.selectedItem?.representedObject as? Double ?? 0.5 }
    @objc private func autoPasteChanged() { Settings.autoPaste = autoPasteCheck.state == .on }
    @objc private func richChanged() { Settings.captureRichText = richCheck.state == .on }
    @objc private func shotChanged() {
        Settings.screenshotsEnabled = shotCheck.state == .on
        Settings.screenshotOCR = shotOCRCheck.state == .on
        Settings.screenshotOrganize = shotOrganizeCheck.state == .on
        refresh()
    }
    @objc private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = Settings.screenshotFolder
        if p.runModal() == .OK, let url = p.url { Settings.screenshotFolder = url; refresh() }
    }
    @objc private func notchChanged() { Settings.notchEnabled = notchCheck.state == .on; refresh() }
    @objc private func notchToastChanged() { Settings.notchToasts = notchToastCheck.state == .on }
    @objc private func loginChanged() { Settings.launchAtLogin = loginCheck.state == .on; refresh() }
    @objc private func openAccessibility() {
        Paster.promptForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Hotkey recorder

/// Click, then press a key combo (must include ⌘, ⌃ or ⌥). Esc cancels.
final class HotKeyRecorderView: NSView {
    var onChange: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    private var keyCode: UInt16 = 0
    private var modifiers: NSEvent.ModifierFlags = []
    private var recording = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    func setBinding(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
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
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text = recording ? "Press shortcut…" : KeyNames.describe(keyCode: keyCode, modifiers: modifiers)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
