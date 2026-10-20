import AppKit

// MARK: - Small UI helpers

enum UI {
    static func symbol(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .medium) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(cfg)
    }

    /// Borderless symbol button (toolbar-style).
    static func iconButton(_ name: String, tip: String, target: AnyObject?, action: Selector) -> NSButton {
        let b = NSButton(image: symbol(name, size: 15)!, target: target, action: action)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageOnly
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tip
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    static func label(_ text: String = "", size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }
}

/// Rounded tile with a tinted background and a symbol or image — the Settings.app-style icon.
final class IconTile: NSView {
    private let imageView = NSImageView()
    private var tint: NSColor = .systemGray
    private var symbolConstraints: [NSLayoutConstraint] = []
    private var fillConstraints: [NSLayoutConstraint] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        symbolConstraints = [
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.55),
            imageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.55),
        ]
        fillConstraints = [
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        NSLayoutConstraint.activate(symbolConstraints)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setFill(_ fill: Bool) {
        NSLayoutConstraint.deactivate(fill ? symbolConstraints : fillConstraints)
        NSLayoutConstraint.activate(fill ? fillConstraints : symbolConstraints)
    }

    func setSymbol(_ name: String, tint: NSColor) {
        self.tint = tint
        imageView.image = UI.symbol(name, size: 16, weight: .semibold)
        imageView.contentTintColor = tint
        setFill(false)
        updateLayerColors()
    }

    func setImage(_ image: NSImage) {
        imageView.image = image
        imageView.contentTintColor = nil
        setFill(true)
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    }

    func setColor(_ color: NSColor) {
        imageView.image = nil
        setFill(false)
        layer?.backgroundColor = color.cgColor
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateLayerColors() }

    private func updateLayerColors() {
        guard imageView.contentTintColor != nil else { return }
        layer?.backgroundColor = tint.withAlphaComponent(effectiveAppearance.name == .darkAqua ? 0.22 : 0.15).cgColor
    }
}

/// Subtle inset card that keeps its colors right across light/dark.
final class CardView: NSView {
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; recolor() }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); recolor() }
    private func recolor() {
        let dark = effectiveAppearance.name == .darkAqua
        layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.035)).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(dark ? 0.5 : 0.35).cgColor
    }
}

/// Capsule badge: tinted background, symbol + text.
final class CapsuleBadge: NSView {
    private let icon = NSImageView()
    private let text = UI.label(size: 11, weight: .semibold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        let h = NSStackView(views: [icon, text])
        h.spacing = 4
        h.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 9)
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)
        NSLayoutConstraint.activate([
            h.topAnchor.constraint(equalTo: topAnchor), h.bottomAnchor.constraint(equalTo: bottomAnchor),
            h.leadingAnchor.constraint(equalTo: leadingAnchor), h.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 12), icon.heightAnchor.constraint(equalToConstant: 12),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ type: SmartType) {
        icon.image = UI.symbol(type.symbol, size: 10, weight: .bold)
        icon.contentTintColor = type.tint
        text.stringValue = type.rawValue
        text.textColor = type.tint
        layer?.backgroundColor = type.tint.withAlphaComponent(0.16).cgColor
    }
}

// MARK: - History view controller

final class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: ClipStore
    private let monitor: ClipboardMonitor
    private let screenshots: ScreenshotWatcher
    private let dismiss: () -> Void

    private let searchField = NSSearchField()
    private let filterControl = NSSegmentedControl()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyStack = NSStackView()
    private let emptyIcon = NSImageView()
    private let emptyLabel = UI.label(size: 13, color: .secondaryLabelColor)
    private let countLabel = UI.label(size: 11, color: .secondaryLabelColor)
    private let hintLabel = UI.label(size: 11, color: .tertiaryLabelColor)

    // Preview pane
    private let typeBadge = CapsuleBadge()
    private let metaLabel = UI.label(size: 11, color: .secondaryLabelColor)
    private let actionsPopup = NSPopUpButton()
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let previewCard = CardView()
    private let previewScroll = NSScrollView()
    private let previewText = NSTextView()
    private let previewImage = NSImageView()
    private let colorSwatch = NSView()

    private var results: [ClipItem] = []
    private var keyMonitor: Any?
    private var imageBottomFull: NSLayoutConstraint!
    private var imageBottomHalf: NSLayoutConstraint!
    private var scrollTopFull: NSLayoutConstraint!
    private var scrollTopHalf: NSLayoutConstraint!
    private var splitPreview = false {
        didSet {
            imageBottomFull.isActive = !splitPreview; scrollTopFull.isActive = !splitPreview
            imageBottomHalf.isActive = splitPreview; scrollTopHalf.isActive = splitPreview
        }
    }

    private static let size = NSSize(width: 800, height: 520)
    private static let leftWidth: CGFloat = 370

    init(store: ClipStore, monitor: ClipboardMonitor, screenshots: ScreenshotWatcher, dismiss: @escaping () -> Void) {
        self.store = store
        self.monitor = monitor
        self.screenshots = screenshots
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
        view = NSView(frame: NSRect(origin: .zero, size: Self.size))
        preferredContentSize = Self.size

        // ----- Left: search, filter, list
        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 15)
        searchField.focusRingType = .none

        filterControl.segmentStyle = .rounded
        filterControl.controlSize = .small
        filterControl.font = .systemFont(ofSize: 11, weight: .medium)
        filterControl.segmentCount = ClipStore.Filter.allCases.count
        for f in ClipStore.Filter.allCases {
            filterControl.setLabel(f.title, forSegment: f.rawValue)
            filterControl.setWidth(0, forSegment: f.rawValue)
        }
        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.style = .inset
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.menu = makeContextMenu()
        tableView.focusRingType = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)

        emptyIcon.image = UI.symbol("clipboard", size: 40, weight: .light)
        emptyIcon.contentTintColor = .quaternaryLabelColor
        emptyStack.orientation = .vertical
        emptyStack.spacing = 8
        emptyStack.alignment = .centerX
        emptyStack.addArrangedSubview(emptyIcon)
        emptyStack.addArrangedSubview(emptyLabel)
        emptyStack.isHidden = true
        emptyStack.translatesAutoresizingMaskIntoConstraints = false

        let left = NSStackView(views: [pad(searchField, 14, 14, 8, 14), pad(filterControl, 0, 14, 8, 14), scrollView])
        left.orientation = .vertical
        left.spacing = 0
        left.alignment = .leading
        left.setContentHuggingPriority(.required, for: .horizontal)
        searchField.widthAnchor.constraint(equalToConstant: Self.leftWidth - 28).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: Self.leftWidth).isActive = true
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // ----- Right: preview
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.font = .systemFont(ofSize: 11, weight: .medium)
        openButton.target = self
        openButton.action = #selector(openSelected)

        actionsPopup.pullsDown = true
        actionsPopup.isBordered = false
        actionsPopup.controlSize = .regular
        (actionsPopup.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        actionsPopup.setContentHuggingPriority(.required, for: .horizontal)
        actionsPopup.toolTip = "Actions"

        let previewHeader = NSStackView(views: [typeBadge, metaLabel, openButton, actionsPopup])
        previewHeader.orientation = .horizontal
        previewHeader.spacing = 8
        previewHeader.alignment = .centerY

        previewText.isEditable = false
        previewText.isRichText = true
        previewText.font = .systemFont(ofSize: 13)
        previewText.textContainerInset = NSSize(width: 12, height: 12)
        previewText.isVerticallyResizable = true
        previewText.isHorizontallyResizable = false
        previewText.autoresizingMask = [.width]
        previewText.textContainer?.widthTracksTextView = true
        previewText.drawsBackground = false
        previewScroll.documentView = previewText
        previewScroll.hasVerticalScroller = true
        previewScroll.autohidesScrollers = true
        previewScroll.borderType = .noBorder
        previewScroll.drawsBackground = false
        previewScroll.translatesAutoresizingMaskIntoConstraints = false

        previewImage.imageScaling = .scaleProportionallyDown
        previewImage.isHidden = true
        previewImage.translatesAutoresizingMaskIntoConstraints = false
        previewImage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewImage.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        previewImage.setContentHuggingPriority(.defaultLow, for: .vertical)
        previewImage.wantsLayer = true
        previewImage.layer?.cornerRadius = 8
        previewImage.layer?.cornerCurve = .continuous
        previewImage.layer?.masksToBounds = true

        colorSwatch.wantsLayer = true
        colorSwatch.layer?.cornerRadius = 12
        colorSwatch.layer?.cornerCurve = .continuous
        colorSwatch.layer?.borderWidth = 1
        colorSwatch.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        colorSwatch.isHidden = true
        colorSwatch.translatesAutoresizingMaskIntoConstraints = false

        previewCard.wantsLayer = true
        previewCard.layer?.cornerRadius = 12
        previewCard.layer?.cornerCurve = .continuous
        previewCard.layer?.borderWidth = 1
        previewCard.layer?.masksToBounds = true
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        previewCard.addSubview(previewScroll)
        previewCard.addSubview(previewImage)
        previewCard.addSubview(colorSwatch)

        imageBottomFull = previewImage.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -12)
        imageBottomHalf = previewImage.bottomAnchor.constraint(equalTo: previewCard.centerYAnchor, constant: -6)
        scrollTopFull = previewScroll.topAnchor.constraint(equalTo: previewCard.topAnchor)
        scrollTopHalf = previewScroll.topAnchor.constraint(equalTo: previewCard.centerYAnchor)
        imageBottomFull.isActive = true; scrollTopFull.isActive = true
        NSLayoutConstraint.activate([
            previewScroll.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor),
            previewScroll.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor),
            previewScroll.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor),
            previewImage.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 12),
            previewImage.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            previewImage.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
            colorSwatch.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 12),
            colorSwatch.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            colorSwatch.widthAnchor.constraint(equalToConstant: 72),
            colorSwatch.heightAnchor.constraint(equalToConstant: 72),
        ])

        let right = NSStackView(views: [previewHeader, previewCard])
        right.orientation = .vertical
        right.spacing = 10
        right.alignment = .leading
        right.edgeInsets = NSEdgeInsets(top: 14, left: 4, bottom: 12, right: 14)
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)
        previewHeader.widthAnchor.constraint(equalTo: right.widthAnchor, constant: -18).isActive = true
        previewCard.widthAnchor.constraint(equalTo: right.widthAnchor, constant: -18).isActive = true
        previewCard.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -12).isActive = true
        previewCard.setContentHuggingPriority(.defaultLow, for: .vertical)

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        left.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(left)
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: sidebar.topAnchor), left.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            left.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor), left.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
        ])
        let vSep = NSBox(); vSep.boxType = .separator
        let columns = NSStackView(views: [sidebar, vSep, right])
        columns.orientation = .horizontal
        columns.spacing = 0
        columns.alignment = .top
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)

        // ----- Footer
        let prefsBtn = UI.iconButton("gearshape", tip: "Preferences", target: self, action: #selector(openPreferences))
        let clearBtn = UI.iconButton("trash", tip: "Clear history (keeps pinned)", target: self, action: #selector(clearHistory))
        let quitBtn = UI.iconButton("power", tip: "Quit ClipStack", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [countLabel, hintLabel, spacer, prefsBtn, clearBtn, quitBtn])
        footer.orientation = .horizontal
        footer.spacing = 14
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 10, right: 14)
        footer.setContentHuggingPriority(.required, for: .vertical)
        footer.setCustomSpacing(8, after: countLabel)

        let hSep = NSBox(); hSep.boxType = .separator
        let root = NSStackView(views: [columns, hSep, footer])
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        view.addSubview(emptyStack)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Self.size.width),
            view.heightAnchor.constraint(equalToConstant: Self.size.height),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            columns.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            sidebar.heightAnchor.constraint(equalTo: columns.heightAnchor),
            right.heightAnchor.constraint(equalTo: columns.heightAnchor),
            vSep.heightAnchor.constraint(equalTo: columns.heightAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
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
        updateHint()
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

    /// Modification time of the running binary — tells you at a glance whether a rebuild actually launched.
    private static let buildStamp: String = {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        guard let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return "?" }
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return f.string(from: date)
    }()

    private func updateHint() {
        hintLabel.stringValue = "↩ paste  ⇧↩ plain  ⌘1–9 quick  \(Settings.hotKeyDescription) toggle  ·  build \(Self.buildStamp)"
    }

    // MARK: Data

    private var currentFilter: ClipStore.Filter { ClipStore.Filter(rawValue: filterControl.selectedSegment) ?? .all }
    @objc private func filterChanged() { reload() }

    private func reload() {
        let previousID = selected?.id
        results = store.filtered(searchField.stringValue, filter: currentFilter)
        tableView.reloadData()
        emptyLabel.stringValue = searchField.stringValue.isEmpty ? "Nothing here yet" : "No matches"
        emptyStack.isHidden = !results.isEmpty
        countLabel.stringValue = "\(store.items.count) item\(store.items.count == 1 ? "" : "s")"
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
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.image = UI.symbol("ellipsis.circle", size: 17, weight: .regular)
        actionsPopup.menu?.addItem(titleItem)

        previewImage.isHidden = true
        colorSwatch.isHidden = true
        previewScroll.isHidden = false
        openButton.isHidden = true
        splitPreview = false
        previewText.textContainerInset = NSSize(width: 12, height: 12)

        guard let item = selected else {
            typeBadge.isHidden = true
            metaLabel.stringValue = ""
            previewText.string = ""
            actionsPopup.isEnabled = false
            return
        }

        let type = item.smartType
        typeBadge.isHidden = false
        typeBadge.set(type)

        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        var meta = [df.string(from: item.createdAt)]
        if item.pinned { meta.insert("Pinned", at: 0) }

        switch item.kind {
        case .image:
            previewImage.image = item.image
            previewImage.isHidden = false
            previewScroll.isHidden = true
            if let img = item.image { meta.append("\(Int(img.size.width)) × \(Int(img.size.height))") }
            if let p = item.sourcePath ?? item.imagePath, let size = try? FileManager.default.attributesOfItem(atPath: p)[.size] as? Int {
                meta.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            if item.isScreenshot {
                if let app = item.appName { meta.append(app) }
                if !item.sourceExists { meta.append("file missing") }
                openButton.title = "Reveal"
                openButton.isHidden = !item.sourceExists
                addAction(item.ocrText == nil ? "Recognize Text" : "Copy Recognized Text", #selector(copyOCR))
                addAction("Move File to Trash", #selector(trashShot))
                actionsPopup.isEnabled = true
                if let ocr = item.ocrText, !ocr.isEmpty {
                    previewText.string = ocr
                    previewText.font = .systemFont(ofSize: 12)
                    previewText.textColor = .secondaryLabelColor
                    previewScroll.isHidden = false
                    splitPreview = true
                }
            } else {
                actionsPopup.isEnabled = false
            }

        case .files:
            previewText.string = (item.filePaths ?? []).joined(separator: "\n")
            previewText.font = .systemFont(ofSize: 12)
            previewText.textColor = .labelColor
            meta.append("\(item.filePaths?.count ?? 0) file\(item.filePaths?.count == 1 ? "" : "s")")
            openButton.title = "Reveal"
            openButton.isHidden = false
            actionsPopup.isEnabled = false

        case .text:
            let text = item.text ?? ""
            if let rtf = item.rtf, let attr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                previewText.textStorage?.setAttributedString(attr)
            } else {
                previewText.string = text
                previewText.font = type == .code || type == .json ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
                previewText.textColor = .labelColor
            }
            let lines = text.components(separatedBy: .newlines).count
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            meta.append("\(text.count) chars · \(words) words · \(lines) line\(lines == 1 ? "" : "s")")
            if item.isRich { meta.append("formatted") }

            if type == .color, let c = SmartType.parseColor(text), let c {
                colorSwatch.layer?.backgroundColor = c.cgColor
                colorSwatch.isHidden = false
                previewText.textContainerInset = NSSize(width: 96, height: 12)
            }

            if type.openURL(for: text) != nil {
                openButton.title = type == .email ? "Compose" : type == .phone ? "Call" : "Open"
                openButton.isHidden = false
            }

            for (i, a) in type.actions().enumerated() {
                let mi = NSMenuItem(title: a.title, action: #selector(runAction(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = i
                actionsPopup.menu?.addItem(mi)
            }
            actionsPopup.menu?.addItem(.separator())
            addAction("Paste as Plain Text", #selector(pastePlain), key: "⇧↩")
            actionsPopup.isEnabled = true
        }

        metaLabel.stringValue = meta.joined(separator: "  ·  ")
    }

    private func addAction(_ title: String, _ sel: Selector, key: String? = nil) {
        let mi = NSMenuItem(title: key.map { "\(title)  \($0)" } ?? title, action: sel, keyEquivalent: "")
        mi.target = self
        actionsPopup.menu?.addItem(mi)
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

    @objc private func copyOCR() {
        guard let item = selected else { return }
        if let t = item.ocrText, !t.isEmpty {
            dismiss()
            Paster.use(item, monitor: monitor, override: t)
        } else {
            screenshots.ocrNow(item)
        }
    }

    @objc private func trashShot() {
        if let item = selected, item.isScreenshot { store.trashScreenshot(item) }
    }

    @objc private func openSelected() {
        guard let item = selected else { return }
        dismiss()
        if item.isScreenshot, let url = item.sourceURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if item.kind == .files {
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
        m.addItem(withTitle: "Copy Only", action: #selector(copySelected), keyEquivalent: "")
        m.addItem(withTitle: "Paste as Plain Text", action: #selector(pastePlain), keyEquivalent: "")
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
    private let tile = IconTile()
    private let title = UI.label(size: 13, weight: .medium)
    private let subtitle = UI.label(size: 11, color: .secondaryLabelColor)
    private let pin = NSImageView()
    private let keyBadge = UI.label(size: 10, weight: .medium, color: .tertiaryLabelColor)
    private let keyBox = NSView()
    private static let relFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        tile.translatesAutoresizingMaskIntoConstraints = false

        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        subtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)

        pin.image = UI.symbol("pin.fill", size: 10, weight: .semibold)
        pin.contentTintColor = .systemOrange
        pin.translatesAutoresizingMaskIntoConstraints = false

        keyBadge.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        keyBadge.alignment = .center
        keyBox.wantsLayer = true
        keyBox.layer?.cornerRadius = 5
        keyBox.layer?.borderWidth = 1
        keyBox.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        keyBox.translatesAutoresizingMaskIntoConstraints = false
        keyBadge.translatesAutoresizingMaskIntoConstraints = false
        keyBox.addSubview(keyBadge)

        let h = NSStackView(views: [tile, text, pin, keyBox])
        h.orientation = .horizontal
        h.spacing = 10
        h.alignment = .centerY
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)

        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            h.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            text.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            h.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 38),
            tile.heightAnchor.constraint(equalToConstant: 38),
            pin.widthAnchor.constraint(equalToConstant: 12),
            keyBox.widthAnchor.constraint(equalToConstant: 30),
            keyBox.heightAnchor.constraint(equalToConstant: 18),
            keyBadge.centerXAnchor.constraint(equalTo: keyBox.centerXAnchor),
            keyBadge.centerYAnchor.constraint(equalTo: keyBox.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with item: ClipItem, index: Int) {
        let type = item.smartType
        title.stringValue = item.preview
        let when = Self.relFmt.localizedString(for: item.createdAt, relativeTo: Date())
        var sub = type == .plain ? when : "\(type.rawValue) · \(when)"
        if item.isScreenshot, let app = item.appName { sub = "\(app) · \(when)" }
        subtitle.stringValue = sub
        pin.isHidden = !item.pinned
        keyBox.isHidden = index >= 9
        keyBadge.stringValue = "⌘\(index + 1)"

        if item.kind == .image, let img = item.image {
            tile.setImage(img)
        } else if type == .color, let c = SmartType.parseColor(item.text ?? ""), let c {
            tile.setColor(c)
        } else if item.kind == .files, let first = item.fileURLs.first {
            tile.setImage(NSWorkspace.shared.icon(forFile: first.path))
        } else {
            tile.setSymbol(type.symbol, tint: type.tint)
        }
    }
}
