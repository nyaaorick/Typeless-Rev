import AppKit

/// The small floating pill near the caret while dictating, in two layers of clear Liquid Glass
/// like Control Center: an outer capsule, and inside it a smaller glass capsule holding a red dot
/// and a live level meter while listening, or a spinner while the model polishes. It never takes
/// focus, ignores the mouse, and is hidden whenever the voice path is idle.
final class VoiceHUD {
    static let shared = VoiceHUD()

    private let window: FloatingPanel
    private let content = HUDContentView()

    private init() {
        window = FloatingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = .clear
        // The glass draws its own edge and depth; a window shadow on top of it reads as a halo.
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = GlassStyle.makeGlass(cornerRadius: HUDContentView.height / 2, content: content)
        window.appearance = GlassStyle.appearance
    }

    /// Shows the HUD in `phase` below (or above, near a screen edge) the caret rectangle `anchor`.
    func show(_ phase: VoicePhase, anchor: NSRect) {
        guard phase != .idle else { return hide() }
        content.phase = phase
        let size = content.fittingSize
        window.setContentSize(size)
        content.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(PanelPlacement.origin(for: size, anchor: anchor))
        window.orderFrontRegardless()
    }

    var isVisible: Bool { window.isVisible }
    var frame: NSRect { window.frame }
    /// Clear glass outside, and a second glass layer inside it.
    var usesGlass: Bool {
        guard let outer = window.contentView as? NSGlassEffectView else { return false }
        return outer.style == .clear && content.hasInnerGlass
    }

    /// Meter position, 0...1.
    func setLevel(_ level: Float) {
        content.level = level
    }

    func hide() {
        window.orderOut(nil)
        content.level = 0
    }
}

/// The label on the outer glass, and the indicator in its own inner glass capsule.
private final class HUDContentView: NSView {
    static let height: CGFloat = 36
    /// The gap between the outer and inner capsules, the same all round so the curves nest.
    private static let inset: CGFloat = 4

    private let label = NSTextField(labelWithString: "")
    private let platter = NSGlassEffectView()
    private let indicator = IndicatorView()

    var hasInnerGlass: Bool { platter.superview === self }

    var phase = VoicePhase.idle {
        didSet {
            label.stringValue = phase == .polishing ? "Polishing" : "Listening"
            indicator.phase = phase
            // A red cast on the inner capsule while the microphone is live; plain glass while polishing.
            platter.tintColor = phase == .listening ? NSColor.systemRed.withAlphaComponent(0.35) : nil
            needsLayout = true
        }
    }

    var level: Float = 0 {
        didSet { indicator.level = level }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        platter.style = .clear
        platter.cornerRadius = (Self.height - Self.inset * 2) / 2
        platter.contentView = indicator
        addSubview(platter)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var platterWidth: CGFloat { indicator.width + 2 * 10 }

    override var fittingSize: NSSize {
        let text = ceil(label.intrinsicContentSize.width)
        return NSSize(width: Self.inset + platterWidth + 10 + text + 16, height: Self.height)
    }

    override func layout() {
        super.layout()
        let inset = Self.inset
        platter.frame = NSRect(x: inset, y: inset, width: platterWidth, height: bounds.height - inset * 2)
        indicator.frame = platter.bounds
        let size = label.intrinsicContentSize
        label.frame = NSRect(
            x: platter.frame.maxX + 10, y: (bounds.height - size.height) / 2, width: ceil(size.width),
            height: size.height)
    }
}

/// What sits in the inner capsule: a red dot and the meter, or a spinner.
private final class IndicatorView: NSView {
    private let spinner = NSProgressIndicator()
    private let meter = LevelMeterView()

    var phase = VoicePhase.idle {
        didSet {
            meter.isHidden = phase != .listening
            spinner.isHidden = phase != .polishing
            if phase == .polishing { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
            needsLayout = true
            needsDisplay = true
        }
    }

    var level: Float = 0 {
        didSet { meter.level = level }
    }

    /// The content width; the capsule adds its own padding.
    var width: CGFloat { phase == .listening ? 8 + 6 + 28 : 16 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true
        meter.isHidden = true
        addSubview(spinner)
        addSubview(meter)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var originX: CGFloat { (bounds.width - width) / 2 }

    override func layout() {
        super.layout()
        if phase == .listening {
            meter.frame = NSRect(x: originX + 8 + 6, y: (bounds.height - 16) / 2, width: 28, height: 16)
        } else {
            spinner.frame = NSRect(x: originX, y: (bounds.height - 16) / 2, width: 16, height: 16)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard phase == .listening else { return }
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: originX, y: (bounds.height - 8) / 2, width: 8, height: 8)).fill()
    }
}

/// Five bars that follow the microphone level, with a quick rise and a slower fall.
private final class LevelMeterView: NSView {
    private static let weights: [CGFloat] = [0.55, 0.8, 1, 0.8, 0.55]
    private var shown: CGFloat = 0

    var level: Float = 0 {
        didSet {
            let target = CGFloat(level)
            shown = target > shown ? target : shown * 0.75 + target * 0.25
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth: CGFloat = 3
        let gap = (bounds.width - barWidth * CGFloat(Self.weights.count)) / CGFloat(Self.weights.count - 1)
        NSColor.labelColor.setFill()
        for (i, weight) in Self.weights.enumerated() {
            let height = 3 + (bounds.height - 3) * min(1, shown * weight * 1.2)
            let rect = NSRect(
                x: CGFloat(i) * (barWidth + gap), y: (bounds.height - height) / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
