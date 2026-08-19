import AppKit
@preconcurrency import QuickLookUI
import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }
}

struct ApplicationIcon: View {
    let url: URL
    var size: CGFloat = 38

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct SafetyBadge: View {
    let level: SafetyLevel

    private var color: Color {
        switch level {
        case .safe: .green
        case .review: .orange
        case .sensitive: .red
        }
    }

    var body: some View {
        Label(level.title, systemImage: level.symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct CleanupItemsPanel: View {
    @Binding var items: [CleanupItem]
    let emptyTitle: String
    let emptyMessage: String

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: emptyTitle, message: emptyMessage, systemImage: "checkmark.circle")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($items) { $item in
                        CleanupItemRow(item: $item)
                        Divider().padding(.leading, 48)
                    }
                }
                .padding(.horizontal, 4)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.separator.opacity(0.35))
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

private struct CleanupItemRow: View {
    @Binding var item: CleanupItem

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $item.isSelected)
                .labelsHidden()

            Image(systemName: item.category.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(item.safety == .safe ? Color.teal : Color.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(item.category.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let modifiedAt = item.modifiedAt {
                    Text("最近更新：\(modifiedAt.shortChineseText)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 7) {
                Text(ByteFormatting.string(item.size))
                    .font(.callout.monospacedDigit())
                SafetyBadge(level: item.safety)
            }
            .fixedSize(horizontal: true, vertical: false)

            Button {
                QuickLookPreviewer.shared.preview(item.url)
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help("快速预览")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中查看")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

final class QuickLookPreviewer: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewer()

    private var previewURL: URL?

    func preview(_ url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}

struct SelectionSummary: View {
    let items: [CleanupItem]

    private var selected: [CleanupItem] { items.filter(\.isSelected) }

    var body: some View {
        HStack(spacing: 8) {
            Text("已选 \(selected.count) 项")
            Text("·").foregroundStyle(.tertiary)
            Text("已选占用 \(ByteFormatting.string(selected.reduce(0) { $0 + $1.size }))")
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
