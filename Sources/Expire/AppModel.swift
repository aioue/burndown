import AppKit
import ExpireCore
import Observation
import ServiceManagement

@MainActor @Observable
final class AppModel {
    /// Debug only: EXPIRE_TIME_SCALE=3600 turns hours into seconds so expiry can be watched live.
    static let timeScale = Double(ProcessInfo.processInfo.environment["EXPIRE_TIME_SCALE"] ?? "") ?? 1

    var state: PersistedState {
        didSet {
            persist()
            let old = oldValue.settings, new = state.settings
            if old.screenshots.enabled != new.screenshots.enabled { syncScreenshots() }
            if old.paused && !new.paused { expireDue() }
        }
    }

    private let downloadsDir = Expirer.defaultDownloads
    private var downloadsWatcher: DownloadsWatcher?
    private var screenshotWatcher: ScreenshotWatcher?
    private var timerTask: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    var settings: ExpireSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Expire: launch at login failed: \(error.localizedDescription)")
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
        let d = state.settings.defaults(for: scope)
        if toast, d.showToast, life.seconds != nil { showToast(for: item, lifetime: life) }
    }

    /// Menu action: start countdowns for files already sitting in Downloads.
    func adoptExisting() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil)) ?? []
        for url in urls where !PartialFilter.shouldSkip(name: url.lastPathComponent) {
            track(url, scope: .download, toast: false)
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

    // MARK: Actions

    func keep(_ id: UUID) {
        guard let item = state.items.first(where: { $0.id == id }) else { return }
        do {
            try FileMeta.markKept(FileMeta.resolve(path: item.path, bookmark: item.bookmark))
        } catch {
            NSLog("Expire: could not tag \(item.name): \(error.localizedDescription)")
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
            NSLog("Expire: \(item.name): \(message)")
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
        guard state.settings.screenshots.enabled else { return }
        if state.screenshotsSince == nil { state.screenshotsSince = Date() }
        let watcher = ScreenshotWatcher(since: state.screenshotsSince ?? Date()) { [weak self] url in
            self?.track(url, scope: .screenshot)
        }
        watcher.start()
        screenshotWatcher = watcher
    }

    private func persist() {
        do { try Store.save(state) } catch { NSLog("Expire: save failed: \(error.localizedDescription)") }
    }
}
