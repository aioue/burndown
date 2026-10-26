import AppKit
import BurndownCore
import SwiftUI

/// Docs only: `Burndown --render-docs <dir>` draws the app's real views with made-up demo data into
/// PNGs for the README, then exits. It never starts the watchers, and it runs against a throwaway
/// home folder (CFFIXED_USER_HOME), so the real state.json and ~/Downloads are never read or written.
@MainActor
enum DocsRender {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-docs") else { return }
        guard i + 1 < args.count else { fail("usage: Burndown --render-docs <output dir>") }
        let out = URL(fileURLWithPath: args[i + 1], isDirectory: true).standardizedFileURL
        isolateHome()
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try render(into: out)
            removeTemporaryHome()
        } catch {
            fail("render failed: \(error.localizedDescription)")
        }
        exit(0)
    }

    // MARK: Isolation

    /// Re-executes with a fresh temporary home unless one is already in place, then double-checks that
    /// the store and Downloads resolve outside the real home before anything is touched.
    private static func isolateHome() {
        let env = ProcessInfo.processInfo.environment
        let realHome = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        if env["BURNDOWN_DOCS_HOME"] == nil {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("burndown-docs-\(getpid())").path
            try? FileManager.default.createDirectory(atPath: tmp + "/Downloads", withIntermediateDirectories: true)
            setenv("CFFIXED_USER_HOME", tmp, 1)
            setenv("BURNDOWN_DOCS_HOME", tmp, 1)
            let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let argv = CommandLine.arguments.map { strdup($0) } + [nil]
            execv(exe, argv)
            fail("could not re-exec \(exe)")
        }
        for path in [Store.defaultURL.path, Expirer.defaultDownloads.path, NSHomeDirectory()]
        where path == realHome || path.hasPrefix(realHome + "/") {
            fail("refusing to run: \(path) is inside the real home folder")
        }
    }

    private static func removeTemporaryHome() {
        guard let home = ProcessInfo.processInfo.environment["BURNDOWN_DOCS_HOME"],
              (home as NSString).lastPathComponent.hasPrefix("burndown-docs-") else { return }
        try? FileManager.default.removeItem(atPath: home)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Burndown: \(message)\n".utf8))
        exit(1)
    }

    // MARK: Demo data

    private static let downloads = Expirer.defaultDownloads

    private static func ago(_ hours: Double) -> Date { Date().addingTimeInterval(-hours * 3_600) }
    private static func inHours(_ hours: Double) -> Date { Date().addingTimeInterval(hours * 3_600) }

    private static func seedFiles() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try makePDF(at: downloads.appendingPathComponent("Invoice-2026-0417.pdf"))
        try makePDF(at: downloads.appendingPathComponent("boarding-pass.pdf"))
        try makePNG(at: downloads.appendingPathComponent("Screenshot 2026-10-26 at 09.41.12.png"))
        for name in ["Figma-126.4.0.dmg", "terraform_1.13.4_darwin_arm64.zip", "quarterly-report.xlsx",
                     "team-offsite.mov", "slides-v3-final.key"] {
            fm.createFile(atPath: downloads.appendingPathComponent(name).path, contents: Data())
        }
    }

    /// A one-page invoice-looking PDF so the toast preview shows a real first page.
    private static func makePDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 420, height: 594)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(.white)
        ctx.fill(box)
        ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.42, blue: 0.13, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 534, width: 420, height: 60))
        ctx.setFillColor(CGColor(gray: 0.25, alpha: 1))
        ctx.fill(CGRect(x: 36, y: 470, width: 180, height: 16))
        ctx.setFillColor(CGColor(gray: 0.7, alpha: 1))
        for row in 0..<9 {
            let y = CGFloat(420 - row * 34)
            ctx.fill(CGRect(x: 36, y: y, width: 230, height: 9))
            ctx.fill(CGRect(x: 324, y: y, width: 60, height: 9))
        }
        ctx.setFillColor(CGColor(gray: 0.25, alpha: 1))
        ctx.fill(CGRect(x: 290, y: 80, width: 94, height: 16))
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// A stand-in screenshot: a window-like card on a desktop gradient.
    private static func makePNG(at url: URL) throws {
        let w = 640, h = 400
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        let colors = [CGColor(srgbRed: 0.27, green: 0.45, blue: 0.85, alpha: 1),
                      CGColor(srgbRed: 0.62, green: 0.36, blue: 0.80, alpha: 1)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
        ctx.setFillColor(.white)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 90, y: 60, width: 460, height: 280), cornerWidth: 14,
                           cornerHeight: 14, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
        for row in 0..<5 { ctx.fill(CGRect(x: 120, y: 260 - row * 36, width: 300 - row * 30, height: 12)) }
        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    private static func demoState() -> PersistedState {
        var state = PersistedState()
        var s = BurndownSettings()
        s.screenshots.enabled = true
        s.screenshots.lifetime = .days(3)
        s.rules = [
            Rule(name: "Installers go quickly",
                 conditions: [.scope(.download), .extensions(["dmg", "pkg"])],
                 outcome: .expire(.days(1), .trash)),
            Rule(name: "Never track invoices",
                 conditions: [.scope(.download), .nameGlob("invoice-*.pdf")],
                 outcome: .ignore),
            Rule(name: "Wipe big videos",
                 conditions: [.scope(.download), .extensions(["mov", "mp4"]), .sizeGreaterThan(500 * 1024 * 1024)],
                 outcome: .expire(.days(3), .wipe)),
            Rule(name: "Slack files: 7 days",
                 conditions: [.sourceDomain("slack.com")],
                 outcome: .expire(.days(7), .trash)),
            Rule(name: "Ignore torrents", enabled: false,
                 conditions: [.scope(.download), .extensions(["torrent"])],
                 outcome: .ignore),
        ]
        state.settings = s
        func item(_ name: String, _ scope: Scope = .download, arrived: Double, due: Double, _ action: Action = .trash,
                  from host: String? = nil) -> TrackedItem {
            TrackedItem(path: downloads.appendingPathComponent(name).path, scope: scope, arrived: ago(arrived),
                        due: inHours(due), action: action, sourceHost: host)
        }
        state.items = [
            item("Figma-126.4.0.dmg", arrived: 20, due: 4, from: "desktop.figma.com"),
            item("Screenshot 2026-10-26 at 09.41.12.png", .screenshot, arrived: 3, due: 69),
            item("team-offsite.mov", arrived: 26, due: 46, .wipe),
            item("slides-v3-final.key", arrived: 30, due: 138, from: "files.slack.com"),
            item("boarding-pass.pdf", arrived: 2, due: 334),
            item("terraform_1.13.4_darwin_arm64.zip", arrived: 50, due: 286, from: "releases.hashicorp.com"),
            item("quarterly-report.xlsx", arrived: 70, due: 266),
        ]
        let trash = downloads.deletingLastPathComponent().appendingPathComponent(".Trash")
        func log(_ name: String, hoursAgo: Double, _ action: Action = .trash, reason: String = "expired") -> LogEntry {
            LogEntry(date: ago(hoursAgo), name: name, action: action, reason: reason,
                     originalPath: downloads.appendingPathComponent(name).path,
                     trashedPath: action == .trash ? trash.appendingPathComponent(name).path : nil)
        }
        state.log = [
            log("Zoom-6.6.2.pkg", hoursAgo: 1.5),
            log("IMG_4821.HEIC", hoursAgo: 5),
            log("conference-talk-recording.mp4", hoursAgo: 26, .wipe),
            log("receipt-38215.pdf", hoursAgo: 49, reason: "expired now"),
            log("Screenshot 2026-10-22 at 16.03.57.png", hoursAgo: 75),
            log("node-v24.10.0.pkg", hoursAgo: 98),
            log("meeting-notes (1).docx", hoursAgo: 170),
        ]
        state.screenshotsSince = ago(24 * 10)
        return state
    }

    // MARK: Rendering

    private static func render(into out: URL) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)

        try seedFiles()
        // Saved before the model is made so it loads as-is and no setter side effects (watchers) fire.
        try Store.save(demoState())
        let model = AppModel()

        try menuBarIcons(out)
        try toasts(out)
        try snapshot(popover(MenuContent(model: model)), name: "menu", into: out)
        try snapshot(popover(MenuContent(model: model, open: .tracked)), name: "menu-tracked", into: out)
        try snapshot(popover(MenuContent(model: model, open: .activity)), name: "menu-activity", into: out)
        try settings(model: model, into: out)
    }

    private static func menuBarIcons(_ out: URL) throws {
        func tile(_ image: NSImage, _ label: String) -> some View {
            VStack(spacing: 10) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(18)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        let row = HStack(spacing: 28) {
            tile(MenuBarIcon.normal, "Tracking")
            tile(MenuBarIcon.paused, "Paused")
        }
        try snapshot(row, name: "menubar-icons", into: out)
    }

    private static func toasts(_ out: URL) throws {
        let pdf = downloads.appendingPathComponent("boarding-pass.pdf")
        let png = downloads.appendingPathComponent("Screenshot 2026-10-26 at 09.41.12.png")
        let pdfPreview = ToastPreview()
        let pngPreview = ToastPreview()
        pdfPreview.image = waitFor { await ImagePreview.thumbnail(of: pdf) }
        pngPreview.image = waitFor { await ImagePreview.thumbnail(of: png) }
        func toast(_ url: URL, _ message: String, _ preview: ToastPreview) -> some View {
            ToastView(model: ToastModel(fileURL: url, message: message, keepLabel: "Keep", secondLabel: "Expire in 15m",
                                        dismissAfter: 8, onKeep: {}, onSecond: {}),
                      hover: ToastHover(), preview: preview, onKeep: {}, onSecond: {}, onClose: {})
                // The real card is Liquid Glass, which does not render offscreen: stand in a light card.
                .background {
                    RoundedRectangle(cornerRadius: ToastView.radius)
                        .fill(Color(white: 0.975))
                        .overlay(RoundedRectangle(cornerRadius: ToastView.radius).strokeBorder(.black.opacity(0.08)))
                        .padding(8)
                }
        }
        // Stacked the way ToastCenter lays them out: newest on top, the 8 pt shadow padding overlapping.
        let stack = VStack(spacing: ToastCenter.spacing) {
            toast(png, "\(png.lastPathComponent) will be trashed after 3 days", pngPreview)
            toast(pdf, "\(pdf.lastPathComponent) will be trashed after 14 days", pdfPreview)
        }
        try snapshot(stack, name: "toast", into: out)
    }

    private static func settings(model: AppModel, into out: URL) throws {
        let tabs = ["general", "downloads", "screenshots", "rules", "activity"]
        for (index, tab) in tabs.enumerated() {
            if tab == "rules" {
                // Rendered taller than the window so the whole rule editor shows without scrolling.
                let rules = RulesTab(model: model).frame(width: 660, height: 640)
                try snapshot(window(rules), size: CGSize(width: 660, height: 640), name: "settings-rules", into: out,
                             radius: 12) { root in selectRule(2, in: root) }
                continue
            }
            try snapshot(window(SettingsView(model: model)), size: CGSize(width: 660, height: 520),
                         name: "settings-\(tab)", into: out, radius: 12,
                         prepare: { root in
                             if let tabView: NSTabView = find(in: root) { tabView.selectTabViewItem(at: index) }
                         },
                         crop: { root in
                             // The tab strip is glass and renders as an empty pill offscreen, so cut it off.
                             guard let seg: NSSegmentedControl = find(in: root) else { return 0 }
                             return seg.convert(seg.bounds, to: root).maxY + 6
                         })
        }
    }

    /// Selects a rule row the way a click would, so the rule editor appears.
    private static func selectRule(_ row: Int, in root: NSView) {
        guard let table: NSTableView = find(in: root) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        NotificationCenter.default.post(name: NSTableView.selectionDidChangeNotification, object: table)
    }

    /// The menu bar popover's real background is glass, which does not render offscreen: use a plain card.
    private static func popover(_ content: some View) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black.opacity(0.08)))
    }

    private static func window(_ content: some View) -> some View {
        content.background(Color(nsColor: .windowBackgroundColor))
    }

    /// Lays the view out in a borderless offscreen window, lets SwiftUI settle, captures it at 2x and
    /// composites it onto a soft backdrop. `crop` returns how many points to cut from the top.
    private static func snapshot(_ content: some View, size: CGSize? = nil, name: String, into out: URL,
                                 radius: CGFloat = 0, prepare: (NSView) -> Void = { _ in },
                                 crop: (NSView) -> CGFloat = { _ in 0 }) throws {
        let host = NSHostingView(rootView: content.environment(\.controlActiveState, .key))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        let window = KeyWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        spin(0.6)
        prepare(host)
        spin(0.8)
        var image = try capture(host)
        let top = Int(crop(host) * 2)
        if top > 0, let cropped = image.cropping(to: CGRect(x: 0, y: top, width: image.width,
                                                            height: image.height - top)) {
            image = cropped
        }
        window.orderOut(nil)
        try composite(image, cornerRadius: radius, to: out.appendingPathComponent("\(name).png"))
    }

    // MARK: Helpers

    /// Runs the main run loop so SwiftUI layout, tables and main-actor tasks can settle.
    private static func spin(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    @MainActor private final class Box<T> {
        var value: T?
        var done = false
    }

    /// Waits for an async call by spinning the main run loop (the render runs synchronously at launch).
    private static func waitFor<T>(_ work: @escaping @MainActor () async -> T?) -> T? {
        let box = Box<T>()
        Task { @MainActor in
            box.value = await work()
            box.done = true
        }
        let end = Date().addingTimeInterval(10)
        while !box.done, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return box.value
    }

    private static func find<T: NSView>(in view: NSView) -> T? {
        if let v = view as? T { return v }
        for sub in view.subviews { if let v: T = find(in: sub) { return v } }
        return nil
    }

    /// The view's layer tree drawn into a 2x bitmap, top row first. `cacheDisplay` misses SwiftUI's
    /// layer-drawn form rows, so the layers are rendered directly.
    private static func capture(_ view: NSView) throws -> CGImage {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let size = view.bounds.size
        guard let layer = view.layer,
              let ctx = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        ctx.translateBy(x: 0, y: size.height * 2)
        ctx.scaleBy(x: 2, y: -2)
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    /// Puts a capture on a warm-to-cool gradient with a soft drop shadow, so transparent edges and
    /// shadows read well on GitHub in light and dark mode.
    private static func composite(_ image: CGImage, cornerRadius: CGFloat, to url: URL) throws {
        let pad = 64
        let w = image.width + pad * 2, h = image.height + pad * 2
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        let colors = [CGColor(srgbRed: 0.99, green: 0.91, blue: 0.84, alpha: 1),
                      CGColor(srgbRed: 0.87, green: 0.89, blue: 0.96, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: 24, cornerHeight: 24,
                           transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        let rect = CGRect(x: pad, y: pad, width: image.width, height: image.height)
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 48, color: CGColor(gray: 0, alpha: 0.25))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if cornerRadius > 0 {
            let r = cornerRadius * 2
            let shape = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.draw(image, in: rect)
            ctx.restoreGState()
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: r - 1, cornerHeight: r - 1,
                               transform: nil))
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
            ctx.setLineWidth(2)
            ctx.strokePath()
        } else {
            ctx.draw(image, in: rect)
        }
        ctx.endTransparencyLayer()
        guard let out = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        print("wrote \(url.lastPathComponent) (\(w) x \(h))")
    }
}

/// Draws controls with their active (key window) appearance although the window is offscreen.
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
