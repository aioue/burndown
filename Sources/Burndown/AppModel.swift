import AppKit
import BurndownCore
import Observation
import ServiceManagement

@MainActor @Observable
final class AppModel {
    /// Debug only: BURNDOWN_TIME_SCALE=3600 turns hours into seconds so expiry can be watched live.
    static let timeScale = Double(ProcessInfo.processInfo.environment["BURNDOWN_TIME_SCALE"] ?? "") ?? 1

    var state: PersistedState {
        didSet {
            persist()
            let old = oldValue.settings, new = state.settings
            if old.screenshots.enabled != new.screenshots.enabled
                || old.screenshotEarlyToast != new.screenshotEarlyToast { syncScreenshots() }
            if old.paused && !new.paused { expireDue() }
        }
    }

    private let downloadsDir = Expirer.defaultDownloads
    private var downloadsWatcher: DownloadsWatcher?
    private var screenshotWatcher: ScreenshotWatcher?
    private var screenshotLogWatcher: ScreenshotLogWatcher?
    /// Early screenshot toasts waiting for their file (macOS writes it ~5 s after the thumbnail appears).
    private var pendingShots: [PendingShot] = []
    private var shotItems: [UUID: UUID] = [:]

    private enum Queued { case keep, second }

    private struct PendingShot {
        let id = UUID()
        let created = Date()
        var queued: Queued?
        var toast: ToastHandle?
    }
    private var timerTask: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    var settings: BurndownSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Burndown: launch at login failed: \(error.localizedDescription)")
            }
        }
    }

    init() {
        state = Store.load()
    }

    func start() {
        let watcher = DownloadsWatcher(directory: downloadsDir) { [weak self] url in
            self?.track(url, scope: .download)
        }
        watcher.start()
        downloadsWatcher = watcher
        syncScreenshots()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.expireDue() }
        }
        expireDue()
    }

    // MARK: Tracking

    func track(_ url: URL, scope: Scope, toast: Bool = true) {
        guard !state.settings.paused else { return }
        guard !state.items.contains(where: { $0.path == url.path }) else { return }
        // Kept files (e.g. screenshots re-reported after a relaunch) are never re-tracked.
        guard !FileMeta.hasKeepTag(url) else { return }
        let info = FileMeta.info(for: url, scope: scope)
        guard let outcome = RuleEngine.evaluate(info, settings: state.settings),
              case .expire(let life, let action) = outcome else { return }
        let item = TrackedItem(
            path: url.path, bookmark: FileMeta.bookmark(for: url), scope: scope,
            due: life.seconds.map { Date().addingTimeInterval($0 / Self.timeScale) },
            action: action, sourceHost: info.sourceHost)
        state.items.append(item)
        rearm()
        // A screenshot whose toast was already shown at capture time just gets bound to its item.
        if scope == .screenshot, let early = takePendingShot() {
            shotItems[early.id] = item.id
            if let handle = early.toast {
                Task {
                    if let image = await ImagePreview.thumbnail(of: url) { handle.setPreview(image) }
                }
            }
            switch early.queued {
            case .keep: keep(item.id)
            case .second: secondAction(item.id)
            case nil: break
            }
            return
        }
        let d = state.settings.defaults(for: scope)
        if toast, d.showToast, life.seconds != nil { showToast(for: item, lifetime: life) }
    }

    // MARK: Early screenshot toast

    /// Called when `screencapture` logs a capture: the toast appears with the thumbnail, the file arrives later.
    private func screenshotCaptured(_ capture: ScreenshotLogWatcher.Capture) {
        let s = state.settings
        guard !s.paused, s.screenshots.enabled, s.screenshots.showToast else { return }
        let name = capture.url.lastPathComponent
        let info = FileInfo(name: name, size: 0, scope: .screenshot)
        guard let outcome = RuleEngine.evaluate(info, settings: s),
              case .expire(let life, let action) = outcome, life.seconds != nil else { return }
        var shot = PendingShot()
        let id = shot.id
        shot.toast = ToastCenter.shared.show(ToastModel(
            fileURL: capture.url,
            placeholder: "📸",
            message: "\(name) will be \(action.pastTense) after \(life.phrase)",
            keepLabel: s.keepLabel,
            secondLabel: s.secondLabel ?? s.secondButton.defaultLabel,
            dismissAfter: s.toastSeconds,
            onKeep: { [weak self] in self?.resolveShot(id, .keep) },
            onSecond: { [weak self] in self?.resolveShot(id, .second) }))
        pendingShots.append(shot)
    }

    /// Oldest capture still waiting for its file. Captures that never produce one (thumbnail swiped away,
    /// cancelled) are dropped after two minutes.
    private func takePendingShot() -> PendingShot? {
        pendingShots.removeAll { Date().timeIntervalSince($0.created) > 120 }
        return pendingShots.isEmpty ? nil : pendingShots.removeFirst()
    }

    private func resolveShot(_ id: UUID, _ action: Queued) {
        if let itemID = shotItems[id] {
            if action == .keep { keep(itemID) } else { secondAction(itemID) }
        } else if let i = pendingShots.firstIndex(where: { $0.id == id }) {
            pendingShots[i].queued = action
        }
    }

    private func showToast(for item: TrackedItem, lifetime: Lifetime) {
        let s = state.settings
        let secondLabel = s.secondLabel ?? s.secondButton.defaultLabel
        let url = URL(fileURLWithPath: item.path)
        ToastCenter.shared.show(ToastModel(
            fileURL: url,
            message: "\(item.name) will be \(item.action.pastTense) after \(lifetime.phrase)",
            keepLabel: s.keepLabel,
            secondLabel: secondLabel,
            dismissAfter: s.toastSeconds,
            onKeep: { [weak self] in self?.keep(item.id) },
            onSecond: { [weak self] in self?.secondAction(item.id) }))
    }

    /// Settings chip: shows a toast with the current labels and timings, without tracking anything.
    func sendTestToast() {
        let s = state.settings
        let d = s.downloads
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Test download.pdf")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        ToastCenter.shared.show(ToastModel(
            fileURL: file,
            message: "\(file.lastPathComponent) will be \(d.action.pastTense) after \(d.lifetime.phrase)",
            keepLabel: s.keepLabel,
            secondLabel: s.secondLabel ?? s.secondButton.defaultLabel,
            dismissAfter: s.toastSeconds,
            onKeep: {},
            onSecond: {}))
    }

    // MARK: Actions

    func keep(_ id: UUID) {
        guard let item = state.items.first(where: { $0.id == id }) else { return }
        do {
            try FileMeta.markKept(FileMeta.resolve(path: item.path, bookmark: item.bookmark))
        } catch {
            NSLog("Burndown: could not tag \(item.name): \(error.localizedDescription)")
        }
        remove(id)
    }

    func secondAction(_ id: UUID) {
        switch state.settings.secondButton {
        case .expireNow: expireNow(id)
        case .snooze: snooze(id)
        case .reveal: reveal(id)
        }
    }

    func expireNow(_ id: UUID) {
        guard let item = state.items.first(where: { $0.id == id }) else { return }
        if item.action == .wipe {
            let alert = NSAlert()
            alert.messageText = "Permanently delete \(item.name)?"
            alert.informativeText = "This skips the Trash and cannot be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        process(item, reason: "expired now")
    }

    func snooze(_ id: UUID) {
        guard let i = state.items.firstIndex(where: { $0.id == id }) else { return }
        state.items[i].due = Date().addingTimeInterval(state.settings.snoozeDays * 86_400 / Self.timeScale)
        rearm()
    }

    func reveal(_ id: UUID) {
        guard let item = state.items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([FileMeta.resolve(path: item.path, bookmark: item.bookmark)])
    }

    func remove(_ id: UUID) {
        state.items.removeAll { $0.id == id }
        rearm()
    }

    // MARK: Expiry

    func expireDue() {
        if !state.settings.paused {
            for item in Scheduler.due(state.items) { process(item, reason: "expired") }
        }
        rearm()
    }

    private func process(_ item: TrackedItem, reason: String) {
        switch Expirer.expire(item, downloadsDir: downloadsDir) {
        case .expired:
            state.appendLog(LogEntry(name: item.name, action: item.action, reason: reason))
            remove(item.id)
        case .untrack:
            remove(item.id)
        case .failed(let message):
            NSLog("Burndown: \(item.name): \(message)")
            if let i = state.items.firstIndex(where: { $0.id == item.id }) {
                // Retry in an hour rather than hammering a file we cannot remove.
                state.items[i].due = Date().addingTimeInterval(3_600)
            }
        }
    }

    private func rearm() {
        timerTask?.cancel()
        guard let next = Scheduler.nextDue(state.items) else { return }
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.5, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.expireDue()
        }
    }

    // MARK: Screenshots

    private func syncScreenshots() {
        screenshotWatcher?.stop()
        screenshotWatcher = nil
        screenshotLogWatcher?.stop()
        screenshotLogWatcher = nil
        pendingShots = []
        guard state.settings.screenshots.enabled else { return }
        if state.settings.screenshotEarlyToast {
            let logWatcher = ScreenshotLogWatcher { [weak self] in self?.screenshotCaptured($0) }
            logWatcher.start()
            screenshotLogWatcher = logWatcher
        }
        if state.screenshotsSince == nil { state.screenshotsSince = Date() }
        let watcher = ScreenshotWatcher(since: state.screenshotsSince ?? Date()) { [weak self] url in
            self?.track(url, scope: .screenshot)
        }
        watcher.start()
        screenshotWatcher = watcher
    }

    private func persist() {
        do { try Store.save(state) } catch { NSLog("Burndown: save failed: \(error.localizedDescription)") }
    }
}
