import AppKit
import Foundation

enum FileAccessService {
    static func fullDiskAccessStatus() -> FullDiskAccessStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tccDatabase = home.appendingPathComponent(
            "Library/Application Support/com.apple.TCC/TCC.db",
            isDirectory: false
        )
        if FileManager.default.fileExists(atPath: tccDatabase.path) {
            if let handle = try? FileHandle(forReadingFrom: tccDatabase) {
                try? handle.close()
                return .granted
            }
        }
        let protectedDirectories = [
            home.appendingPathComponent("Library/Mail", isDirectory: true),
            home.appendingPathComponent("Library/Messages", isDirectory: true),
            home.appendingPathComponent("Library/Safari", isDirectory: true),
        ]
        var existingDirectoryCount = FileManager.default.fileExists(atPath: tccDatabase.path) ? 1 : 0

        for directory in protectedDirectories where FileManager.default.fileExists(atPath: directory.path) {
            existingDirectoryCount += 1
            if (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )) != nil {
                return .granted
            }
        }

        return existingDirectoryCount > 0 ? .notGranted : .unknown
    }

    @discardableResult
    static func openFullDiskAccessSettings() -> Bool {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            )
        else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func shouldSkip(_ url: URL, in mode: ScanAccessMode) -> Bool {
        guard mode == .limited else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let protectedRoots = [
            "Desktop",
            "Documents",
            "Downloads",
            "Movies",
            "Music",
            "Pictures",
            "Library/Mail",
            "Library/Messages",
            "Library/Safari",
            "Library/Containers",
            "Library/Group Containers",
            "Library/Mobile Documents",
            "Library/CloudStorage",
            "Library/Calendars",
            "Library/AddressBook",
            "Library/HomeKit",
        ].map { URL(fileURLWithPath: home).appendingPathComponent($0).standardizedFileURL.path }

        return protectedRoots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }
}
