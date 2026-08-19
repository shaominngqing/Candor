import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationUninstallView: View {
    @EnvironmentObject private var state: AppState
    @State private var searchText = ""
    @State private var showingConfirmation = false
    @State private var isDropTarget = false

    private var filteredApplications: [InstalledApplication] {
        guard !searchText.isEmpty else { return state.applications }
        return state.applications.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var selectedItems: [CleanupItem] { state.relatedItems.filter(\.isSelected) }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var totalFootprint: Int64 { state.relatedItems.reduce(0) { $0 + $1.size } }
    private var relatedFootprint: Int64 {
        state.relatedItems.filter { $0.category != .application }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        HSplitView {
            applicationList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 310)
            detail
                .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: state.selectedApplicationID) { _ in
            state.inspectSelectedApplication()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleDrop)
        .overlay {
            if isDropTarget {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.teal, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    VStack(spacing: 12) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 42))
                            .foregroundStyle(.teal)
                        Text("松开以分析这个应用")
                            .font(.title3.bold())
                        Text("会合并计算应用本体和关联资源，不会立即删除。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
        }
        .alert("确认移到废纸篓？", isPresented: $showingConfirmation) {
            Button("取消", role: .cancel) {}
            Button("移动 \(selectedItems.count) 项（\(ByteFormatting.string(selectedBytes))）", role: .destructive) {
                state.cleanSelected(.application)
            }
        } message: {
            Text("所选项目占用 \(ByteFormatting.string(selectedBytes))，清空废纸篓后才会真正释放。标为“可能含数据”的项目可能包括本地数据库或用户内容。")
        }
    }

    private var applicationList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("应用卸载").font(.title2.bold())
                    Spacer()
                    Label("应用大小", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("搜索应用", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(18)

            Divider()

            List(filteredApplications, selection: $state.selectedApplicationID) { app in
                HStack(spacing: 11) {
                    ApplicationIcon(url: app.url, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(app.size > 0 ? ByteFormatting.string(app.size) : "大小未知")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .tag(app.id)
            }
            .listStyle(.inset)

            Divider()
            Label("也可以把 .app 拖到窗口中分析", systemImage: "square.and.arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)

            if state.applications.isEmpty && !state.isScanning {
                Text("没有找到可卸载的第三方应用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if let application = state.selectedApplication {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 15) {
                    ApplicationIcon(url: application.url, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(application.name).font(.title2.bold())
                        Text(application.subtitle).font(.callout).foregroundStyle(.secondary)
                        if let bundleIdentifier = application.bundleIdentifier {
                            Text(bundleIdentifier).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("在 Finder 显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([application.url])
                    }
                }

                HStack(spacing: 12) {
                    footprintMetric(
                        title: "应用本体",
                        value: ByteFormatting.string(application.size),
                        icon: "app.fill",
                        color: .blue
                    )
                    footprintMetric(
                        title: "关联资源",
                        value: ByteFormatting.string(relatedFootprint),
                        icon: "folder.badge.gearshape",
                        color: .orange
                    )
                    footprintMetric(
                        title: "完整占用",
                        value: ByteFormatting.string(totalFootprint),
                        icon: "sum",
                        color: .teal
                    )
                }

                HStack {
                    SelectionSummary(items: state.relatedItems)
                    Spacer()
                    Button("仅选安全项") {
                        for index in state.relatedItems.indices {
                            let item = state.relatedItems[index]
                            state.relatedItems[index].isSelected = item.safety == .safe
                                || (item.category == .application && canRemove(item))
                        }
                    }
                    Button("全选") {
                        for index in state.relatedItems.indices {
                            state.relatedItems[index].isSelected = canRemove(state.relatedItems[index])
                        }
                    }
                    Button("取消全选") {
                        for index in state.relatedItems.indices {
                            state.relatedItems[index].isSelected = false
                        }
                    }
                }

                if state.isInspectingApplication {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在核对关联路径…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CleanupItemsPanel(
                        items: $state.relatedItems,
                        emptyTitle: "没有发现关联文件",
                        emptyMessage: "仍可只将应用本体移到废纸篓。"
                    )
                }

                HStack {
                    Label("敏感数据默认不选", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showingConfirmation = true
                    } label: {
                        if state.isCleaning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("移到废纸篓（\(ByteFormatting.string(selectedBytes))）", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selectedItems.isEmpty || state.isCleaning)
                }
            }
            .padding(26)
        } else {
            EmptyStateView(
                title: "选择或拖入一个应用",
                message: "余净会列出应用本体和能确认来源的关联文件，再合并计算完整占用。",
                systemImage: "app.badge.checkmark"
            )
        }
    }

    private func footprintMetric(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.monospacedDigit().weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let droppedURL = item as? URL {
                url = droppedURL
            } else if let droppedURL = item as? NSURL {
                url = droppedURL as URL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }

            guard let url else { return }
            Task { @MainActor in
                state.inspectApplication(at: url)
            }
        }
        return true
    }

    private func canRemove(_ item: CleanupItem) -> Bool {
        (try? DeletionService.validate(item.url)) != nil
    }
}
