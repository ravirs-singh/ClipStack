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

    private let expandedSize = NSSize(width: 560, height: 170)
    private let musicExtra: CGFloat = 84          // extra height for the player card when music is playing
    private let wing: CGFloat = 44                // width added each side of the notch for the now-playing hint
    private let nowPlaying = NowPlayingMonitor()
    private var positionTimer: Timer?
    private var animToken = 0
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
        notchView.onMusic = { [weak self] cmd in
            switch cmd { case .playPause: self?.nowPlaying.playPause(); case .next: self?.nowPlaying.next(); case .previous: self?.nowPlaying.previous() }
        }

        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
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
        observers.append(NotificationCenter.default.addObserver(forName: NowPlayingMonitor.changed, object: nil, queue: .main) { [weak self] _ in
            self?.nowPlayingChanged()
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
        case .collapsed:
            let wings = notchView.nowPlaying != nil ? wing * 2 : 0
            size = NSSize(width: notchSize.width + (hasRealNotch ? 12 : 0) + wings, height: notchSize.height)
        case .toast:     size = NSSize(width: max(notchSize.width + 240, 380), height: notchSize.height + 14)
        case .shot:      size = NSSize(width: max(shotToastSize.width, notchSize.width + 200), height: notchSize.height + shotToastSize.height)
        case .expanded:  size = NSSize(width: expandedSize.width, height: expandedSize.height + (notchView.nowPlaying != nil ? musicExtra : 0))
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
        guard animated, let screen, panel.isVisible else {
            panel.setFrame(target, display: true)
            notchView.shapeRect = nil
            return
        }
        // Window frame animation is timer-driven and stutters, so: size the window to the union of old and new
        // immediately, morph the black shape with Core Animation, then shrink the window to the final size.
        let current = panel.frame
        let unionSize = NSSize(width: max(current.width, target.width), height: max(current.height, target.height))
        let union = NSRect(x: screen.frame.midX - unionSize.width / 2, y: screen.frame.maxY - unionSize.height,
                           width: unionSize.width, height: unionSize.height)
        let curShape = notchView.rect
        let dx = (unionSize.width - current.width) / 2
        let from = curShape.offsetBy(dx: dx, dy: 0)
        let to = NSRect(x: (unionSize.width - target.width) / 2, y: 0, width: target.width, height: target.height)
        if union != current {
            notchView.shapeRect = from
            panel.setFrame(union, display: false)
        }
        animToken += 1
        let token = animToken
        notchView.animateShape(from: from, to: to, duration: 0.3) { [weak self] in
            guard let self, token == self.animToken else { return }
            self.panel.setFrame(target, display: true)
            self.notchView.shapeRect = nil
        }
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

    // MARK: Now playing

    private func nowPlayingChanged() {
        let was = notchView.nowPlaying != nil
        notchView.nowPlaying = nowPlaying.info
        notchView.wing = wing
        let now = notchView.nowPlaying != nil
        // Grow/shrink the notch only when playback starts/stops; plain progress updates just relayout in place.
        if was != now { setState(state, animated: true) } else { notchView.needsLayout = true }
        positionTimer?.invalidate()
        if let i = nowPlaying.info, i.isPlaying {
            positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.notchView.tickProgress(0.5) }
        }
    }

    private func collapse() {
        collapseTimer?.invalidate()
        guard state != .collapsed else { return }
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
        if state == .expanded { notchView.items = Array(store.filtered("").prefix(6)); return }
        guard Settings.notchEnabled else { return }
        // Screenshots never flash the notch unless the screenshot drop-down is explicitly on.
        if item.isScreenshot {
            guard Settings.notchScreenshotToast else { return }
        } else {
            guard Settings.notchToasts else { return }
        }
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
    enum MusicCommand { case playPause, next, previous }
    var onMusic: ((MusicCommand) -> Void)?
    var nowPlaying: NowPlayingInfo? { didSet { updateMusic() } }
    var wing: CGFloat = 44
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
    private let rim = CAShapeLayer()
    /// Everything visible lives in `content`, which is positioned over the black shape so the window can be
    /// larger than the shape during transitions.
    private let content = FlippedView()
    /// Where the black shape currently sits within bounds (nil = fills bounds).
    var shapeRect: NSRect? { didSet { needsLayout = true } }
    var rect: NSRect { shapeRect ?? bounds }
    private let toastIcon = NSImageView()
    private let toastLabel = NSTextField(labelWithString: "")
    private let toastStack = NSStackView()
    private let chipsStack = NSStackView()
    private let header = NSTextField(labelWithString: "Recent clips")
    private let historyButton = FirstClickButton(title: "History", target: nil, action: nil)
    private let dropHint = NSTextField(labelWithString: "Drop files or text here to copy")
    private var dragHighlight = false { didSet { needsDisplay = true } }
    private let shotThumb = NSImageView()
    private let shotTitle = NSTextField(labelWithString: "")
    private let shotSub = NSTextField(labelWithString: "")
    private let shotButtons = NSStackView()
    private var shotViews: [NSView] { [shotThumb, shotTitle, shotSub, shotButtons] }

    // Now playing: collapsed hint (art + bars in the wings) and expanded player card
    private let hintArt = NSImageView()
    private let hintBars = AudioBarsView()
    private let cardArt = NSImageView()
    private let cardTitle = NSTextField(labelWithString: "")
    private let cardArtist = NSTextField(labelWithString: "")
    private let cardProgress = CALayer()
    private let cardTrack = CALayer()
    private let cardTime = NSTextField(labelWithString: "")
    private let prevButton = FirstClickButton()
    private let playButton = FirstClickButton()
    private let nextButton = FirstClickButton()
    private var progressPosition: TimeInterval = 0
    private var musicViews: [NSView] { [cardArt, cardTitle, cardArtist, cardTime, prevButton, playButton, nextButton] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(shape)
        shape.fillColor = NSColor.black.cgColor
        rim.fillColor = nil
        rim.strokeColor = NSColor.white.withAlphaComponent(0.09).cgColor
        rim.lineWidth = 1
        layer?.addSublayer(rim)
        addSubview(content)

        toastIcon.contentTintColor = .white
        toastIcon.wantsLayer = true
        toastIcon.layer?.cornerRadius = 9
        toastIcon.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
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
        content.addSubview(toastStack)

        header.textColor = NSColor.white.withAlphaComponent(0.5)
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.stringValue = "RECENT"
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
        [header, historyButton, chipsStack, dropHint].forEach { $0.isHidden = true; content.addSubview($0) }

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
            let b = FirstClickButton(title: title, image: NSImage(systemSymbolName: sym, accessibilityDescription: title)!, target: self, action: #selector(shotButtonTapped(_:)))
            b.bezelStyle = .inline
            b.controlSize = .small
            b.imagePosition = .imageLeading
            b.contentTintColor = .white
            b.tag = [ShotAction.copy, .text, .reveal, .trash].firstIndex(of: action)!
            shotButtons.addArrangedSubview(b)
        }
        shotViews.forEach { $0.isHidden = true; content.addSubview($0) }

        for v in [hintArt, cardArt] {
            v.imageScaling = .scaleProportionallyUpOrDown
            v.wantsLayer = true
            v.layer?.cornerRadius = 6
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
        cardArt.layer?.cornerRadius = 10
        hintBars.color = NSColor(red: 0.98, green: 0.35, blue: 0.45, alpha: 1)
        cardTitle.textColor = .white
        cardTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        cardTitle.lineBreakMode = .byTruncatingTail
        cardArtist.textColor = NSColor.white.withAlphaComponent(0.6)
        cardArtist.font = .systemFont(ofSize: 11)
        cardArtist.lineBreakMode = .byTruncatingTail
        cardTime.textColor = NSColor.white.withAlphaComponent(0.45)
        cardTime.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        cardTrack.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        cardTrack.cornerRadius = 1.5
        cardProgress.backgroundColor = NSColor.white.cgColor
        cardProgress.cornerRadius = 1.5
        content.wantsLayer = true
        content.layer?.addSublayer(cardTrack)
        content.layer?.addSublayer(cardProgress)
        for (b, sym, cmd) in [(prevButton, "backward.fill", MusicCommand.previous), (playButton, "play.fill", .playPause), (nextButton, "forward.fill", .next)] {
            b.image = UI.symbol(sym, size: b === playButton ? 16 : 13, weight: .bold)
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.contentTintColor = .white
            b.target = self
            b.action = #selector(musicButtonTapped(_:))
            b.tag = [MusicCommand.previous, .playPause, .next].firstIndex(of: cmd)!
        }
        ([hintArt, hintBars] + musicViews).forEach { $0.isHidden = true; content.addSubview($0) }
        cardTrack.isHidden = true; cardProgress.isHidden = true

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        registerForDraggedTypes([.fileURL, .string, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Layout & drawing

    override func layout() {
        super.layout()
        let r = rect
        shape.frame = bounds
        shape.path = notchPath(in: r).toCGPath()
        rim.frame = bounds
        rim.path = shape.path
        rim.isHidden = mode == .collapsed
        shape.fillColor = (dragHighlight ? NSColor(white: 0.12, alpha: 1) : .black).cgColor
        content.frame = r
        let cb = content.bounds   // inner layout is relative to the shape

        let padX: CGFloat = 16
        switch mode {
        case .collapsed:
            toastStack.isHidden = true
            shotViews.forEach { $0.isHidden = true }
            setExpandedVisible(false)
            setMusicCardVisible(false)
            let music = nowPlaying != nil
            hintArt.isHidden = !music
            hintBars.isHidden = !music
            if music {
                let s = cb.height - 10
                hintArt.frame = NSRect(x: 10, y: 5, width: s, height: s)
                hintBars.frame = NSRect(x: cb.width - 10 - 18, y: (cb.height - 14) / 2, width: 18, height: 14)
                hintBars.isAnimating = nowPlaying?.isPlaying == true
            }
        case .shot:
            toastStack.isHidden = true
            setExpandedVisible(false)
            hintArt.isHidden = true; hintBars.isHidden = true; setMusicCardVisible(false)
            shotViews.forEach { $0.isHidden = false }
            let top = baseNotchSize.height + 10
            let thumbH = cb.height - top - 10
            shotThumb.frame = NSRect(x: padX, y: top, width: thumbH * 1.5, height: thumbH)
            let tx = padX + thumbH * 1.5 + 12
            shotTitle.frame = NSRect(x: tx, y: top, width: cb.width - tx - padX, height: 16)
            shotSub.frame = NSRect(x: tx, y: top + 18, width: cb.width - tx - padX, height: 14)
            shotButtons.frame = NSRect(x: tx, y: cb.height - 34, width: cb.width - tx - padX, height: 24)
        case .toast:
            shotViews.forEach { $0.isHidden = true }
            setExpandedVisible(false)
            hintArt.isHidden = true; hintBars.isHidden = true; setMusicCardVisible(false)
            toastStack.isHidden = false
            let w = cb.width - padX * 2
            toastStack.frame = NSRect(x: padX, y: (cb.height - 18) / 2, width: w, height: 18)
            toastIcon.frame.size = NSSize(width: 18, height: 18)
        case .expanded:
            toastStack.isHidden = true
            shotViews.forEach { $0.isHidden = true }
            hintArt.isHidden = true; hintBars.isHidden = true
            setExpandedVisible(true)
            var top = baseNotchSize.height + 8
            let music = nowPlaying != nil
            setMusicCardVisible(music)
            if music {
                let artS: CGFloat = 56
                cardArt.frame = NSRect(x: padX, y: top, width: artS, height: artS)
                let tx = padX + artS + 12
                let controlsW: CGFloat = 110
                let textW = cb.width - tx - padX - controlsW
                cardTitle.frame = NSRect(x: tx, y: top + 2, width: textW, height: 17)
                cardArtist.frame = NSRect(x: tx, y: top + 21, width: textW, height: 14)
                cardTrack.frame = CGRect(x: tx, y: top + 44, width: textW, height: 3)
                layoutProgress()
                cardTime.sizeToFit()
                cardTime.frame.origin = NSPoint(x: tx, y: top + 50)
                let cx = cb.width - padX - controlsW
                prevButton.frame = NSRect(x: cx, y: top + 14, width: 30, height: 28)
                playButton.frame = NSRect(x: cx + 38, y: top + 12, width: 34, height: 32)
                nextButton.frame = NSRect(x: cx + 80, y: top + 14, width: 30, height: 28)
                top += artS + 28
            }
            header.frame = NSRect(x: padX, y: top, width: 200, height: 16)
            historyButton.sizeToFit()
            historyButton.frame.origin = NSPoint(x: cb.width - padX - historyButton.frame.width, y: top - 3)
            chipsStack.frame = NSRect(x: padX, y: top + 24, width: cb.width - padX * 2, height: 72)
            dropHint.sizeToFit()
            dropHint.frame.origin = NSPoint(x: (cb.width - dropHint.frame.width) / 2, y: cb.height - 22)
        }
    }

    /// Morph the black shape from one rect to another with Core Animation; content cross-fades.
    func animateShape(from: NSRect, to: NSRect, duration: TimeInterval, completion: @escaping () -> Void) {
        guard from != to else { shapeRect = to; completion(); return }
        let fromPath = notchPath(in: from).toCGPath()
        shapeRect = to
        content.alphaValue = 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layoutSubtreeIfNeeded()
        CATransaction.commit()

        let morph = CABasicAnimation(keyPath: "path")
        morph.fromValue = fromPath
        morph.toValue = shape.path
        morph.duration = duration
        morph.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
        shape.add(morph, forKey: "morph")
        rim.add(morph, forKey: "morph")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.45) { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration * 0.5
                self?.content.animator().alphaValue = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }

    private func setMusicCardVisible(_ v: Bool) {
        musicViews.forEach { $0.isHidden = !v }
        cardTrack.isHidden = !v; cardProgress.isHidden = !v
    }

    private func layoutProgress() {
        guard let i = nowPlaying, i.duration > 0 else { cardProgress.frame = .zero; return }
        let frac = CGFloat(min(1, max(0, progressPosition / i.duration)))
        cardProgress.frame = CGRect(x: cardTrack.frame.minX, y: cardTrack.frame.minY, width: cardTrack.frame.width * frac, height: cardTrack.frame.height)
        let fmt: (TimeInterval) -> String = { t in String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
        cardTime.stringValue = "\(fmt(progressPosition)) / \(fmt(i.duration))"
    }

    private func updateMusic() {
        guard let i = nowPlaying else { needsLayout = true; return }
        progressPosition = i.position
        hintArt.image = i.artwork
        cardArt.image = i.artwork
        cardTitle.stringValue = i.title
        cardArtist.stringValue = i.artist
        playButton.image = UI.symbol(i.isPlaying ? "pause.fill" : "play.fill", size: 16, weight: .bold)
        hintBars.isAnimating = i.isPlaying
        needsLayout = true
    }

    /// Advance the progress bar between polls.
    func tickProgress(_ dt: TimeInterval) {
        guard let i = nowPlaying, i.isPlaying else { return }
        progressPosition = min(i.duration, progressPosition + dt)
        if mode == .expanded { CATransaction.begin(); CATransaction.setDisableActions(true); layoutProgress(); CATransaction.commit() }
    }

    @objc private func musicButtonTapped(_ sender: NSButton) {
        onMusic?([MusicCommand.previous, .playPause, .next][sender.tag])
    }

    private func setExpandedVisible(_ v: Bool) {
        header.isHidden = !v
        historyButton.isHidden = !v
        chipsStack.isHidden = !v
        dropHint.isHidden = !v
    }

    /// Flat top (hugs the screen edge), rounded bottom corners, small concave "ears" at the top like the real notch.
    private func notchPath(in b: NSRect) -> NSBezierPath {
        let r: CGFloat = mode == .collapsed ? (hasRealNotch ? 10 : 12) : 22
        let ear: CGFloat = hasRealNotch ? 6 : 0
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
        let hit = hitTest(convert(event.locationInWindow, from: nil))
        if hit === self || hit === content { onClick?() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Ignore clicks outside the black shape so transparent corners don't eat events.
        guard notchPath(in: rect).contains(point) else { return nil }
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

/// Plain container with top-left origin, matching NotchView.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Button that reacts to the very first click even when its panel isn't key.
final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Chip

/// A tappable card showing one recent clip.
final class ChipView: NSView, NSDraggingSource {
    var onTap: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private let item: ClipItem
    private var dragStart: NSPoint?

    init(item: ClipItem, index: Int) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor

        let type = item.smartType
        let icon = NSImageView()
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyUpOrDown
        let isThumb = item.kind == .image && item.image != nil
        if isThumb, let img = item.image {
            icon.image = img
            icon.contentTintColor = nil
            icon.imageScaling = .scaleAxesIndependently
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 5
            icon.layer?.cornerCurve = .continuous
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
        label.maximumNumberOfLines = isThumb ? 1 : 2
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
            icon.widthAnchor.constraint(equalToConstant: isThumb ? 48 : 18),
            icon.heightAnchor.constraint(equalToConstant: isThumb ? 30 : 18),
            label.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -16),
        ])
        toolTip = item.text.map { String($0.prefix(400)) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 1, alpha: 0.2).cgColor; layer?.borderColor = NSColor(white: 1, alpha: 0.18).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor; layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor }
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
