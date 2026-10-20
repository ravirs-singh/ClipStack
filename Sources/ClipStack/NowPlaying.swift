import AppKit

struct NowPlayingInfo: Equatable {
    enum Source: String, CaseIterable {
        case spotify = "Spotify", music = "Music"
        case chrome = "Google Chrome", brave = "Brave Browser", edge = "Microsoft Edge", arc = "Arc"
        var isBrowser: Bool { self != .spotify && self != .music }
        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music: return "com.apple.Music"
            case .chrome: return "com.google.Chrome"
            case .brave: return "com.brave.Browser"
            case .edge: return "com.microsoft.edgemac"
            case .arc: return "company.thebrowser.Browser"
            }
        }
    }
    let source: Source
    let trackID: String
    let title: String
    let artist: String
    let isPlaying: Bool
    let position: TimeInterval   // seconds
    let duration: TimeInterval   // seconds
    var artwork: NSImage?

    static func == (a: NowPlayingInfo, b: NowPlayingInfo) -> Bool {
        a.source == b.source && a.trackID == b.trackID && a.isPlaying == b.isPlaying && Int(a.position) == Int(b.position)
    }
}

/// Polls Spotify / Apple Music via Apple Events (needs the one-time Automation permission prompt).
final class NowPlayingMonitor {
    static let changed = Notification.Name("ClipStackNowPlayingChanged")
    private(set) var info: NowPlayingInfo? { didSet { if info != oldValue { NotificationCenter.default.post(name: Self.changed, object: self) } } }

    private var timer: Timer?
    private var lastScriptError = ""
    private var lastScriptErrorAt = Date.distantPast
    private var artworkCache: (key: String, image: NSImage?)?
    private var fetchingArtwork = false
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in self?.applyEnabled() }
        applyEnabled()
    }

    private func applyEnabled() {
        timer?.invalidate(); timer = nil
        guard Settings.notchEnabled, Settings.notchNowPlaying else { info = nil; return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 0.2
        poll()
    }

    /// Poll interval is 1 s; position is interpolated by callers between polls.
    private func poll() {
        // Only talk to apps that are actually running — avoids launching them and avoids needless prompts.
        if isRunning("com.spotify.client"), let i = querySpotify() { update(i); return }
        if isRunning("com.apple.Music"), let i = queryMusic() { update(i); return }
        for src in NowPlayingInfo.Source.allCases where src.isBrowser {
            if isRunning(src.bundleID), let i = queryBrowser(src) { update(i); return }
        }
        info = nil
    }

    private func update(_ fresh: NowPlayingInfo) {
        var i = fresh
        let key = fresh.source.rawValue + ":" + fresh.trackID
        if let c = artworkCache, c.key == key {
            i.artwork = c.image
        } else {
            i.artwork = nil
            fetchArtwork(for: fresh, key: key)
        }
        info = i
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard let src = info?.source else { return }
        if src.isBrowser { sendBrowser(command, src: src) } else {
            _ = run("tell application \"\(src.rawValue)\" to \(command)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poll() }
    }

    // MARK: Queries

    private func querySpotify() -> NowPlayingInfo? {
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set t to current track
            return (player state as string) & "|" & (name of t) & "|" & (artist of t) & "|" & (artwork url of t) & "|" & (player position as string) & "|" & ((duration of t) / 1000 as string) & "|" & (id of t)
        end tell
        """
        guard let out = run(script), !out.isEmpty else { return nil }
        let f = out.components(separatedBy: "|")
        guard f.count >= 7 else { return nil }
        return NowPlayingInfo(source: .spotify, trackID: f[6], title: f[1], artist: f[2], isPlaying: f[0] == "playing",
                              position: Double(f[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
                              duration: Double(f[5].replacingOccurrences(of: ",", with: ".")) ?? 0, artwork: nil)
    }

    private var browserArtURL: String?
    private var lastBrowserTitle = ""

    private func queryMusic() -> NowPlayingInfo? {
        let script = """
        tell application "Music"
            if player state is stopped then return ""
            set t to current track
            return (player state as string) & "|" & (name of t) & "|" & (artist of t) & "||" & (player position as string) & "|" & (duration of t as string) & "|" & (database ID of t as string)
        end tell
        """
        guard let out = run(script), !out.isEmpty else { return nil }
        let f = out.components(separatedBy: "|")
        guard f.count >= 7 else { return nil }
        return NowPlayingInfo(source: .music, trackID: f[6], title: f[1], artist: f[2], isPlaying: f[0] == "playing",
                              position: Double(f[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
                              duration: Double(f[5].replacingOccurrences(of: ",", with: ".")) ?? 0, artwork: nil)
    }

    // MARK: Browsers (YouTube Music, YouTube) — needs View ▸ Developer ▸ "Allow JavaScript from Apple Events" in Chrome

    private var browserTabRef: String?   // "windowIndex,tabIndex" of the tab we last found

    private static let readJS = """
    (function(){var v=document.querySelector('video');var m=navigator.mediaSession&&navigator.mediaSession.metadata;if(!v||!m||!m.title)return '';var a='';if(m.artwork&&m.artwork.length){a=m.artwork[m.artwork.length-1].src;}return (v.paused?'paused':'playing')+'|'+m.title+'|'+(m.artist||'')+'|'+a+'|'+v.currentTime+'|'+(isFinite(v.duration)?v.duration:0)+'|'+location.pathname+location.search;})()
    """

    private func queryBrowser(_ src: NowPlayingInfo.Source) -> NowPlayingInfo? {
        let js = Self.readJS.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        // Scan every media tab; prefer one that is playing, else fall back to the first paused one.
        let script = """
        tell application "\(src.rawValue)"
            set best to ""
            set fallback to ""
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ti to 0
                repeat with t in tabs of w
                    set ti to ti + 1
                    set u to URL of t
                    if u contains "music.youtube.com" or u contains "youtube.com/watch" or u contains "soundcloud.com" then
                        try
                            set r to execute t javascript "\(js)"
                            if r is not "" and r is not missing value then
                                set r to (wi as string) & "," & (ti as string) & "|" & r
                                if r contains "|playing|" then
                                    set best to r
                                    exit repeat
                                else if fallback is "" then
                                    set fallback to r
                                end if
                            end if
                        end try
                    end if
                end repeat
                if best is not "" then exit repeat
            end repeat
            if best is not "" then return best
            return fallback
        end tell
        """
        guard let out = run(script), !out.isEmpty else { return nil }
        let f = out.components(separatedBy: "|")
        guard f.count >= 8 else { NSLog("ClipStack: unexpected browser reply: \(out)"); return nil }
        if f[2] != lastBrowserTitle { NSLog("ClipStack: now playing in \(src.rawValue): \(f[2]) — \(f[1])"); lastBrowserTitle = f[2] }
        browserTabRef = f[0]
        browserArtURL = f[4]
        return NowPlayingInfo(source: src, trackID: f[7] + "#" + f[2], title: f[2], artist: f[3], isPlaying: f[1] == "playing",
                              position: Double(f[5].replacingOccurrences(of: ",", with: ".")) ?? 0,
                              duration: Double(f[6].replacingOccurrences(of: ",", with: ".")) ?? 0, artwork: nil)
    }

    private func sendBrowser(_ command: String, src: NowPlayingInfo.Source) {
        guard let ref = browserTabRef else { return }
        let parts = ref.components(separatedBy: ",")
        guard parts.count == 2 else { return }
        let js: String
        switch command {
        case "playpause":
            js = "(function(){var v=document.querySelector('video');if(!v)return;v.paused?v.play():v.pause();})()"
        case "next track":
            js = "(function(){var b=document.querySelector('.next-button, tp-yt-paper-icon-button.next-button, .ytp-next-button, .skipControl__next');if(b)b.click();})()"
        default:
            js = "(function(){var b=document.querySelector('.previous-button, tp-yt-paper-icon-button.previous-button, .ytp-prev-button, .skipControl__previous');if(b)b.click();else{var v=document.querySelector('video');if(v)v.currentTime=0;}})()"
        }
        let esc = js.replacingOccurrences(of: "\"", with: "\\\"")
        _ = run("tell application \"\(src.rawValue)\" to execute tab \(parts[1]) of window \(parts[0]) javascript \"\(esc)\"")
    }

    private func fetchArtwork(for i: NowPlayingInfo, key: String) {
        guard !fetchingArtwork else { return }
        fetchingArtwork = true
        switch i.source {
        case .spotify, .chrome, .brave, .edge, .arc:
            let urlStr = i.source == .spotify ? run("tell application \"Spotify\" to artwork url of current track") : browserArtURL
            guard let urlStr, let url = URL(string: urlStr) else { storeArtwork(nil, key: key); return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let img = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async { self?.storeArtwork(img, key: key) }
            }.resume()
        case .music:
            // Artwork comes back as raw image data in the descriptor.
            let script = "tell application \"Music\" to get data of artwork 1 of current track"
            var err: NSDictionary?
            let desc = NSAppleScript(source: script)?.executeAndReturnError(&err)
            storeArtwork(desc.flatMap { NSImage(data: $0.data) }, key: key)
        }
    }

    private func storeArtwork(_ img: NSImage?, key: String) {
        fetchingArtwork = false
        artworkCache = (key, img)
        if var i = info, i.source.rawValue + ":" + i.trackID == key {
            i.artwork = img
            info = i
            NotificationCenter.default.post(name: Self.changed, object: self)   // artwork isn't part of ==
        }
    }

    private func run(_ source: String) -> String? {
        var err: NSDictionary?
        guard let s = NSAppleScript(source: source) else { return nil }
        let out = s.executeAndReturnError(&err)
        if let err {
            let msg = "\(err[NSAppleScript.errorMessage] ?? "") (\(err[NSAppleScript.errorNumber] ?? ""))"
            if msg != lastScriptError || Date().timeIntervalSince(lastScriptErrorAt) > 20 {
                NSLog("ClipStack: AppleScript error: \(msg)"); lastScriptError = msg; lastScriptErrorAt = Date()
            }
            return nil
        }
        return out.stringValue
    }
}

/// Four bouncing bars, like the iPhone's Dynamic Island audio indicator.
final class AudioBarsView: NSView {
    private var bars: [CALayer] = []
    var color: NSColor = .white { didSet { bars.forEach { $0.backgroundColor = color.cgColor } } }
    var isAnimating = false { didSet { if isAnimating != oldValue { isAnimating ? start() : stop() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let l = CALayer()
            l.backgroundColor = color.cgColor
            l.cornerRadius = 1.5
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(l)
            bars.append(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 14) }

    override func layout() {
        super.layout()
        let w: CGFloat = 3, gap: CGFloat = 2
        let total = CGFloat(bars.count) * w + CGFloat(bars.count - 1) * gap
        let x0 = (bounds.width - total) / 2
        for (i, b) in bars.enumerated() {
            b.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            b.position = CGPoint(x: x0 + CGFloat(i) * (w + gap) + w / 2, y: 0)
            if !isAnimating { b.transform = CATransform3DMakeScale(1, 0.25, 1) }
        }
    }

    private func start() {
        for (i, b) in bars.enumerated() {
            let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
            let seq: [CGFloat] = [0.3, 1.0, 0.5, 0.85, 0.35, 0.7, 0.3]
            let k = i % seq.count
            a.values = Array(seq[k...]) + Array(seq[..<k])
            a.duration = 0.9 + Double(i) * 0.13
            a.repeatCount = .infinity
            a.autoreverses = true
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            b.add(a, forKey: "bounce")
        }
    }

    private func stop() {
        bars.forEach { $0.removeAnimation(forKey: "bounce"); $0.transform = CATransform3DMakeScale(1, 0.25, 1) }
    }
}
