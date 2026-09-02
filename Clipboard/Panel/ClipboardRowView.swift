import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onPaste) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        .frame(width: 18, height: 22)

                    Text(item.content)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .textSelection(.disabled)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovering || isSelected || item.isPinned {
                HStack(spacing: 2) {
                    rowButton(item.isPinned ? "pin.fill" : "pin", help: item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
                    rowButton("trash", help: "Delete", action: onDelete)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.white.opacity(isHovering ? 0.08 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.16 : 0.07), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Paste", action: onPaste)
            Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .secondary)
        .help(help)
    }
}
