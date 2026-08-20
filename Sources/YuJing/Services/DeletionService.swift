import AppKit
import Foundation

enum DeletionService {
    enum ManagedUnitKind: Sendable, Equatable {
        case androidNDK
        case androidBuildTools
        case androidPlatform
        case androidSystemImage
        case androidSources
        case androidCMake

        var title: String {
            switch self {
            case .androidNDK: "Android NDK"
            case .androidBuildTools: "Android Build Tools"
            case .androidPlatform: "Android SDK Platform"
            case .androidSystemImage: "Android 系统镜像"
            case .androidSources: "Android SDK Sources"
            case .androidCMake: "Android CMake"
            }
        }
    }

    struct ManagedRemovalUnit: Sendable {
        let url: URL
        let kind: ManagedUnitKind

        var displayName: String {
            let identifier: String
            if kind == .androidSystemImage {
                identifier = url.pathComponents.suffix(3).joined(separator: " / ")
            } else {
                identifier = url.lastPathComponent
            }
            return identifier.isEmpty ? kind.title : "\(kind.title) \(identifier)"
        }
    }

    enum SafetyError: LocalizedError {
        case pathOutsideAllowedLocations(URL)
        case protectedRoot(URL)
        case managedUnitRequiresWholeRemoval(String)
        case currentApplication(URL)
        case applicationIsRunning(String)

        var errorDescription: String? {
            switch self {
            case .pathOutsideAllowedLocations(let url):
                "路径不在 Candor 允许清理的范围内：\(url.path)"
            case .protectedRoot(let url):
                "为避免误删，不能清理目录根节点：\(url.path)"
            case .managedUnitRequiresWholeRemoval(let name):
                "\(name) 内的文件不能单独删除，请返回组件目录整体处理。"
            case .currentApplication:
                "Candor 不能在运行时删除自己。"
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

        if let managedUnit = managedRemovalUnit(containing: canonicalURL) {
            guard canonicalURL == managedUnit.url else {
                throw SafetyError.managedUnitRequiresWholeRemoval(managedUnit.displayName)
            }
            if isAndroidStudioRunning {
                throw SafetyError.applicationIsRunning("Android Studio")
            }
            return
        }

        if allowedRoots.contains(canonicalURL) {
            throw SafetyError.protectedRoot(url)
        }

        let isAllowed = allowedRoots.contains { root in
            canonicalPath.hasPrefix(root.path + "/")
        }
        guard isAllowed else { throw SafetyError.pathOutsideAllowedLocations(url) }
    }

    static func managedRemovalUnit(containing sourceURL: URL) -> ManagedRemovalUnit? {
        let url = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let sdk = home.appendingPathComponent("Library/Android/sdk", isDirectory: true)
        let patterns: [(URL, Int, ManagedUnitKind)] = [
            (sdk.appendingPathComponent("ndk", isDirectory: true), 1, .androidNDK),
            (sdk.appendingPathComponent("build-tools", isDirectory: true), 1, .androidBuildTools),
            (sdk.appendingPathComponent("platforms", isDirectory: true), 1, .androidPlatform),
            (sdk.appendingPathComponent("system-images", isDirectory: true), 3, .androidSystemImage),
            (sdk.appendingPathComponent("sources", isDirectory: true), 1, .androidSources),
            (sdk.appendingPathComponent("cmake", isDirectory: true), 1, .androidCMake)
        ]

        for (rootURL, unitDepth, kind) in patterns {
            let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/") else { continue }
            let relativeComponents = Array(url.pathComponents.dropFirst(root.pathComponents.count))
            guard relativeComponents.count >= unitDepth,
                  !relativeComponents.prefix(unitDepth).contains(where: { $0.hasPrefix(".") }) else {
                continue
            }
            var unitURL = root
            for component in relativeComponents.prefix(unitDepth) {
                unitURL.appendPathComponent(component, isDirectory: true)
            }
            return ManagedRemovalUnit(
                url: unitURL.standardizedFileURL.resolvingSymlinksInPath(),
                kind: kind
            )
        }
        return nil
    }

    private static var isAndroidStudioRunning: Bool {
        ["com.google.android.studio", "com.google.android.studio-EAP"].contains { bundleIdentifier in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
    }
}
