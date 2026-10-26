import AppKit
import SwiftUI

/// A row thumbnail: the real image preview for images and PDFs, else the Finder icon for the file or its type.
struct FileThumb: View {
    /// Where to look for a preview (the file now, or its copy in the Trash).
    let previewPath: String?
    /// Used for the Finder icon when there is no preview, even if the file is gone.
    let iconPath: String
    var size: CGFloat = 28

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            } else {
                Image(nsImage: FileIcon.small(path: iconPath))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .task(id: previewPath) {
            guard let previewPath else { return }
            image = await ImagePreview.thumbnail(of: URL(fileURLWithPath: previewPath), maxPixel: Int(size * 2))
        }
    }
}
