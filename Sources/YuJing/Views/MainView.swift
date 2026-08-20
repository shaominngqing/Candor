import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingCleanupBasket = false

    var body: some View {
        let stagedCount = state.stagedSelectionCount
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingCleanupBasket = true
                } label: {
                    Label(
                        stagedCount == 0
                            ? "待清理篮"
                            : "待清理 \(stagedCount) 项",
                        systemImage: stagedCount == 0 ? "basket" : "basket.fill"
                    )
                }
                .help("统一核对已勾选项目")

                if state.isScanning {
                    ProgressView().controlSize(.small)
                        .help(state.scanPhase)
                } else {
                    Menu {
                        Button {
                            state.refreshAll()
                        } label: {
                            Label("快速更新", systemImage: "bolt.fill")
                        }
                        Button {
                            state.refreshAll(forceDeep: true)
                        } label: {
                            Label("深度校准", systemImage: "scope")
                        }
                    } label: {
                        Label("更新账本", systemImage: "arrow.clockwise")
                    }
                    .help("快速更新只检查变化；深度校准会重新遍历全部来源")
                }
            }
        }
        .sheet(isPresented: $showingCleanupBasket) {
            CleanupBasketView()
                .environmentObject(state)
        }
        .alert(item: $state.feedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .overlay {
            if state.shouldPresentAccessSetup {
                AccessSetupView()
                    .environmentObject(state)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CandorAppIcon(size: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Candor").font(.title3.weight(.semibold))
                    Text("磁盘分析与清理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 16)

            List(SidebarSection.allCases, selection: $state.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
                    .padding(.vertical, 5)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    state.isLimitedAccess ? "当前为有限扫描" : "磁盘访问已就绪",
                    systemImage: state.isLimitedAccess ? "exclamationmark.shield.fill" : "checkmark.shield.fill"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.isLimitedAccess ? .orange : .green)
                Text(state.isLimitedAccess ? "部分目录会显示为未归类" : "扫描时不再逐目录询问权限")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if state.isLimitedAccess {
                    Button("开启完全访问") { state.showAccessSetup() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selectedSection {
        case .overview: OverviewView()
        case .largeItems: LargeItemsView()
        case .safeCleanup: SafeCleanupView()
        case .applications: ApplicationUninstallView()
        }
    }
}
