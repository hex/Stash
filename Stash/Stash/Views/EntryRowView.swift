// ABOUTME: Displays a single clipboard entry as a row with content preview and metadata.
// ABOUTME: Shows content type icon, truncated text, source app, and timestamp.

import SwiftUI

struct EntryRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .lineLimit(2)
                    .font(.body)

                HStack(spacing: 4) {
                    if let appName = entry.sourceAppName {
                        Text(appName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
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
