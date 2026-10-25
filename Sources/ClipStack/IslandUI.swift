import AppKit

// MARK: - Theme

enum Theme {
    static let text = NSColor.white
    static let secondary = NSColor(white: 1, alpha: 0.62)
    static let dim = NSColor(white: 1, alpha: 0.38)
    static let accent = NSColor(red: 0.40, green: 0.55, blue: 1.0, alpha: 1)

    /// Rounded SF for the friendly geometric look; falls back to the system font.
    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
        return base
    }

    static func label(_ text: String = "", size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = Theme.secondary) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font(size, weight); l.textColor = color; l.lineBreakMode = .byTruncatingTail
        return l
    }

    static func attributed(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font(size, weight), .foregroundColor: color])
    }
}

// MARK: - Components

/// Dark glass card: soft vertical gradient, hairline border, continuous 24 pt corners.
final class GlassCard: NSView {
    private let grad = CAGradientLayer()
    var highlighted = false { didSet { update() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 24; layer?.cornerCurve = .continuous; layer?.masksToBounds = true
        layer?.borderWidth = 1
        grad.startPoint = CGPoint(x: 0.5, y: 0); grad.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.insertSublayer(grad, at: 0)
        update()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); grad.frame = bounds; CATransaction.commit() }

    private func update() {
        let a: CGFloat = highlighted ? 0.16 : 0.09, b: CGFloat = highlighted ? 0.08 : 0.03
        grad.colors = [NSColor(white: 1, alpha: a).cgColor, NSColor(white: 1, alpha: b).cgColor]
        layer?.borderColor = NSColor(white: 1, alpha: highlighted ? 0.16 : 0.09).cgColor
    }
}

/// Circular icon button: white filled (primary) or outlined glass (secondary).
final class CircleButton: FirstClickButton {
    init(symbol: String, size: CGFloat = 40, filled: Bool = true, target: AnyObject?, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        self.target = target; self.action = action
        isBordered = false; imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = size / 2
        layer?.backgroundColor = (filled ? NSColor.white : NSColor(white: 1, alpha: 0.06)).cgColor
        layer?.borderWidth = filled ? 0 : 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.22).cgColor
        image = UI.symbol(symbol, size: size * 0.36, weight: .bold)
        contentTintColor = filled ? NSColor(white: 0.08, alpha: 1) : .white
        setFrameSize(NSSize(width: size, height: size))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { frame.size }
}

/// Capsule button: white filled, or translucent glass.
final class PillButton: FirstClickButton {
    private var filledStyle: Bool
    var isOn: Bool = false { didSet { restyle() } }
    private let titleText: String

    init(_ title: String, filled: Bool = false, target: AnyObject?, action: Selector) {
        titleText = title; filledStyle = filled
        super.init(frame: .zero)
        self.target = target; self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 15
        restyle()
        sizeToFit()
        setFrameSize(NSSize(width: frame.width + 22, height: 30))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func restyle() {
        let on = filledStyle || isOn
        layer?.backgroundColor = (on ? NSColor.white : NSColor(white: 1, alpha: 0.07)).cgColor
        layer?.borderWidth = on ? 0 : 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        attributedTitle = Theme.attributed(titleText, size: 12, weight: .semibold, color: on ? NSColor(white: 0.08, alpha: 1) : .white)
    }
}

/// Glance-style tab capsule: icon tabs with counts; the selected one expands into a labelled pill.
final class TabCapsule: NSView {
    struct Item { let symbol: String; let title: String }
    var items: [Item] = [] { didSet { rebuild() } }
    var counts: [Int] = [] { didSet { needsLayout = true } }
    var selected = 0 { didSet { needsLayout = true } }
    var onSelect: ((Int) -> Void)?

    private var buttons: [FirstClickButton] = []
    private var countLabels: [NSTextField] = []
    private let highlight = NSView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 20; layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        layer?.borderWidth = 1; layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 15; highlight.layer?.cornerCurve = .continuous
        highlight.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        highlight.layer?.borderWidth = 1; highlight.layer?.borderColor = NSColor(white: 1, alpha: 0.18).cgColor
        addSubview(highlight)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }; countLabels.forEach { $0.removeFromSuperview() }
        buttons = []; countLabels = []
        for (i, it) in items.enumerated() {
            let b = FirstClickButton(title: "", target: self, action: #selector(tapped(_:)))
            b.isBordered = false; b.tag = i; b.imagePosition = .imageLeading
            b.image = UI.symbol(it.symbol, size: 14, weight: .semibold)
            b.contentTintColor = .white
            addSubview(b); buttons.append(b)
            let c = Theme.label("", size: 11, weight: .medium, color: Theme.dim)
            addSubview(c); countLabels.append(c)
        }
        needsLayout = true
    }

    /// Width needed for the current state.
    var preferredWidth: CGFloat {
        var w: CGFloat = 10
        for i in items.indices { w += (i == selected ? selectedWidth(i) : itemWidth(i)) + 4 }
        return w + 6
    }

    private func countText(_ i: Int) -> String { count(i) > 99 ? "99+" : "\(count(i))" }
    private func countWidth(_ i: Int) -> CGFloat { count(i) > 0 ? (countText(i) as NSString).size(withAttributes: [.font: Theme.font(11, .medium)]).width + 6 : 0 }
    private func itemWidth(_ i: Int) -> CGFloat { 32 + countWidth(i) }
    private func selectedWidth(_ i: Int) -> CGFloat {
        let t = (items[i].title as NSString).size(withAttributes: [.font: Theme.font(13, .semibold)]).width
        return 44 + t + countWidth(i)
    }
    private func count(_ i: Int) -> Int { i < counts.count ? counts[i] : 0 }

    override func layout() {
        super.layout()
        var x: CGFloat = 8
        for (i, b) in buttons.enumerated() {
            let sel = i == selected
            let w = sel ? selectedWidth(i) : itemWidth(i)
            b.frame = NSRect(x: x, y: 5, width: w - countWidth(i), height: 30)
            b.alignment = .center
            b.image = UI.symbol(items[i].symbol, size: 14, weight: .semibold)
            b.contentTintColor = sel ? .white : NSColor(white: 1, alpha: 0.75)
            b.attributedTitle = sel ? Theme.attributed(" " + items[i].title, size: 13, weight: .semibold, color: .white) : NSAttributedString(string: "")
            let c = countLabels[i]
            c.isHidden = count(i) == 0
            c.stringValue = countText(i)
            c.textColor = sel ? NSColor(white: 1, alpha: 0.7) : Theme.dim
            c.sizeToFit()
            c.frame.origin = NSPoint(x: x + w - c.frame.width - 9, y: 5 + (30 - c.frame.height) / 2)
            if sel {
                NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.22; ctx.allowsImplicitAnimation = true; highlight.animator().frame = NSRect(x: x, y: 5, width: w, height: 30) }
            }
            x += w + 4
        }
    }

    @objc private func tapped(_ sender: NSButton) { selected = sender.tag; onSelect?(sender.tag) }
}

/// A list row: coloured ring, title, subtitle, optional right-aligned tag or button.
final class ListRow: NSView {
    override var isFlipped: Bool { true }
    init(color: NSColor, title: String, subtitle: String, tag: String? = nil, tagColor: NSColor = Theme.accent, button: NSView? = nil, filled: Bool = false) {
        super.init(frame: .zero)
        let ring = NSView(); ring.wantsLayer = true; ring.layer?.cornerRadius = 10
        ring.layer?.borderWidth = 2.5; ring.layer?.borderColor = color.cgColor
        if filled { ring.layer?.backgroundColor = color.cgColor }
        ring.frame = NSRect(x: 18, y: 15, width: 20, height: 20)
        addSubview(ring)
        let t = Theme.label(title, size: 15, weight: .medium, color: .white); t.frame = NSRect(x: 54, y: 8, width: 0, height: 18); addSubview(t)
        let s = Theme.label(subtitle, size: 12, color: Theme.dim); s.frame = NSRect(x: 54, y: 29, width: 0, height: 15); addSubview(s)
        titleField = t; subField = s
        if let tag { let g = Theme.label(tag, size: 12, weight: .medium, color: tagColor); g.sizeToFit(); addSubview(g); tagField = g }
        if let button { addSubview(button); accessory = button }
        let sep = NSView(); sep.wantsLayer = true; sep.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor; addSubview(sep); separator = sep
    }
    required init?(coder: NSCoder) { fatalError() }
    private var titleField: NSTextField!, subField: NSTextField!, tagField: NSTextField?, accessory: NSView?, separator: NSView!
    var showsSeparator = true { didSet { separator.isHidden = !showsSeparator } }

    override func layout() {
        super.layout()
        var right = bounds.width - 18
        if let a = accessory { a.frame.origin = NSPoint(x: right - a.frame.width, y: (bounds.height - a.frame.height) / 2); right -= a.frame.width + 12 }
        if let g = tagField { g.frame.origin = NSPoint(x: right - g.frame.width, y: 10); right -= g.frame.width + 12 }
        titleField.frame.size.width = right - 54; subField.frame.size.width = right - 54
        separator.frame = NSRect(x: 18, y: bounds.height - 1, width: bounds.width - 36, height: 1)
    }
}

// MARK: - Island content

protocol IslandDataSource: AnyObject {
    var recentItems: [ClipItem] { get }
    var totalItems: Int { get }
    var todayItems: Int { get }
    var shelfURLs: [URL] { get }
    var timer: NotchTimer { get }
    var pomodoroSessions: Int { get }
    var agents: AgentMonitor { get }
    var calendar: CalendarMonitor { get }
    var weather: WeatherMonitor { get }
    var nowPlayingInfo: NowPlayingInfo? { get }
    var promptText: String { get }
}

final class IslandContentView: NSView {
    enum Tab: Int, CaseIterable { case home, clips, shelf, agents, upNext, prompter, focus }
    weak var data: IslandDataSource?

    var onPick: ((ClipItem) -> Void)?
    var onOpenHistory: (() -> Void)?
    var onShelfRemove: ((URL) -> Void)?
    var onShelfClear: (() -> Void)?
    var onTimerStart: ((Double, Bool) -> Void)?      // minutes, isPomodoro
    var onTimerCancel: (() -> Void)?
    var onTimerAdd: ((Double) -> Void)?
    var onMusic: ((NotchView.MusicCommand) -> Void)?
    var onAgentDecision: ((AgentMonitor.Permission, Bool) -> Void)?
    var onJoin: ((CalendarMonitor.Item) -> Void)?

    var selectedTab: Tab = .home { didSet { tabs.selected = selectedTab.rawValue; refresh() } }

    private let tabs = TabCapsule()
    private let left = GlassCard(), right = GlassCard()
    private var homeCards: [GlassCard] = [GlassCard(), GlassCard(), GlassCard(), GlassCard()]
    private let padX: CGFloat = 22
    private var prompterTimer: Timer?
    private var prompterRate: CGFloat = 1
    private var prompterScroll: NSScrollView?
    private var prompterText: NSTextView?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        tabs.items = [.init(symbol: "square.grid.2x2", title: "Home"), .init(symbol: "doc.on.clipboard", title: "Clips"),
                      .init(symbol: "tray", title: "Shelf"), .init(symbol: "sparkles", title: "Agents"),
                      .init(symbol: "checklist", title: "Up Next"), .init(symbol: "text.alignleft", title: "Prompter"),
                      .init(symbol: "timer", title: "Focus")]
        tabs.onSelect = { [weak self] i in self?.selectedTab = Tab(rawValue: i) ?? .home }
        addSubview(tabs)
        (homeCards + [left, right]).forEach { $0.isHidden = true; addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        tabs.frame = NSRect(x: padX, y: 16, width: tabs.preferredWidth, height: 40)
        let y0: CGFloat = 70, ch = h - y0 - 18
        let gap: CGFloat = 12
        if selectedTab == .home {
            let widths: [CGFloat] = [292, 168, 184, w - padX * 2 - 292 - 168 - 184 - gap * 3]
            var x = padX
            for (i, c) in homeCards.enumerated() { c.frame = NSRect(x: x, y: y0, width: widths[i], height: ch); x += widths[i] + gap }
        } else {
            let lw: CGFloat = 250
            left.frame = NSRect(x: padX, y: y0, width: lw, height: ch)
            right.frame = NSRect(x: padX + lw + gap, y: y0, width: w - padX * 2 - lw - gap, height: ch)
        }
        layoutCardContents()
    }

    /// Rebuilds the card contents from the data source.
    func refresh() {
        guard let d = data else { return }
        tabs.counts = [0, d.todayItems, d.shelfURLs.count, d.agents.activeSessions.count + (d.agents.waiting ? 1 : 0),
                       d.calendar.events.count + d.calendar.reminders.count, 0, d.timer.isRunning ? 1 : 0]
        tabs.selected = selectedTab.rawValue
        homeCards.forEach { $0.isHidden = selectedTab != .home }
        left.isHidden = selectedTab == .home; right.isHidden = selectedTab == .home
        [left, right].forEach { $0.subviews.forEach { $0.removeFromSuperview() } }
        homeCards.forEach { $0.subviews.forEach { $0.removeFromSuperview() } }
        switch selectedTab {
        case .home: buildHome(d)
        case .clips: buildClips(d)
        case .shelf: buildShelf(d)
        case .agents: buildAgents(d)
        case .upNext: buildUpNext(d)
        case .prompter: buildPrompter(d)
        case .focus: buildFocus(d)
        }
        needsLayout = true
    }

    /// Light refresh for ticking values (timer, progress) without rebuilding.
    func tick() {
        guard let d = data else { return }
        if selectedTab == .focus || selectedTab == .home { refresh() }
        _ = d
    }

    private var pendingLayout: [() -> Void] = []
    private func layoutCardContents() { pendingLayout.forEach { $0() } }
    private func onLayout(_ f: @escaping () -> Void) { pendingLayout.append(f) }

    // Summary card helper: small label top-left, big numeral bottom-left, optional circle button top-right.
    private func summary(_ card: GlassCard, title: String, subtitle: String? = nil, big: String, bigSuffix: String? = nil, caption: String? = nil, button: NSView? = nil, dot: NSColor? = nil) {
        let t = Theme.label(title, size: 13, color: Theme.secondary); card.addSubview(t)
        var s: NSTextField?
        if let subtitle { let l = Theme.label(subtitle, size: 13, color: Theme.secondary); card.addSubview(l); s = l }
        let b = Theme.label(big, size: big.count > 3 ? 48 : 64, weight: .light, color: .white); card.addSubview(b)
        var suf: NSTextField?
        if let bigSuffix { let l = Theme.label(bigSuffix, size: 24, weight: .light, color: Theme.dim); card.addSubview(l); suf = l }
        var cap: NSTextField?
        if let caption { let l = Theme.label(caption, size: 13, color: Theme.secondary); card.addSubview(l); cap = l }
        var dv: NSView?
        if let dot { let v = NSView(); v.wantsLayer = true; v.layer?.cornerRadius = 4; v.layer?.backgroundColor = dot.cgColor; card.addSubview(v); dv = v }
        if let button { card.addSubview(button) }
        onLayout {
            let W = card.bounds.width, H = card.bounds.height
            t.sizeToFit(); t.frame.origin = NSPoint(x: 22, y: 20)
            s?.sizeToFit(); s?.frame.origin = NSPoint(x: 22, y: 38)
            b.sizeToFit(); b.frame.origin = NSPoint(x: 18, y: H - 22 - (cap != nil ? 22 : 0) - b.frame.height)
            suf?.sizeToFit(); suf?.frame.origin = NSPoint(x: b.frame.maxX + 2, y: b.frame.maxY - (suf?.frame.height ?? 0) - 12)
            cap?.sizeToFit(); cap?.frame.origin = NSPoint(x: 22 + (dv != nil ? 14 : 0), y: H - 22 - (cap?.frame.height ?? 0))
            dv?.frame = NSRect(x: 22, y: (cap?.frame.midY ?? 0) - 4, width: 8, height: 8)
            if let button { button.frame.origin = NSPoint(x: W - 20 - button.frame.width, y: 18) }
        }
    }

    // MARK: Home

    private func buildHome(_ d: IslandDataSource) {
        pendingLayout = []
        // Now playing
        let m = homeCards[0]
        let art = NSImageView(); art.wantsLayer = true; art.layer?.cornerRadius = 12; art.layer?.cornerCurve = .continuous; art.layer?.masksToBounds = true
        art.layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor; art.imageScaling = .scaleProportionallyUpOrDown
        art.image = d.nowPlayingInfo?.artwork
        let title = Theme.label(d.nowPlayingInfo?.title ?? "Nothing playing", size: 16, weight: .semibold, color: .white)
        let sub = Theme.label(d.nowPlayingInfo.map { "\($0.artist) · \($0.source.rawValue == "Google Chrome" ? "YouTube" : $0.source.rawValue)" } ?? "Spotify, Music or YouTube Music", size: 12, color: Theme.secondary)
        let track = NSView(); track.wantsLayer = true; track.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor; track.layer?.cornerRadius = 1.5
        let fill = NSView(); fill.wantsLayer = true; fill.layer?.backgroundColor = NSColor.white.cgColor; fill.layer?.cornerRadius = 1.5; track.addSubview(fill)
        let prev = CircleButton(symbol: "backward.fill", size: 36, filled: false, target: self, action: #selector(musicPrev))
        let play = CircleButton(symbol: d.nowPlayingInfo?.isPlaying == true ? "pause.fill" : "play.fill", size: 44, filled: true, target: self, action: #selector(musicPlay))
        let next = CircleButton(symbol: "forward.fill", size: 36, filled: false, target: self, action: #selector(musicNext))
        [art, title, sub, track, prev, play, next].forEach { m.addSubview($0) }
        let enabled = d.nowPlayingInfo != nil
        [prev, play, next].forEach { $0.isEnabled = enabled; $0.alphaValue = enabled ? 1 : 0.35 }
        onLayout {
            let W = m.bounds.width, H = m.bounds.height
            art.frame = NSRect(x: 20, y: 20, width: 64, height: 64)
            title.frame = NSRect(x: 98, y: 26, width: W - 118, height: 20)
            sub.frame = NSRect(x: 98, y: 50, width: W - 118, height: 16)
            track.frame = NSRect(x: 20, y: 106, width: W - 40, height: 3)
            let frac = CGFloat(d.nowPlayingInfo.map { $0.duration > 0 ? $0.position / $0.duration : 0 } ?? 0)
            fill.frame = NSRect(x: 0, y: 0, width: track.frame.width * frac, height: 3)
            prev.frame.origin = NSPoint(x: 20, y: H - 20 - 36)
            next.frame.origin = NSPoint(x: W - 20 - 36, y: H - 20 - 36)
            play.frame.origin = NSPoint(x: W / 2 - 22, y: H - 20 - 44)
        }
        // Agent
        let a = homeCards[1]
        let s = d.agents.activeSessions.first
        let agentState = d.agents.waiting ? "Needs you" : (s?.state == .working ? "Running" : (s == nil ? "Idle" : s!.state.rawValue.capitalized))
        summary(a, title: s?.name ?? "Claude", subtitle: agentState, big: "\(d.agents.activeSessions.count)", caption: d.agents.waiting ? "waiting" : "sessions",
                dot: d.agents.waiting ? .systemOrange : (s?.state == .working ? .systemGreen : Theme.dim))
        // Weather
        let w = homeCards[2]
        if let r = d.weather.reading {
            summary(w, title: r.place.isEmpty ? "Weather" : r.place, subtitle: Self.condition(r.code), big: "\(Int(r.tempC.rounded()))", bigSuffix: "°")
        } else {
            summary(w, title: "Weather", subtitle: Settings.weatherEnabled ? "Locating…" : "Off", big: "--", bigSuffix: "°")
        }
        // Up next
        let u = homeCards[3]
        if let e = d.calendar.events.first {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            let arrow = CircleButton(symbol: "arrow.up.right", size: 40, filled: true, target: self, action: #selector(joinFirst))
            summary(u, title: "Up next", subtitle: CalendarMonitor.relative(e), big: f.string(from: e.start), caption: e.title, button: arrow, dot: .systemBlue)
        } else {
            summary(u, title: "Up next", subtitle: Settings.calendarEnabled ? "Nothing in 24 h" : "Calendar off", big: "--:--")
        }
    }

    static func condition(_ code: Int) -> String {
        switch code { case 0: return "Clear"; case 1, 2: return "Partly cloudy"; case 3: return "Cloudy"; case 45, 48: return "Fog"
        case 51...67, 80...82: return "Rain"; case 71...77, 85, 86: return "Snow"; case 95...99: return "Thunderstorm"; default: return "Cloudy" }
    }

    // MARK: Clips

    private func buildClips(_ d: IslandDataSource) {
        pendingLayout = []
        let open = CircleButton(symbol: "arrow.up.right", size: 40, filled: true, target: self, action: #selector(openHistoryTapped))
        summary(left, title: "Clipboard", subtitle: "\(d.totalItems) items kept", big: "\(d.todayItems)", caption: "copied today", button: open)
        let hint = Theme.label("Tap to paste · ⌘1–6 · drag out", size: 12, color: Theme.dim); right.addSubview(hint)
        let stack = NSStackView(); stack.orientation = .horizontal; stack.spacing = 10; stack.distribution = .fillEqually
        for (i, item) in d.recentItems.prefix(6).enumerated() {
            let chip = ChipView(item: item, index: i)
            chip.onTap = { [weak self] in self?.onPick?(item) }
            stack.addArrangedSubview(chip)
        }
        if d.recentItems.isEmpty { stack.addArrangedSubview(Theme.label("Nothing copied yet", size: 13, color: Theme.dim)) }
        right.addSubview(stack)
        onLayout {
            let W = self.right.bounds.width, H = self.right.bounds.height
            hint.sizeToFit(); hint.frame.origin = NSPoint(x: 22, y: 20)
            stack.frame = NSRect(x: 20, y: 48, width: W - 40, height: H - 68)
        }
    }

    // MARK: Shelf

    private func buildShelf(_ d: IslandDataSource) {
        pendingLayout = []
        let clear = CircleButton(symbol: "trash", size: 40, filled: false, target: self, action: #selector(shelfClearTapped))
        clear.isHidden = d.shelfURLs.isEmpty
        summary(left, title: "Shelf", subtitle: "Drop files on the notch", big: "\(d.shelfURLs.count)", caption: d.shelfURLs.count == 1 ? "file" : "files", button: clear)
        if d.shelfURLs.isEmpty {
            let e = Theme.label("Drop files or folders anywhere on the notch. They wait here until you drag them out.", size: 13, color: Theme.dim)
            e.lineBreakMode = .byWordWrapping; e.maximumNumberOfLines = 3; right.addSubview(e)
            onLayout { e.frame = NSRect(x: 22, y: 22, width: self.right.bounds.width - 44, height: 60) }
            return
        }
        let stack = NSStackView(); stack.orientation = .horizontal; stack.spacing = 10; stack.distribution = .fillEqually
        for url in d.shelfURLs.prefix(5) {
            let c = ShelfChip(url: url); c.onRemove = { [weak self] in self?.onShelfRemove?(url) }
            stack.addArrangedSubview(c)
        }
        right.addSubview(stack)
        let hint = Theme.label("Drag a file out to use it anywhere · right-click to remove", size: 12, color: Theme.dim); right.addSubview(hint)
        onLayout {
            let W = self.right.bounds.width, H = self.right.bounds.height
            hint.sizeToFit(); hint.frame.origin = NSPoint(x: 22, y: 20)
            stack.frame = NSRect(x: 20, y: 48, width: W - 40, height: H - 68)
        }
    }

    // MARK: Agents

    private func buildAgents(_ d: IslandDataSource) {
        pendingLayout = []
        let sessions = d.agents.activeSessions
        summary(left, title: "Agents", subtitle: AgentMonitor.hooksInstalled ? "Claude Code connected" : "Hooks not installed", big: "\(sessions.count)",
                caption: d.agents.waiting ? "needs your approval" : "active sessions", dot: d.agents.waiting ? .systemOrange : (sessions.isEmpty ? Theme.dim : .systemGreen))
        if let p = d.agents.pending.first {
            right.highlighted = true
            let name = d.agents.sessions[p.sessionID]?.name ?? "Claude Code"
            let t = Theme.label("\(name) wants to run \(p.tool)", size: 15, weight: .semibold, color: .white)
            let cmd = NSTextField(wrappingLabelWithString: p.summary); cmd.font = .monospacedSystemFont(ofSize: 13, weight: .regular); cmd.textColor = Theme.secondary; cmd.maximumNumberOfLines = 3
            let allow = PillButton("Allow", filled: true, target: self, action: #selector(allowTapped))
            let deny = PillButton("Deny", target: self, action: #selector(denyTapped))
            [t, cmd, allow, deny].forEach { right.addSubview($0) }
            onLayout {
                let W = self.right.bounds.width, H = self.right.bounds.height
                t.frame = NSRect(x: 22, y: 22, width: W - 44, height: 20)
                cmd.frame = NSRect(x: 22, y: 50, width: W - 44, height: 60)
                allow.frame.origin = NSPoint(x: 22, y: H - 22 - 30)
                deny.frame.origin = NSPoint(x: 22 + allow.frame.width + 10, y: H - 22 - 30)
            }
            return
        }
        right.highlighted = false
        if sessions.isEmpty {
            let e = Theme.label(AgentMonitor.hooksInstalled ? "No agents running. Start a Claude Code session and it shows up here." : "Install the Claude Code hooks in Preferences › Agents.", size: 13, color: Theme.dim)
            e.lineBreakMode = .byWordWrapping; e.maximumNumberOfLines = 3; right.addSubview(e)
            onLayout { e.frame = NSRect(x: 22, y: 22, width: self.right.bounds.width - 44, height: 60) }
            return
        }
        var rows: [ListRow] = []
        for s in sessions.prefix(3) {
            let color: NSColor = s.state == .waiting ? .systemOrange : (s.state == .working ? .systemGreen : .systemGray)
            let r = ListRow(color: color, title: s.name, subtitle: s.message.isEmpty ? s.state.rawValue.capitalized : s.message, tag: s.state.rawValue.capitalized, tagColor: color)
            right.addSubview(r); rows.append(r)
        }
        rows.last?.showsSeparator = false
        onLayout { for (i, r) in rows.enumerated() { r.frame = NSRect(x: 0, y: 10 + CGFloat(i) * 50, width: self.right.bounds.width, height: 50) } }
    }

    // MARK: Up next

    private func buildUpNext(_ d: IslandDataSource) {
        pendingLayout = []
        let df = DateFormatter(); df.dateFormat = "EEEE, MMM d"
        let items = Array((d.calendar.events + d.calendar.reminders).prefix(3))
        summary(left, title: "Today,", subtitle: df.string(from: Date()), big: "\(d.calendar.reminders.count)", bigSuffix: "/\(d.calendar.reminders.count + d.calendar.events.count)", caption: "to do today")
        if !Settings.calendarEnabled || items.isEmpty {
            let e = Theme.label(Settings.calendarEnabled ? "Nothing coming up in the next 24 hours." : "Turn on Up Next in Preferences › Notch to see events and reminders.", size: 13, color: Theme.dim)
            e.lineBreakMode = .byWordWrapping; e.maximumNumberOfLines = 3; right.addSubview(e)
            onLayout { e.frame = NSRect(x: 22, y: 22, width: self.right.bounds.width - 44, height: 60) }
            return
        }
        var rows: [ListRow] = []
        let palette: [NSColor] = [.systemBlue, .systemOrange, .systemGreen]
        for (i, it) in items.enumerated() {
            let f = DateFormatter(); f.timeStyle = .short
            let sub = it.isReminder ? "Today" : "Today · \(f.string(from: it.start)) · \(CalendarMonitor.relative(it))"
            var btn: NSView?
            if !it.isReminder {
                let b = CircleButton(symbol: it.joinURL != nil ? "video.fill" : "arrow.up.right", size: 32, filled: it.joinURL != nil, target: self, action: #selector(joinTapped(_:)))
                b.tag = i; btn = b
            }
            let r = ListRow(color: palette[i % 3], title: it.title, subtitle: sub, tag: it.isReminder ? "Reminder" : (it.location.isEmpty ? "Calendar" : it.location), tagColor: palette[i % 3], button: btn)
            right.addSubview(r); rows.append(r)
        }
        rows.last?.showsSeparator = false
        onLayout { for (i, r) in rows.enumerated() { r.frame = NSRect(x: 0, y: 10 + CGFloat(i) * 56, width: self.right.bounds.width, height: 56) } }
    }

    // MARK: Prompter

    private func buildPrompter(_ d: IslandDataSource) {
        pendingLayout = []
        let text = d.promptText.isEmpty ? "Copy some text and come back — it scrolls here at your pace." : d.promptText
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let minutes = max(1, Int((Double(words) / 150).rounded(.up)))
        summary(left, title: "Teleprompter", subtitle: prompterTimer == nil ? "Ready" : "Rolling", big: "\(minutes)", bigSuffix: "min", caption: "\(words) words")
        let scroll = NSScrollView(); let tv = NSTextView()
        tv.isEditable = false; tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 10, height: 40)
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = false; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true
        tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: Theme.font(24, .regular), .foregroundColor: NSColor.white, .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = 10; return p }()]))
        scroll.documentView = tv; scroll.drawsBackground = false; scroll.hasVerticalScroller = false; scroll.borderType = .noBorder
        right.addSubview(scroll); prompterScroll = scroll; prompterText = tv
        let play = CircleButton(symbol: prompterTimer == nil ? "play.fill" : "pause.fill", size: 44, filled: true, target: self, action: #selector(prompterPlay))
        let reset = CircleButton(symbol: "arrow.counterclockwise", size: 36, filled: false, target: self, action: #selector(prompterReset))
        let speed = PillButton("\(String(format: "%.1f", prompterRate))×  ", target: self, action: #selector(prompterSpeed))
        [play, reset, speed].forEach { right.addSubview($0) }
        onLayout {
            let W = self.right.bounds.width, H = self.right.bounds.height
            scroll.frame = NSRect(x: 16, y: 10, width: W - 32, height: H - 80)
            play.frame.origin = NSPoint(x: 22, y: H - 22 - 44)
            reset.frame.origin = NSPoint(x: 76, y: H - 22 - 40)
            speed.frame.origin = NSPoint(x: W - 22 - speed.frame.width, y: H - 22 - 37)
        }
    }

    // MARK: Focus

    private var pomodoroMode = true

    private func buildFocus(_ d: IslandDataSource) {
        pendingLayout = []
        let t = d.timer
        let running = t.isRunning
        let remaining = running ? t.remaining : (pomodoroMode ? 25 * 60 : 15 * 60)
        let mm = Int(remaining.rounded(.up)) / 60, ss = Int(remaining.rounded(.up)) % 60
        let play = CircleButton(symbol: running ? "stop.fill" : "play.fill", size: 48, filled: true, target: self, action: #selector(focusToggle))
        summary(left, title: pomodoroMode ? "Pomodoro" : "Timer", subtitle: running ? "Running" : "Ready", big: "\(mm)", bigSuffix: String(format: ":%02d", ss),
                caption: pomodoroMode ? "Focus" : "Countdown", button: play, dot: Theme.accent)
        // right: mode pills + end time + progress line + session dots
        let pomo = PillButton("Pomodoro", target: self, action: #selector(modePomodoro)); pomo.isOn = pomodoroMode
        let plain = PillButton("Timer", target: self, action: #selector(modeTimer)); plain.isOn = !pomodoroMode
        let endLabel = Theme.label("Would end at", size: 13, color: Theme.secondary)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let endTime = Theme.label(f.string(from: Date().addingTimeInterval(remaining)), size: 44, weight: .light, color: .white)
        let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.2).cgColor; line.layer?.cornerRadius = 1
        let fill = NSView(); fill.wantsLayer = true; fill.layer?.backgroundColor = NSColor.white.cgColor; fill.layer?.cornerRadius = 1
        [pomo, plain, endLabel, endTime, line, fill].forEach { right.addSubview($0) }
        var ticks: [NSTextField] = []
        let total = running ? t.duration : remaining
        let tickEvery: Double = total > 1800 ? 15 : 5
        var m = 0.0
        while m <= total / 60 + 0.01 { let l = Theme.label("\(Int(m))", size: 11, color: Theme.dim); right.addSubview(l); ticks.append(l); m += tickEvery }
        var presets: [PillButton] = []
        if !pomodoroMode && !running {
            for mins in [5, 10, 15, 25, 45, 60] { let b = PillButton("\(mins) min", target: self, action: #selector(presetTapped(_:))); b.tag = mins; right.addSubview(b); presets.append(b) }
        }
        var dots: [NSView] = []
        let bottom = Theme.label(pomodoroMode ? "Focus · session \(min(4, d.pomodoroSessions + 1)) / 4" : (running ? "Counting down" : "Pick a length"), size: 13, color: Theme.secondary)
        right.addSubview(bottom)
        if pomodoroMode {
            for i in 0..<4 { let v = NSView(); v.wantsLayer = true; v.layer?.cornerRadius = 5; v.layer?.borderWidth = 1.5
                let done = i < d.pomodoroSessions, current = i == d.pomodoroSessions
                v.layer?.borderColor = (done || current ? Theme.accent : Theme.dim).cgColor
                v.layer?.backgroundColor = (done ? Theme.accent : NSColor.clear).cgColor
                right.addSubview(v); dots.append(v) }
        }
        let plus = running ? PillButton("+5 min", target: self, action: #selector(plusFive)) : nil
        if let plus { right.addSubview(plus) }
        onLayout {
            let W = self.right.bounds.width, H = self.right.bounds.height
            pomo.frame.origin = NSPoint(x: 22, y: 18); plain.frame.origin = NSPoint(x: 22 + pomo.frame.width + 8, y: 18)
            endLabel.sizeToFit(); endLabel.frame.origin = NSPoint(x: 22, y: 64)
            endTime.sizeToFit(); endTime.frame.origin = NSPoint(x: 20, y: 80)
            line.frame = NSRect(x: 22, y: H - 62, width: W - 44, height: 2)
            let frac = CGFloat(running ? t.progress : 0)
            fill.frame = NSRect(x: 22, y: H - 62, width: (W - 44) * frac, height: 2)
            for (i, l) in ticks.enumerated() { l.sizeToFit(); let x = 22 + (W - 44) * CGFloat(Double(i) * tickEvery) / CGFloat(max(1, total / 60)); l.frame.origin = NSPoint(x: min(W - 22 - l.frame.width, x - l.frame.width / 2), y: H - 54) }
            bottom.sizeToFit(); bottom.frame.origin = NSPoint(x: dots.isEmpty ? 22 : 22 + 4 * 18, y: H - 22 - bottom.frame.height)
            for (i, v) in dots.enumerated() { v.frame = NSRect(x: 22 + CGFloat(i) * 18, y: bottom.frame.midY - 5, width: 10, height: 10) }
            var px: CGFloat = W - 22
            for b in presets.reversed() { px -= b.frame.width; b.frame.origin = NSPoint(x: px, y: 18); px -= 8 }
            if let plus { plus.frame.origin = NSPoint(x: W - 22 - plus.frame.width, y: 18) }
        }
    }

    // MARK: Actions

    @objc private func musicPrev() { onMusic?(.previous) }
    @objc private func musicPlay() { onMusic?(.playPause) }
    @objc private func musicNext() { onMusic?(.next) }
    @objc private func openHistoryTapped() { onOpenHistory?() }
    @objc private func shelfClearTapped() { onShelfClear?() }
    @objc private func allowTapped() { if let p = data?.agents.pending.first { onAgentDecision?(p, true) } }
    @objc private func denyTapped() { if let p = data?.agents.pending.first { onAgentDecision?(p, false) } }
    @objc private func joinFirst() { if let e = data?.calendar.events.first { onJoin?(e) } }
    @objc private func joinTapped(_ sender: NSButton) {
        guard let d = data else { return }
        let items = Array((d.calendar.events + d.calendar.reminders).prefix(3))
        if items.indices.contains(sender.tag) { onJoin?(items[sender.tag]) }
    }
    @objc private func modePomodoro() { pomodoroMode = true; refresh() }
    @objc private func modeTimer() { pomodoroMode = false; refresh() }
    @objc private func presetTapped(_ sender: NSButton) { onTimerStart?(Double(sender.tag), false) }
    @objc private func plusFive() { onTimerAdd?(5) }
    @objc private func focusToggle() {
        guard let d = data else { return }
        if d.timer.isRunning { onTimerCancel?() } else { onTimerStart?(pomodoroMode ? 25 : 15, pomodoroMode) }
    }
    @objc private func prompterPlay() {
        if prompterTimer != nil { prompterTimer?.invalidate(); prompterTimer = nil; refresh(); return }
        prompterTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self, let sc = self.prompterScroll, let tv = self.prompterText else { return }
            let cv = sc.contentView
            let maxY = max(0, tv.frame.height - cv.bounds.height)
            var y = cv.bounds.origin.y + 0.8 * self.prompterRate
            if y >= maxY { y = maxY; self.prompterTimer?.invalidate(); self.prompterTimer = nil; self.refresh() }
            cv.scroll(to: NSPoint(x: 0, y: y)); sc.reflectScrolledClipView(cv)
        }
        refresh()
    }
    @objc private func prompterReset() { prompterScroll?.contentView.scroll(to: .zero); prompterScroll.map { $0.reflectScrolledClipView($0.contentView) } }
    @objc private func prompterSpeed() { prompterRate = prompterRate >= 2.5 ? 0.5 : prompterRate + 0.5; refresh() }
}
