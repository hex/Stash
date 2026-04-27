// ABOUTME: Single clipboard entry row — Native + Quiet plus typographic content-type differentiation.
// ABOUTME: Leading icon/thumbnail column, mono fonts for URLs and file paths, topmost-elevation accent.

import SwiftUI

struct EntryRowView: View {
    struct Action {
        let label: String
        let systemImage: String
        let perform: () -> Void
    }

    let entry: ClipboardEntry
    let isTopmost: Bool
    let isHovered: Bool
    let isCopied: Bool
    let action: Action?

    @State private var buttonHovered = false
    @State private var cachedThumbnail: NSImage?

    var body: some View {
        rowContent
            .opacity(isCopied ? 0 : 1)
            .overlay {
                if isCopied {
                    copiedAffirmation
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if entry.isPinned && !isHovered {
                    pinnedIndicator
                } else {
                    actionButton
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill)
            )
            .task(id: entry.persistentModelID) {
                await loadThumbnail()
            }
    }

    private func loadThumbnail() async {
        guard entry.contentType == .image, let data = entry.imageData else {
            cachedThumbnail = nil
            return
        }
        let thumb = await Task.detached(priority: .userInitiated) {
            Self.makeThumbnail(from: data, maxPixelSize: 224)
        }.value
        cachedThumbnail = thumb
    }

    private nonisolated static func makeThumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
    }

    private var rowFill: Color {
        if isCopied  { return .green.opacity(0.10) }
        if isHovered { return .primary.opacity(0.06) }
        if isTopmost { return .primary.opacity(0.035) }
        return .clear
    }

    // MARK: - Copied affirmation

    private var copiedAffirmation: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Copied")
                .font(.body.weight(.medium))
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Row content

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingIcon

            VStack(alignment: .leading, spacing: 3) {
                contentPreview
                metadataRow
            }

            Spacer(minLength: 0)

            if entry.contentType == .image, let cachedThumbnail {
                Image(nsImage: cachedThumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(.trailing, 4)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let action {
            let visible = isHovered && !isCopied
            Button(action: action.perform) {
                Label(action.label, systemImage: action.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: Capsule())
                    .brightness(buttonHovered ? 0.08 : 0)
                    .scaleEffect(buttonHovered ? 1.03 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { buttonHovered = $0 }
            .padding(.trailing, 12)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.10), value: buttonHovered)
            .allowsHitTesting(visible)
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        let (color, icon) = badgeStyle
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
    }

    private var badgeStyle: (Color, String) {
        switch entry.contentType {
        case .image:       return (Color(red: 0.545, green: 0.435, blue: 0.980), "photo")           // #8B6FFA purple
        case .url:         return (Color(red: 0.361, green: 0.545, blue: 0.980), "link")            // #5C8BFA blue
        case .fileURL:     return (Color(red: 0.910, green: 0.725, blue: 0.275), "doc")             // #E8B946 yellow
        case .plainText, .richText:
            return (Color(red: 0.235, green: 0.255, blue: 0.314), "text.alignleft")                  // #3C4150 dark slate
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch entry.contentType {
        case .image:
            Text(imageDescription)
                .font(.body)
                .foregroundStyle(Color(red: 0.545, green: 0.435, blue: 0.980)) // purple, matches badge
                .lineLimit(1)
        case .url:
            Text(displayText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .fileURL:
            Text(displayText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        default:
            Text(displayText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let appName = entry.sourceAppName {
                Text(appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(relativeTimestamp)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var pinnedIndicator: some View {
        if entry.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 14))
                .rotationEffect(.degrees(35))
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42)) // #FF6B6B coral red
                .padding(.trailing, 12)
        }
    }

    // MARK: - Content helpers

    private var imageDescription: String {
        guard let data = entry.imageData,
              let rep = NSBitmapImageRep(data: data) else {
            return "Image"
        }
        return "\(rep.pixelsWide)×\(rep.pixelsHigh) image"
    }

    private var displayText: String {
        let text = previewText
        return text.isEmpty ? "[empty]" : text
    }

    private var previewText: String {
        switch entry.contentType {
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

    private var relativeTimestamp: String {
        let seconds = Date().timeIntervalSince(entry.timestamp)
        if seconds < 60        { return "just now" }
        if seconds < 3600      { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400     { return "\(Int(seconds / 3600))h ago" }
        if seconds < 172800    { return "yesterday" }
        if seconds < 604800    { return "\(Int(seconds / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: entry.timestamp)
    }
}
