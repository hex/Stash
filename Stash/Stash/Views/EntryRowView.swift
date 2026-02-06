// ABOUTME: Displays a single clipboard entry as a row with content preview and metadata.
// ABOUTME: Shows content type icon, truncated text, source app, and timestamp.

import SwiftUI

struct EntryRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                contentPreview

                HStack(spacing: 0) {
                    if let appName = entry.sourceAppName {
                        Text(appName)
                            .foregroundStyle(.secondary)
                        Text(" \u{00B7} ")
                            .foregroundStyle(.tertiary)
                    }
                    Text(friendlyTimestamp)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }

            Spacer(minLength: 4)

            if entry.contentType == .image, entry.imageData != nil {
                Button {
                    previewImage()
                } label: {
                    Image(systemName: "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preview image")
            }

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var contentPreview: some View {
        if entry.contentType == .image, let data = entry.imageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 48)
                .cornerRadius(4)
        } else {
            Text(previewText)
                .lineLimit(2)
                .font(.body.weight(.medium))
        }
    }

    private var iconName: String {
        switch entry.contentType {
        case .plainText: "doc.text"
        case .richText: "doc.richtext"
        case .image: "photo"
        case .fileURL: "doc"
        case .url: "link"
        }
    }

    private func previewImage() {
        guard let data = entry.imageData else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stash-preview.png")
        try? data.write(to: url)
        NSWorkspace.shared.open(url)
    }

    private var friendlyTimestamp: String {
        let now = Date()
        let seconds = now.timeIntervalSince(entry.timestamp)

        if seconds < 60 { return "Just now" }
        if seconds < 3600 {
            let mins = Int(seconds / 60)
            return "\(mins)m ago"
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        }
        if seconds < 172800 { return "Yesterday" }
        if seconds < 604800 {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: entry.timestamp)
    }

    private var previewText: String {
        switch entry.contentType {
        case .image:
            return "[Image]"
        case .fileURL:
            if let paths = entry.filePaths {
                return paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            }
            return entry.plainText ?? "[File]"
        default:
            return entry.plainText ?? ""
        }
    }
}
