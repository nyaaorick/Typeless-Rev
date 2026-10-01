// Renders the input-method menu icon: a monochrome rounded square with a "T".
// Usage: swift scripts/make-icon.swift Resources/InputIcon.pdf
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "InputIcon.pdf"
var box = CGRect(x: 0, y: 0, width: 32, height: 32)

guard let context = CGContext(URL(fileURLWithPath: output) as CFURL, mediaBox: &box, nil) else {
    fatalError("cannot create PDF context at \(output)")
}
context.beginPDFPage(nil)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

NSColor.black.setStroke()
let frame = NSBezierPath(roundedRect: box.insetBy(dx: 3, dy: 3), xRadius: 7, yRadius: 7)
frame.lineWidth = 2
frame.stroke()

let glyph = NSAttributedString(
    string: "T",
    attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: NSColor.black])
let size = glyph.size()
glyph.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))

context.endPDFPage()
context.closePDF()
