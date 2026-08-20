import AppKit
import SwiftUI

struct CleanupBasketView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmation = false

    var body: some View {
        let stagedItems = state.stagedCleanupItems
        let stagedBytes = stagedItems.reduce(0) { $0 + $1.size }
        let higherImpactCount = stagedItems.filter { $0.risk >= .reacquirable }.count
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("待清理篮")
                        .font(.title2.bold())
                    Text("项目仍在原位置，最后确认后才会统一移到废纸篓。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack {
                Label(
                    "已暂存 \(stagedItems.count) 项 · \(ByteFormatting.string(stagedBytes))",
                    systemImage: "basket.fill"
                )
                .font(.headline)
                Spacer()
                Button("取消所有选择") { state.clearStagedSelection() }
                    .disabled(stagedItems.isEmpty)
            }

            if stagedItems.isEmpty {
                EmptyStateView(
                    title: "待清理篮是空的",
                    message: "在应用卸载、清理建议或大文件与目录中勾选内容，它们会统一出现在这里。",
                    systemImage: "basket"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stagedItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.category.systemImage)
                                    .foregroundStyle(item.risk <= .regenerable ? Color.teal : Color.orange)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.displayName)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(item.url.path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                    Text(item.impact)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(ByteFormatting.string(item.size))
                                    .font(.callout.monospacedDigit())
                                CleanupRiskBadge(level: item.risk)
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
                                .help("在 Finder 中显示")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35))
                }
            }

            HStack {
                if higherImpactCount > 0 {
                    Label("包含 \(higherImpactCount) 个需要重新获取或可能含数据的项目", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("受保护路径会在执行前再次拦截", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingConfirmation = true
                } label: {
                    Label("移到废纸篓（\(ByteFormatting.string(stagedBytes))）", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(stagedItems.isEmpty || state.isCleaning)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 520)
        .alert("确认清理待清理篮？", isPresented: $showingConfirmation) {
            Button("取消", role: .cancel) {}
            Button(
                "移动 \(stagedItems.count) 项（\(ByteFormatting.string(stagedBytes))）",
                role: .destructive
            ) {
                state.cleanStagedItems()
                dismiss()
            }
        } message: {
            Text("这些项目占用 \(ByteFormatting.string(stagedBytes))，会统一移到废纸篓；清空废纸篓后空间才会真正释放。")
        }
    }
}
