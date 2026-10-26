// Draws the Burndown app icon (a trash can on fire) and builds Resources/AppIcon.icns.
// Run from the repo root: swift Scripts/make-icon.swift [preview-dir]
// With a preview dir, the iconset PNGs are also copied there for a look.
import AppKit

// All drawing is in a 1024 x 1024 space, y up. Plate follows the macOS icon grid (824 pt, 100 pt margin).
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

/// Rounded rect whose corners are superellipse quarters, so curvature eases into the straight edges.
func squircle(_ r: CGRect, radius: CGFloat, n: CGFloat = 4) -> CGPath {
    let p = CGMutablePath()
    let corners: [(CGFloat, CGFloat, CGFloat)] = [  // centre x, centre y, start angle
        (r.maxX - radius, r.maxY - radius, 0), (r.minX + radius, r.maxY - radius, .pi / 2),
        (r.minX + radius, r.minY + radius, .pi), (r.maxX - radius, r.minY + radius, 3 * .pi / 2),
    ]
    for (cx, cy, a0) in corners {
        for i in 0...24 {
            let t = a0 + CGFloat(i) / 24 * .pi / 2
            let c = cos(t), s = sin(t)
            let pt = CGPoint(x: cx + radius * copysign(pow(abs(c), 2 / n), c),
                             y: cy + radius * copysign(pow(abs(s), 2 / n), s))
            if p.isEmpty { p.move(to: pt) } else { p.addLine(to: pt) }
        }
    }
    p.closeSubpath()
    return p
}

/// A flame through a list of points: base left, alternating tips and notches, base right. Rising edges swell
/// out and flick into the tip; falling edges drop into the notch, so the tongues read as licks, not spikes.
func flame(_ pts: [CGPoint], lean: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: pts[0])
    for (a, b) in zip(pts, pts.dropFirst()) {
        let dx = b.x - a.x, dy = b.y - a.y
        if dy > 0 {
            p.addCurve(to: b, control1: CGPoint(x: a.x + dx * 0.1 - copysign(24, dx), y: a.y + dy * 0.55),
                       control2: CGPoint(x: a.x + dx * 0.55 + lean, y: a.y + dy * 0.9))
        } else {
            p.addCurve(to: b, control1: CGPoint(x: a.x + dx * 0.2 + lean, y: a.y + dy * 0.3),
                       control2: CGPoint(x: a.x + dx * 0.9, y: a.y + dy * 0.75))
        }
    }
    p.closeSubpath()
    return p
}

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// Fills `path` with a vertical gradient running from y `from` (first stop) to y `to` (last stop).
func fill(_ ctx: CGContext, _ path: CGPath, _ stops: [(CGFloat, CGColor)], from: CGFloat, to: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient(stops), start: pt(512, from), end: pt(512, to), options: [])
    ctx.restoreGState()
}

/// At 32 px and below a simplified variant: bigger flame and rim, fewer (or no) slats, no fine detail.
func draw(_ ctx: CGContext, px: Int) {
    let small = px <= 32
    let platePath = squircle(plate, radius: 300)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.3))
    ctx.addPath(platePath); ctx.setFillColor(rgb(0xF2DCC2)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath); ctx.clip()
    // Warm off-white plate, a touch deeper at the bottom, lit by the fire.
    fill(ctx, platePath, [(0, rgb(0xF0D6BA)), (1, rgb(0xFFF9F0))], from: 100, to: 924)
    ctx.drawRadialGradient(gradient([(0, rgb(0xFF9A3C, 0.5)), (0.55, rgb(0xFFB25C, 0.16)), (1, rgb(0xFFB25C, 0))]),
                           startCenter: pt(512, 690), startRadius: 0, endCenter: pt(512, 690), endRadius: 430,
                           options: [])
    // Contact shadow under the can.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 178); ctx.scaleBy(x: 1, y: 0.14)
    ctx.drawRadialGradient(gradient([(0, rgb(0x4A2A10, 0.4)), (1, rgb(0x4A2A10, 0))]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 250, options: [])
    ctx.restoreGState()

    // Flame: outer red-orange, middle orange, pale yellow core. Its base hides behind the rim.
    let outer = small
        ? [pt(300, 560), pt(326, 760), pt(398, 706), pt(500, 918), pt(608, 724), pt(690, 812), pt(724, 560)]
        : [pt(310, 560), pt(336, 760), pt(404, 702), pt(498, 906), pt(596, 728), pt(678, 822), pt(714, 560)]
    let middle = small
        ? [pt(360, 560), pt(390, 700), pt(446, 668), pt(508, 832), pt(588, 680), pt(640, 736), pt(668, 560)]
        : [pt(366, 560), pt(394, 694), pt(450, 664), pt(508, 822), pt(582, 676), pt(632, 730), pt(660, 560)]
    let core = small
        ? [pt(410, 560), pt(512, 750), pt(614, 560)]
        : [pt(414, 560), pt(444, 640), pt(478, 624), pt(514, 742), pt(566, 620), pt(612, 560)]
    let outerPath = flame(outer, lean: -8)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 44, color: rgb(0xFF6A00, 0.55))
    ctx.addPath(outerPath); ctx.setFillColor(rgb(0xFF5A1F)); ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, outerPath, [(0, rgb(0xFF9A1F)), (0.55, rgb(0xFF5A1E)), (1, rgb(0xE42F1A))], from: 580, to: 910)
    fill(ctx, flame(middle, lean: -6), [(0, rgb(0xFFD04A)), (0.6, rgb(0xFFA21C)), (1, rgb(0xFF8412))],
         from: 580, to: 830)
    fill(ctx, flame(core, lean: -3), [(0, rgb(0xFFFDEB)), (0.5, rgb(0xFFF1B0)), (1, rgb(0xFFDD6A))],
         from: 580, to: 750)

    // Can body: tapered, with a horizontal graphite gradient for a rounded, metallic look.
    let body = CGMutablePath()
    body.move(to: pt(300, 590))
    body.addLine(to: pt(724, 590))
    body.addLine(to: pt(686, 214))
    body.addQuadCurve(to: pt(648, 176), control: pt(683, 176))
    body.addLine(to: pt(376, 176))
    body.addQuadCurve(to: pt(338, 214), control: pt(341, 176))
    body.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0x000000, 0.28))
    ctx.addPath(body); ctx.setFillColor(rgb(0x3A3E46)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0x2A2D33)), (0.26, rgb(0x5A5F69)), (0.4, rgb(0x6E737D)),
                                     (0.72, rgb(0x41454D)), (1, rgb(0x25282D))]),
                           start: pt(300, 400), end: pt(724, 400), options: [])
    // Firelight on the upper body, screened so it warms the metal rather than muddying it.
    ctx.setBlendMode(.screen)
    ctx.drawLinearGradient(gradient([(0, rgb(0xB0501C, 0.35)), (1, rgb(0xB0501C, 0))]),
                           start: pt(512, 590), end: pt(512, 530), options: [])
    ctx.setBlendMode(.normal)

    // Slats: rounded grooves that follow the taper, dark with a faint lit edge.
    ctx.setLineCap(.round)
    for f in px <= 16 ? [] : small ? [0.3, 0.7] as [CGFloat] : [0.25, 0.5, 0.75] {
        let top = pt(300 + 424 * f, 520), bot = pt(338 + 348 * f, 250)
        let groove = CGMutablePath()
        groove.move(to: top); groove.addLine(to: bot)
        ctx.setLineWidth(small ? 44 : 26)
        if !small {
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.13))
            ctx.saveGState(); ctx.translateBy(x: 3, y: -3); ctx.addPath(groove); ctx.strokePath(); ctx.restoreGState()
        }
        ctx.setStrokeColor(rgb(0x1C1E23, 0.92))
        ctx.addPath(groove); ctx.strokePath()
    }
    ctx.restoreGState()

    // Rim: a lip slightly wider than the body, catching the firelight on top.
    let rimRect = small ? CGRect(x: 272, y: 556, width: 480, height: 70)
                        : CGRect(x: 278, y: 562, width: 468, height: 58)
    let rim = CGPath(roundedRect: rimRect, cornerWidth: rimRect.height / 2, cornerHeight: rimRect.height / 2,
                     transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: rgb(0x000000, 0.35))
    ctx.addPath(rim); ctx.setFillColor(rgb(0x4A4E57)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rim); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0x34373E)), (0.3, rgb(0x7A7F8A)), (0.44, rgb(0x8C919B)),
                                     (0.78, rgb(0x4A4E56)), (1, rgb(0x2C2F35))]),
                           start: pt(rimRect.minX, 0), end: pt(rimRect.maxX, 0), options: [])
    ctx.setBlendMode(.screen)
    ctx.drawLinearGradient(gradient([(0, rgb(0xFF9A40, 0.7)), (0.5, rgb(0xFF9A40, 0))]),
                           start: pt(512, rimRect.maxY), end: pt(512, rimRect.minY), options: [])
    ctx.setBlendMode(.normal)
    ctx.restoreGState()
    if !small {  // Specular line along the top of the lip.
        ctx.move(to: pt(rimRect.minX + 30, rimRect.maxY - 3))
        ctx.addLine(to: pt(rimRect.maxX - 30, rimRect.maxY - 3))
        ctx.setLineWidth(4); ctx.setStrokeColor(rgb(0xFFE2C0, 0.55)); ctx.strokePath()
    }

    // A faint light edge around the plate.
    ctx.addPath(platePath); ctx.setLineWidth(8); ctx.setStrokeColor(rgb(0xFFFFFF, 0.5)); ctx.strokePath()
    ctx.restoreGState()
}

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.interpolationQuality = .high
    cg.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(cg, px: px)
    ctx.flushGraphics()
    NSGraphicsContext.current = nil
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let preview = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(px: px).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
        if let preview { try! data.write(to: preview.appendingPathComponent(name)) }
    }
}
if let preview {
    try! render(px: 1024).representation(using: .png, properties: [:])!
        .write(to: preview.appendingPathComponent("master-1024.png"))
}

let out = "Resources/AppIcon.icns"
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try! task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try? fm.removeItem(at: iconset)
print("Wrote \(out)")
