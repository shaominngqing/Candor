import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    let updaterController: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates = false

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Button("检查软件更新…") {
            updateController.checkForUpdates()
        }
        .disabled(!updateController.canCheckForUpdates)
    }
}

struct UpdateSettingsView: View {
    @ObservedObject private var updateController: UpdateController
    private let updater: SPUUpdater

    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updateController: UpdateController) {
        self.updateController = updateController
        updater = updateController.updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        Form {
            Section("软件更新") {
                Toggle("自动检查更新", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }

                Toggle("自动下载更新", isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { newValue in
                        updater.automaticallyDownloadsUpdates = newValue
                    }

                Button("现在检查") {
                    updater.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
            }

            Text("发现新版本后，Candor 会验证更新签名，并在确认后完成替换与重新打开。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 12)
    }
}
