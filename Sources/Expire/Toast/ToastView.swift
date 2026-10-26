import AppKit
import SwiftUI

/// Hover state shared between the AppKit tracking area and the SwiftUI content.
@MainActor @Observable
final class ToastHover {
    var isHovered = false
}

struct ToastView: View {
    static let width: CGFloat = 360

    let model: ToastModel
    let hover: ToastHover
    let onKeep: () -> Void
    let onSecond: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.fileURL.path))
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.callout)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(model.secondLabel, action: onSecond)
                    Button(model.keepLabel, action: onKeep)
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: model.fileURL) ?? NSItemProvider() }
        .frame(width: Self.width)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            if hover.isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -5, y: -5)
                .help("Dismiss")
            }
        }
        .padding(6)
    }

    /// The filename prefix is bolded when the message starts with it.
    private var message: AttributedString {
        let name = model.fileURL.lastPathComponent
        guard model.message.hasPrefix(name) else { return AttributedString(model.message) }
        var bold = AttributedString(name)
        bold.inlinePresentationIntent = .stronglyEmphasized
        return bold + AttributedString(String(model.message.dropFirst(name.count)))
    }
}
