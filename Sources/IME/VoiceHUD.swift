import AppKit

/// The small floating pill near the caret while dictating: a red dot and a live level meter
/// while listening, a spinner while the model polishes. It never takes focus, ignores the
/// mouse, and is hidden whenever the voice path is idle.
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
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = content
    }

    /// Shows the HUD in `phase` below (or above, near a screen edge) the caret rectangle `anchor`.
    func show(_ phase: VoicePhase, anchor: NSRect) {
        guard phase != .idle else { return hide() }
        content.phase = phase
        let size = content.fittingSize
        window.setContentSize(size)
        window.setFrameOrigin(PanelPlacement.origin(for: size, anchor: anchor))
        window.orderFrontRegardless()
    }

    var isVisible: Bool { window.isVisible }
    var frame: NSRect { window.frame }

    /// Meter position, 0...1.
    func setLevel(_ level: Float) {
        content.level = level
    }

    func hide() {
        window.orderOut(nil)
        content.level = 0
    }
}

private final class HUDContentView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let meter = LevelMeterView()

    var phase = VoicePhase.idle {
        didSet {
            label.stringValue = phase == .polishing ? "Polishing" : "Listening"
            meter.isHidden = phase != .listening
            if phase == .polishing { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
            spinner.isHidden = phase != .polishing
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }

    var level: Float = 0 {
        didSet { meter.level = level }
    }

    private let height: CGFloat = 30
    private let padding: CGFloat = 12

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true
        meter.isHidden = true
        addSubview(label)
        addSubview(spinner)
        addSubview(meter)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var fittingSize: NSSize {
        let text = ceil(label.intrinsicContentSize.width)
        let leading: CGFloat = phase == .listening ? 8 + 6 + 28 : 16 + 6
        return NSSize(width: padding + leading + 6 + text + padding, height: height)
    }

    override func layout() {
        super.layout()
        var x = padding
        if phase == .listening {
            x += 14  // the dot is drawn here
            meter.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: 28, height: 16)
            x += 28 + 6
        } else {
            spinner.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: 16, height: 16)
            x += 16 + 6
        }
        let size = label.intrinsicContentSize
        label.frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: ceil(size.width), height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard phase == .listening else { return }
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: padding, y: (bounds.height - 8) / 2, width: 8, height: 8)).fill()
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
