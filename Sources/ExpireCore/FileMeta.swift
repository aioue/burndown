import CoreServices
import Foundation

public enum FileMeta {
    public static let keepTag = "Keep"
    static let keepXattr = "com.aioue.expire.kept"

    /// Size, source URLs (kMDItemWhereFroms) and scope → rule-engine input.
    public static func info(for url: URL, scope: Scope) -> FileInfo {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return FileInfo(name: url.lastPathComponent, size: size, sourceURLs: whereFroms(url), scope: scope)
    }

    public static func whereFroms(_ url: URL) -> [String] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              let v = MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String]
        else { return [] }
        return v
    }

    public static func hasKeepTag(_ url: URL) -> Bool {
        let tags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? nil
        return tags?.contains(keepTag) ?? false
    }

    /// Adds the Finder tag (source of truth) plus an xattr recording that we set it.
    public static func markKept(_ url: URL) throws {
        var url = url
        var tags = (try url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        if !tags.contains(keepTag) { tags.append(keepTag) }
        var values = URLResourceValues()
        values.tagNames = tags
        try url.setResourceValues(values)
        _ = url.withUnsafeFileSystemRepresentation { p in
            setxattr(p, keepXattr, "1", 1, 0, 0)
        }
    }

    public static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .minimalBookmark)
    }

    public static func resolve(path: String, bookmark: Data?) -> URL {
        if let b = bookmark {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: b, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale) {
                return u
            }
        }
        return URL(fileURLWithPath: path)
    }
}
