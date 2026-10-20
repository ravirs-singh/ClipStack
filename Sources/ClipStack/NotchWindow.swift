import AppKit

/// A Dynamic-Island-style panel that lives over the MacBook notch.
///
/// States:
///  - collapsed: black shape the size of the notch (invisible against it); hover target + drop target
///  - toast:     briefly widened after a copy, showing what was captured
///  - expanded:  hover/click → recent clips as chips, tap to paste, drop zone
final class NotchController {
    private let store: ClipStore
    private let monitor: ClipboardMonitor
    private let openHistory: () -> Void

    private var panel: NSPanel!
    private var notchView: NotchView!
    private var screen: NSScreen?
    private var notchSize = NSSize(width: 200, height: 32)
    private var hasRealNotch = false

    private enum State { case collapsed, toast, shot, expanded }
    private var state: State = .collapsed
    private var collapseTimer: Timer?
    private var hovering = false
    private var observers: [NSObjectProtocol] = []

    private let expandedSize = NSSize(width: 560, height: 190)
    private let shotToastSize = NSSize(width: 520, height: 96)

    init(store: ClipStore, monitor: ClipboardMonitor, openHistory: @escaping () -> Void) {
        self.store = store
        self.monitor = monitor
        self.openHistory = openHistory

        notchView = NotchView()
        notchView.onEnter = { [weak self] in self?.mouseEntered() }
        notchView.onExit = { [weak self] in self?.mouseExited() }
        notchView.onClick = { [weak self] in self?.clicked() }
        notchView.onPick = { [weak self] item in self?.pick(item) }
        notchView.onOpenHistory = { [weak self] in self?.collapse(); self?.openHistory() }
        notchView.onDrop = { [weak self] in self?.handleDrop($0) ?? false }
        notchView.onShotAction = { [weak self] action, item in self?.shotAction(action, item) }

        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = notchView

        observers.append(NotificationCenter.default.addObserver(forName: ClipStore.didAdd, object: nil, queue: .main) { [weak self] n in
            guard let item = n.userInfo?["item"] as? ClipItem else { return }
            self?.showToast(for: item)
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.relayout()
        })
        observers.append(NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.applyEnabled()
        })

        applyEnabled()
    }

    // MARK: Enable / layout

    private func applyEnabled() {
        if Settings.notchEnabled {
            relayout()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func relayout() {
        // Prefer the built-in display (the one with a notch); fall back to the main screen.
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else { return }

        let inset = screen.safeAreaInsets.top
        hasRealNotch = inset > 0
        if hasRealNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchSize = NSSize(width: screen.frame.width - l.width - r.width, height: inset)
        } else {
            notchSize = NSSize(width: 180, height: NSStatusBar.system.thickness)
        }
        notchView.baseNotchSize = notchSize
        notchView.hasRealNotch = hasRealNotch
        setState(state, animated: false)
    }

    private func frame(for state: State) -> NSRect {
        guard let screen else { return .zero }
        let size: NSSize
        switch state {
        case .collapsed: size = NSSize(width: notchSize.width + (hasRealNotch ? 12 : 0), height: notchSize.height)
        case .toast:     size = NSSize(width: max(notchSize.width + 240, 380), height: notchSize.height + 14)
        case .shot:      size = NSSize(width: max(shotToastSize.width, notchSize.width + 200), height: notchSize.height + shotToastSize.height)
        case .expanded:  size = expandedSize
        }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func setState(_ new: State, animated: Bool) {
        state = new
        notchView.mode = {
            switch new {
            case .collapsed: return .collapsed
            case .toast: return .toast
            case .shot: return .shot
            case .expanded: return .expanded
            }
        }()
        let target = frame(for: new)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
        notchView.needsLayout = true
    }

    // MARK: Interactions

    private func mouseEntered() {
        hovering = true
        collapseTimer?.invalidate()
        if state != .expanded && state != .shot { expand() }
    }

    private func mouseExited() {
        hovering = false
        scheduleCollapse(after: 0.35)
    }

    private func clicked() {
        if state == .expanded { collapse(); openHistory() } else { expand() }
    }

    private func expand() {
        notchView.items = Array(store.filtered("").prefix(6))
        setState(.expanded, animated: true)
    }

    private func collapse() {
        collapseTimer?.invalidate()
        setState(.collapsed, animated: true)
    }

    private func scheduleCollapse(after s: TimeInterval) {
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: s, repeats: false) { [weak self] _ in
            guard let self, !self.hovering else { return }
            self.collapse()
        }
    }

    private func showToast(for item: ClipItem) {
        guard Settings.notchEnabled, Settings.notchToasts, state != .expanded else {
            if state == .expanded { notchView.items = Array(store.filtered("").prefix(6)) }
            return
        }
        if item.isScreenshot && !Settings.notchScreenshotToast { return }
        notchView.toastItem = item
        if item.isScreenshot {
            setState(.shot, animated: true)
            scheduleCollapse(after: 6)
        } else {
            setState(.toast, animated: true)
            scheduleCollapse(after: 2.2)
        }
    }

    private func shotAction(_ action: NotchView.ShotAction, _ item: ClipItem) {
        collapse()
        switch action {
        case .copy: Paster.copy(item, monitor: monitor)
        case .text:
            if let t = item.ocrText, !t.isEmpty { Paster.copy(item, monitor: monitor, override: t) } else { NSSound.beep() }
        case .reveal: if let u = item.sourceURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        case .trash: store.trashScreenshot(item)
        }
    }

    private func pick(_ item: ClipItem) {
        collapse()
        // Panel is non-activating, so the user's app is still frontmost — paste lands there directly.
        Paster.use(item, monitor: monitor)
    }

    private func handleDrop(_ pb: NSPasteboard) -> Bool {
        let general = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            general.clearContents(); general.writeObjects(urls as [NSURL]); return true
        }
        if let s = pb.string(forType: .string) {
            general.clearContents(); general.setString(s, forType: .string); return true
        }
        if let img = NSImage(pasteboard: pb) {
            general.clearContents(); general.writeObjects([img]); return true
        }
        return false
    }
}

// MARK: - View

final class NotchView: NSView {
    enum Mode { case collapsed, toast, shot, expanded }
    enum ShotAction { case copy, text, reveal, trash }
    var onShotAction: ((ShotAction, ClipItem) -> Void)?

    var mode: Mode = .collapsed { didSet { needsLayout = true; needsDisplay = true } }
    var baseNotchSize = NSSize(width: 200, height: 32)
    var hasRealNotch = false
    var items: [ClipItem] = [] { didSet { rebuildChips() } }
    var toastItem: ClipItem? { didSet { updateToast() } }

    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?
    var onPick: ((ClipItem) -> Void)?
    var onOpenHistory: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?

    private let shape = CAShapeLayer()
    private let toastIcon = NSImageView()
    private let toastLabel = NSTextField(labelWithString: "")
    private let toastStack = NSStackView()
    private let chipsStack = NSStackView()
    private let header = NSTextField(labelWithString: "Recent clips")
    private let historyButton = NSButton(title: "History", target: nil, action: nil)
    private let dropHint = NSTextField(labelWithString: "Drop files or text here to copy")
    private var dragHighlight = false { didSet { needsDisplay = true } }
    private let shotThumb = NSImageView()
    private let shotTitle = NSTextField(labelWithString: "")
    private let shotSub = NSTextField(labelWithString: "")
    private let shotButtons = NSStackView()
    private var shotViews: [NSView] { [shotThumb, shotTitle, shotSub, shotButtons] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(shape)
        shape.fillColor = NSColor.black.cgColor

        toastIcon.contentTintColor = .white
        toastIcon.imageScaling = .scaleProportionallyUpOrDown
        toastLabel.textColor = .white
        toastLabel.font = .systemFont(ofSize: 12, weight: .medium)
        toastLabel.lineBreakMode = .byTruncatingTail
        toastLabel.maximumNumberOfLines = 1
        toastStack.orientation = .horizontal
        toastStack.spacing = 8
        toastStack.addArrangedSubview(toastIcon)
        toastStack.addArrangedSubview(toastLabel)
        toastStack.isHidden = true
        addSubview(toastStack)

        header.textColor = NSColor.white.withAlphaComponent(0.7)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        historyButton.bezelStyle = .inline
        historyButton.controlSize = .small
        historyButton.target = self
        historyButton.action = #selector(openHistoryTapped)
        historyButton.contentTintColor = .white
        dropHint.textColor = NSColor.white.withAlphaComponent(0.45)
        dropHint.font = .systemFont(ofSize: 10)

        chipsStack.orientation = .horizontal
        chipsStack.spacing = 8
        chipsStack.distribution = .fillEqually
        [header, historyButton, chipsStack, dropHint].forEach { $0.isHidden = true; addSubview($0) }

        shotThumb.imageScaling = .scaleProportionallyUpOrDown
        shotThumb.wantsLayer = true
        shotThumb.layer?.cornerRadius = 6
        shotThumb.layer?.masksToBounds = true
        shotTitle.textColor = .white
        shotTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        shotTitle.lineBreakMode = .byTruncatingMiddle
        shotSub.textColor = NSColor.white.withAlphaComponent(0.6)
        shotSub.font = .systemFont(ofSize: 10)
        shotButtons.orientation = .horizontal
        shotButtons.spacing = 6
        for (title, sym, action) in [("Copy", "doc.on.doc", ShotAction.copy), ("Text", "text.viewfinder", .text),
                                     ("Reveal", "folder", .reveal), ("Trash", "trash", .trash)] {
            let b = NSButton(title: title, image: NSImage(systemSymbolName: sym, accessibilityDescription: title)!, target: self, action: #selector(shotButtonTapped(_:)))
            b.bezelStyle = .inline
            b.controlSize = .small
            b.imagePosition = .imageLeading
            b.contentTintColor = .white
            b.tag = [ShotAction.copy, .text, .reveal, .trash].firstIndex(of: action)!
            shotButtons.addArrangedSubview(b)
        }
        shotViews.forEach { $0.isHidden = true; addSubview($0) }

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        registerForDraggedTypes([.fileURL, .string, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Layout & drawing

    override func layout() {
        super.layout()
        shape.frame = bounds
        shape.path = notchPath().toCGPath()
        shape.fillColor = (dragHighlight ? NSColor(white: 0.12, alpha: 1) : .black).cgColor

        let padX: CGFloat = 16
        switch mode {
        case .collapsed:
            toastStack.isHidden = true
            shotViews.forEach { $0.isHidden = true }
            setExpandedVisible(false)
        case .shot:
            toastStack.isHidden = true
            setExpandedVisible(false)
            shotViews.forEach { $0.isHidden = false }
            let top = baseNotchSize.height + 10
            let thumbH = bounds.height - top - 10
            shotThumb.frame = NSRect(x: padX, y: top, width: thumbH * 1.5, height: thumbH)
            let tx = padX + thumbH * 1.5 + 12
            shotTitle.frame = NSRect(x: tx, y: top, width: bounds.width - tx - padX, height: 16)
            shotSub.frame = NSRect(x: tx, y: top + 18, width: bounds.width - tx - padX, height: 14)
            shotButtons.frame = NSRect(x: tx, y: bounds.height - 34, width: bounds.width - tx - padX, height: 24)
        case .toast:
            shotViews.forEach { $0.isHidden = true }
            setExpandedVisible(false)
            toastStack.isHidden = false
            let w = bounds.width - padX * 2
            toastStack.frame = NSRect(x: padX, y: (bounds.height - 18) / 2, width: w, height: 18)
            toastIcon.frame.size = NSSize(width: 16, height: 16)
        case .expanded:
            toastStack.isHidden = true
            shotViews.forEach { $0.isHidden = true }
            setExpandedVisible(true)
            let top = baseNotchSize.height + 8
            header.frame = NSRect(x: padX, y: top, width: 200, height: 16)
            historyButton.sizeToFit()
            historyButton.frame.origin = NSPoint(x: bounds.width - padX - historyButton.frame.width, y: top - 3)
            chipsStack.frame = NSRect(x: padX, y: top + 24, width: bounds.width - padX * 2, height: 72)
            dropHint.sizeToFit()
            dropHint.frame.origin = NSPoint(x: (bounds.width - dropHint.frame.width) / 2, y: bounds.height - 22)
        }
    }

    private func setExpandedVisible(_ v: Bool) {
        header.isHidden = !v
        historyButton.isHidden = !v
        chipsStack.isHidden = !v
        dropHint.isHidden = !v
    }

    /// Flat top (hugs the screen edge), rounded bottom corners, small concave "ears" at the top like the real notch.
    private func notchPath() -> NSBezierPath {
        let r: CGFloat = mode == .collapsed ? (hasRealNotch ? 10 : 12) : 22
        let ear: CGFloat = hasRealNotch ? 6 : 0
        let b = bounds
        let p = NSBezierPath()
        p.move(to: NSPoint(x: b.minX, y: b.minY))
        // top-left ear curving down into the body
        p.curve(to: NSPoint(x: b.minX + ear, y: b.minY + ear),
                controlPoint1: NSPoint(x: b.minX + ear * 0.6, y: b.minY),
                controlPoint2: NSPoint(x: b.minX + ear, y: b.minY + ear * 0.4))
        p.line(to: NSPoint(x: b.minX + ear, y: b.maxY - r))
        p.appendArc(withCenter: NSPoint(x: b.minX + ear + r, y: b.maxY - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        p.line(to: NSPoint(x: b.maxX - ear - r, y: b.maxY))
        p.appendArc(withCenter: NSPoint(x: b.maxX - ear - r, y: b.maxY - r), radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        p.line(to: NSPoint(x: b.maxX - ear, y: b.minY + ear))
        p.curve(to: NSPoint(x: b.maxX, y: b.minY),
                controlPoint1: NSPoint(x: b.maxX - ear, y: b.minY + ear * 0.4),
                controlPoint2: NSPoint(x: b.maxX - ear * 0.6, y: b.minY))
        p.close()
        return p
    }

    // MARK: Content

    private func updateToast() {
        guard let item = toastItem else { return }
        let t = item.smartType
        toastIcon.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.rawValue)
        toastLabel.stringValue = "Copied · " + item.preview
        if item.isScreenshot {
            shotThumb.image = item.image
            shotTitle.stringValue = "Screenshot saved · " + item.preview
            shotSub.stringValue = [item.appName, item.image.map { "\(Int($0.size.width))×\(Int($0.size.height))" }].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private func rebuildChips() {
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, item) in items.enumerated() {
            let chip = ChipView(item: item, index: i)
            chip.onTap = { [weak self] in self?.onPick?(item) }
            chipsStack.addArrangedSubview(chip)
        }
        if items.isEmpty {
            let empty = NSTextField(labelWithString: "Nothing copied yet")
            empty.textColor = NSColor.white.withAlphaComponent(0.5)
            empty.alignment = .center
            chipsStack.addArrangedSubview(empty)
        }
    }

    @objc private func openHistoryTapped() { onOpenHistory?() }
    @objc private func shotButtonTapped(_ sender: NSButton) {
        guard let item = toastItem else { return }
        onShotAction?([ShotAction.copy, .text, .reveal, .trash][sender.tag], item)
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseUp(with event: NSEvent) {
        // Only treat clicks on the black shape itself (not chips/buttons) as a toggle.
        if hitTest(convert(event.locationInWindow, from: nil)) === self { onClick?() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Ignore clicks outside the black shape so transparent corners don't eat events.
        guard notchPath().contains(point) else { return nil }
        return super.hitTest(point)
    }

    // MARK: Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragHighlight = true
        onEnter?()
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dragHighlight = false; onExit?() }
    override func draggingEnded(_ sender: NSDraggingInfo) { dragHighlight = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragHighlight = false
        return onDrop?(sender.draggingPasteboard) ?? false
    }
}

// MARK: - Chip

/// A tappable card showing one recent clip.
final class ChipView: NSView, NSDraggingSource {
    var onTap: (() -> Void)?
    private let item: ClipItem
    private var dragStart: NSPoint?

    init(item: ClipItem, index: Int) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
        layer?.cornerRadius = 12

        let type = item.smartType
        let icon = NSImageView()
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyUpOrDown
        if item.kind == .image, let img = item.image {
            icon.image = img
            icon.contentTintColor = nil
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 4
            icon.layer?.masksToBounds = true
        } else if type == .color, let c = SmartType.parseColor(item.text ?? ""), let c {
            icon.wantsLayer = true
            icon.layer?.backgroundColor = c.cgColor
            icon.layer?.cornerRadius = 4
        } else {
            icon.image = NSImage(systemSymbolName: type.symbol, accessibilityDescription: type.rawValue)
        }

        let label = NSTextField(wrappingLabelWithString: item.preview)
        label.textColor = .white
        label.font = .systemFont(ofSize: 11)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let key = NSTextField(labelWithString: index < 9 ? "⌘\(index + 1)" : "")
        key.textColor = NSColor.white.withAlphaComponent(0.4)
        key.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)

        let v = NSStackView(views: [icon, label, key])
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 4
        v.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 6, right: 8)
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor),
            v.bottomAnchor.constraint(equalTo: bottomAnchor),
            v.leadingAnchor.constraint(equalTo: leadingAnchor),
            v.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -16),
        ])
        toolTip = item.text.map { String($0.prefix(400)) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 1, alpha: 0.22).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor }
    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { if dragStart != nil { onTap?() }; dragStart = nil }

    /// Drag a screenshot or file chip out of the notch to drop it into another app.
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 6 else { return }
        dragStart = nil
        let urls: [URL] = item.isScreenshot ? (item.sourceURL.map { [$0] } ?? []) : item.fileURLs
        guard !urls.isEmpty else { return }
        let dragItems = urls.map { url -> NSDraggingItem in
            let di = NSDraggingItem(pasteboardWriter: url as NSURL)
            di.setDraggingFrame(bounds, contents: item.image ?? NSWorkspace.shared.icon(forFile: url.path))
            return di
        }
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

private extension NSBezierPath {
    func toCGPath() -> CGPath {
        if #available(macOS 14, *) { return cgPath }
        let path = CGMutablePath()
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo: path.move(to: pts[0])
            case .lineTo: path.addLine(to: pts[0])
            case .curveTo: path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .closePath: path.closeSubpath()
            default: break
            }
        }
        return path
    }
}
