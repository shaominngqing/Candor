import SwiftUI

struct AccessSetupView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.mint, .teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "externaldrive.badge.checkmark")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 78, height: 78)

                    VStack(spacing: 8) {
                        Text("开始前，一次完成磁盘访问设置")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("完整磁盘访问可以一次覆盖桌面、文稿、下载、应用容器和受保护数据，避免长时间扫描过程中连续询问权限。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                    }

                    statusBadge

                    HStack(alignment: .top, spacing: 12) {
                        setupStep(number: "1", title: "打开系统设置", detail: "进入“隐私与安全性 → 完整磁盘访问”。")
                        setupStep(number: "2", title: "加入并开启余净", detail: "点“+”选择余净，然后打开右侧开关。")
                        setupStep(number: "3", title: "返回开始分析", detail: "按系统提示重新打开，或回来点“重新检查”。")
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Label("只读取文件元数据", systemImage: "doc.text.magnifyingglass")
                        Label("不读取文档正文和聊天内容", systemImage: "eye.slash.fill")
                        Label("扫描结果只保存在这台 Mac", systemImage: "lock.macwindow")
                        Label("任何删除仍需再次确认，并只移到废纸篓", systemImage: "trash.slash")
                    }
                    .font(.callout)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(16)
                    .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

                    Text(state.accessSetupMessage)
                        .font(.callout)
                        .foregroundStyle(state.fullDiskAccessStatus == .granted ? Color.green : Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)

                    HStack(spacing: 12) {
                        Button {
                            state.openFullDiskAccessSettings()
                        } label: {
                            Label("打开完整磁盘访问设置", systemImage: "gearshape.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .controlSize(.large)

                        Button("我已开启，重新检查") {
                            state.recheckFullDiskAccess()
                        }
                        .controlSize(.large)
                    }

                    HStack(spacing: 16) {
                        Button("先使用有限扫描") { state.useLimitedAccess() }
                            .buttonStyle(.link)
                        if state.fileAccessMode != nil {
                            Button("暂不更改") { state.dismissAccessSetup() }
                                .buttonStyle(.link)
                        }
                    }
                    .font(.callout)

                    Text("有限扫描会主动避开受保护目录，不会逐个弹窗；未覆盖容量会明确显示为“尚未说明”。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 42)
                .padding(.vertical, 34)
                .frame(maxWidth: 820)
            }
        }
    }

    private var statusBadge: some View {
        Label(
            state.fullDiskAccessStatus.title,
            systemImage: state.fullDiskAccessStatus == .granted
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.callout.weight(.semibold))
        .foregroundStyle(state.fullDiskAccessStatus == .granted ? Color.green : Color.orange)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(
            (state.fullDiskAccessStatus == .granted ? Color.green : Color.orange).opacity(0.1),
            in: Capsule()
        )
    }

    private func setupStep(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.teal, in: Circle())
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.35)) }
    }
}
