import AppKit
import SwiftUI

/// Hover state shared between the AppKit tracking area and the SwiftUI content.
@MainActor @Observable
final class ToastHover {
    var isHovered = false
}

/// Laid out to match a macOS alert-style notification. Measured from a Tahoe screenshot (2x):
/// 344 x 72 pt card, ~20 pt corners, 32 pt icon 13 pt from the edge, text 13 pt (title semibold, body
/// regular, 16 pt line pitch) starting 58 pt in, timestamp right-aligned.
struct ToastView: View {
    static let width: CGFloat = 344
    static let radius: CGFloat = 20
    static let actionWidth: CGFloat = 78

    let model: ToastModel
    let hover: ToastHover
    let onKeep: () -> Void
    let onSecond: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: model.fileURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text("now")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Text(bodyText)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(contentsOf: model.fileURL) ?? NSItemProvider() }

            // Alert-style action column: two flat cells split by hairlines.
            Rectangle().fill(.separator).frame(width: 0.5)
            VStack(spacing: 0) {
                actionCell(model.keepLabel, onKeep)
                Rectangle().fill(.separator).frame(height: 0.5)
                actionCell(model.secondLabel, onSecond)
            }
            .frame(width: Self.actionWidth)
        }
        .frame(width: Self.width)
        .frame(minHeight: 60)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.radius))
        .overlay(alignment: .topLeading) {
            if hover.isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.separator))
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .help("Dismiss")
            }
        }
        .padding(8)
    }

    private func actionCell(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToastActionStyle())
    }

    private var title: String { model.fileURL.lastPathComponent }

    /// "will be trashed after 14 days" shown as a sentence under the filename title.
    private var bodyText: String {
        guard model.message.hasPrefix(title) else { return model.message }
        let rest = model.message.dropFirst(title.count).trimmingCharacters(in: .whitespaces)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }
}

private struct ToastActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : .clear)
    }
}
