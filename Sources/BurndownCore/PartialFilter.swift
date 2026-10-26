import Foundation

public enum PartialFilter {
    private static let partialExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "opdownload", "tmp", "temp", "aria2", "!ut", "filepart",
    ]

    /// True for dotfiles and browser/downloader in-progress names that should never be tracked.
    public static func shouldSkip(name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return partialExtensions.contains(ext)
    }
}
