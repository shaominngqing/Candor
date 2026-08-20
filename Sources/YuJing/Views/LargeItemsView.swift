import AppKit
import SwiftUI

struct LargeItemsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingConfirmation = false
    @State private var selectedRisk: CleanupRiskLevel?
    @State private var onlyCleanable = false

    private var visibleItems: [StorageItem] {
        state.currentLargeItems.filter { item in
            if let selectedRisk, item.risk != selectedRisk { return false }
            if onlyCleanable && !item.canClean { return false }
            return true
        }
    }

    private var managedAncestor: (depth: Int, item: StorageItem)? {
        for (index, item) in state.largeItemPath.enumerated().reversed()
            where item.action == .removeAsUnit {
            return (index + 1, item)
        }
        return nil
    }

    private var isRootAnalysisPending: Bool {
        state.largeItemPath.isEmpty && !state.storageDataState.isReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "大文件与目录",
                subtitle: "按实际占用从大到小排列；打开目录后再分析下一层。"
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
                    Text("正在读取这一层…").font(.headline)
                    Text("优先使用空间账本；只有索引缺失的小目录才会补算。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.35)) }
            } else if visibleItems.isEmpty {
                EmptyStateView(
                    title: largeItemsEmptyTitle,
                    message: largeItemsEmptyMessage,
                    systemImage: isRootAnalysisPending ? "externaldrive.badge.timemachine" : "folder.badge.questionmark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleItems) { item in
                    StorageItemRow(item: item)
                        .environmentObject(state)
                        .contextMenu {
                            if item.canOpen {
                                Button("查看下一层") { state.enterLargeItem(item) }
                            }
                            Button("快速预览") { QuickLookPreviewer.shared.preview(item.url) }
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                    }
                .listStyle(.inset)
            }

            HStack {
                Group {
                    if isRootAnalysisPending && state.selectedLargeItems.isEmpty {
                        HStack(spacing: 8) {
                            if state.storageDataState == .analyzing {
                                ProgressView().controlSize(.small)
                            }
                            Text(state.storageDataState == .analyzing
                                ? "正在分析大文件与目录"
                                : "完成空间分析后可选择项目")
                        }
                    } else {
                        Label(
                            "已选 \(state.selectedLargeItems.count) 项 · 清空废纸篓后可释放 \(ByteFormatting.string(state.selectedLargeItemBytes))",
                            systemImage: "checkmark.circle"
                        )
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingConfirmation = true
                } label: {
                    if isRootAnalysisPending && state.selectedLargeItems.isEmpty {
                        Text("分析完成后可处理")
                    } else {
                        Label("移到废纸篓（\(ByteFormatting.string(state.selectedLargeItemBytes))）", systemImage: "trash")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRootAnalysisPending || state.selectedLargeItems.isEmpty || state.isCleaning)
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

            if let managedAncestor,
               managedAncestor.depth < state.largeItemPath.count {
                Button {
                    state.navigateLargeItems(to: managedAncestor.depth)
                } label: {
                    Label(
                        "返回 \(managedAncestor.item.name) 整体处理",
                        systemImage: "arrow.uturn.backward"
                    )
                }
                .help(managedAncestor.item.actionReason ?? "返回完整组件")
            }

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

            Menu {
                Button("全部等级") { selectedRisk = nil }
                Divider()
                ForEach(availableRisks, id: \.rawValue) { risk in
                    Button(risk.title) { selectedRisk = risk }
                }
                Divider()
                Toggle("只看可处理项目", isOn: $onlyCleanable)
            } label: {
                Label(selectedRisk?.title ?? (onlyCleanable ? "可处理" : "全部等级"), systemImage: "slider.horizontal.3")
            }

            Button("选择当前可处理项") {
                for item in visibleItems
                    where item.action == .selectable && item.risk < .sensitive {
                    state.setLargeItem(item, selected: true)
                }
            }
                .disabled(!visibleItems.contains {
                    $0.action == .selectable && $0.risk < .sensitive
                })
            Button("取消选择") { state.clearCurrentLargeItemSelection() }
                .disabled(state.selectedLargeItems.isEmpty)
        }
        .padding(.horizontal, 2)
    }

    private var availableRisks: [CleanupRiskLevel] {
        Array(Set(state.currentLargeItems.map(\.risk))).sorted()
    }

    private var largeItemsEmptyTitle: String {
        if state.storageDataState == .analyzing { return "正在发现大项目" }
        if state.storageDataState == .waiting { return "尚未完成空间分析" }
        return "没有符合条件的项目"
    }

    private var largeItemsEmptyMessage: String {
        if state.storageDataState == .analyzing {
            return "分析完成的目录会立即出现在这里。"
        }
        if state.storageDataState == .waiting {
            return "运行磁盘分析后，这里会按占用从大到小显示文件和目录。"
        }
        return "可以返回上一级，或更改分类和等级筛选。"
    }
}

private struct StorageItemRow: View {
    @EnvironmentObject private var state: AppState
    let item: StorageItem

    var body: some View {
        HStack(spacing: 12) {
            if item.canClean {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { state.isLargeItemSelected(item) },
                        set: { state.setLargeItem(item, selected: $0) }
                    )
                )
                .labelsHidden()
            } else {
                Image(systemName: item.action.symbol)
                    .foregroundStyle(actionColor(item.action))
                    .frame(width: 14)
                    .help(item.actionReason ?? item.action.title)
            }

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
                    if item.action == .removeAsUnit {
                        Label(item.action.title, systemImage: item.action.symbol)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
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
                if let actionReason = item.actionReason {
                    Text(actionReason)
                        .font(.caption)
                        .foregroundStyle(item.action == .partOfManagedUnit ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 6) {
                Text(ByteFormatting.string(item.size))
                    .font(.callout.monospacedDigit().weight(.semibold))
                if item.canClean {
                    CleanupRiskBadge(level: item.risk)
                } else {
                    Label(item.action.title, systemImage: item.action.symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(actionColor(item.action))
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 8) {
                if item.canOpen {
                    Button {
                        state.enterLargeItem(item)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("查看下一层")
                } else {
                    Color.clear.frame(width: 22, height: 24)
                }

                Menu {
                    Button("快速预览") { QuickLookPreviewer.shared.preview(item.url) }
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("预览或在 Finder 中显示")
            }
            .fixedSize()
            .padding(.leading, 6)
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

    private func actionColor(_ action: StorageItemAction) -> Color {
        switch action {
        case .removeAsUnit, .partOfManagedUnit: .orange
        case .manageInApp, .applicationUninstall: .blue
        case .trash: .brown
        case .systemProtected: .secondary
        case .inspectDeeper, .unavailable, .selectable: .secondary
        }
    }
}
