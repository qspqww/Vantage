import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift GenerateIcon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Unable to create graphics context\n", stderr)
    exit(1)
}

context.setFillColor(NSColor(red: 0.035, green: 0.047, blue: 0.049, alpha: 1).cgColor)
context.fill(CGRect(origin: .zero, size: size))

let backgroundRect = NSRect(x: 62, y: 62, width: 900, height: 900)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 205, yRadius: 205)
let backgroundGradient = NSGradient(colors: [
    NSColor(red: 0.10, green: 0.15, blue: 0.15, alpha: 1),
    NSColor(red: 0.035, green: 0.055, blue: 0.057, alpha: 1)
])!
backgroundGradient.draw(in: backgroundPath, angle: -90)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 38, color: NSColor.black.withAlphaComponent(0.48).cgColor)
let hexagon = NSBezierPath()
hexagon.move(to: NSPoint(x: 512, y: 812))
hexagon.line(to: NSPoint(x: 762, y: 666))
hexagon.line(to: NSPoint(x: 762, y: 374))
hexagon.line(to: NSPoint(x: 512, y: 228))
hexagon.line(to: NSPoint(x: 262, y: 374))
hexagon.line(to: NSPoint(x: 262, y: 666))
hexagon.close()
NSColor(red: 0.039, green: 0.518, blue: 1.0, alpha: 1).setFill()
hexagon.fill()
context.restoreGState()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 335, weight: .black),
    .foregroundColor: NSColor(red: 0.020, green: 0.031, blue: 0.055, alpha: 1),
    .paragraphStyle: paragraph
]
NSString(string: "V").draw(in: NSRect(x: 262, y: 326, width: 500, height: 395), withAttributes: attributes)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to encode icon\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)
