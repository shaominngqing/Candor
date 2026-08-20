import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingUnexplainedDetails = false

    private var isStorageDataReady: Bool { state.storageDataState.isReady }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("存储")
                    .font(.system(size: 28, weight: .bold))

                if state.isScanning { scanProgress }
                storageSummary
                classificationSummary
                categoryList
            }
            .padding(28)
        }
        .sheet(isPresented: $showingUnexplainedDetails) {
            UnexplainedStorageView().environmentObject(state)
        }
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(state.scanPhase)
                    .lineLimit(1)
                Spacer()
                if state.totalLedgerSources > 0 {
                    Text("\(Int(state.ledgerProgressFraction * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: state.ledgerProgressFraction)

            if !state.isDeepScanning,
               state.reusedLedgerSources > 0 || state.rescannedLedgerSources > 0 {
                Text("复用 \(state.reusedLedgerSources) · 更新 \(state.rescannedLedgerSources)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var storageSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("已用 \(ByteFormatting.string(state.storage.used)) / \(ByteFormatting.string(state.storage.total))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("可用 \(ByteFormatting.string(state.storage.available))")
                        .font(.headline.monospacedDigit())
                }

                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        if isStorageDataReady {
                            ForEach(state.storageCategories.filter { $0.size > 0 }) { category in
                                Rectangle()
                                    .fill(categoryColor(category.kind))
                                    .frame(width: segmentWidth(category.size, totalWidth: geometry.size.width))
                                    .help("\(category.kind.title)：\(ByteFormatting.string(category.size))")
                            }
                        } else {
                            Rectangle()
                                .fill(.secondary.opacity(0.35))
                                .frame(width: segmentWidth(state.storage.used, totalWidth: geometry.size.width))
                                .help("已用空间正在分类")
                        }
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: segmentWidth(state.storage.available, totalWidth: geometry.size.width))
                            .help("可用：\(ByteFormatting.string(state.storage.available))")
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)

                Divider()

                HStack(spacing: 14) {
                    if isStorageDataReady {
                        Label(
                            "\(state.ledgerScannedItemCount.formatted(.number.notation(.compactName))) 个项目",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    } else {
                        Label(
                            state.storageDataState == .analyzing ? "正在统计项目" : "尚未分析项目",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                    if state.ledgerInaccessibleCount > 0 {
                        Button {
                            showingUnexplainedDetails = true
                        } label: {
                            Label("\(state.ledgerInaccessibleCount) 处无法访问", systemImage: "lock")
                        }
                        .buttonStyle(.link)
                    }
                    Spacer()
                    if let updatedAt = state.lastLedgerUpdatedAt {
                        Text("更新 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            Text("Mac 磁盘")
        }
    }

    private var classificationSummary: some View {
        HStack(spacing: 12) {
            metric(
                title: "已分类",
                value: isStorageDataReady ? ByteFormatting.string(state.explainedBytes) : "—",
                detail: storageMetricDetail
            )

            Button {
                showingUnexplainedDetails = true
            } label: {
                metric(
                    title: "未归类",
                    value: isStorageDataReady ? ByteFormatting.string(state.unexplainedBytes) : "—",
                    detail: !isStorageDataReady
                        ? storageMetricDetail
                        : state.ledgerInaccessibleCount > 0
                        ? "\(state.ledgerInaccessibleCount) 处无法访问"
                        : "查看权限与系统差额",
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)
            .disabled(!isStorageDataReady)

            Button {
                state.selectedSection = .safeCleanup
            } label: {
                metric(
                    title: "清理建议",
                    value: cleanupMetricValue,
                    detail: cleanupMetricDetail,
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func metric(
        title: String,
        value: String,
        detail: String,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4))
        }
        .contentShape(Rectangle())
    }

    private var cleanupMetricValue: String {
        guard state.cleanupDataState.isReady else {
            return state.cleanupDataState == .analyzing ? "分析中" : "未检查"
        }
        return ByteFormatting.string(state.safeCandidateBytes)
    }

    private var cleanupMetricDetail: String {
        if !state.cleanupDataState.isReady {
            return state.cleanupDataState == .analyzing ? "正在建立分级建议" : "存储分析后自动检查"
        }
        if state.reviewCandidateBytes > 0 {
            return "另有 \(ByteFormatting.string(state.reviewCandidateBytes)) 需核对"
        }
        return state.safeCandidateBytes > 0 ? "推荐力度" : "当前没有推荐项目"
    }

    private var categoryList: some View {
        GroupBox {
            if isStorageDataReady {
                VStack(spacing: 0) {
                    ForEach(Array(state.storageCategories.enumerated()), id: \.element.id) { index, category in
                        Button {
                            if category.kind == .unexplained {
                                showingUnexplainedDetails = true
                            } else {
                                state.showStorageCategory(category.kind)
                            }
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: category.kind.systemImage)
                                    .foregroundStyle(categoryColor(category.kind))
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(category.kind.title)
                                            .font(.callout.weight(.medium))
                                        if !category.isComplete {
                                            Text("分析中")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(categoryDetail(category))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(ByteFormatting.string(category.size))
                                        .monospacedDigit()
                                    cleanupDetail(category)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < state.storageCategories.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 6)
            } else if state.storageDataState == .analyzing {
                AnalysisPendingView(
                    title: "正在整理空间分类",
                    message: "已完成的来源会陆续归入应用、个人文件、缓存和系统文件。"
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                EmptyStateView(
                    title: "尚未完成空间分析",
                    message: "运行一次磁盘分析后，这里会显示各类文件的实际占用。",
                    systemImage: "internaldrive"
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        } label: {
            Text("分类")
        }
    }

    private var storageMetricDetail: String {
        switch state.storageDataState {
        case .ready: state.isScanning ? "正在更新" : "已归入明确类别"
        case .analyzing: "正在分类"
        case .waiting: "等待磁盘分析"
        }
    }

    private func categoryDetail(_ category: StorageCategory) -> String {
        if category.kind == .unexplained {
            return "权限、APFS 或扫描差额"
        }
        return "\(category.sourceCount) 个来源"
    }

    @ViewBuilder
    private func cleanupDetail(_ category: StorageCategory) -> some View {
        if category.recommendedCleanupSize > 0 || category.reviewCleanupSize > 0 {
            HStack(spacing: 6) {
                if category.recommendedCleanupSize > 0 {
                    Text("建议 \(ByteFormatting.string(category.recommendedCleanupSize))")
                        .foregroundStyle(.green)
                }
                if category.reviewCleanupSize > 0 {
                    Text("另有 \(ByteFormatting.string(category.reviewCleanupSize))")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
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
        case .unexplained: .gray
        }
    }
}

private struct UnexplainedStorageView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("未归类空间")
                        .font(.title2.bold())
                    Text(ByteFormatting.string(state.unexplainedBytes))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            GroupBox("可能原因") {
                VStack(alignment: .leading, spacing: 12) {
                    reasonRow(
                        icon: "lock",
                        title: "访问受限",
                        detail: state.ledgerInaccessibleCount > 0
                            ? "\(state.ledgerInaccessibleCount) 处无法读取，无法统计内部大小。"
                            : "当前没有记录到明确的权限错误。"
                    )
                    Divider()
                    reasonRow(
                        icon: "externaldrive",
                        title: "APFS 动态空间",
                        detail: "包括本地快照、共享数据、可清除空间和文件系统元数据。"
                    )
                    if state.isScanning {
                        Divider()
                        reasonRow(
                            icon: "clock",
                            title: "分析中",
                            detail: "已读取的数据会继续归入对应分类。"
                        )
                    }
                }
                .padding(.top, 4)
            }

            Label("未归类空间不会被自动列为清理项", systemImage: "shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                if state.isLimitedAccess {
                    Button("检查完全磁盘访问权限…") { state.showAccessSetup() }
                }
                Spacer()
                Button("快速更新") {
                    dismiss()
                    state.refreshAll()
                }
                .disabled(state.isScanning)
                Button("深度校准…") {
                    dismiss()
                    state.refreshAll(forceDeep: true)
                }
                .disabled(state.isScanning)
            }
        }
        .padding(24)
        .frame(width: 540, height: 400)
    }

    private func reasonRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
