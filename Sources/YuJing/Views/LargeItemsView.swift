import AppKit
import SwiftUI

struct LargeItemsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "大项目",
                subtitle: "不只看单个文件，也展示隐藏目录、应用数据和由大量小文件组成的大文件夹。"
            )

            if state.isScanning && state.largeItemPath.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(state.scanPhase).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text("结果按大小持续更新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            browserToolbar

            if state.isScanningLargeItemFolder {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在计算下一层实际占用…").font(.headline)
                    Text("只分析你刚刚点开的文件夹。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.35)) }
            } else if state.currentLargeItems.isEmpty {
                EmptyStateView(
                    title: state.isScanning ? "正在发现大项目" : "这一层没有占用项目",
                    message: state.isScanning
                        ? "分析完成的目录会立即出现在这里。"
                        : "可以返回上一级，或切换其他分类。",
                    systemImage: "folder.badge.questionmark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.currentLargeItems) { item in
                            StorageItemRow(item: item)
                                .environmentObject(state)
                            Divider().padding(.leading, 50)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.35)) }
            }

            HStack {
                Label(
                    "已选 \(state.selectedLargeItems.count) 项 · 预计占用 \(ByteFormatting.string(state.selectedLargeItemBytes))",
                    systemImage: "checkmark.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingConfirmation = true
                } label: {
                    Label("移到废纸篓（\(ByteFormatting.string(state.selectedLargeItemBytes))）", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(state.selectedLargeItems.isEmpty || state.isCleaning)
            }
        }
        .padding(28)
        .alert("确认移动所选大项目？", isPresented: $showingConfirmation) {
            Button("取消", role: .cancel) {}
            Button("移动 \(state.selectedLargeItems.count) 项", role: .destructive) {
                state.cleanSelected(.largeItems)
            }
        } message: {
            Text("这些项目可能包含个人文件、项目或应用数据。请确认路径和说明；移动到废纸篓后仍可恢复。")
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            Button {
                state.navigateLargeItems(to: 0)
            } label: {
                Label("全部大项目", systemImage: "house")
            }
            .buttonStyle(.borderless)
            .font(.callout.weight(state.largeItemPath.isEmpty ? .semibold : .regular))

            ForEach(Array(state.largeItemPath.enumerated()), id: \.element.id) { index, item in
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button(item.name) { state.navigateLargeItems(to: index + 1) }
                    .buttonStyle(.borderless)
                    .font(.callout.weight(index == state.largeItemPath.count - 1 ? .semibold : .regular))
                    .lineLimit(1)
            }

            Spacer()

            if state.largeItemPath.isEmpty {
                Menu {
                    Button("全部大项目") {
                        state.selectedStorageCategory = nil
                        state.selectedStorageScene = nil
                    }
                    Section("通用分类") {
                        ForEach(StorageCategoryKind.allCases.filter { $0 != .unexplained }) { kind in
                            Button(kind.title) {
                                state.selectedStorageCategory = kind
                                state.selectedStorageScene = nil
                            }
                        }
                    }
                    if !state.prominentStorageScenes.isEmpty {
                        Section("本机场景") {
                            ForEach(state.prominentStorageScenes) { scene in
                                Button(scene.kind.title) {
                                    state.selectedStorageScene = scene.kind
                                    state.selectedStorageCategory = nil
                                }
                            }
                        }
                    }
                } label: {
                    Label(
                        state.selectedStorageScene?.title
                            ?? state.selectedStorageCategory?.title
                            ?? "全部大项目",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
            }

            Button("全选可处理项") { state.selectAllCurrentLargeItems() }
            Button("取消全选") { state.clearCurrentLargeItemSelection() }
        }
        .padding(.horizontal, 2)
    }
}

private struct StorageItemRow: View {
    @EnvironmentObject private var state: AppState
    let item: StorageItem

    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { state.isLargeItemSelected(item) },
                    set: { state.setLargeItem(item, selected: $0) }
                )
            )
            .labelsHidden()
            .disabled(!item.canClean)

            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(categoryColor(item.category))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Label(item.category.title, systemImage: item.category.systemImage)
                        .font(.caption2)
                        .foregroundStyle(categoryColor(item.category))
                    if let scene = item.scene {
                        Label(scene.title, systemImage: scene.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 6) {
                Text(ByteFormatting.string(item.size))
                    .font(.callout.monospacedDigit().weight(.semibold))
                if item.canClean {
                    SafetyBadge(level: item.safety)
                } else {
                    Label("仅查看", systemImage: "eye.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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

            if item.canOpen {
                Button {
                    state.enterLargeItem(item)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("分析下一层")
            } else {
                Color.clear.frame(width: 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func categoryColor(_ kind: StorageCategoryKind) -> Color {
        switch kind {
        case .applications: .blue
        case .appData: .purple
        case .personalFiles: .indigo
        case .cacheTemporary: .teal
        case .trash: .brown
        case .systemProtected: .secondary
        case .unexplained: .gray
        }
    }
}
