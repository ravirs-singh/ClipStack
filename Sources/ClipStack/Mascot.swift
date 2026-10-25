import AppKit

/// Pip: two eyes that live beside the notch. Blinks, follows the cursor, reacts to what the app is doing.
final class MascotView: NSView {
    enum Mood { case normal, happy, alert, sleepy, groove }

    var mood: Mood = .normal { didSet { if mood != oldValue { applyMood() } } }
    /// -1…1 horizontal gaze, set from the cursor position.
    var gaze: CGFloat = 0 { didSet { needsLayout = true } }

    private let left = CAShapeLayer()
    private let right = CAShapeLayer()
    private var blinkTimer: Timer?
    private var happyTimer: Timer?
    private var lidScale: CGFloat = 1        // 1 open … 0.08 closed
    private var bob: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for e in [left, right] {
            e.fillColor = NSColor.white.cgColor
            e.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(e)
        }
        scheduleBlink()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 18) }

    override func layout() {
        super.layout()
        let eyeW: CGFloat = 8, eyeH: CGFloat = mood == .alert ? 15 : 13, gap: CGFloat = 7
        let cx = bounds.midX + gaze * 3, cy = bounds.midY + bob
        let lx = cx - gap / 2 - eyeW / 2, rx = cx + gap / 2 + eyeW / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (e, x) in [(left, lx), (right, rx)] {
            e.bounds = CGRect(x: 0, y: 0, width: eyeW, height: eyeH)
            e.position = CGPoint(x: x, y: cy)
            e.path = eyePath(w: eyeW, h: eyeH)
            e.transform = CATransform3DMakeScale(1, lidScale, 1)
        }
        CATransaction.commit()
    }

    private func eyePath(w: CGFloat, h: CGFloat) -> CGPath {
        switch mood {
        case .happy:
            // upward arcs ^‿^
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: w / 2, y: h * 0.25), radius: w * 0.62, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
            p.addArc(center: CGPoint(x: w / 2, y: h * 0.25), radius: w * 0.62 - 2.6, startAngle: .pi * 0.85, endAngle: .pi * 0.15, clockwise: true)
            p.closeSubpath()
            return p
        default:
            return CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        }
    }

    private func applyMood() {
        happyTimer?.invalidate()
        let color: NSColor = mood == .alert ? .systemOrange : .white
        left.fillColor = color.cgColor; right.fillColor = color.cgColor
        switch mood {
        case .sleepy: setLid(0.45, animated: true)
        case .alert: setLid(1.15, animated: true)
        case .happy:
            setLid(1, animated: true)
            happyTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in self?.mood = .normal }
        case .groove: setLid(0.85, animated: true); startBob()
        case .normal: setLid(1, animated: true)
        }
        if mood != .groove { stopBob() }
        needsLayout = true
    }

    private func setLid(_ v: CGFloat, animated: Bool) {
        lidScale = v
        if animated {
            CATransaction.begin(); CATransaction.setAnimationDuration(0.18)
            for e in [left, right] { e.transform = CATransform3DMakeScale(1, v, 1) }
            CATransaction.commit()
        } else { needsLayout = true }
    }

    // MARK: Blink

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2.5...6), repeats: false) { [weak self] _ in
            self?.blink(); self?.scheduleBlink()
        }
    }

    private func blink() {
        guard mood != .happy, window != nil, !isHidden else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
        a.values = [lidScale, 0.08, lidScale]; a.keyTimes = [0, 0.5, 1]; a.duration = 0.14
        left.add(a, forKey: "blink"); right.add(a, forKey: "blink")
        // occasional double blink
        if Bool.random() && Int.random(in: 0..<4) == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                self?.left.add(a, forKey: "blink2"); self?.right.add(a, forKey: "blink2")
            }
        }
    }

    // MARK: Groove (music)

    private var bobTimer: Timer?
    private func startBob() {
        bobTimer?.invalidate()
        var t: CGFloat = 0
        bobTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            t += 1 / 30
            self?.bob = sin(t * 2 * .pi * 1.87) * 1.6     // ~112 BPM
            self?.needsLayout = true
        }
    }
    private func stopBob() { bobTimer?.invalidate(); bobTimer = nil; bob = 0 }

    deinit { blinkTimer?.invalidate(); bobTimer?.invalidate(); happyTimer?.invalidate() }
}
