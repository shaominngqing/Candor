import Foundation

struct CachedStorageLedger: Codable, Sendable {
    let updatedAt: Date
    let accessMode: ScanAccessMode
    let isComplete: Bool
    let scan: StorageLedgerScan
}

enum DiskLedgerCache {
    static func load() -> CachedStorageLedger? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CachedStorageLedger.self, from: data)
    }

    static func save(
        _ scan: StorageLedgerScan,
        accessMode: ScanAccessMode,
        isComplete: Bool = true,
        updatedAt: Date = Date()
    ) {
        let record = CachedStorageLedger(
            updatedAt: updatedAt,
            accessMode: accessMode,
            isComplete: isComplete,
            scan: scan
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("余净", isDirectory: true)
            .appendingPathComponent("storage-ledger-v3.json", isDirectory: false)
    }
}
