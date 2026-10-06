import AppKit

struct CandidateRow {
    let label: String
    let text: String
    let comment: String
}

/// The floating candidate list in two layers of Liquid Glass: a dark, clear bar, and a blue glass
/// capsule for the highlighted candidate. One panel is shared by every input controller; it never
/// takes focus from the host app.
final class CandidatePanel {
    static let shared = CandidatePanel()

    private let window: FloatingPanel
    private let bar = CandidateBarView()
    private var listView: CandidateListView { bar.list }
    private var hideTimer: Timer?

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
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        window.contentView = GlassStyle.makeGlass(cornerRadius: CandidateListView.cornerRadius, content: bar)
        window.appearance = GlassStyle.appearance
    }

    /// Shows candidates below (or above, near a screen edge) `anchor`, the caret
    /// rectangle in screen coordinates. `onPick` receives the clicked row index.
    func present(rows: [CandidateRow], highlighted: Int, anchor: NSRect, onPick: @escaping (Int) -> Void) {
        hideTimer?.invalidate()
        listView.onPick = onPick
        bar.configure(rows: rows, highlighted: highlighted)
        show(anchor: anchor)
    }

    /// A short, non-interactive status message such as "Deploying…".
    func presentTip(_ text: String, anchor: NSRect, duration: TimeInterval = 1.2) {
        hideTimer?.invalidate()
        listView.onPick = nil
        bar.configure(rows: [CandidateRow(label: "", text: text, comment: "")], highlighted: nil)
        show(anchor: anchor)
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    var isVisible: Bool { window.isVisible }
    /// The highlighted candidate is drawn inside its own glass, never under it.
    var highlightIsGlassHoldingText: Bool { bar.highlightIsGlassHoldingText }

    func hide() {
        hideTimer?.invalidate()
        window.orderOut(nil)
    }

    private func show(anchor: NSRect) {
        let size = listView.contentSize
        bar.frame = NSRect(origin: .zero, size: size)
        bar.layoutHighlight()
        window.setContentSize(size)
        window.setFrameOrigin(origin(for: size, anchor: anchor))
        window.orderFrontRegardless()
    }

    private func origin(for size: NSSize, anchor: NSRect) -> NSPoint {
        PanelPlacement.origin(for: size, anchor: anchor)
    }
}

/// The look shared by the floating panels: clear Liquid Glass darkened a little so the desktop
/// shows through but text stays readable, in the dark appearance so text and controls are light.
enum GlassStyle {
    static let appearance = NSAppearance(named: .darkAqua)
    static let tint = NSColor.black.withAlphaComponent(0.28)

    static func makeGlass(cornerRadius: CGFloat, content: NSView) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.tintColor = tint
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }
}

/// Where a floating panel goes relative to the caret.
enum PanelPlacement {
    /// Below `anchor` (the caret rectangle in screen coordinates), or above near a screen
    /// edge, and always on screen. Falls back to the pointer when the client gave no rectangle.
    static func origin(for size: NSSize, anchor: NSRect) -> NSPoint {
        var anchor = anchor
        if anchor == .zero {
            let mouse = NSEvent.mouseLocation
            anchor = NSRect(x: mouse.x, y: mouse.y - 20, width: 1, height: 20)
        }
        let probe = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)

        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 4)
        if origin.y < visible.minY { origin.y = anchor.maxY + 4 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        return origin
    }
}

/// A panel that never takes focus from the host app.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The bar's content: the list, and over the highlighted slot a blue glass capsule that holds that
/// candidate's text. The text lives inside the glass's contentView, the one view NSGlassEffectView
/// keeps in order; glass renders a beat late, and a glass layer laid over separately drawn text
/// ended up covering it as a solid blue block.
private final class CandidateBarView: NSView {
    let list = CandidateListView()
    private let highlight = NSGlassEffectView()
    private let highlightRow = HighlightRowView()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        highlight.style = .clear
        highlight.tintColor = NSColor.controlAccentColor.withAlphaComponent(0.7)
        highlight.cornerRadius = CandidateListView.highlightRadius
        highlight.contentView = highlightRow
        highlight.isHidden = true
        addSubview(list)
        addSubview(highlight)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(rows: [CandidateRow], highlighted: Int?) {
        list.configure(rows: rows, highlighted: highlighted)
    }

    func layoutHighlight() {
        list.frame = bounds
        guard let (row, frame) = list.highlightedRow else {
            highlight.isHidden = true
            return
        }
        highlight.frame = frame
        highlightRow.frame = NSRect(origin: .zero, size: frame.size)
        highlightRow.row = row
        highlight.isHidden = false
    }

    var highlightIsGlassHoldingText: Bool {
        !highlight.isHidden && highlight.contentView === highlightRow && highlightRow.row != nil
            && list.highlightedRow?.1 == highlight.frame
    }

    /// Clicks on the highlight still go to the list, which maps them to a row.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? list : nil
    }
}

/// The highlighted candidate's text, drawn inside the blue glass.
private final class HighlightRowView: NSView {
    var row: CandidateRow? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let row else { return }
        CandidateListView.draw(row, in: bounds, highlighted: true)
    }
}

/// Draws the candidates in a single row, leaving the highlighted one to the glass above it, and
/// maps clicks back to a row index.
private final class CandidateListView: NSView {
    var onPick: ((Int) -> Void)?
    private(set) var contentSize = NSSize.zero

    private var rows: [CandidateRow] = []
    private var highlighted: Int?
    private var frames: [NSRect] = []

    private static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let textFont = NSFont.systemFont(ofSize: 17)
    private static let commentFont = NSFont.systemFont(ofSize: 12)
    private var labelFont: NSFont { Self.labelFont }
    private var textFont: NSFont { Self.textFont }
    private var commentFont: NSFont { Self.commentFont }

    /// The bar's corners; the highlight inside uses the same curve less the inset, so they nest.
    static let cornerRadius: CGFloat = 14
    private static let inset: CGFloat = 5
    static var highlightRadius: CGFloat { cornerRadius - inset }
    private let outerPadding = NSSize(width: CandidateListView.inset, height: CandidateListView.inset)
    private static let itemPadding: CGFloat = 8
    private static let gap: CGFloat = 4
    private var itemPadding: CGFloat { Self.itemPadding }
    private var gap: CGFloat { Self.gap }
    private let itemSpacing: CGFloat = 2

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The highlighted candidate and its slot, for the glass capsule.
    var highlightedRow: (CandidateRow, NSRect)? {
        guard let highlighted, rows.indices.contains(highlighted) else { return nil }
        return (rows[highlighted], frames[highlighted])
    }

    func configure(rows: [CandidateRow], highlighted: Int?) {
        self.rows = rows
        self.highlighted = highlighted
        layoutRows()
        needsDisplay = true
    }

    private func width(of string: String, font: NSFont) -> CGFloat {
        string.isEmpty ? 0 : ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    private func layoutRows() {
        let rowHeight = ceil(textFont.boundingRectForFont.height) + 4
        var x = outerPadding.width
        frames = rows.map { row in
            let labelWidth = width(of: row.label, font: labelFont)
            let commentWidth = width(of: row.comment, font: commentFont)
            var w = itemPadding * 2 + width(of: row.text, font: textFont)
            if labelWidth > 0 { w += labelWidth + gap }
            if commentWidth > 0 { w += commentWidth + gap }
            defer { x += w + itemSpacing }
            return NSRect(x: x, y: outerPadding.height, width: w, height: rowHeight)
        }
        let right = (frames.last?.maxX ?? outerPadding.width) + outerPadding.width
        contentSize = NSSize(width: right, height: rowHeight + outerPadding.height * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, row) in rows.enumerated() where i != highlighted {
            Self.draw(row, in: frames[i], highlighted: false)
        }
    }

    /// One candidate's label, text and comment, laid out left to right in `frame`.
    static func draw(_ row: CandidateRow, in frame: NSRect, highlighted: Bool) {
        let primary: NSColor = highlighted ? .white : .labelColor
        let secondary: NSColor = highlighted ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        var x = frame.minX + itemPadding
        func draw(_ string: String, font: NSFont, color: NSColor) {
            guard !string.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (string as NSString).size(withAttributes: attributes)
            (string as NSString).draw(at: NSPoint(x: x, y: frame.midY - size.height / 2), withAttributes: attributes)
            x += ceil(size.width) + gap
        }
        draw(row.label, font: labelFont, color: secondary)
        draw(row.text, font: textFont, color: primary)
        draw(row.comment, font: commentFont, color: secondary)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = frames.firstIndex(where: { $0.contains(point) }) {
            onPick?(index)
        }
    }
}
