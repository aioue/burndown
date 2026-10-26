import BurndownCore
import Foundation

/// Live Spotlight query for screen captures created at or after `since`, wherever they are saved.
/// The query only exists between start() and stop().
@MainActor
final class ScreenshotWatcher {
    private let since: Date
    private let onArrival: @MainActor (URL) -> Void
    private var query: NSMetadataQuery?
    private var starting = false
    private var folderWatcher: DownloadsWatcher?
    private var observers: [NSObjectProtocol] = []
    /// Reported paths and file identities, so a later rename or move is not a new arrival.
    private var reported: Set<String> = []
    private var reportedIDs: Set<FileID> = []

    private struct FileID: Hashable {
        var dev: Int32
        var ino: UInt64
    }

    init(since: Date, onArrival: @escaping @MainActor (URL) -> Void) {
        self.since = since
        self.onArrival = onArrival
    }

    /// Spotlight silently hides results from protected folders (Desktop, Documents, Downloads...) until
    /// the app has been granted access, so touch the screenshot folder first to trigger the prompt.
    func start() {
        guard !starting, query == nil else { return }
        starting = true
        let folder = Self.screenshotFolder
        Task.detached {
            _ = try? FileManager.default.contentsOfDirectory(atPath: folder)
            await MainActor.run { [weak self] in self?.startQuery() }
        }
    }

    private nonisolated static var screenshotFolder: String {
        let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") ?? "~/Desktop"
        return (loc as NSString).expandingTildeInPath
    }

    private func startQuery() {
        guard starting, query == nil else { return }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K == 1 AND %K >= %@",
                                  "kMDItemIsScreenCapture", NSMetadataItemFSCreationDateKey, since as NSDate)
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.notificationBatchingInterval = 0.5
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.processAll() }
            },
            nc.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let items = ((info[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? [])
                    + ((info[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]) ?? [])
                let found = items.compactMap(Self.candidate)
                MainActor.assumeIsolated { self?.report(found) }
            },
        ]
        query = q
        q.start()

        // Spotlight can lag behind the file being written, so also watch the screenshot folder directly.
        // Screenshots carry a kMDItemIsScreenCapture xattr from the moment they are written.
        let folder = URL(fileURLWithPath: Self.screenshotFolder)
        let fw = DownloadsWatcher(directory: folder) { [weak self] url in
            guard let self, Self.isScreenCapture(url),
                  let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            else { return }
            self.report([(url.path, created)])
        }
        fw.start()
        folderWatcher = fw
    }

    private nonisolated static func isScreenCapture(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { p in
            p.map { getxattr($0, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0 } ?? false
        }
    }

    func stop() {
        starting = false
        folderWatcher?.stop()
        folderWatcher = nil
        guard let q = query else { return }
        q.stop()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        query = nil
        reported = []
        reportedIDs = []
    }

    private func processAll() {
        guard let q = query else { return }
        q.disableUpdates()
        let found = (0..<q.resultCount).compactMap { (q.result(at: $0) as? NSMetadataItem).flatMap(Self.candidate) }
        q.enableUpdates()
        report(found)
    }

    private func report(_ found: [(path: String, created: Date)]) {
        for (path, created) in found where created >= since {
            var st = stat()
            guard !reported.contains(path) else { continue }
            guard lstat(path, &st) == 0 else { continue }
            reported.insert(path)
            guard reportedIDs.insert(FileID(dev: st.st_dev, ino: UInt64(st.st_ino))).inserted else { continue }
            onArrival(URL(fileURLWithPath: path))
        }
    }

    private nonisolated static func candidate(_ item: NSMetadataItem) -> (path: String, created: Date)? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
              !PartialFilter.shouldSkip(name: (path as NSString).lastPathComponent)
        else { return nil }
        let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
        return (path, created)
    }
}

