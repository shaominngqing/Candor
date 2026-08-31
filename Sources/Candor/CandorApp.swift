import AppKit
import SwiftUI

@main
struct CandorApp: App {
    @StateObject private var state = AppState()
    @StateObject private var updateController: UpdateController

    init() {
        _updateController = StateObject(wrappedValue: UpdateController())
        NSApplication.shared.applicationIconImage = CandorIcon.image
    }

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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updateController: updateController)
            }
            CommandGroup(after: .newItem) {
                Button("重新扫描") { state.refreshAll() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(state.isScanning)
            }
        }

        Settings {
            UpdateSettingsView(updateController: updateController)
        }
    }
}
