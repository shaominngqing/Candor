import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingCleanupBasket = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "空间账本",
                    subtitle: "每一 GB 都有归属。先看清占用，再判断哪些能安全处理。"
                )

                if state.isScanning { scanBanner }

                storageSummary

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    MetricCard(
                        title: "已说明",
                        value: ByteFormatting.string(state.explainedBytes),
                        detail: state.isScanning ? "随分析持续增加" : "已归入明确用途",
                        systemImage: "checkmark.seal.fill",
                        color: .teal
                    )
                    MetricCard(
                        title: "可安全检查",
                        value: ByteFormatting.string(state.safeCandidateBytes),
                        detail: state.hasScannedSafeCleanup
                            ? "缓存与可再生成内容"
                            : "打开安全清理时按需检查",
                        systemImage: "sparkles",
                        color: .green
                    )
                    MetricCard(
                        title: "需要确认",
                        value: ByteFormatting.string(state.reviewCandidateBytes),
                        detail: "不会默认选择",
                        systemImage: "hand.raised.fill",
                        color: .orange
                    )
                    MetricCard(
                        title: "尚未说明",
                        value: ByteFormatting.string(state.unexplainedBytes),
                        detail: state.ledgerInaccessibleCount > 0
                            ? "含 \(state.ledgerInaccessibleCount) 处无权限读取"
                            : "正在分析或系统未能归因",
                        systemImage: "questionmark.folder.fill",
                        color: .gray
                    )
                }

                if !state.prominentStorageScenes.isEmpty {
                    sceneSection
                }

                HStack(alignment: .top, spacing: 14) {
                    categoryLedger
                        .frame(maxWidth: .infinity)
                    actionColumn
                        .frame(width: 300)
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showingCleanupBasket) {
            CleanupBasketView().environmentObject(state)
        }
    }

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text("这台 Mac 的主要使用场景").font(.headline)
                Text("根据实际文件自动识别；只有占用明显的场景才会出现")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(state.prominentStorageScenes) { scene in
                    Button { state.showStorageScene(scene.kind) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(sceneColor(scene.kind).opacity(0.13))
                                Image(systemName: scene.kind.systemImage)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(sceneColor(scene.kind))
                            }
                            .frame(width: 42, height: 42)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(scene.kind.title).font(.callout.weight(.semibold))
                                Text(scene.kind.explanation)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(ByteFormatting.string(scene.size))
                                    .font(.callout.monospacedDigit().weight(.semibold))
                                Text("\(scene.sourceCount) 个来源")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.background, in: RoundedRectangle(cornerRadius: 15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(.separator.opacity(0.35))
                    }
                }
            }
        }
    }

    private var scanBanner: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(state.scanPhase)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if state.totalLedgerSources > 0 {
                    Text("\(Int(state.ledgerProgressFraction * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: state.ledgerProgressFraction)
                .tint(.teal)
            Text(state.isDeepScanning
                 ? "深度校准会重新遍历全部来源，用于修正长期缓存的账本。"
                 : "优先复用未变化的 \(state.reusedLedgerSources) 个来源，仅递归更新 \(state.rescannedLedgerSources) 个来源。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac 磁盘").font(.headline)
                    Text("已使用 \(ByteFormatting.string(state.storage.used)) / \(ByteFormatting.string(state.storage.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("剩余 \(ByteFormatting.string(state.storage.available))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(state.storageCategories.filter { $0.size > 0 }) { category in
                        Rectangle()
                            .fill(categoryColor(category.kind))
                            .frame(width: segmentWidth(category.size, totalWidth: geometry.size.width))
                            .help("\(category.kind.title)：\(ByteFormatting.string(category.size))")
                    }
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: segmentWidth(state.storage.available, totalWidth: geometry.size.width))
                        .help("剩余：\(ByteFormatting.string(state.storage.available))")
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            HStack(spacing: 14) {
                Label("已读取 \(state.ledgerScannedItemCount) 个文件项目", systemImage: "doc.text.magnifyingglass")
                if state.ledgerInaccessibleCount > 0 {
                    Label("\(state.ledgerInaccessibleCount) 处无法访问", systemImage: "lock.fill")
                }
                Spacer()
                if let updatedAt = state.lastLedgerUpdatedAt {
                    Text("账本更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("分类总量与剩余空间共用同一份账本")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }

    private var categoryLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("空间都去了哪里").font(.headline)
                    Text("按占用从大到小；点击可查看对应大项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("占用 / 清理候选")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            ForEach(state.storageCategories) { category in
                Button {
                    if category.kind == .unexplained {
                        if !state.isScanning { state.refreshAll() }
                    } else {
                        state.showStorageCategory(category.kind)
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(categoryColor(category.kind).opacity(0.12))
                            Image(systemName: category.kind.systemImage)
                                .foregroundStyle(categoryColor(category.kind))
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(category.kind.title).font(.callout.weight(.semibold))
                                if !category.isComplete {
                                    Text("分析中")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.teal)
                                }
                            }
                            Text(category.kind.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(ByteFormatting.string(category.size))
                                .font(.callout.monospacedDigit().weight(.semibold))
                            if category.cleanupCandidateSize > 0 {
                                Text("候选 \(ByteFormatting.string(category.cleanupCandidateSize))")
                                    .font(.caption)
                                    .foregroundStyle(.teal)
                            } else {
                                Text(category.kind == .unexplained ? "继续分析" : "\(category.sourceCount) 个来源")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: category.kind == .unexplained ? "arrow.clockwise" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(category.kind == .unexplained && state.isScanning)
                Divider().padding(.leading, 68)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }

    private var actionColumn: some View {
        VStack(spacing: 14) {
            actionCard(
                title: "安全清理",
                value: ByteFormatting.string(state.safeCleanupTotal),
                detail: "缓存、临时文件和残留候选",
                icon: "checkmark.shield.fill",
                color: .teal,
                destination: .safeCleanup
            )
            actionCard(
                title: "大项目",
                value: "\(state.ledgerLargeItems.count) 项",
                detail: "包含文件夹、隐藏目录和开发环境",
                icon: "list.bullet.rectangle.portrait",
                color: .indigo,
                destination: .largeItems
            )

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: state.stagedCleanupItems.isEmpty ? "basket" : "basket.fill")
                        .foregroundStyle(.orange)
                    Text("待清理篮").font(.headline)
                    Spacer()
                }
                Text(ByteFormatting.string(state.stagedCleanupBytes))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(state.stagedCleanupItems.isEmpty
                     ? "勾选内容后先放到这里统一复核。"
                     : "已暂存 \(state.stagedCleanupItems.count) 项，文件尚未移动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("统一核对") { showingCleanupBasket = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                    .disabled(state.stagedCleanupItems.isEmpty)
            }
            .padding(17)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.35)) }
        }
    }

    private func actionCard(
        title: String,
        value: String,
        detail: String,
        icon: String,
        color: Color,
        destination: SidebarSection
    ) -> some View {
        Button { state.selectedSection = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(value).font(.callout.monospacedDigit().weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.35)) }
    }

    private func segmentWidth(_ bytes: Int64, totalWidth: CGFloat) -> CGFloat {
        let categoryBytes = state.storageCategories.reduce(Int64(0)) { $0 + $1.size }
        let visualTotal = max(state.storage.total, categoryBytes + state.storage.available, 1)
        return totalWidth * CGFloat(Double(max(bytes, 0)) / Double(visualTotal))
    }

    private func categoryColor(_ kind: StorageCategoryKind) -> Color {
        switch kind {
        case .applications: .blue
        case .appData: .purple
        case .personalFiles: .indigo
        case .cacheTemporary: .teal
        case .trash: .brown
        case .systemProtected: .secondary
        case .unexplained: .gray.opacity(0.55)
        }
    }

    private func sceneColor(_ kind: StorageSceneKind) -> Color {
        switch kind {
        case .photosVideos: .pink
        case .downloadsInstallers: .blue
        case .communication: .cyan
        case .cloudOffline: .mint
        case .games: .purple
        case .virtualMachines: .orange
        case .creativeWork: .indigo
        case .developer: .orange
        case .aiModels: .green
        case .deviceBackups: .teal
        }
    }
}
