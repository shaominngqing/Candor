import AppKit
@preconcurrency import QuickLookUI
import SwiftUI

enum CandorIcon {
    static let image: NSImage = {
        guard let url = Bundle.main.url(forResource: "CandorIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        else {
            return NSApplication.shared.applicationIconImage
        }
        return image
    }()
}

struct CandorAppIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: CandorIcon.image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct CleanupRiskBadge: View {
    let level: CleanupRiskLevel

    private var color: Color {
        switch level {
        case .disposable: .green
        case .regenerable: .teal
        case .reacquirable: .orange
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

struct AnalysisPendingView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

struct CleanupItemRow: View {
    @Binding var item: CleanupItem
    var isExcluded = false
    var onSelectionChange: ((Bool) -> Void)?
    var onToggleExclusion: (() -> Void)?

    private var selection: Binding<Bool> {
        Binding(
            get: { item.isSelected },
            set: { value in
                if let onSelectionChange {
                    onSelectionChange(value)
                } else {
                    item.isSelected = value
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: selection)
                .labelsHidden()
                .disabled(isExcluded)

            Image(systemName: item.category.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(riskColor(item.risk))
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
                    .lineLimit(1)
                Text(item.impact)
                    .font(.caption)
                    .foregroundStyle(item.risk >= .reacquirable ? .secondary : .tertiary)
                    .lineLimit(1)
                if let modifiedAt = item.modifiedAt {
                    Text("更新于 \(modifiedAt.shortChineseText)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 7) {
                Text(ByteFormatting.string(item.size))
                    .font(.callout.monospacedDigit())
                if isExcluded {
                    Label("已排除", systemImage: "minus.circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    CleanupRiskBadge(level: item.risk)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Menu {
                Button("快速预览") { QuickLookPreviewer.shared.preview(item.url) }
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                if let onToggleExclusion {
                    Divider()
                    Button(isExcluded ? "取消排除" : "始终排除此项目") {
                        onToggleExclusion()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func riskColor(_ risk: CleanupRiskLevel) -> Color {
        switch risk {
        case .disposable: .green
        case .regenerable: .teal
        case .reacquirable: .orange
        case .sensitive: .red
        }
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
