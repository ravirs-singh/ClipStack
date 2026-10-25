import AppKit

/// Pip: a small round character that lives beside the notch. Breathes, blinks, follows the cursor,
/// smiles when you copy, goes wide-eyed orange when an agent needs you, sways to music, dozes when idle.
final class MascotView: NSView {
    enum Mood { case normal, happy, alert, sleepy, groove }

    var mood: Mood = .normal { didSet { if mood != oldValue { applyMood() } } }
    /// -1…1 horizontal gaze, set from the cursor position.
    var gaze: CGFloat = 0 { didSet { needsLayout = true } }

    private let body = CAShapeLayer()
    private let shine = CAShapeLayer()
    private let cheekL = CAShapeLayer(), cheekR = CAShapeLayer()
    private let eyeL = CAShapeLayer(), eyeR = CAShapeLayer()
    private let glintL = CAShapeLayer(), glintR = CAShapeLayer()
    private let mouth = CAShapeLayer()
    private let zzz = CATextLayer()
    private var blinkTimer: Timer?
    private var happyTimer: Timer?
    private var motionTimer: Timer?
    private var phase: CGFloat = 0
    private var eyeOpen: CGFloat = 1

    private static let bodyColor = NSColor(red: 0.52, green: 0.58, blue: 1.0, alpha: 1)
    private static let alertColor = NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1)
    private static let ink = NSColor(red: 0.10, green: 0.08, blue: 0.22, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        body.fillColor = Self.bodyColor.cgColor
        shine.fillColor = NSColor.white.withAlphaComponent(0.22).cgColor
        for c in [cheekL, cheekR] { c.fillColor = NSColor(red: 1, green: 0.45, blue: 0.6, alpha: 0.55).cgColor }
        for e in [eyeL, eyeR] { e.fillColor = Self.ink.cgColor; e.anchorPoint = CGPoint(x: 0.5, y: 0.5) }
        for g in [glintL, glintR] { g.fillColor = NSColor.white.cgColor }
        mouth.fillColor = nil; mouth.strokeColor = Self.ink.cgColor; mouth.lineWidth = 1.6; mouth.lineCap = .round
        zzz.string = "z"; zzz.fontSize = 9; zzz.foregroundColor = NSColor.white.withAlphaComponent(0.8).cgColor
        zzz.alignmentMode = .center; zzz.contentsScale = 2; zzz.isHidden = true
        for l in [body, shine, cheekL, cheekR, eyeL, eyeR, glintL, glintR, mouth, zzz] as [CALayer] { layer?.addSublayer(l) }
        scheduleBlink()
        startMotion()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 34, height: 28) }

    // MARK: Drawing

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        // idle breathing + mood-specific motion
        let breathe = 1 + 0.025 * sin(phase * 1.6)
        var dx: CGFloat = 0, dy: CGFloat = 0, squash: CGFloat = 1
        switch mood {
        case .groove: dx = sin(phase * 3.7) * 2.2; squash = 1 + 0.06 * sin(phase * 7.4)
        case .happy:  dy = -abs(sin(phase * 9)) * 2.5; squash = 1 + 0.08 * sin(phase * 9)
        case .alert:  dx = sin(phase * 18) * 0.8
        default: break
        }
        let bw: CGFloat = 26 * breathe * squash, bh: CGFloat = 22 * breathe / squash
        let bx = w / 2 - bw / 2 + dx, by = h / 2 - bh / 2 + dy + 1
        let bodyRect = CGRect(x: bx, y: by, width: bw, height: bh)

        CATransaction.begin(); CATransaction.setDisableActions(true)
        body.path = CGPath(roundedRect: bodyRect, cornerWidth: bw * 0.46, cornerHeight: bh * 0.5, transform: nil)
        shine.path = CGPath(ellipseIn: CGRect(x: bx + bw * 0.16, y: by + bh * 0.62, width: bw * 0.36, height: bh * 0.2), transform: nil)

        let g = gaze * 1.6
        let eyeY = by + bh * 0.52
        let eyeW: CGFloat = 4.2, eyeH: CGFloat = (mood == .alert ? 7.2 : 5.6) * eyeOpen
        let lx = bx + bw * 0.34 + g, rx = bx + bw * 0.66 + g
        for (e, x) in [(eyeL, lx), (eyeR, rx)] {
            if mood == .happy {
                // closed happy arcs
                let p = CGMutablePath()
                p.addArc(center: CGPoint(x: x, y: eyeY - 1.5), radius: 3, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                e.path = p; e.fillColor = nil; e.strokeColor = Self.ink.cgColor; e.lineWidth = 1.6; e.lineCap = .round
            } else if mood == .sleepy {
                let p = CGMutablePath(); p.move(to: CGPoint(x: x - 2.6, y: eyeY)); p.addLine(to: CGPoint(x: x + 2.6, y: eyeY))
                e.path = p; e.fillColor = nil; e.strokeColor = Self.ink.cgColor; e.lineWidth = 1.6; e.lineCap = .round
            } else {
                e.path = CGPath(ellipseIn: CGRect(x: x - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: max(0.6, eyeH)), transform: nil)
                e.fillColor = Self.ink.cgColor; e.strokeColor = nil
            }
        }
        let showGlint = mood != .happy && mood != .sleepy && eyeOpen > 0.5
        glintL.isHidden = !showGlint; glintR.isHidden = !showGlint
        glintL.path = CGPath(ellipseIn: CGRect(x: lx + 0.4, y: eyeY + 1.2, width: 1.6, height: 1.6), transform: nil)
        glintR.path = CGPath(ellipseIn: CGRect(x: rx + 0.4, y: eyeY + 1.2, width: 1.6, height: 1.6), transform: nil)

        cheekL.path = CGPath(ellipseIn: CGRect(x: bx + bw * 0.14, y: by + bh * 0.3, width: 4.5, height: 2.6), transform: nil)
        cheekR.path = CGPath(ellipseIn: CGRect(x: bx + bw * 0.86 - 4.5, y: by + bh * 0.3, width: 4.5, height: 2.6), transform: nil)

        let m = CGMutablePath(); let mx = bx + bw / 2 + g * 0.5, my = by + bh * 0.3
        switch mood {
        case .happy, .groove:
            m.addArc(center: CGPoint(x: mx, y: my + 1.5), radius: 3.4, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        case .alert:
            m.addEllipse(in: CGRect(x: mx - 1.8, y: my - 2.2, width: 3.6, height: 3.6))
        case .sleepy:
            m.move(to: CGPoint(x: mx - 1.5, y: my)); m.addLine(to: CGPoint(x: mx + 1.5, y: my))
        case .normal:
            m.addArc(center: CGPoint(x: mx, y: my + 1.2), radius: 2.4, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
        }
        mouth.path = m
        zzz.isHidden = mood != .sleepy
        zzz.frame = CGRect(x: bx + bw - 4, y: by + bh - 2 + sin(phase * 1.6) * 1.5, width: 10, height: 12)
        zzz.opacity = Float(0.5 + 0.5 * sin(phase * 1.6))
        CATransaction.commit()
    }

    private func applyMood() {
        happyTimer?.invalidate()
        CATransaction.begin(); CATransaction.setAnimationDuration(0.25)
        body.fillColor = (mood == .alert ? Self.alertColor : Self.bodyColor).cgColor
        CATransaction.commit()
        if mood == .happy {
            happyTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in if self?.mood == .happy { self?.mood = .normal } }
        }
        needsLayout = true
    }

    // MARK: Motion & blink

    private func startMotion() {
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self, !self.isHidden, self.window != nil else { return }
            self.phase += 1 / 30
            self.needsLayout = true
        }
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2.5...6), repeats: false) { [weak self] _ in
            self?.blink(); self?.scheduleBlink()
        }
    }

    private func blink() {
        guard mood == .normal || mood == .groove || mood == .alert, window != nil, !isHidden else { return }
        let steps: [CGFloat] = [0.6, 0.15, 0.6, 1]
        for (i, v) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) { [weak self] in self?.eyeOpen = v; self?.needsLayout = true }
        }
    }

    deinit { blinkTimer?.invalidate(); motionTimer?.invalidate(); happyTimer?.invalidate() }
}
