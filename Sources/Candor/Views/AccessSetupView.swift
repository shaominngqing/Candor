import AppKit
import SwiftUI

struct AccessSetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var hasOpenedSettings = false
    @State private var isCheckingAccess = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    CandorAppIcon(size: 68)

                    VStack(spacing: 7) {
                        Text("让每一份磁盘占用都有去向")
                            .font(.system(size: 27, weight: .bold))

                        Text("macOS 会保护邮件、信息、浏览器和应用容器等目录。开启完全磁盘访问权限后，Candor 才能准确统计这些空间。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 650)
                    }

                    statusBadge

                    permissionGuide

                    Text(state.accessSetupMessage)
                        .font(.callout)
                        .foregroundStyle(state.fullDiskAccessStatus == .granted ? Color.green : Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 680)

                    actionButtons

                    Divider()
                        .frame(maxWidth: 700)

                    HStack(spacing: 18) {
                        Label("仅读取文件名、路径、大小和日期", systemImage: "doc.text.magnifyingglass")
                        Label("分析结果只保存在这台 Mac", systemImage: "lock.shield")
                        Label("删除前始终再次确认", systemImage: "trash.slash")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    limitedAccessActions
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard hasOpenedSettings, state.shouldPresentAccessSetup, !isCheckingAccess else { return }
            isCheckingAccess = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                state.recheckFullDiskAccess(silent: true)
                isCheckingAccess = false
            }
        }
    }

    private var permissionGuide: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("只需完成一次")
                    .font(.headline)

                guideStep(
                    number: "1",
                    title: "打开系统设置",
                    detail: "按钮会直接打开“隐私与安全性 → 完全磁盘访问权限”。"
                )
                guideStep(
                    number: "2",
                    title: "找到 Candor",
                    detail: "如果列表里没有 Candor，点击列表下方的“+”添加。"
                )
                guideStep(
                    number: "3",
                    title: "打开右侧开关",
                    detail: "完成后回到 Candor；应用会自动检查并开始分析。"
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(22)

            Divider()

            settingsPreview
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(22)
        }
        .frame(maxWidth: 760)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
        }
    }

    private var settingsPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                Text("隐私与安全性")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("完全磁盘访问权限")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CandorAppIcon(size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Candor")
                            .font(.body.weight(.semibold))
                        Text("允许访问所有文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .allowsHitTesting(false)
                }
                .padding(14)

                Divider()

                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(
                            Color(nsColor: .quaternaryLabelColor).opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                    Text("列表里没有时，点击“+”添加 Candor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(
                Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
            }

            Label("打开后直接返回，无需停留等待", systemImage: "arrow.uturn.backward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if state.fullDiskAccessStatus == .granted {
            Button("使用完全访问并开始分析") { state.recheckFullDiskAccess() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            HStack(spacing: 10) {
                Button {
                    hasOpenedSettings = true
                    state.openFullDiskAccessSettings()
                } label: {
                    Label("打开系统设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    state.recheckFullDiskAccess()
                } label: {
                    if isCheckingAccess {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("重新检查")
                    }
                }
                .controlSize(.large)
                .disabled(isCheckingAccess)
            }
        }
    }

    private var limitedAccessActions: some View {
        VStack(spacing: 7) {
            HStack(spacing: 16) {
                Button("暂不授权，使用有限扫描") { state.useLimitedAccess() }
                    .buttonStyle(.link)
                if state.fileAccessMode != nil {
                    Button("暂不更改") { state.dismissAccessSetup() }
                        .buttonStyle(.link)
                }
            }
            .font(.callout)

            Text("有限扫描会避开受保护目录，相应容量会显示为“未归类”。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusBadge: some View {
        Label(
            statusTitle,
            systemImage: state.fullDiskAccessStatus == .granted
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.callout.weight(.semibold))
        .foregroundStyle(state.fullDiskAccessStatus == .granted ? Color.green : Color.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (state.fullDiskAccessStatus == .granted ? Color.green : Color.orange).opacity(0.1),
            in: Capsule()
        )
    }

    private var statusTitle: String {
        switch state.fullDiskAccessStatus {
        case .granted: "完全磁盘访问权限已开启"
        case .notGranted: "需要开启完全磁盘访问权限"
        case .unknown: "等待确认磁盘访问状态"
        }
    }

    private func guideStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
