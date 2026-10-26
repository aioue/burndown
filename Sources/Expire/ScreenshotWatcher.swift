import ExpireCore
import Foundation

/// Live Spotlight query for screen captures created at or after `since`, wherever they are saved.
/// The query only exists between start() and stop().
@MainActor
final class ScreenshotWatcher {
    private let since: Date
    private let onArrival: @MainActor (URL) -> Void
    private var query: NSMetadataQuery?
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

    func start() {
        guard query == nil else { return }
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
    }

    func stop() {
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
            guard !reported.contains(path), lstat(path, &st) == 0 else { continue }
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
