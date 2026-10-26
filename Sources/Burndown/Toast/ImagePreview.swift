import AppKit
import ImageIO
import PDFKit

enum ImagePreview {
    /// Small decoded thumbnail of an image or the first page of a PDF, made in memory. Nil for anything else.
    static func thumbnail(of url: URL, maxPixel: Int = 96) async -> NSImage? {
        await Task.detached(priority: .utility) {
            if url.pathExtension.lowercased() == "pdf" {
                guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
                return page.thumbnail(of: NSSize(width: maxPixel, height: maxPixel), for: .mediaBox)
            }
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}
