import Foundation

public enum ExpireResult: Equatable, Sendable {
    /// `trashedAt` is where the file landed in the Trash (nil when wiped).
    case expired(trashedAt: URL?)
    /// Left alone; the item should be dropped from tracking.
    case untrack(reason: String)
    case failed(String)
}

public enum Expirer {
    /// Applies the safety checks, then trashes or wipes. Never acts on kept files, files that
    /// have left Downloads, or files that no longer exist.
    public static func expire(_ item: TrackedItem, downloadsDir: URL = defaultDownloads,
                              fileManager fm: FileManager = .default) -> ExpireResult {
        let url = FileMeta.resolve(path: item.path, bookmark: item.bookmark)
        guard fm.fileExists(atPath: url.path) else { return .untrack(reason: "missing") }
        if FileMeta.hasKeepTag(url) { return .untrack(reason: "kept") }
        if item.scope == .download {
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            if parent != downloadsDir.resolvingSymlinksInPath().standardizedFileURL {
                return .untrack(reason: "moved out of Downloads")
            }
        }
        do {
            switch item.action {
            case .trash:
                var result: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &result)
                return .expired(trashedAt: result as URL?)
            case .wipe:
                try fm.removeItem(at: url)
                return .expired(trashedAt: nil)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Moves a trashed file back to its original folder, picking a free name if the old one is taken.
    /// Returns where it ended up. The restored file is tagged Keep so it is never tracked again.
    public static func putBack(_ entry: LogEntry, fileManager fm: FileManager = .default) throws -> URL {
        guard let original = entry.originalPath, let trashed = entry.trashedPath else {
            throw CocoaError(.fileNoSuchFile)
        }
        let src = URL(fileURLWithPath: trashed)
        guard fm.fileExists(atPath: src.path) else { throw CocoaError(.fileNoSuchFile) }
        let wanted = URL(fileURLWithPath: original)
        let folder = wanted.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var dest = wanted
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            let ext = wanted.pathExtension
            let base = wanted.deletingPathExtension().lastPathComponent
            dest = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        try fm.moveItem(at: src, to: dest)
        try? FileMeta.markKept(dest)
        return dest
    }

    public static var defaultDownloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
