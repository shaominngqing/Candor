import SwiftUI

@main
struct YuJingApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 1_040, minHeight: 680)
                .task {
                    state.beginInitialScanIfReady()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新扫描") { state.refreshAll() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(state.isScanning)
            }
        }
    }
}
