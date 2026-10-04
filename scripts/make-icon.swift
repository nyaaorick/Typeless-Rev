// Renders the input-method menu icon: a monochrome rounded square with a "T".
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

let glyph = NSAttributedString(
    string: "T",
    attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.black])
let size = glyph.size()
glyph.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))

context.endPDFPage()
context.closePDF()
