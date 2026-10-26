import AppKit

/// Menu bar icons drawn as template images so they adapt to light and dark menu bars.
/// Normal: a trash can with a flame. Paused: the fire is out and paper piles up on and around the bin.
enum MenuBarIcon {
    static let normal = make(draw: drawBurning)
    static let paused = make(draw: drawPaused)

    private static func make(draw: @escaping () -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            draw()
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func lid(y: CGFloat) {
        NSBezierPath(roundedRect: NSRect(x: 2.5, y: y, width: 13, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
    }

    /// Tapered body with three slots cut out (even-odd). `top` is the y of its upper edge.
    private static func body(top: CGFloat) {
        let body = NSBezierPath()
        body.windingRule = .evenOdd
        body.move(to: NSPoint(x: 4, y: 0.8))
        body.line(to: NSPoint(x: 14, y: 0.8))
        body.line(to: NSPoint(x: 15, y: top))
        body.line(to: NSPoint(x: 3, y: top))
        body.close()
        for x in [6.4, 8.6, 10.8] {
            body.appendRect(NSRect(x: x, y: 2.6, width: 0.8, height: top - 4.2))
        }
        body.fill()
    }

    private static func drawBurning() {
        lid(y: 10)
        body(top: 9.4)

        // A flame with a leaning tip, a second tongue on the right and a hollow core (even-odd).
        let flame = NSBezierPath()
        flame.windingRule = .evenOdd
        flame.move(to: NSPoint(x: 9, y: 11.7))
        flame.curve(to: NSPoint(x: 5.5, y: 14.0),
                    controlPoint1: NSPoint(x: 7, y: 11.7), controlPoint2: NSPoint(x: 5.5, y: 12.7))
        flame.curve(to: NSPoint(x: 7.4, y: 16.4),
                    controlPoint1: NSPoint(x: 5.5, y: 15.1), controlPoint2: NSPoint(x: 6.6, y: 15.7))
        flame.curve(to: NSPoint(x: 8.4, y: 17.9),
                    controlPoint1: NSPoint(x: 7.3, y: 17.1), controlPoint2: NSPoint(x: 7.8, y: 17.6))
        flame.curve(to: NSPoint(x: 10.4, y: 15.6),
                    controlPoint1: NSPoint(x: 9.9, y: 17.0), controlPoint2: NSPoint(x: 10.3, y: 16.3))
        flame.curve(to: NSPoint(x: 11.8, y: 16.7),
                    controlPoint1: NSPoint(x: 10.9, y: 15.7), controlPoint2: NSPoint(x: 11.4, y: 16.1))
        flame.curve(to: NSPoint(x: 12.5, y: 14.0),
                    controlPoint1: NSPoint(x: 12.4, y: 15.8), controlPoint2: NSPoint(x: 12.5, y: 14.9))
        flame.curve(to: NSPoint(x: 9, y: 11.7),
                    controlPoint1: NSPoint(x: 12.5, y: 12.7), controlPoint2: NSPoint(x: 11, y: 11.7))
        flame.close()
        flame.move(to: NSPoint(x: 9, y: 14.7))
        flame.curve(to: NSPoint(x: 10.2, y: 13.1),
                    controlPoint1: NSPoint(x: 9.6, y: 14.1), controlPoint2: NSPoint(x: 10.2, y: 13.7))
        flame.curve(to: NSPoint(x: 9, y: 12.3),
                    controlPoint1: NSPoint(x: 10.2, y: 12.6), controlPoint2: NSPoint(x: 9.7, y: 12.3))
        flame.curve(to: NSPoint(x: 7.8, y: 13.1),
                    controlPoint1: NSPoint(x: 8.3, y: 12.3), controlPoint2: NSPoint(x: 7.8, y: 12.6))
        flame.curve(to: NSPoint(x: 9, y: 14.7),
                    controlPoint1: NSPoint(x: 7.8, y: 13.7), controlPoint2: NSPoint(x: 8.4, y: 14.1))
        flame.close()
        flame.fill()
    }

    /// A sheet of paper with a clear halo so overlapping sheets stay readable as a single-colour template.
    private static func sheet(center: NSPoint, size: NSSize, degrees: CGFloat) {
        let path = NSBezierPath(roundedRect: NSRect(x: -size.width / 2, y: -size.height / 2,
                                                    width: size.width, height: size.height),
                                xRadius: 0.4, yRadius: 0.4)
        var t = AffineTransform(translationByX: center.x, byY: center.y)
        t.rotate(byDegrees: degrees)
        path.transform(using: t)
        NSGraphicsContext.current?.compositingOperation = .clear
        path.lineWidth = 1.3
        path.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        path.fill()
    }

    private static func drawPaused() {
        // Sheets on the ground either side of the bin, the pile standing in it, then lid and body in front.
        sheet(center: NSPoint(x: 1.9, y: 1.9), size: NSSize(width: 3.8, height: 2.5), degrees: 22)
        sheet(center: NSPoint(x: 16.2, y: 1.7), size: NSSize(width: 3.6, height: 2.4), degrees: -28)
        sheet(center: NSPoint(x: 6.6, y: 12.2), size: NSSize(width: 6.0, height: 7.2), degrees: 14)
        sheet(center: NSPoint(x: 11.4, y: 12.4), size: NSSize(width: 6.0, height: 7.2), degrees: -12)
        sheet(center: NSPoint(x: 9.0, y: 14.4), size: NSSize(width: 5.8, height: 6.8), degrees: 3)
        haloed { lid(y: 8.2) }
        body(top: 7.8)
    }

    /// Cuts a thin clear gap around whatever `draw` fills, so it separates from shapes already drawn.
    private static func haloed(_ draw: () -> Void) {
        let r = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 8.2, width: 13, height: 1.6), xRadius: 0.8, yRadius: 0.8)
        NSGraphicsContext.current?.compositingOperation = .clear
        r.lineWidth = 1.3
        r.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        draw()
    }
}
