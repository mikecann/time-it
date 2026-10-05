import AppKit
let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.16, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedRed: 0.91, green: 0.68, blue: 0.34, alpha: 1).setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 205, y: 185, width: 614, height: 614)); ring.lineWidth = 58; ring.stroke()
let top = NSBezierPath(); top.move(to: NSPoint(x: 512, y: 813)); top.line(to: NSPoint(x: 512, y: 880)); top.lineWidth = 50; top.lineCapStyle = .round; top.stroke()
let bar = NSBezierPath(); bar.move(to: NSPoint(x: 448, y: 880)); bar.line(to: NSPoint(x: 576, y: 880)); bar.lineWidth = 45; bar.lineCapStyle = .round; bar.stroke()
let hands = NSBezierPath(); hands.move(to: NSPoint(x: 512, y: 696)); hands.line(to: NSPoint(x: 512, y: 492)); hands.line(to: NSPoint(x: 646, y: 408)); hands.lineWidth = 54; hands.lineCapStyle = .round; hands.lineJoinStyle = .round; hands.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
