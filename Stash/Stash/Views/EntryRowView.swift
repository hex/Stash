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
                Text(previewText)
                    .lineLimit(2)
                    .font(.body.weight(.medium))

                HStack(spacing: 0) {
                    if let appName = entry.sourceAppName {
                        Text(appName)
                            .foregroundStyle(.secondary)
                        Text(" \u{00B7} ")
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.timestamp, style: .relative)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }

            Spacer(minLength: 4)

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
