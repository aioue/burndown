import Foundation

/// Learns about a screenshot the moment it is taken, ~5 s before macOS writes the file.
///
/// `screencapture` logs "destination = file" to the unified log at the capture instant, and the
/// filename is derived from that timestamp. The log can only be streamed through `/usr/bin/log`
/// (private entitlements, admin users only), so it runs as a child process: ~3 MB, ~0% CPU.
/// If it cannot run, Burndown falls back to the Spotlight watcher alone.
@MainActor
final class ScreenshotLogWatcher {
    struct Capture {
        let date: Date
        let url: URL
    }

    private static let predicate =
        #"subsystem == "com.apple.screencapture" AND eventMessage CONTAINS "destination = file""#

    private let onCapture: @MainActor (Capture) -> Void
    private var process: Process?
    private var buffer = Data()
    private var wanted = false
    private var launched = Date.distantPast
    private var quickFailures = 0

    init(onCapture: @escaping @MainActor (Capture) -> Void) {
        self.onCapture = onCapture
    }

    func start() {
        wanted = true
        quickFailures = 0
        launch()
    }

    func stop() {
        wanted = false
        if let p = process {
            p.terminationHandler = nil
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            p.terminate()
        }
        process = nil
        buffer = Data()
    }

    private func launch() {
        guard wanted, process == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--level", "info", "--style", "ndjson", "--predicate", Self.predicate]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.exited() }
        }
        do {
            try p.run()
            process = p
            launched = Date()
        } catch {
            NSLog("Burndown: could not start log stream: \(error.localizedDescription)")
        }
    }

    private func exited() {
        process = nil
        guard wanted else { return }
        // `log stream` exits at once for non-admin users; do not spin if that is what is happening.
        quickFailures = Date().timeIntervalSince(launched) < 3 ? quickFailures + 1 : 0
        guard quickFailures < 3 else {
            NSLog("Burndown: log stream keeps exiting; early screenshot toasts disabled")
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.launch()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let stamp = obj["timestamp"] as? String,
                  let date = Self.logDate.date(from: stamp)
            else { continue }
            onCapture(Capture(date: date, url: Self.expectedURL(for: date)))
        }
    }

    // MARK: Expected filename

    private static let logDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return f
    }()

    /// "<location>/<name> YYYY-MM-DD at HH.MM.SS.<type>", from the screencapture preferences.
    static func expectedURL(for date: Date) -> URL {
        let prefs = UserDefaults(suiteName: "com.apple.screencapture")
        let folder = ((prefs?.string(forKey: "location") ?? "~/Desktop") as NSString).expandingTildeInPath
        let name = prefs?.string(forKey: "name") ?? "Screenshot"
        let type = prefs?.string(forKey: "type") ?? "png"
        var file = name
        if prefs?.object(forKey: "include-date") as? Bool ?? true {
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.dateFormat = "yyyy-MM-dd"
            let time = DateFormatter()
            time.locale = Locale(identifier: "en_US_POSIX")
            let twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
            time.dateFormat = twelveHour ? "h.mm.ss\u{202F}a" : "HH.mm.ss"
            file += " \(day.string(from: date)) at \(time.string(from: date))"
        }
        return URL(fileURLWithPath: folder).appendingPathComponent("\(file).\(type)")
    }
}
