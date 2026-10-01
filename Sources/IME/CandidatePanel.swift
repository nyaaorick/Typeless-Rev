import AppKit

struct CandidateRow {
    let label: String
    let text: String
    let comment: String
}

/// The floating candidate list. One panel is shared by every input controller;
/// it never takes focus from the host app.
final class CandidatePanel {
    static let shared = CandidatePanel()

    private let window: FloatingPanel
    private let listView = CandidateListView()
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
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        window.contentView = background
        background.addSubview(listView)
    }

    /// Shows candidates below (or above, near a screen edge) `anchor`, the caret
    /// rectangle in screen coordinates. `onPick` receives the clicked row index.
    func present(rows: [CandidateRow], highlighted: Int, anchor: NSRect, onPick: @escaping (Int) -> Void) {
        hideTimer?.invalidate()
        listView.onPick = onPick
        listView.configure(rows: rows, highlighted: highlighted)
        show(anchor: anchor)
    }

    /// A short, non-interactive status message such as "Deploying…".
    func presentTip(_ text: String, anchor: NSRect, duration: TimeInterval = 1.2) {
        hideTimer?.invalidate()
        listView.onPick = nil
        listView.configure(rows: [CandidateRow(label: "", text: text, comment: "")], highlighted: nil)
        show(anchor: anchor)
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        hideTimer?.invalidate()
        window.orderOut(nil)
    }

    private func show(anchor: NSRect) {
        let size = listView.contentSize
        listView.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        window.setFrameOrigin(origin(for: size, anchor: anchor))
        window.orderFrontRegardless()
    }

    private func origin(for size: NSSize, anchor: NSRect) -> NSPoint {
        PanelPlacement.origin(for: size, anchor: anchor)
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

/// Draws the candidates in a single row and maps clicks back to a row index.
private final class CandidateListView: NSView {
    var onPick: ((Int) -> Void)?
    private(set) var contentSize = NSSize.zero

    private var rows: [CandidateRow] = []
    private var highlighted: Int?
    private var frames: [NSRect] = []

    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let textFont = NSFont.systemFont(ofSize: 17)
    private let commentFont = NSFont.systemFont(ofSize: 12)

    private let outerPadding = NSSize(width: 8, height: 5)
    private let itemPadding: CGFloat = 8
    private let gap: CGFloat = 4
    private let itemSpacing: CGFloat = 2

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        for (i, row) in rows.enumerated() {
            let frame = frames[i]
            let isHighlighted = i == highlighted
            if isHighlighted {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).fill()
            }
            let primary: NSColor = isHighlighted ? .alternateSelectedControlTextColor : .labelColor
            let secondary: NSColor = isHighlighted ? .alternateSelectedControlTextColor : .secondaryLabelColor

            var x = frame.minX + itemPadding
            func draw(_ string: String, font: NSFont, color: NSColor) {
                guard !string.isEmpty else { return }
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = (string as NSString).size(withAttributes: attributes)
                (string as NSString).draw(
                    at: NSPoint(x: x, y: frame.midY - size.height / 2), withAttributes: attributes)
                x += ceil(size.width) + gap
            }
            draw(row.label, font: labelFont, color: secondary)
            draw(row.text, font: textFont, color: primary)
            draw(row.comment, font: commentFont, color: secondary)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = frames.firstIndex(where: { $0.contains(point) }) {
            onPick?(index)
        }
    }
}
