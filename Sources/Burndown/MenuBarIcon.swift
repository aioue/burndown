import AppKit

/// A trash can with a flame, drawn as a template image so it adapts to light/dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            // Lid
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: 10, width: 13, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()

            // Body with three slots cut out (even-odd)
            let body = NSBezierPath()
            body.windingRule = .evenOdd
            body.move(to: NSPoint(x: 4, y: 0.8))
            body.line(to: NSPoint(x: 14, y: 0.8))
            body.line(to: NSPoint(x: 15, y: 9.4))
            body.line(to: NSPoint(x: 3, y: 9.4))
            body.close()
            for x in [6.4, 8.6, 10.8] {
                body.appendRect(NSRect(x: x, y: 2.6, width: 0.8, height: 5.2))
            }
            body.fill()

            // Flame above the lid
            let flame = NSBezierPath()
            flame.move(to: NSPoint(x: 9, y: 17.8))
            flame.curve(to: NSPoint(x: 12.6, y: 13.6),
                        controlPoint1: NSPoint(x: 9.6, y: 15.6), controlPoint2: NSPoint(x: 12.6, y: 15.4))
            flame.curve(to: NSPoint(x: 9, y: 11.8),
                        controlPoint1: NSPoint(x: 12.6, y: 12.6), controlPoint2: NSPoint(x: 11, y: 11.8))
            flame.curve(to: NSPoint(x: 5.4, y: 13.6),
                        controlPoint1: NSPoint(x: 7, y: 11.8), controlPoint2: NSPoint(x: 5.4, y: 12.6))
            flame.curve(to: NSPoint(x: 7.4, y: 15.4),
                        controlPoint1: NSPoint(x: 5.4, y: 14.6), controlPoint2: NSPoint(x: 6.4, y: 15.2))
            flame.curve(to: NSPoint(x: 9, y: 17.8),
                        controlPoint1: NSPoint(x: 7.4, y: 16.6), controlPoint2: NSPoint(x: 8.4, y: 17.2))
            flame.close()
            flame.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
