import CoreServices
import BurndownCore
import Foundation

/// Watches the top level of one directory with FSEvents and reports items that arrived after
/// `start()` once their size has settled. Identity is the inode, so renames of known items
/// (including a partial's rename to its final name before it was ever reported) are handled.
@MainActor
final class DownloadsWatcher {
    private struct Signature: Equatable {
        var size: Int64
        var mtime: Double
        var count: Int
    }

    private struct Pending {
        var inode: UInt64
        var signature: Signature?
        var checks = 0
        var task: Task<Void, Never>?
    }

    /// Weak trampoline handed to the C callback, so a dropped watcher is never messaged.
    /// Only read on the main queue, where the stream delivers.
    private final class Ref: @unchecked Sendable {
        weak var owner: DownloadsWatcher?
        init(_ owner: DownloadsWatcher) { self.owner = owner }
    }

    static let settleDelay: Duration = .milliseconds(1500)
    static let maxChecks = 20
    static let maxDirEntries = 20_000

    private let directory: URL
    private let dirPath: String
    private let onArrival: @MainActor (URL) -> Void
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    nonisolated(unsafe) private var ref: Unmanaged<Ref>?
    /// Inodes present at start() plus everything already reported.
    private var known: Set<UInt64> = []
    private var pending: [String: Pending] = [:]

    init(directory: URL, onArrival: @escaping @MainActor (URL) -> Void) {
        self.directory = directory
        self.dirPath = Self.realPath(directory.path)
        self.onArrival = onArrival
    }

    deinit {
        Self.teardown(stream, ref)
    }

    func start() {
        guard stream == nil else { return }
        known = Set(children().compactMap { Self.inode(of: $0) })
        let box = Unmanaged.passRetained(Ref(self))
        var ctx = FSEventStreamContext(version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(nil, Self.callback, &ctx, [dirPath] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags)
        else { box.release(); return }
        FSEventStreamSetDispatchQueue(s, .main)
        guard FSEventStreamStart(s) else { Self.teardown(s, box); return }
        stream = s
        ref = box
    }

    func stop() {
        Self.teardown(stream, ref)
        stream = nil
        ref = nil
        for p in pending.values { p.task?.cancel() }
        pending = [:]
        known = []
    }

    private nonisolated static func teardown(_ s: FSEventStreamRef?, _ box: Unmanaged<Ref>?) {
        if let s {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        box?.release()
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let ref = Unmanaged<Ref>.fromOpaque(info).takeUnretainedValue()
        let cfPaths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
        var events: [(String, FSEventStreamEventFlags)] = []
        events.reserveCapacity(count)
        for i in 0..<count {
            if let p = cfPaths[i] as? String { events.append((p, flags[i])) }
        }
        MainActor.assumeIsolated {
            ref.owner?.handle(events)
        }
    }

    // MARK: - Events

    private func handle(_ events: [(String, FSEventStreamEventFlags)]) {
        let rescanFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
        var names: Set<String> = []
        for (path, flags) in events {
            if flags & rescanFlags != 0 {
                for url in children() { names.insert(url.lastPathComponent) }
                continue
            }
            if let name = topLevelName(path) { names.insert(name) }
        }
        for name in names { consider(name) }
    }

    /// The direct child of the watched directory an event path belongs to. Events inside a
    /// subfolder map to that folder, so a new folder still filling up keeps settling as one item.
    private func topLevelName(_ path: String) -> String? {
        let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
        guard let r = path.range(of: prefix, options: [.anchored, .caseInsensitive]) else { return nil }
        let rest = path[r.upperBound...]
        guard let name = rest.split(separator: "/", maxSplits: 1).first, !name.isEmpty else { return nil }
        return String(name)
    }

    private func consider(_ name: String) {
        guard !PartialFilter.shouldSkip(name: name) else { return }
        let path = (dirPath as NSString).appendingPathComponent(name)
        guard let ino = Self.inode(atPath: path) else {
            pending.removeValue(forKey: path)?.task?.cancel()
            return
        }
        guard !known.contains(ino) else { return }
        if pending[path] != nil {
            pending[path]?.inode = ino
            return
        }
        var p = Pending(inode: ino, signature: Self.signature(atPath: path))
        p.task = schedule(path)
        pending[path] = p
    }

    private func schedule(_ path: String) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.check(path)
        }
    }

    private func check(_ path: String) {
        guard var p = pending[path] else { return }
        let name = (path as NSString).lastPathComponent
        guard let ino = Self.inode(atPath: path), !known.contains(ino), !PartialFilter.shouldSkip(name: name) else {
            pending[path] = nil
            return
        }
        let sig = Self.signature(atPath: path)
        if sig != nil, sig == p.signature, ino == p.inode {
            pending[path] = nil
            known.insert(ino)
            onArrival(directory.appendingPathComponent(name))
            return
        }
        p.checks += 1
        guard p.checks < Self.maxChecks else {
            // Gives up quietly; a later write event starts a fresh settle.
            pending[path] = nil
            return
        }
        p.inode = ino
        p.signature = sig
        p.task = schedule(path)
        pending[path] = p
    }

    // MARK: - File system

    private func children() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dirPath)) ?? []
        return names.filter { !PartialFilter.shouldSkip(name: $0) }
            .map { URL(fileURLWithPath: (dirPath as NSString).appendingPathComponent($0)) }
    }

    private static func inode(of url: URL) -> UInt64? { inode(atPath: url.path) }

    private static func inode(atPath path: String) -> UInt64? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return UInt64(st.st_ino)
    }

    /// Size and mtime for a file; for a directory a bounded recursive total, newest mtime and count.
    private static func signature(atPath path: String) -> Signature? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        var sig = Signature(size: Int64(st.st_size), mtime: mtime(st), count: 1)
        guard st.st_mode & S_IFMT == S_IFDIR else { return sig }
        autoreleasepool {
            guard let e = FileManager.default.enumerator(atPath: path) else { return }
            while let rel = e.nextObject() as? String, sig.count < maxDirEntries {
                var cst = stat()
                guard lstat((path as NSString).appendingPathComponent(rel), &cst) == 0 else { continue }
                sig.size += Int64(cst.st_size)
                sig.mtime = max(sig.mtime, mtime(cst))
                sig.count += 1
            }
        }
        return sig
    }

    private static func mtime(_ st: stat) -> Double {
        Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
    }

    private static func realPath(_ path: String) -> String {
        guard let r = realpath(path, nil) else { return path }
        defer { free(r) }
        return String(cString: r)
    }
}
