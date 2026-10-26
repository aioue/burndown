import Foundation

public enum ExpireResult: Equatable, Sendable {
    case expired
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
            case .trash: try fm.trashItem(at: url, resultingItemURL: nil)
            case .wipe: try fm.removeItem(at: url)
            }
            return .expired
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public static var defaultDownloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
