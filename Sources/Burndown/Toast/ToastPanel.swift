import AppKit
import SwiftUI

struct ToastModel {
    let fileURL: URL
    /// Shown in the icon slot instead of the file-type icon (until a preview arrives).
    var placeholder: String?
    let message: String
    let keepLabel: String
    let secondLabel: String
    /// Seconds before auto-dismiss; 0 = never.
    let dismissAfter: Double
    let onKeep: @MainActor () -> Void
    let onSecond: @MainActor () -> Void
}

/// Returned by `ToastCenter.show` so the caller can update a toast that is already visible.
struct ToastHandle {
    let setPreview: @MainActor (NSImage) -> Void
}

/// Stacks toast panels at the top right of the main screen, newest first.
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    static let maxVisible = 5
    static let margin: CGFloat = 10
    /// Each panel carries 8 pt of shadow padding per side, so -8 leaves roughly an 8 pt gap between cards.
    static let spacing: CGFloat = -8

    private var toasts: [Toast] = []
    /// Double-tap Shift keeps the newest toast's file; set from settings.
    var shiftKeeps = true
    private var shiftWatcher: Task<Void, Never>?

    private init() {}

    @discardableResult
    func show(_ model: ToastModel) -> ToastHandle {
        let toast = Toast(model: model, center: self)
        toasts.insert(toast, at: 0)
        while toasts.count > Self.maxVisible, let oldest = toasts.last {
            dismiss(oldest, relayout: false)
        }
        layout(appearing: toast)
        startShiftWatcher()
        return ToastHandle(setPreview: { [weak toast] image in toast?.preview.image = image })
    }

    fileprivate func dismiss(_ toast: Toast, relayout: Bool = true) {
        guard let i = toasts.firstIndex(where: { $0 === toast }) else { return }
        toasts.remove(at: i)
        toast.close()
        if relayout { layout(appearing: nil) }
        if toasts.isEmpty { shiftWatcher?.cancel(); shiftWatcher = nil }
    }

    /// Watches for a double tap of Shift, but only while a toast is on screen. The current modifier
    /// state can be read without any permission, so this polls briefly instead of installing a global
    /// key monitor (which would need Input Monitoring).
    private func startShiftWatcher() {
        guard shiftWatcher == nil else { return }
        shiftWatcher = Task { @MainActor [weak self] in
            var shiftDown = false
            var lastPress: Date?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(25))
                guard let self, self.shiftKeeps else { continue }
                let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags != [] && flags != [.shift] { lastPress = nil; shiftDown = false; continue }
                let down = flags == [.shift]
                guard down != shiftDown else { continue }
                shiftDown = down
                guard down else { continue }
                let now = Date()
                if let last = lastPress, now.timeIntervalSince(last) < 0.45,
                   // No key was typed between the two taps, so this is not capitalisation.
                   CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
                    > now.timeIntervalSince(last) {
                    lastPress = nil
                    self.toasts.first?.keepFromShortcut()
                } else {
                    lastPress = now
                }
            }
        }
    }

    private func layout(appearing: Toast?) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        var top = area.maxY - Self.margin
        var targets: [(Toast, NSRect)] = []
        for t in toasts {
            let size = t.panel.frame.size
            let frame = NSRect(x: area.maxX - Self.margin - size.width, y: top - size.height,
                               width: size.width, height: size.height)
            top = frame.minY - Self.spacing
            targets.append((t, frame))
        }
        // Park the new toast just off the right screen edge before any animation starts, so it slides
        // in like a system notification instead of animating from wherever the window was created.
        if let (t, frame) = targets.first(where: { $0.0 === appearing }) {
            t.panel.alphaValue = 0
            t.panel.setFrame(frame.offsetBy(dx: frame.width + Self.margin, dy: 0), display: false)
            t.panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (t, frame) in targets {
                if t === appearing { t.panel.animator().alphaValue = 1 }
                t.panel.animator().setFrame(frame, display: true)
            }
        }
    }
}

/// One toast: its panel, hover state and auto-dismiss timer.
@MainActor
private final class Toast {
    let panel: ToastWindow
    private let model: ToastModel
    private let hover = ToastHover()
    let preview = ToastPreview()
    private weak var center: ToastCenter?
    private var timer: Task<Void, Never>?
    private var deadline: Date?
    private var remaining: Double

    init(model: ToastModel, center: ToastCenter) {
        self.model = model
        self.center = center
        remaining = model.dismissAfter
        panel = ToastWindow()

        let view = ToastView(model: model, hover: hover, preview: preview,
                             onKeep: { [weak self] in self?.finish(model.onKeep) },
                             onSecond: { [weak self] in self?.finish(model.onSecond) },
                             onClose: { [weak self] in self?.finish(nil) })
        let hosting = ToastHostingView(rootView: view)
        let size = hosting.fittingSize
        let container = HoverView(frame: NSRect(origin: .zero, size: size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.onHover = { [weak self] inside in self?.setHovered(inside) }
        panel.contentView = container
        panel.setContentSize(size)
        startTimer()
    }

    func close() {
        timer?.cancel()
        timer = nil
        let panel = panel
        (panel.contentView as? HoverView)?.onHover = nil
        Task { @MainActor in
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
    }

    /// Flash the Keep button briefly so the shortcut visibly registers, then keep and dismiss.
    func keepFromShortcut() {
        guard !hover.keepFlash else { return }
        hover.keepFlash = true
        timer?.cancel()
        timer = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self else { return }
            self.finish(self.model.onKeep)
        }
    }

    private func finish(_ action: (@MainActor () -> Void)?) {
        action?()
        center?.dismiss(self)
    }

    private func setHovered(_ inside: Bool) {
        hover.isHovered = inside
        if inside {
            if let d = deadline { remaining = max(0, d.timeIntervalSinceNow) }
            timer?.cancel()
            timer = nil
            deadline = nil
        } else {
            remaining = max(remaining, 2)
            startTimer()
        }
    }

    private func startTimer() {
        guard model.dismissAfter > 0, timer == nil else { return }
        let seconds = remaining
        deadline = Date().addingTimeInterval(seconds)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.center?.dismiss(self)
        }
    }
}

/// Borderless, non-activating, floating on every space, never key or main.
private final class ToastWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Clicks land on the first try even though the panel is never key.
private final class ToastHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Reports hover with an always-active tracking area (the app is usually inactive).
private final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
