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
    private var notchCenterX: CGFloat = 0

    private enum State { case collapsed, toast, shot, expanded, timerDone, hud, agentAsk }
    private var state: State = .collapsed
    private var collapseTimer: Timer?
    private var hovering = false
    private var observers: [NSObjectProtocol] = []

    private var expandedSize: NSSize { NSSize(width: 720, height: 236 + notchSize.height) }
    private let musicExtra: CGFloat = 84          // extra height for the player card when music is playing
    private let wing: CGFloat = 44                // width added each side of the notch for the now-playing hint
    private let nowPlaying = NowPlayingMonitor()
    let shelf = ShelfStore()
    let timer = NotchTimer()
    let agents = AgentMonitor()
    let calendar = CalendarMonitor()
    let hud = SystemHUD()
    let weather = WeatherMonitor()
    private var hudTimer: Timer?
    private(set) var pomodoroSessions = 0
    private var pomodoroRunning = false
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
        notchView.latestText = { [weak self] in self?.store.items.first { $0.kind == .text }?.text ?? "" }
        let island = notchView.island
        island.data = self
        island.onPick = { [weak self] item in self?.pick(item) }
        island.onOpenHistory = { [weak self] in self?.collapse(); self?.openHistory() }
        island.onShelfRemove = { [weak self] url in self?.shelf.remove(url) }
        island.onShelfClear = { [weak self] in self?.shelf.clear() }
        island.onTimerStart = { [weak self] min, pomo in self?.pomodoroRunning = pomo; self?.timer.start(minutes: min); self?.timerChanged() }
        island.onTimerCancel = { [weak self] in self?.pomodoroRunning = false; self?.timer.cancel(); self?.timerChanged() }
        island.onTimerAdd = { [weak self] min in self?.timer.add(minutes: min) }
        island.onMusic = { [weak self] cmd in
            switch cmd { case .playPause: self?.nowPlaying.playPause(); case .next: self?.nowPlaying.next(); case .previous: self?.nowPlaying.previous() }
        }
        island.onAgentDecision = { [weak self] perm, allow in self?.agents.decide(perm, allow: allow); if self?.state == .agentAsk { self?.collapse() } }
        island.onJoin = { [weak self] item in
            self?.collapse()
            if let u = item.joinURL { NSWorkspace.shared.open(u) } else if let cal = URL(string: "ical://") { NSWorkspace.shared.open(cal) }
        }
        notchView.shelf = shelf
        notchView.timer = timer
        notchView.agents = agents
        notchView.calendar = calendar
        notchView.weather = weather
        notchView.onAgentDecision = { [weak self] perm, allow in
            self?.agents.decide(perm, allow: allow)
            if self?.state == .agentAsk { self?.collapse() }
        }
        notchView.onJoin = { [weak self] item in
            self?.collapse()
            if let u = item.joinURL { NSWorkspace.shared.open(u) }
            else if let cal = URL(string: "ical://") { NSWorkspace.shared.open(cal) }
        }
        notchView.onTimerStart = { [weak self] min in self?.timer.start(minutes: min); self?.timerChanged() }
        notchView.onTimerCancel = { [weak self] in self?.timer.cancel(); self?.timerChanged() }
        notchView.onTimerAdd = { [weak self] min in self?.timer.add(minutes: min) }
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
        observers.append(NotificationCenter.default.addObserver(forName: AgentMonitor.changed, object: nil, queue: .main) { [weak self] _ in
            self?.agentsChanged()
        })
        observers.append(NotificationCenter.default.addObserver(forName: AgentMonitor.permissionRequested, object: nil, queue: .main) { [weak self] _ in
            self?.agentAsk()
        })
        observers.append(NotificationCenter.default.addObserver(forName: CalendarMonitor.changed, object: nil, queue: .main) { [weak self] _ in
            self?.calendarChanged()
        })
        observers.append(NotificationCenter.default.addObserver(forName: WeatherMonitor.changed, object: nil, queue: .main) { [weak self] _ in
            self?.notchView.needsLayout = true
        })
        observers.append(NotificationCenter.default.addObserver(forName: SystemHUD.changed, object: nil, queue: .main) { [weak self] n in
            if let e = n.userInfo?["event"] as? SystemHUD.Event { self?.showHUD(e) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: ShelfStore.changed, object: nil, queue: .main) { [weak self] _ in
            self?.notchView.rebuildShelf()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NotchTimer.tick, object: nil, queue: .main) { [weak self] _ in
            self?.notchView.needsLayout = true
            if self?.state == .expanded { self?.notchView.island.tick() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NotchTimer.finished, object: nil, queue: .main) { [weak self] _ in
            self?.timerFinished()
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
            notchSize = NSSize(width: r.minX - l.maxX, height: inset)
            notchCenterX = (l.maxX + r.minX) / 2
        } else {
            notchSize = NSSize(width: 180, height: NSStatusBar.system.thickness)
            notchCenterX = screen.frame.midX
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
            let music = notchView.nowPlaying != nil
            let left: CGFloat = agents.waiting ? 84 : (music ? wing : 0)
            let right: CGFloat = timer.isRunning ? 72 : (calendar.imminent != nil ? 70 : (music ? wing : 0))
            size = NSSize(width: notchSize.width + (hasRealNotch ? 12 : 0) + left + right, height: notchSize.height)
        case .toast:     size = NSSize(width: max(notchSize.width + 200, 420), height: notchSize.height + 42)
        case .timerDone: size = NSSize(width: max(notchSize.width + 260, 420), height: notchSize.height + 46)
        case .hud:       size = NSSize(width: max(notchSize.width + 160, 380), height: notchSize.height + 40)
        case .agentAsk:  size = NSSize(width: max(notchSize.width + 260, 540), height: notchSize.height + 92)
        case .shot:      size = NSSize(width: max(shotToastSize.width, notchSize.width + 200), height: notchSize.height + shotToastSize.height)
        case .expanded:  size = expandedSize
        }
        let x = notchCenterX - size.width / 2
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
            case .timerDone: return .timerDone
            case .hud: return .hud
            case .agentAsk: return .agentAsk
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
        let union = NSRect(x: notchCenterX - unionSize.width / 2, y: screen.frame.maxY - unionSize.height,
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
        if agents.waiting && state != .expanded && state != .agentAsk { setState(.agentAsk, animated: true); return }
        if state != .expanded && state != .shot && state != .timerDone && state != .agentAsk { expand() }
    }

    private func mouseExited() {
        hovering = false
        scheduleCollapse(after: 0.35)
    }

    private func clicked() {
        if agents.waiting && state != .agentAsk && state != .expanded { setState(.agentAsk, animated: true); return }
        if state == .agentAsk { notchView.island.selectedTab = .agents; expand(); return }
        if state == .expanded { collapse(); openHistory() } else { expand() }
    }

    private func expand() {
        notchView.items = Array(store.filtered("").prefix(6))
        if agents.waiting { notchView.island.selectedTab = .agents }
        notchView.island.refresh()
        setState(.expanded, animated: true)
    }

    // MARK: Timer

    private func timerChanged() {
        if state == .collapsed || state == .timerDone { setState(.collapsed, animated: true) } else { notchView.needsLayout = true }
    }

    private func timerFinished() {
        if pomodoroRunning { pomodoroSessions = (pomodoroSessions + 1) % 4; pomodoroRunning = false }
        setState(.timerDone, animated: true)
        scheduleCollapse(after: 8)
    }

    // MARK: Agents / calendar / HUD

    private func islandRefresh() { if state == .expanded { notchView.island.refresh() } }

    private func agentsChanged() {
        notchView.needsLayout = true
        islandRefresh()
        if state == .collapsed { setState(.collapsed, animated: true) }     // wing may appear/disappear
        if state == .agentAsk && !agents.waiting { collapse() }
    }

    private func agentAsk() {
        guard Settings.agentsEnabled, Settings.notchEnabled else { return }
        notchView.needsLayout = true
        NSSound(named: "Tink")?.play()
        if state == .expanded { notchView.island.selectedTab = .agents; notchView.island.refresh(); return }
        setState(.agentAsk, animated: true)
        scheduleCollapse(after: 25)
    }

    private func calendarChanged() {
        notchView.needsLayout = true
        islandRefresh()
        if state == .collapsed { setState(.collapsed, animated: true) }
    }

    private func showHUD(_ e: SystemHUD.Event) {
        guard Settings.notchEnabled, state == .collapsed || state == .hud || state == .toast else { return }
        notchView.hudEvent = e
        hudTimer?.invalidate()
        setState(.hud, animated: state != .hud)
        hudTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in
            guard let self, !self.hovering else { return }
            self.collapse()
        }
    }

    // MARK: Now playing

    private func nowPlayingChanged() {
        let was = notchView.nowPlaying != nil
        notchView.nowPlaying = nowPlaying.info
        notchView.wing = wing
        let now = notchView.nowPlaying != nil
        // Grow/shrink the notch only when playback starts/stops; plain progress updates just relayout in place.
        if was != now { setState(state, animated: true) } else { notchView.needsLayout = true }
        islandRefresh()
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
            shelf.add(urls)
            notchView.island.selectedTab = .shelf
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
    enum Mode { case collapsed, toast, shot, expanded, timerDone, hud, agentAsk }
    enum Tab: Int { case clips, shelf, timer, agents, upNext, prompter }
    weak var agents: AgentMonitor?
    weak var calendar: CalendarMonitor?
    weak var weather: WeatherMonitor?
    var hudEvent: SystemHUD.Event? { didSet { needsLayout = true } }
    var onAgentDecision: ((AgentMonitor.Permission, Bool) -> Void)?
    var onJoin: ((CalendarMonitor.Item) -> Void)?
    var selectedTab: Tab = .clips { didSet { needsLayout = true } }
    weak var shelf: ShelfStore?
    weak var timer: NotchTimer?
    var onTimerStart: ((Double) -> Void)?
    var onTimerCancel: (() -> Void)?
    var onTimerAdd: ((Double) -> Void)?
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

    // Tabs, shelf, timer
    private let tabBar = NSStackView()
    private var tabButtons: [FirstClickButton] = []
    private let shelfStack = NSStackView()
    private let shelfEmpty = NSTextField(labelWithString: "Drop files here to keep them handy")
    private let shelfClear = FirstClickButton(title: "Clear", target: nil, action: nil)
    private let timerPresets = NSStackView()
    private let timerBig = NSTextField(labelWithString: "")
    private let timerSub = NSTextField(labelWithString: "")
    private let timerCancel = FirstClickButton(title: "Cancel", target: nil, action: nil)
    private let timerPlus = FirstClickButton(title: "+5 min", target: nil, action: nil)
    private let hintRing = RingView()
    private let hintTime = NSTextField(labelWithString: "")
    private let doneLabel = NSTextField(labelWithString: "Timer done")
    private let doneRepeat = FirstClickButton(title: "+5 min", target: nil, action: nil)
    private let doneDismiss = FirstClickButton(title: "Dismiss", target: nil, action: nil)
    private var tabViews: [NSView] { [tabBar, chipsStack, shelfStack, shelfEmpty, shelfClear, timerPresets, timerBig, timerSub, timerCancel, timerPlus,
                                       agentCard, agentList, upNextList, prompterScroll, prompterPlay, prompterSpeed, prompterHint, weatherLabel] }

    // Agents
    private let agentCard = NSView()
    private let agentTitle = NSTextField(labelWithString: "")
    private let agentSummary = NSTextField(labelWithString: "")
    private let agentAllow = FirstClickButton(title: "Allow", target: nil, action: nil)
    private let agentDeny = FirstClickButton(title: "Deny", target: nil, action: nil)
    private let agentList = NSStackView()
    private let hintAgent = NSView()
    private let hintAgentLabel = NSTextField(labelWithString: "Approve?")
    private var agentPulse = false
    // Up next
    private let upNextList = NSStackView()
    private let hintCal = NSImageView()
    private let hintCalLabel = NSTextField(labelWithString: "")
    // Prompter
    private let prompterScroll = NSScrollView()
    private let prompterText = NSTextView()
    private let prompterPlay = FirstClickButton(title: "Play", target: nil, action: nil)
    private let prompterSpeed = FirstClickButton(title: "1×", target: nil, action: nil)
    private let prompterHint = NSTextField(labelWithString: "Scrolls your most recent copied text")
    private var prompterTimer: Timer?
    private var prompterRate: CGFloat = 1
    // HUD
    private let hudIcon = NSImageView()
    private let hudBar = NSView()
    private let hudFill = NSView()
    private let hudLabel = NSTextField(labelWithString: "")
    private let weatherLabel = NSTextField(labelWithString: "")
    private let glow = CAShapeLayer()
    let island = IslandContentView()

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

        // tab strip
        tabBar.orientation = .horizontal; tabBar.spacing = 4
        for (i, title) in ["Clips", "Shelf", "Timer"].enumerated() {
            let b = FirstClickButton(title: title, target: self, action: #selector(tabTapped(_:)))
            b.isBordered = false; b.tag = i; b.wantsLayer = true
            b.layer?.cornerRadius = 9; b.font = .systemFont(ofSize: 11, weight: .semibold)
            b.contentTintColor = .white
            b.widthAnchor.constraint(equalToConstant: 58).isActive = true
            b.heightAnchor.constraint(equalToConstant: 20).isActive = true
            tabButtons.append(b); tabBar.addArrangedSubview(b)
        }
        // shelf
        shelfStack.orientation = .horizontal; shelfStack.spacing = 8; shelfStack.distribution = .fillEqually
        shelfEmpty.textColor = NSColor.white.withAlphaComponent(0.45); shelfEmpty.font = .systemFont(ofSize: 11); shelfEmpty.alignment = .center
        shelfClear.bezelStyle = .inline; shelfClear.controlSize = .small; shelfClear.contentTintColor = .white
        shelfClear.target = self; shelfClear.action = #selector(shelfClearTapped)
        // timer
        timerPresets.orientation = .horizontal; timerPresets.spacing = 8; timerPresets.distribution = .fillEqually
        for m in [5, 10, 15, 25, 45, 60] {
            let b = FirstClickButton(title: "\(m) min", target: self, action: #selector(timerPresetTapped(_:)))
            b.isBordered = false; b.tag = m; b.wantsLayer = true
            b.layer?.cornerRadius = 14; b.layer?.cornerCurve = .continuous
            b.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
            b.layer?.borderWidth = 1; b.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
            b.font = .systemFont(ofSize: 13, weight: .semibold); b.contentTintColor = .white
            timerPresets.addArrangedSubview(b)
        }
        timerBig.font = .monospacedDigitSystemFont(ofSize: 40, weight: .semibold); timerBig.textColor = .white
        timerSub.font = .systemFont(ofSize: 11); timerSub.textColor = NSColor.white.withAlphaComponent(0.55)
        for b in [timerCancel, timerPlus, doneRepeat, doneDismiss] { b.bezelStyle = .inline; b.controlSize = .small; b.contentTintColor = .white; b.target = self }
        timerCancel.action = #selector(timerCancelTapped); timerPlus.action = #selector(timerPlusTapped)
        doneRepeat.action = #selector(timerPlusTapped); doneDismiss.action = #selector(doneDismissTapped)
        hintTime.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold); hintTime.textColor = .white
        doneLabel.font = .systemFont(ofSize: 14, weight: .semibold); doneLabel.textColor = .white
        (tabViews + [hintRing, hintTime, doneLabel, doneRepeat, doneDismiss]).forEach { $0.isHidden = true; content.addSubview($0) }
        rebuildShelf()

        // tabs 4–6
        for (i, title) in ["Agents", "Up Next", "Prompter"].enumerated() {
            let b = FirstClickButton(title: title, target: self, action: #selector(tabTapped(_:)))
            b.isBordered = false; b.tag = i + 3; b.wantsLayer = true
            b.layer?.cornerRadius = 9; b.font = .systemFont(ofSize: 11, weight: .semibold)
            b.contentTintColor = .white
            b.widthAnchor.constraint(equalToConstant: 62).isActive = true
            b.heightAnchor.constraint(equalToConstant: 20).isActive = true
            tabButtons.append(b); tabBar.addArrangedSubview(b)
        }
        // agents
        agentCard.wantsLayer = true
        agentCard.layer?.cornerRadius = 14; agentCard.layer?.cornerCurve = .continuous
        agentCard.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor
        agentCard.layer?.borderWidth = 1; agentCard.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.4).cgColor
        agentTitle.font = .systemFont(ofSize: 13, weight: .semibold); agentTitle.textColor = .white; agentTitle.lineBreakMode = .byTruncatingTail
        agentSummary.font = .monospacedSystemFont(ofSize: 11, weight: .regular); agentSummary.textColor = NSColor.white.withAlphaComponent(0.75); agentSummary.lineBreakMode = .byTruncatingMiddle
        for b in [agentAllow, agentDeny] { b.bezelStyle = .inline; b.controlSize = .small; b.target = self }
        agentAllow.action = #selector(agentAllowTapped); agentDeny.action = #selector(agentDenyTapped)
        agentAllow.contentTintColor = .white; agentDeny.contentTintColor = .white
        [agentTitle, agentSummary, agentAllow, agentDeny].forEach { agentCard.addSubview($0) }
        agentList.orientation = .vertical; agentList.alignment = .leading; agentList.spacing = 4
        hintAgent.wantsLayer = true; hintAgent.layer?.cornerRadius = 5; hintAgent.layer?.backgroundColor = NSColor.systemOrange.cgColor
        hintAgentLabel.font = .systemFont(ofSize: 11, weight: .semibold); hintAgentLabel.textColor = .systemOrange
        // up next
        upNextList.orientation = .vertical; upNextList.alignment = .leading; upNextList.spacing = 4
        hintCal.image = UI.symbol("calendar", size: 12, weight: .semibold); hintCal.contentTintColor = .systemRed
        hintCalLabel.font = .systemFont(ofSize: 11, weight: .semibold); hintCalLabel.textColor = .white
        // prompter
        prompterText.isEditable = false; prompterText.drawsBackground = false
        prompterText.textColor = .white; prompterText.font = .systemFont(ofSize: 15, weight: .medium)
        prompterText.textContainerInset = NSSize(width: 6, height: 30)
        prompterText.isVerticallyResizable = true; prompterText.isHorizontallyResizable = false
        prompterText.autoresizingMask = [.width]; prompterText.textContainer?.widthTracksTextView = true
        prompterScroll.documentView = prompterText; prompterScroll.drawsBackground = false; prompterScroll.hasVerticalScroller = false
        prompterScroll.wantsLayer = true; prompterScroll.layer?.cornerRadius = 12
        prompterScroll.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        for b in [prompterPlay, prompterSpeed] { b.bezelStyle = .inline; b.controlSize = .small; b.contentTintColor = .white; b.target = self }
        prompterPlay.action = #selector(prompterPlayTapped); prompterSpeed.action = #selector(prompterSpeedTapped)
        prompterHint.font = .systemFont(ofSize: 10); prompterHint.textColor = NSColor.white.withAlphaComponent(0.45)
        // hud
        hudIcon.contentTintColor = .white
        hudBar.wantsLayer = true; hudBar.layer?.cornerRadius = 3; hudBar.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        hudFill.wantsLayer = true; hudFill.layer?.cornerRadius = 3; hudFill.layer?.backgroundColor = NSColor.white.cgColor
        hudBar.addSubview(hudFill)
        hudLabel.font = .systemFont(ofSize: 12, weight: .semibold); hudLabel.textColor = .white
        weatherLabel.font = .systemFont(ofSize: 11, weight: .medium); weatherLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        // glow ring under the rim
        glow.fillColor = nil; glow.lineWidth = 2; glow.strokeColor = NSColor.clear.cgColor
        glow.shadowRadius = 10; glow.shadowOpacity = 0; glow.shadowOffset = .zero
        layer?.insertSublayer(glow, above: shape)
        island.isHidden = true
        content.addSubview(island)
        ([agentCard, agentList, hintAgent, hintAgentLabel, upNextList, hintCal, hintCalLabel, prompterScroll, prompterPlay, prompterSpeed, prompterHint,
          hudIcon, hudBar, hudLabel, weatherLabel]).forEach { $0.isHidden = true; content.addSubview($0) }
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
        glow.frame = bounds; glow.path = shape.path
        updateGlow()
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
            let timing = timer?.isRunning == true
            let asking = agents?.waiting == true
            let soon = calendar?.imminent
            hintArt.isHidden = !music || asking
            hintBars.isHidden = !music || timing || soon != nil
            hintRing.isHidden = !timing; hintTime.isHidden = !timing
            hintAgent.isHidden = !asking; hintAgentLabel.isHidden = !asking
            hintCal.isHidden = soon == nil || timing; hintCalLabel.isHidden = hintCal.isHidden
            setDoneVisible(false); setHUDVisible(false)
            if asking {
                hintAgent.frame = NSRect(x: 12, y: (cb.height - 10) / 2, width: 10, height: 10)
                hintAgentLabel.sizeToFit(); hintAgentLabel.frame.origin = NSPoint(x: 27, y: (cb.height - hintAgentLabel.frame.height) / 2)
                pulseAgentDot()
            }
            if let soon, !timing {
                hintCalLabel.stringValue = soon.minutesUntil <= 0 ? "now" : "\(soon.minutesUntil)m"
                hintCalLabel.sizeToFit()
                hintCalLabel.frame.origin = NSPoint(x: cb.width - 12 - hintCalLabel.frame.width, y: (cb.height - hintCalLabel.frame.height) / 2)
                hintCal.frame = NSRect(x: hintCalLabel.frame.minX - 18, y: (cb.height - 14) / 2, width: 14, height: 14)
            }
            if music && !asking {
                let s = cb.height - 10
                hintArt.frame = NSRect(x: 10, y: 5, width: s, height: s)
                hintBars.frame = NSRect(x: cb.width - 10 - 18, y: (cb.height - 14) / 2, width: 18, height: 14)
                hintBars.isAnimating = nowPlaying?.isPlaying == true
            }
            if timing, let tm = timer {
                hintRing.frame = NSRect(x: cb.width - 10 - 18, y: (cb.height - 18) / 2, width: 18, height: 18)
                hintRing.progress = tm.progress
                hintTime.stringValue = NotchTimer.format(tm.remaining)
                hintTime.sizeToFit()
                hintTime.frame.origin = NSPoint(x: cb.width - 10 - 18 - 6 - hintTime.frame.width, y: (cb.height - hintTime.frame.height) / 2)
            }
        case .hud:
            toastStack.isHidden = true; shotViews.forEach { $0.isHidden = true }
            setExpandedVisible(false); setMusicCardVisible(false); setDoneVisible(false)
            [hintArt, hintBars, hintRing, hintTime, hintAgent, hintAgentLabel, hintCal, hintCalLabel].forEach { $0.isHidden = true }
            setHUDVisible(true)
            if let e = hudEvent {
                let sym: String
                switch e.kind {
                case .volume: sym = e.level == 0 || !e.on ? "speaker.slash.fill" : (e.level < 0.34 ? "speaker.wave.1.fill" : e.level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                case .brightness: sym = e.level < 0.5 ? "sun.min.fill" : "sun.max.fill"
                case .capsLock: sym = e.on ? "capslock.fill" : "capslock"
                }
                hudIcon.image = UI.symbol(sym, size: 14, weight: .semibold)
                let rowY = baseNotchSize.height + 11
                hudIcon.frame = NSRect(x: padX, y: rowY, width: 18, height: 18)
                if e.kind == .capsLock {
                    hudBar.isHidden = true
                    hudLabel.stringValue = e.on ? "Caps Lock on" : "Caps Lock off"; hudLabel.sizeToFit()
                    hudLabel.frame.origin = NSPoint(x: padX + 26, y: rowY + (18 - hudLabel.frame.height) / 2)
                } else {
                    hudLabel.isHidden = true
                    hudBar.frame = NSRect(x: padX + 28, y: rowY + 6, width: cb.width - padX * 2 - 28, height: 6)
                    hudFill.frame = NSRect(x: 0, y: 0, width: hudBar.frame.width * CGFloat(e.level), height: 6)
                }
            }
        case .agentAsk:
            toastStack.isHidden = true; shotViews.forEach { $0.isHidden = true }
            setExpandedVisible(false); setMusicCardVisible(false); setDoneVisible(false); setHUDVisible(false)
            [hintArt, hintBars, hintRing, hintTime, hintAgent, hintAgentLabel, hintCal, hintCalLabel].forEach { $0.isHidden = true }
            agentCard.isHidden = false
            agentCard.frame = NSRect(x: padX, y: baseNotchSize.height + 10, width: cb.width - padX * 2, height: cb.height - baseNotchSize.height - 20)
            layoutAgentCard()
        case .timerDone:
            toastStack.isHidden = true; shotViews.forEach { $0.isHidden = true }
            setHUDVisible(false); agentCard.isHidden = true
            setExpandedVisible(false); setMusicCardVisible(false)
            hintArt.isHidden = true; hintBars.isHidden = true; hintRing.isHidden = true; hintTime.isHidden = true
            setDoneVisible(true)
            doneLabel.sizeToFit(); doneLabel.frame.origin = NSPoint(x: padX, y: baseNotchSize.height + 12)
            doneRepeat.sizeToFit(); doneDismiss.sizeToFit()
            doneDismiss.frame.origin = NSPoint(x: cb.width - padX - doneDismiss.frame.width, y: baseNotchSize.height + 8)
            doneRepeat.frame.origin = NSPoint(x: doneDismiss.frame.minX - 8 - doneRepeat.frame.width, y: baseNotchSize.height + 8)
        case .shot:
            toastStack.isHidden = true
            setExpandedVisible(false)
            hintRing.isHidden = true; hintTime.isHidden = true; setDoneVisible(false); setHUDVisible(false)
            [hintAgent, hintAgentLabel, hintCal, hintCalLabel, agentCard].forEach { $0.isHidden = true }
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
            hintRing.isHidden = true; hintTime.isHidden = true; setDoneVisible(false); setHUDVisible(false)
            [hintAgent, hintAgentLabel, hintCal, hintCalLabel, agentCard].forEach { $0.isHidden = true }
            hintArt.isHidden = true; hintBars.isHidden = true; setMusicCardVisible(false)
            toastStack.isHidden = false
            let w = cb.width - padX * 2
            toastStack.frame = NSRect(x: padX, y: baseNotchSize.height + 11, width: w, height: 20)
            toastIcon.frame.size = NSSize(width: 18, height: 18)
        case .expanded:
            toastStack.isHidden = true
            shotViews.forEach { $0.isHidden = true }
            [hintArt, hintBars, hintRing, hintTime, hintAgent, hintAgentLabel, hintCal, hintCalLabel].forEach { $0.isHidden = true }
            setMusicCardVisible(false); setDoneVisible(false); setHUDVisible(false); setExpandedVisible(false)
            island.isHidden = false
            island.topInset = baseNotchSize.height
            island.frame = cb
        }
        if mode != .expanded { island.isHidden = true }
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
        header.isHidden = true
        historyButton.isHidden = !v
        chipsStack.isHidden = !v
        dropHint.isHidden = !v
        if !v { tabViews.forEach { $0.isHidden = true } }
    }

    private func setDoneVisible(_ v: Bool) { doneLabel.isHidden = !v; doneRepeat.isHidden = !v; doneDismiss.isHidden = !v }
    private func setHUDVisible(_ v: Bool) { hudIcon.isHidden = !v; hudBar.isHidden = !v; hudLabel.isHidden = !v }

    // MARK: Agents

    private func layoutAgentCard() {
        guard let p = agents?.pending.first else { return }
        let name = agents?.sessions[p.sessionID]?.name ?? "Claude Code"
        agentTitle.stringValue = "\(name) wants to run \(p.tool)"
        agentSummary.stringValue = p.summary
        let w = agentCard.bounds.width
        agentTitle.frame = NSRect(x: 12, y: 9, width: w - 24, height: 17)
        agentSummary.frame = NSRect(x: 12, y: 29, width: w - 24, height: 15)
        agentAllow.sizeToFit(); agentDeny.sizeToFit()
        agentDeny.frame.origin = NSPoint(x: w - 12 - agentDeny.frame.width, y: agentCard.bounds.height - 30)
        agentAllow.frame.origin = NSPoint(x: agentDeny.frame.minX - 8 - agentAllow.frame.width, y: agentCard.bounds.height - 30)
    }

    private func rebuildAgentList() {
        agentList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let list = agents?.activeSessions ?? []
        if list.isEmpty {
            let l = NSTextField(labelWithString: AgentMonitor.hooksInstalled ? "No agents running. Start Claude Code and it shows up here." : "Install the Claude Code hooks in Preferences › Agents to see sessions here.")
            l.textColor = NSColor.white.withAlphaComponent(0.5); l.font = .systemFont(ofSize: 11)
            agentList.addArrangedSubview(l); return
        }
        for s in list.prefix(3) {
            let dot = NSView(); dot.wantsLayer = true; dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = (s.state == .waiting ? NSColor.systemOrange : s.state == .working ? NSColor.systemGreen : NSColor.systemGray).cgColor
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true; dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            let n = NSTextField(labelWithString: s.name); n.textColor = .white; n.font = .systemFont(ofSize: 12, weight: .semibold)
            let m = NSTextField(labelWithString: s.message.isEmpty ? s.state.rawValue : s.message); m.textColor = NSColor.white.withAlphaComponent(0.6); m.font = .systemFont(ofSize: 11); m.lineBreakMode = .byTruncatingTail
            m.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [dot, n, m]); row.spacing = 8
            agentList.addArrangedSubview(row)
        }
    }

    private func pulseAgentDot() {
        guard hintAgent.layer?.animation(forKey: "pulse") == nil else { return }
        let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 1; a.toValue = 0.3; a.duration = 0.7; a.autoreverses = true; a.repeatCount = .infinity
        hintAgent.layer?.add(a, forKey: "pulse")
    }

    @objc private func agentAllowTapped() { if let p = agents?.pending.first { onAgentDecision?(p, true) } }
    @objc private func agentDenyTapped() { if let p = agents?.pending.first { onAgentDecision?(p, false) } }

    // MARK: Up next

    private func rebuildUpNext() {
        upNextList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let cal = calendar else { return }
        let items = Array((cal.events + cal.reminders).prefix(3))
        if !Settings.calendarEnabled || items.isEmpty {
            let l = NSTextField(labelWithString: Settings.calendarEnabled ? "Nothing coming up in the next 24 hours." : "Turn on Calendar in Preferences › Notch to see your next events here.")
            l.textColor = NSColor.white.withAlphaComponent(0.5); l.font = .systemFont(ofSize: 11)
            upNextList.addArrangedSubview(l); return
        }
        for it in items {
            let ic = NSImageView(image: UI.symbol(it.isReminder ? "circle" : "calendar", size: 11, weight: .semibold)!)
            ic.contentTintColor = it.isReminder ? .systemBlue : .systemRed
            ic.widthAnchor.constraint(equalToConstant: 14).isActive = true
            let n = NSTextField(labelWithString: it.title); n.textColor = .white; n.font = .systemFont(ofSize: 12, weight: .medium); n.lineBreakMode = .byTruncatingTail
            n.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let w = NSTextField(labelWithString: it.isReminder ? "today" : CalendarMonitor.relative(it)); w.textColor = NSColor.white.withAlphaComponent(0.55); w.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            let row = NSStackView(views: [ic, n, w]); row.spacing = 8
            if it.joinURL != nil || !it.isReminder {
                let j = FirstClickButton(title: it.joinURL != nil ? "Join" : "Open", target: self, action: #selector(joinTapped(_:)))
                j.bezelStyle = .inline; j.controlSize = .small; j.contentTintColor = .white
                j.tag = items.firstIndex { $0.title == it.title && $0.start == it.start } ?? 0
                row.addArrangedSubview(j)
            }
            upNextList.addArrangedSubview(row)
        }
    }

    @objc private func joinTapped(_ sender: NSButton) {
        guard let cal = calendar else { return }
        let items = Array((cal.events + cal.reminders).prefix(3))
        if items.indices.contains(sender.tag) { onJoin?(items[sender.tag]) }
    }

    // MARK: Prompter

    func loadPrompter(_ text: String) {
        prompterText.string = text.isEmpty ? "Copy some text, then come back here." : text
        prompterScroll.contentView.scroll(to: .zero)
    }

    @objc private func prompterPlayTapped() {
        if prompterTimer != nil { prompterTimer?.invalidate(); prompterTimer = nil; prompterPlay.title = "Play"; return }
        prompterPlay.title = "Pause"
        prompterTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let cv = self.prompterScroll.contentView
            let maxY = max(0, (self.prompterText.frame.height) - cv.bounds.height)
            var y = cv.bounds.origin.y + 0.6 * self.prompterRate
            if y >= maxY { y = maxY; self.prompterTimer?.invalidate(); self.prompterTimer = nil; self.prompterPlay.title = "Play" }
            cv.scroll(to: NSPoint(x: 0, y: y)); self.prompterScroll.reflectScrolledClipView(cv)
        }
    }

    @objc private func prompterSpeedTapped() {
        prompterRate = prompterRate >= 3 ? 1 : prompterRate + 1
        prompterSpeed.title = "\(Int(prompterRate))×"
    }

    // MARK: Glow

    private func updateGlow() {
        let level = Settings.notchGlow
        guard level > 0, mode != .collapsed || nowPlaying != nil || agents?.waiting == true || timer?.isRunning == true else {
            glow.shadowOpacity = 0; glow.strokeColor = NSColor.clear.cgColor; glow.removeAnimation(forKey: "pulse"); return
        }
        var color: NSColor = .systemBlue
        if agents?.waiting == true { color = .systemOrange }
        else if timer?.isRunning == true { color = .systemOrange.blended(withFraction: 0.4, of: .systemYellow) ?? .systemOrange }
        else if let art = nowPlaying?.artwork { color = art.averageColor ?? .systemPink }
        glow.strokeColor = color.withAlphaComponent(level == 2 ? 0.9 : 0.5).cgColor
        glow.shadowColor = color.cgColor
        glow.shadowRadius = level == 2 ? 16 : 9
        glow.shadowOpacity = level == 2 ? 0.9 : 0.55
        if agents?.waiting == true, glow.animation(forKey: "pulse") == nil {
            let a = CABasicAnimation(keyPath: "shadowOpacity"); a.fromValue = glow.shadowOpacity; a.toValue = 0.15; a.duration = 0.8; a.autoreverses = true; a.repeatCount = .infinity
            glow.add(a, forKey: "pulse")
        } else if agents?.waiting != true { glow.removeAnimation(forKey: "pulse") }
    }

    func rebuildShelf() {
        shelfStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for url in (shelf?.urls ?? []).prefix(6) {
            let chip = ShelfChip(url: url)
            chip.onRemove = { [weak self] in self?.shelf?.remove(url) }
            shelfStack.addArrangedSubview(chip)
        }
        needsLayout = true
    }

    var latestText: (() -> String)?
    @objc private func tabTapped(_ sender: NSButton) {
        selectedTab = Tab(rawValue: sender.tag) ?? .clips
        if selectedTab == .prompter { loadPrompter(latestText?() ?? "") }
    }
    @objc private func shelfClearTapped() { shelf?.clear() }
    @objc private func timerPresetTapped(_ sender: NSButton) { onTimerStart?(Double(sender.tag)) }
    @objc private func timerCancelTapped() { onTimerCancel?() }
    @objc private func timerPlusTapped() { onTimerAdd?(5) }
    @objc private func doneDismissTapped() { onTimerCancel?() }

    /// Flat top (hugs the screen edge), rounded bottom corners, small concave "ears" at the top like the real notch.
    private func notchPath(in b: NSRect) -> NSBezierPath {
        let r: CGFloat = mode == .collapsed ? (hasRealNotch ? 10 : 12) : (mode == .expanded ? 30 : 22)
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

/// A file on the shelf: icon + name; drag it out into any app, click to reveal, right-click to remove.
final class ShelfChip: NSView, NSDraggingSource {
    var onRemove: (() -> Void)?
    private let url: URL
    private var dragStart: NSPoint?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        layer?.cornerRadius = 18; layer?.cornerCurve = .continuous
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: url.lastPathComponent)
        name.textColor = .white; name.font = .systemFont(ofSize: 11); name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
        let sub = NSTextField(labelWithString: size)
        sub.textColor = NSColor.white.withAlphaComponent(0.45); sub.font = .systemFont(ofSize: 9)
        let v = NSStackView(views: [icon, name, sub])
        v.orientation = .vertical; v.alignment = .leading; v.spacing = 3
        v.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 6, right: 8)
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
            v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
            name.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -16),
        ])
        toolTip = url.path
        let menu = NSMenu()
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(reveal), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Remove from Shelf", action: #selector(remove), keyEquivalent: "").target = self
        self.menu = menu
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    @objc private func remove() { onRemove?() }

    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { if dragStart != nil { reveal() }; dragStart = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 6 else { return }
        dragStart = nil
        let di = NSDraggingItem(pasteboardWriter: url as NSURL)
        di.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [di], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

extension NSImage {
    /// Mean color of the image (for glow tinting from album art).
    var averageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }
}

/// Plain container with top-left origin, matching NotchView.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Button that reacts to the very first click even when its panel isn't key.
class FirstClickButton: NSButton {
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
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous

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
        label.font = Theme.font(12, .medium)
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
        v.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor),
            v.bottomAnchor.constraint(equalTo: bottomAnchor),
            v.leadingAnchor.constraint(equalTo: leadingAnchor),
            v.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: isThumb ? 64 : 20),
            icon.heightAnchor.constraint(equalToConstant: isThumb ? 40 : 20),
            label.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -16),
        ])
        toolTip = item.text.map { String($0.prefix(400)) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 1, alpha: 0.16).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor }
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


// MARK: - Island data

extension NotchController: IslandDataSource {
    var recentItems: [ClipItem] { Array(store.filtered("").prefix(6)) }
    var totalItems: Int { store.items.count }
    var todayItems: Int { store.items.filter { Calendar.current.isDateInToday($0.createdAt) }.count }
    var shelfURLs: [URL] { shelf.urls }
    var nowPlayingInfo: NowPlayingInfo? { nowPlaying.info }
    var promptText: String { store.items.first { $0.kind == .text }?.text ?? "" }
}
