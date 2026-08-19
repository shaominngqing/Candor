import AppKit
import Foundation

enum DeletionService {
    enum SafetyError: LocalizedError {
        case pathOutsideAllowedLocations(URL)
        case protectedRoot(URL)
        case currentApplication(URL)
        case applicationIsRunning(String)

        var errorDescription: String? {
            switch self {
            case .pathOutsideAllowedLocations(let url):
                "路径不在余净允许清理的范围内：\(url.path)"
            case .protectedRoot(let url):
                "为避免误删，不能清理目录根节点：\(url.path)"
            case .currentApplication:
                "余净不能在运行时删除自己。"
            case .applicationIsRunning(let name):
                "\(name) 仍在运行，请先退出应用后重试。"
            }
        }
    }

    static func moveToTrash(_ items: [CleanupItem]) -> DeletionReport {
        var movedCount = 0
        var movedBytes: Int64 = 0
        var failures: [DeletionFailure] = []

        for item in items {
            do {
                try validate(item.url)
                guard FileManager.default.fileExists(atPath: item.url.path) else { continue }
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                movedCount += 1
                movedBytes += item.size
            } catch {
                failures.append(DeletionFailure(
                    url: item.url,
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ))
            }
        }

        return DeletionReport(movedCount: movedCount, movedBytes: movedBytes, failures: failures)
    }

    static func validate(_ url: URL) throws {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalPath = canonicalURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser
        let allowedRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Movies", isDirectory: true),
            home.appendingPathComponent("Music", isDirectory: true),
            home.appendingPathComponent("Pictures", isDirectory: true),
            home.appendingPathComponent("Library/Caches", isDirectory: true),
            home.appendingPathComponent("Library/Logs", isDirectory: true),
            home.appendingPathComponent("Library/Saved Application State", isDirectory: true),
            home.appendingPathComponent("Library/HTTPStorages", isDirectory: true),
            home.appendingPathComponent("Library/WebKit", isDirectory: true),
            home.appendingPathComponent("Library/Preferences", isDirectory: true),
            home.appendingPathComponent("Library/Application Support", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Group Containers", isDirectory: true),
            home.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
            home.appendingPathComponent(".cache", isDirectory: true),
            home.appendingPathComponent(".gradle/caches", isDirectory: true),
            home.appendingPathComponent(".codex/.tmp/bundled-marketplaces", isDirectory: true)
        ].map { $0.standardizedFileURL.resolvingSymlinksInPath() }

        if canonicalURL == Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath() {
            throw SafetyError.currentApplication(url)
        }

        if canonicalURL.pathExtension.lowercased() == "app",
           let bundle = Bundle(url: canonicalURL),
           let bundleIdentifier = bundle.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? canonicalURL.deletingPathExtension().lastPathComponent
            throw SafetyError.applicationIsRunning(name)
        }

        if allowedRoots.contains(canonicalURL) {
            throw SafetyError.protectedRoot(url)
        }

        let isAllowed = allowedRoots.contains { root in
            canonicalPath.hasPrefix(root.path + "/")
        }
        guard isAllowed else { throw SafetyError.pathOutsideAllowedLocations(url) }
    }
}
