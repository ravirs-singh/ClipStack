import AppKit

/// A persistent pile of files you drop on the notch and drag out later (Glance's "Shelf" / Yoink-style).
final class ShelfStore {
    static let changed = Notification.Name("ClipStackShelfChanged")
    private(set) var urls: [URL] = [] { didSet { save(); NotificationCenter.default.post(name: Self.changed, object: self) } }
    private let key = "shelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ new: [URL]) {
        var list = urls.filter { u in !new.contains(u) }
        list.insert(contentsOf: new, at: 0)
        urls = Array(list.prefix(20))
    }

    func remove(_ url: URL) { urls.removeAll { $0 == url } }
    func clear() { urls = [] }

    private func save() { UserDefaults.standard.set(urls.map(\.path), forKey: key) }
}

/// A single countdown shown in the notch wing; fires a notification each second and when done.
final class NotchTimer {
    static let tick = Notification.Name("ClipStackTimerTick")
    static let finished = Notification.Name("ClipStackTimerFinished")

    private(set) var endDate: Date?
    private(set) var duration: TimeInterval = 0
    private var timer: Timer?

    var isRunning: Bool { endDate != nil }
    var remaining: TimeInterval { max(0, endDate?.timeIntervalSinceNow ?? 0) }
    var progress: Double { duration > 0 ? 1 - remaining / duration : 0 }

    func start(minutes: Double) {
        duration = minutes * 60
        endDate = Date().addingTimeInterval(duration)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.step() }
        NotificationCenter.default.post(name: Self.tick, object: self)
    }

    func add(minutes: Double) {
        guard let end = endDate else { start(minutes: minutes); return }
        endDate = end.addingTimeInterval(minutes * 60)
        duration += minutes * 60
        NotificationCenter.default.post(name: Self.tick, object: self)
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        endDate = nil; duration = 0
        NotificationCenter.default.post(name: Self.tick, object: self)
    }

    private func step() {
        if remaining <= 0 {
            timer?.invalidate(); timer = nil
            endDate = nil
            NSSound(named: "Glass")?.play()
            NotificationCenter.default.post(name: Self.finished, object: self)
        } else {
            NotificationCenter.default.post(name: Self.tick, object: self)
        }
    }

    static func format(_ s: TimeInterval) -> String {
        let t = Int(s.rounded(.up))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Small circular progress ring (CAShapeLayer) used in the collapsed notch.
final class RingView: NSView {
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    var progress: Double = 0 { didSet { fill.strokeEnd = CGFloat(max(0, min(1, progress))) } }
    var color: NSColor = .systemOrange { didSet { fill.strokeColor = color.cgColor } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [track, fill] {
            l.fillColor = nil; l.lineWidth = 2.5; l.lineCap = .round
            layer?.addSublayer(l)
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        fill.strokeColor = color.cgColor
        fill.strokeEnd = 0
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let r = min(bounds.width, bounds.height) / 2 - 2
        let p = CGMutablePath()
        p.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        track.path = p; fill.path = p
        track.frame = bounds; fill.frame = bounds
    }
}
