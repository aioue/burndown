import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ImagePreview {
    /// Small decoded thumbnail of an image or the first page of a PDF, made in memory. Nil for anything else.
    static func thumbnail(of url: URL, maxPixel: Int = 96) async -> NSImage? {
        // Only open files that can have a preview, so a big archive or video is never read for nothing.
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
              type.conforms(to: .image) || type.conforms(to: .pdf)
        else { return nil }
        return await Task.detached(priority: .utility) {
            if url.pathExtension.lowercased() == "pdf" {
                // Keep the document alive while the page renders; a page alone is not enough.
                guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
                let image = page.thumbnail(of: NSSize(width: maxPixel, height: maxPixel), for: .mediaBox)
                withExtendedLifetime(doc) {}
                return image
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
