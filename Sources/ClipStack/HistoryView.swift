import AppKit

/// AppKit popover UI: search + list on the left, full preview + actions on the right.
final class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: ClipStore
    private let monitor: ClipboardMonitor
    private let dismiss: () -> Void

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Nothing copied yet")
    private let countLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    // Preview pane
    private let typeBadge = NSButton()
    private let metaLabel = NSTextField(labelWithString: "")
    private let actionsPopup = NSPopUpButton()
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let previewScroll = NSScrollView()
    private let previewText = NSTextView()
    private let previewImage = NSImageView()
    private let colorSwatch = NSView()

    private var results: [ClipItem] = []
    private var keyMonitor: Any?

    init(store: ClipStore, monitor: ClipboardMonitor, dismiss: @escaping () -> Void) {
        self.store = store
        self.monitor = monitor
        self.dismiss = dismiss
        super.init(nibName: nil, bundle: nil)
        store.onChange = { [weak self] in self?.reload() }
        NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.updateHint()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 480))

        // --- Left column: search + list
        searchField.placeholderString = "Search history…"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.style = .inset
        tableView.menu = makeContextMenu()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let left = NSStackView(views: [pad(searchField, 10, 10, 8, 10), scrollView])
        left.orientation = .vertical
        left.spacing = 0
        left.alignment = .leading
        searchField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 340).isActive = true

        // --- Right column: preview
        typeBadge.isBordered = false
        typeBadge.imagePosition = .imageLeading
        typeBadge.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        typeBadge.setContentHuggingPriority(.required, for: .horizontal)

        metaLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        actionsPopup.pullsDown = true
        actionsPopup.controlSize = .small
        actionsPopup.bezelStyle = .rounded
        actionsPopup.setContentHuggingPriority(.required, for: .horizontal)

        openButton.controlSize = .small
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openSelected)

        let previewHeader = NSStackView(views: [typeBadge, metaLabel, openButton, actionsPopup])
        previewHeader.orientation = .horizontal
        previewHeader.spacing = 8

        previewText.isEditable = false
        previewText.isRichText = true
        previewText.font = .userFixedPitchFont(ofSize: 12)
        previewText.textContainerInset = NSSize(width: 6, height: 6)
        previewText.isVerticallyResizable = true
        previewText.isHorizontallyResizable = false
        previewText.autoresizingMask = [.width]
        previewText.textContainer?.widthTracksTextView = true
        previewScroll.documentView = previewText
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .noBorder
        previewScroll.drawsBackground = true
        previewScroll.backgroundColor = .textBackgroundColor

        previewImage.imageScaling = .scaleProportionallyDown
        previewImage.isHidden = true
        previewImage.translatesAutoresizingMaskIntoConstraints = false

        colorSwatch.wantsLayer = true
        colorSwatch.layer?.cornerRadius = 8
        colorSwatch.layer?.borderWidth = 1
        colorSwatch.layer?.borderColor = NSColor.separatorColor.cgColor
        colorSwatch.isHidden = true
        colorSwatch.translatesAutoresizingMaskIntoConstraints = false

        let previewArea = NSView()
        previewArea.wantsLayer = true
        previewArea.layer?.cornerRadius = 8
        previewArea.layer?.borderWidth = 1
        previewArea.layer?.borderColor = NSColor.separatorColor.cgColor
        previewArea.layer?.masksToBounds = true
        previewArea.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewArea.addSubview(previewScroll)
        previewArea.addSubview(previewImage)
        previewArea.addSubview(colorSwatch)
        NSLayoutConstraint.activate([
            previewScroll.topAnchor.constraint(equalTo: previewArea.topAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: previewArea.bottomAnchor),
            previewScroll.leadingAnchor.constraint(equalTo: previewArea.leadingAnchor),
            previewScroll.trailingAnchor.constraint(equalTo: previewArea.trailingAnchor),
            previewImage.topAnchor.constraint(equalTo: previewArea.topAnchor, constant: 8),
            previewImage.bottomAnchor.constraint(equalTo: previewArea.bottomAnchor, constant: -8),
            previewImage.leadingAnchor.constraint(equalTo: previewArea.leadingAnchor, constant: 8),
            previewImage.trailingAnchor.constraint(equalTo: previewArea.trailingAnchor, constant: -8),
            colorSwatch.topAnchor.constraint(equalTo: previewArea.topAnchor, constant: 8),
            colorSwatch.leadingAnchor.constraint(equalTo: previewArea.leadingAnchor, constant: 8),
            colorSwatch.widthAnchor.constraint(equalToConstant: 72),
            colorSwatch.heightAnchor.constraint(equalToConstant: 72),
        ])

        let right = NSStackView(views: [previewHeader, previewArea])
        right.orientation = .vertical
        right.spacing = 8
        right.alignment = .leading
        right.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 10)
        previewHeader.widthAnchor.constraint(equalTo: right.widthAnchor, constant: -10).isActive = true
        previewArea.widthAnchor.constraint(equalTo: right.widthAnchor, constant: -10).isActive = true

        let vSep = NSBox(); vSep.boxType = .separator
        left.setContentHuggingPriority(.required, for: .horizontal)
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        previewArea.setContentHuggingPriority(.defaultLow, for: .vertical)

        let columns = NSStackView(views: [left, vSep, right])
        columns.orientation = .horizontal
        columns.spacing = 0
        columns.alignment = .top

        // --- Footer
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .tertiaryLabelColor
        let prefsBtn = NSButton(title: "Preferences…", target: self, action: #selector(openPreferences))
        let clearBtn = NSButton(title: "Clear", target: self, action: #selector(clearHistory))
        let quitBtn = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        [prefsBtn, clearBtn, quitBtn].forEach { $0.controlSize = .small; $0.bezelStyle = .rounded }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [countLabel, hintLabel, spacer, prefsBtn, clearBtn, quitBtn])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 8, right: 10)

        let hSep = NSBox(); hSep.boxType = .separator
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)
        footer.setContentHuggingPriority(.required, for: .vertical)

        let root = NSStackView(views: [columns, hSep, footer])
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            columns.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            left.heightAnchor.constraint(equalTo: columns.heightAnchor),
            right.heightAnchor.constraint(equalTo: columns.heightAnchor),
            vSep.heightAnchor.constraint(equalTo: columns.heightAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
        updateHint()
    }

    private func pad(_ v: NSView, _ t: CGFloat, _ l: CGFloat, _ b: CGFloat, _ r: CGFloat) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: box.topAnchor, constant: t),
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: l),
            v.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -b),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -r),
        ])
        return box
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        searchField.stringValue = ""
        reload()
        view.window?.makeFirstResponder(searchField)
        // ⌘1–⌘9 quick-pick, ⇧⏎ plain paste — captured app-wide while the popover is open.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            if mods == .command, let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
                if n <= self.results.count { self.use(self.results[n - 1]) }
                return nil
            }
            if mods == .shift, e.keyCode == 36 /* return */, let s = self.selected {
                self.use(s, plain: true)
                return nil
            }
            return e
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }

    private func updateHint() {
        hintLabel.stringValue = "⏎ paste · ⇧⏎ plain · ⌘1–9 quick · \(Settings.hotKeyDescription) toggle"
    }

    // MARK: Data

    private func reload() {
        let previousID = selected?.id
        results = store.filtered(searchField.stringValue)
        tableView.reloadData()
        emptyLabel.stringValue = searchField.stringValue.isEmpty ? "Nothing copied yet" : "No matches"
        emptyLabel.isHidden = !results.isEmpty
        countLabel.stringValue = "\(store.items.count) items"
        if let prev = previousID, let idx = results.firstIndex(where: { $0.id == prev }) {
            tableView.selectRowIndexes([idx], byExtendingSelection: false)
        } else if !results.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
        updatePreview()
    }

    private var selected: ClipItem? {
        let r = tableView.selectedRow
        return r >= 0 && r < results.count ? results[r] : nil
    }

    private func use(_ item: ClipItem, plain: Bool = false, override: String? = nil) {
        dismiss()
        Paster.use(item, monitor: monitor, plain: plain, override: override)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let next = max(0, min(results.count - 1, tableView.selectedRow + delta))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: Preview pane

    private func updatePreview() {
        actionsPopup.removeAllItems()
        actionsPopup.addItem(withTitle: "Actions")
        guard let item = selected else {
            typeBadge.title = ""
            typeBadge.image = nil
            metaLabel.stringValue = ""
            previewText.string = ""
            previewImage.isHidden = true
            colorSwatch.isHidden = true
            previewScroll.isHidden = false
            openButton.isHidden = true
            actionsPopup.isEnabled = false
            return
        }

        let type = item.smartType
        typeBadge.title = " " + type.rawValue
        typeBadge.image = NSImage(systemSymbolName: type.symbol, accessibilityDescription: type.rawValue)
        typeBadge.contentTintColor = type.tint

        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        var meta = [df.string(from: item.createdAt)]
        if item.pinned { meta.insert("Pinned", at: 0) }

        previewImage.isHidden = true
        colorSwatch.isHidden = true
        previewScroll.isHidden = false
        openButton.isHidden = true

        switch item.kind {
        case .image:
            previewImage.image = item.image
            previewImage.isHidden = false
            previewScroll.isHidden = true
            if let img = item.image { meta.append("\(Int(img.size.width)) × \(Int(img.size.height)) px") }
            if let p = item.imagePath, let size = try? FileManager.default.attributesOfItem(atPath: p)[.size] as? Int {
                meta.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            actionsPopup.isEnabled = false

        case .files:
            previewText.string = (item.filePaths ?? []).joined(separator: "\n")
            meta.append("\(item.filePaths?.count ?? 0) file(s)")
            openButton.title = "Reveal"
            openButton.isHidden = false
            actionsPopup.isEnabled = false

        case .text:
            let text = item.text ?? ""
            if let rtf = item.rtf, let attr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                previewText.textStorage?.setAttributedString(attr)
            } else {
                previewText.string = text
                previewText.font = type == .code || type == .json ? .userFixedPitchFont(ofSize: 12) : .systemFont(ofSize: 13)
                previewText.textColor = .textColor
            }
            let lines = text.components(separatedBy: .newlines).count
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            meta.append("\(text.count) chars · \(words) words · \(lines) line\(lines == 1 ? "" : "s")")
            if item.isRich { meta.append("formatted") }

            if type == .color, let c = SmartType.parseColor(text), let c {
                colorSwatch.layer?.backgroundColor = c.cgColor
                colorSwatch.isHidden = false
                previewText.textContainerInset = NSSize(width: 88, height: 6)
            } else {
                previewText.textContainerInset = NSSize(width: 6, height: 6)
            }

            if type.openURL(for: text) != nil {
                openButton.title = type == .email ? "Compose" : type == .phone ? "Call" : "Open"
                openButton.isHidden = false
            }

            let actions = type.actions()
            for (i, a) in actions.enumerated() {
                let mi = NSMenuItem(title: a.title, action: #selector(runAction(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = i
                actionsPopup.menu?.addItem(mi)
            }
            actionsPopup.menu?.addItem(.separator())
            let plainItem = NSMenuItem(title: "Paste as plain text  ⇧⏎", action: #selector(pastePlain), keyEquivalent: "")
            plainItem.target = self
            actionsPopup.menu?.addItem(plainItem)
            actionsPopup.isEnabled = true
        }

        metaLabel.stringValue = meta.joined(separator: " · ")
    }

    // MARK: Actions

    @objc private func rowClicked() {
        if tableView.clickedRow >= 0, let item = selected { use(item) }
    }

    @objc private func clearHistory() { store.clear() }
    @objc private func openPreferences() { dismiss(); PreferencesWindowController.shared.show() }

    @objc private func pinSelected() { if let s = clickedOrSelected { store.togglePin(s) } }
    @objc private func copySelected() { if let s = clickedOrSelected { Paster.copy(s, monitor: monitor); dismiss() } }
    @objc private func deleteSelected() { if let s = clickedOrSelected { store.remove(s) } }
    @objc private func pastePlain() { if let s = selected { use(s, plain: true) } }

    @objc private func openSelected() {
        guard let item = selected else { return }
        dismiss()
        if item.kind == .files {
            NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs)
        } else if let url = item.smartType.openURL(for: item.text ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let item = selected, item.kind == .text else { return }
        let actions = item.smartType.actions()
        guard actions.indices.contains(sender.tag),
              let out = actions[sender.tag].apply(item.text ?? "") else { NSSound.beep(); return }
        use(item, override: out)
    }

    private var clickedOrSelected: ClipItem? {
        let r = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        return r >= 0 && r < results.count ? results[r] : nil
    }

    private func makeContextMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Pin / Unpin", action: #selector(pinSelected), keyEquivalent: "")
        m.addItem(withTitle: "Copy only", action: #selector(copySelected), keyEquivalent: "")
        m.addItem(withTitle: "Paste as plain text", action: #selector(pastePlain), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Delete", action: #selector(deleteSelected), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        return m
    }

    // MARK: NSSearchFieldDelegate — keyboard handling while typing

    func controlTextDidChange(_ obj: Notification) {
        reload()
        if !results.isEmpty { tableView.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)):      move(1); return true
        case #selector(NSResponder.moveUp(_:)):        move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): if let s = selected { use(s) }; return true
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty { dismiss() } else { searchField.stringValue = ""; reload() }
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            if searchField.stringValue.isEmpty, let s = selected { store.remove(s); return true }
            return false
        default: return false
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ClipRowView) ?? ClipRowView(identifier: id)
        cell.configure(with: results[row], index: row)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }
}

// MARK: - Row view

final class ClipRowView: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let number = NSTextField(labelWithString: "")
    private let pin = NSImageView()
    private static let relFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 4
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: NSFont.systemFontSize)
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        number.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        number.textColor = .tertiaryLabelColor
        number.alignment = .right
        number.translatesAutoresizingMaskIntoConstraints = false

        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pin.contentTintColor = .systemOrange
        pin.translatesAutoresizingMaskIntoConstraints = false

        let h = NSStackView(views: [icon, text, pin, number])
        h.orientation = .horizontal
        h.spacing = 8
        h.alignment = .centerY
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)

        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            h.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            h.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            pin.widthAnchor.constraint(equalToConstant: 14),
            number.widthAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with item: ClipItem, index: Int) {
        let type = item.smartType
        title.stringValue = item.preview
        let when = Self.relFmt.localizedString(for: item.createdAt, relativeTo: Date())
        subtitle.stringValue = type == .plain ? when : "\(type.rawValue) · \(when)"
        pin.isHidden = !item.pinned
        number.stringValue = index < 9 ? "⌘\(index + 1)" : ""

        if item.kind == .image, let img = item.image {
            icon.image = img
            icon.contentTintColor = nil
        } else if type == .color, let c = SmartType.parseColor(item.text ?? ""), let c {
            icon.image = Self.swatch(c)
            icon.contentTintColor = nil
        } else if item.kind == .files, let first = item.fileURLs.first {
            icon.image = NSWorkspace.shared.icon(forFile: first.path)
            icon.contentTintColor = nil
        } else {
            icon.image = NSImage(systemSymbolName: type.symbol, accessibilityDescription: type.rawValue)
            icon.contentTintColor = type.tint
        }
    }

    private static func swatch(_ c: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 36, height: 36), flipped: false) { rect in
            c.setFill(); NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill(); return true
        }
        return img
    }
}
