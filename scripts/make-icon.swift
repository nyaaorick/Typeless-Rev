// Renders the input-method menu icon: a monochrome rounded square holding three level bars and a
// text cursor, the app icon's motif at menu bar size.
// Usage: swift scripts/make-icon.swift Resources/InputIcon.pdf
//
// The page is 16 x 16 pt, the size macOS expects for an input source icon. A 32 pt page was
// drawn about half its height too low in the menu bar.
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "InputIcon.pdf"
var box = CGRect(x: 0, y: 0, width: 16, height: 16)

guard let context = CGContext(URL(fileURLWithPath: output) as CFURL, mediaBox: &box, nil) else {
    fatalError("cannot create PDF context at \(output)")
}
context.beginPDFPage(nil)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

NSColor.black.setStroke()
let frame = NSBezierPath(roundedRect: box.insetBy(dx: 1.5, dy: 1.5), xRadius: 3.5, yRadius: 3.5)
frame.lineWidth = 1
frame.stroke()

// Three bars, weighted like the HUD meter, then a thinner cursor, centred in the frame.
NSColor.black.setFill()
let bars: [(width: CGFloat, height: CGFloat)] = [(1.6, 4), (1.6, 7), (1.6, 4), (1, 6)]
let gap: CGFloat = 1.3
var x = box.midX - (bars.reduce(0) { $0 + $1.width } + gap * CGFloat(bars.count - 1) + 0.4) / 2
for (index, bar) in bars.enumerated() {
    if index == bars.count - 1 { x += 0.4 }  // a little more room before the cursor
    let rect = NSRect(x: x, y: box.midY - bar.height / 2, width: bar.width, height: bar.height)
    NSBezierPath(roundedRect: rect, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
    x += bar.width + gap
}

context.endPDFPage()
context.closePDF()
