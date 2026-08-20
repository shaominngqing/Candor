import SwiftUI

struct SafeCleanupView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingConfirmation = false
    @State private var selectedCategory: CleanupCategory?
    @State private var selectedRisk: CleanupRiskLevel?
    @State private var showsExcluded = false

    private let riskOrder: [CleanupRiskLevel] = [
        .disposable, .regenerable, .reacquirable, .sensitive,
    ]

    private var selectedItems: [CleanupItem] { state.selectedSafeCleanupItems }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var selectedHigherImpactCount: Int {
        selectedItems.filter { $0.risk >= .reacquirable }.count
    }
    private var isCleanupDataReady: Bool { state.cleanupDataState.isReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "清理建议",
                subtitle: "先说明能释放什么、清理后会发生什么，再由你确认。"
            )

            levelPanel
            listToolbar

            if state.safeCleanupItems.isEmpty {
                emptyState
            } else if visibleItemCount == 0 {
                EmptyStateView(
                    title: "没有符合筛选条件的项目",
                    message: "更改筛选条件，或在筛选菜单中显示已排除项目。",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cleanupList
            }

            bottomBar
        }
        .padding(28)
        .task(id: state.isScanning) {
            if !state.isScanning { state.loadSafeCleanupIfNeeded() }
        }
        .alert(confirmationTitle, isPresented: $showingConfirmation) {
            Button("取消", role: .cancel) {}
            Button(
                "移到废纸篓（\(ByteFormatting.string(selectedBytes))）",
                role: .destructive
            ) {
                state.cleanSelected(.safeCleanup)
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var levelPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Picker("清理力度", selection: levelSelection) {
                        ForEach(CleanupLevel.allCases) { level in
                            Text(level.title).tag(Optional(level))
                        }
                        if state.cleanupLevel == nil {
                            Text("自定义").tag(Optional<CleanupLevel>.none)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: state.cleanupLevel == nil ? 390 : 330)
                    .disabled(!isCleanupDataReady)

                    Text(
                        isCleanupDataReady
                            ? (state.cleanupLevel?.detail ?? "已手动调整选择")
                            : cleanupAnalysisMessage
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Spacer()
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("清空废纸篓后可释放")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(isCleanupDataReady ? ByteFormatting.string(selectedBytes) : "—")
                            .font(.title2.monospacedDigit().weight(.semibold))
                    }

                    Divider().frame(height: 34)

                    summaryValue(title: "可直接清理", risk: .disposable)
                    summaryValue(title: "可再生成", risk: .regenerable)
                    summaryValue(title: "可重新获取", risk: .reacquirable)
                    Spacer()
                    Text(isCleanupDataReady ? "已选 \(selectedItems.count) 项" : "正在分析")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                selectionImpactRow
            }
            .padding(.top, 4)
        }
    }

    private var listToolbar: some View {
        HStack(spacing: 8) {
            Text("项目")
                .font(.headline)
            Text("按大小排列")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                Button("全部类型") { selectedCategory = nil }
                Section("类型") {
                    ForEach(availableCategories, id: \.rawValue) { category in
                        Button(category.rawValue) { selectedCategory = category }
                    }
                }
                Section("等级") {
                    Button("全部等级") { selectedRisk = nil }
                    ForEach(riskOrder, id: \.rawValue) { risk in
                        Button(risk.title) { selectedRisk = risk }
                    }
                }
                Divider()
                Toggle("显示已排除项目", isOn: $showsExcluded)
                if !state.excludedCleanupPaths.isEmpty {
                    Button("取消全部排除") { state.resetCleanupExclusions() }
                }
            } label: {
                Label(filterTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .disabled(!isCleanupDataReady)

            Button("取消选择") {
                state.clearSafeCleanupSelection()
            }
            .disabled(!isCleanupDataReady || selectedItems.isEmpty || state.isScanningSafeCleanup)

            Button {
                state.loadSafeCleanupIfNeeded(force: true)
            } label: {
                if state.isScanningSafeCleanup {
                    ProgressView().controlSize(.small)
                } else {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
            }
            .disabled(state.isScanning || state.isScanningSafeCleanup)
        }
    }

    private var cleanupList: some View {
        List {
            ForEach(visibleItems) { item in
                CleanupItemRow(
                    item: binding(for: item),
                    isExcluded: state.isCleanupItemExcluded(item),
                    onToggleExclusion: {
                        state.toggleCleanupExclusion(item)
                    }
                )
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        Group {
            if isCleanupDataReady {
                EmptyStateView(
                    title: "没有清理建议",
                    message: "扫描已完成，当前没有符合清理规则的项目。",
                    systemImage: "checkmark.circle"
                )
            } else {
                AnalysisPendingView(
                    title: cleanupAnalysisTitle,
                    message: cleanupAnalysisMessage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack {
            if isCleanupDataReady {
                Label(selectionStatus.title, systemImage: selectionStatus.symbol)
                    .foregroundStyle(selectionStatus.color)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(cleanupAnalysisTitle)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                showingConfirmation = true
            } label: {
                if state.isCleaning {
                    ProgressView().controlSize(.small)
                } else if !isCleanupDataReady {
                    Text("分析完成后可清理")
                } else {
                    Label("检查并清理（\(ByteFormatting.string(selectedBytes))）", systemImage: "checkmark.shield")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isCleanupDataReady || selectedItems.isEmpty || state.isCleaning)
        }
        .font(.callout)
    }

    private var levelSelection: Binding<CleanupLevel?> {
        Binding(
            get: { state.cleanupLevel },
            set: { level in
                if let level { state.applyCleanupLevel(level) }
            }
        )
    }

    private var availableCategories: [CleanupCategory] {
        Array(Set(state.safeCleanupItems.map(\.category))).sorted {
            $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending
        }
    }

    private var filterTitle: String {
        if let selectedCategory { return selectedCategory.rawValue }
        if let selectedRisk { return selectedRisk.title }
        return showsExcluded ? "包含已排除" : "筛选"
    }

    private var visibleItemCount: Int {
        visibleItems.count
    }

    private var visibleItems: [CleanupItem] {
        state.safeCleanupItems.filter { item in
            if let selectedCategory, item.category != selectedCategory { return false }
            if let selectedRisk, item.risk != selectedRisk { return false }
            if !showsExcluded && state.isCleanupItemExcluded(item) { return false }
            return true
        }
    }

    private func selectedSize(for risk: CleanupRiskLevel) -> Int64 {
        selectedItems.filter { $0.risk == risk }.reduce(0) { $0 + $1.size }
    }

    private func summaryValue(title: String, risk: CleanupRiskLevel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(isCleanupDataReady ? ByteFormatting.string(selectedSize(for: risk)) : "—")
                .font(.callout.monospacedDigit().weight(.medium))
        }
    }

    private func binding(for item: CleanupItem) -> Binding<CleanupItem> {
        Binding(
            get: {
                var value = item
                value.isSelected = state.isSafeCleanupItemSelected(item)
                return value
            },
            set: { value in
                state.setSafeCleanupItem(item, selected: value.isSelected)
            }
        )
    }

    private var selectionStatus: (title: String, detail: String, symbol: String, color: Color) {
        guard !selectedItems.isEmpty else {
            return (
                "当前范围没有可自动清理的内容",
                "0 KB 表示没有项目满足这一范围的安全规则，不是扫描失败。可以切换范围查看其他可处理内容。",
                "checkmark.circle",
                .secondary
            )
        }
        if selectedItems.contains(where: { $0.risk == .sensitive }) {
            return (
                "包含需要人工判断的内容",
                "所选项目中可能包含设置或数据，请逐项确认后再继续。",
                "exclamationmark.triangle.fill",
                .red
            )
        }
        if selectedHigherImpactCount > 0 {
            return (
                "包含可重新获取的内容",
                "不会触碰系统文件，但部分资源之后需要重新下载、安装或创建。",
                "arrow.down.circle.fill",
                .orange
            )
        }
        if selectedItems.contains(where: { $0.risk == .regenerable }) {
            return (
                "所选内容均可重新生成",
                "“更多空间”表示扩大到大型可重建缓存，不代表更危险。不会删除个人文件或应用设置；相关应用下次启动、搜索或构建可能稍慢。",
                "arrow.clockwise.circle.fill",
                .teal
            )
        }
        return (
            "所选为低影响临时内容",
            "不会删除个人文件和应用设置，应用需要时会重新生成这些内容。",
            "checkmark.circle.fill",
            .green
        )
    }

    private var largestSelectedSummary: String? {
        guard !selectedItems.isEmpty else { return nil }
        return
            selectedItems
            .prefix(3)
            .map { "\($0.displayName) \(ByteFormatting.string($0.size))" }
            .joined(separator: "、")
    }

    private var selectionImpactRow: some View {
        Group {
            if isCleanupDataReady {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: selectionStatus.symbol)
                        .foregroundStyle(selectionStatus.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectionStatus.title)
                            .font(.callout.weight(.medium))
                        Text(selectionStatus.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let largestSelectedSummary {
                            Text("最大项目：\(largestSelectedSummary)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cleanupAnalysisTitle)
                            .font(.callout.weight(.medium))
                        Text(cleanupAnalysisMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var cleanupAnalysisTitle: String {
        if state.isScanning { return "正在分析磁盘" }
        if state.isScanningSafeCleanup { return "正在生成清理建议" }
        return "等待开始分析"
    }

    private var cleanupAnalysisMessage: String {
        if state.isScanning {
            return "空间分析完成后，将自动核对缓存、日志、安装文件和应用残留。"
        }
        if state.isScanningSafeCleanup {
            return "正在按影响等级计算可清理容量。"
        }
        return "开始磁盘分析后，这里会显示可清理容量和影响等级。"
    }

    private var confirmationTitle: String {
        if selectedItems.contains(where: { $0.risk == .sensitive }) {
            return "所选内容可能包含数据"
        }
        if selectedHigherImpactCount > 0 {
            return "确认处理可重新获取的内容？"
        }
        return "确认清理这些可恢复内容？"
    }

    private var confirmationMessage: String {
        var parts = [
            "共 \(selectedItems.count) 项，\(ByteFormatting.string(selectedBytes))。",
            selectionStatus.detail,
        ]
        if let largestSelectedSummary {
            parts.append("最大项目：\(largestSelectedSummary)。")
        }
        parts.append("所有项目会先移到废纸篓，清空前可以恢复；清空后才会真正释放空间。")
        return parts.joined(separator: "\n\n")
    }
}
