import AppKit
import UniformTypeIdentifiers

enum FileIcon {
    /// 16 pt Finder icon for a menu item: the file's own icon if it still exists, else the icon for its type.
    static func small(path: String, size: CGFloat = 16) -> NSImage {
        let ws = NSWorkspace.shared
        let icon: NSImage
        if FileManager.default.fileExists(atPath: path) {
            icon = ws.icon(forFile: path)
        } else {
            let type = UTType(filenameExtension: (path as NSString).pathExtension) ?? .data
            icon = ws.icon(for: type)
        }
        let small = (icon.copy() as? NSImage) ?? icon
        small.size = NSSize(width: size, height: size)
        return small
    }
}
