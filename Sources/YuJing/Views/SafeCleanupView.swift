import SwiftUI

struct SafeCleanupView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingConfirmation = false

    private var selectedItems: [CleanupItem] { state.safeCleanupItems.filter(\.isSelected) }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "安全清理",
                subtitle: "把缓存、可再生成内容和残留候选集中展示；每项都说明来源与影响。"
            )

            HStack {
                SelectionSummary(items: state.safeCleanupItems)
                Spacer()
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
                Button("选择全部安全项") { selectSafeItems() }
                    .disabled(state.isScanningSafeCleanup)
                Button("全选") {
                    for index in state.safeCleanupItems.indices {
                        state.safeCleanupItems[index].isSelected = true
                    }
                }
                .disabled(state.isScanningSafeCleanup)
                Button("取消全选") {
                    for index in state.safeCleanupItems.indices {
                        state.safeCleanupItems[index].isSelected = false
                    }
                }
                .disabled(state.isScanningSafeCleanup)
            }

            CleanupItemsPanel(
                items: $state.safeCleanupItems,
                emptyTitle: state.isScanningSafeCleanup ? "正在建立清理候选" : "没有找到清理候选",
                emptyMessage: state.isScanningSafeCleanup
                    ? "正在按需核对缓存、开发环境和应用残留。"
                    : "没有足够明确的项目时，余净不会为了数字好看而建议删除。"
            )

            HStack {
                Label("绿色项目可再生成；橙色项目仍需确认，默认不会选择", systemImage: "info.circle")
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
                .tint(.teal)
                .disabled(selectedItems.isEmpty || state.isCleaning)
            }
        }
        .padding(28)
        .task(id: state.isScanning) {
            if !state.isScanning { state.loadSafeCleanupIfNeeded() }
        }
        .alert("确认移动所选项目？", isPresented: $showingConfirmation) {
            Button("取消", role: .cancel) {}
            Button("移动 \(selectedItems.count) 项（\(ByteFormatting.string(selectedBytes))）", role: .destructive) {
                state.cleanSelected(.safeCleanup)
            }
        } message: {
            Text("项目会先移到废纸篓。预计占用 \(ByteFormatting.string(selectedBytes))，清空废纸篓后才会真正释放空间。")
        }
    }

    private func selectSafeItems() {
        for index in state.safeCleanupItems.indices {
            state.safeCleanupItems[index].isSelected = state.safeCleanupItems[index].safety == .safe
        }
    }
}
