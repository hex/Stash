// ABOUTME: Displays a single clipboard entry as a row with content preview and metadata.
// ABOUTME: Shows colored content type badge, truncated text, source app, and timestamp.

import SwiftUI

struct EntryRowView: View {
    let entry: ClipboardEntry

    var body: some View {
        HStack(spacing: 10) {
            iconBadge

            VStack(alignment: .leading, spacing: 3) {
                contentPreview

                HStack(spacing: 6) {
                    if let appName = entry.sourceAppName {
                        Text(appName)
                            .foregroundStyle(.secondary)
                    }
                    Text(friendlyTimestamp)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }

            Spacer(minLength: 4)

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Icon Badge

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(badgeColor)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: iconName)
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .medium))
            }
    }

    private var badgeColor: Color {
        switch entry.contentType {
        case .plainText, .richText: .gray
        case .image: .purple
        case .url: .blue
        case .fileURL: .yellow
        }
    }

    private var iconName: String {
        switch entry.contentType {
        case .plainText, .richText: "text.alignleft"
        case .image: "photo"
        case .url: "link"
        case .fileURL: "doc"
        }
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        switch entry.contentType {
        case .image:
            Text(imageDimensionText)
                .lineLimit(1)
                .font(.body.weight(.medium))
                .foregroundStyle(.purple)
        default:
            Text(previewText)
                .lineLimit(2)
                .font(.body.weight(.medium))
        }
    }

    private var imageDimensionText: String {
        guard let data = entry.imageData,
              let rep = NSBitmapImageRep(data: data) else {
            return "Image"
        }
        return "Image \(rep.pixelsWide)x\(rep.pixelsHigh)"
    }

    private var previewText: String {
        switch entry.contentType {
        case .image:
            return imageDimensionText
        case .fileURL:
            if let paths = entry.filePaths {
                let home = FileManager.default.homeDirectoryForCurrentUser.path()
                return paths.map { path in
                    if path.hasPrefix(home) {
                        return "~" + path.dropFirst(home.count)
                    }
                    return path
                }.joined(separator: ", ")
            }
            return entry.plainText ?? "[File]"
        default:
            return entry.plainText ?? ""
        }
    }

    // MARK: - Timestamp

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
}
