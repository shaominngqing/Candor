import XCTest
@testable import YuJing

final class DiskLedgerTests: XCTestCase {
    @MainActor
    func testAnalysisDataStateDoesNotPresentMissingResultsAsZero() {
        XCTAssertEqual(
            AppState.resolveAnalysisDataState(hasResults: false, isAnalyzing: false),
            .waiting
        )
        XCTAssertEqual(
            AppState.resolveAnalysisDataState(hasResults: false, isAnalyzing: true),
            .analyzing
        )
        XCTAssertEqual(
            AppState.resolveAnalysisDataState(hasResults: true, isAnalyzing: true),
            .ready,
            "已有结果时应在后台更新期间继续展示，避免界面退回空状态"
        )
    }

    func testKnownPathsAreAssignedToHumanReadableCategories() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        XCTAssertEqual(
            DiskLedgerScanner.category(for: home.appendingPathComponent(".ollama/models")),
            .appData
        )
        XCTAssertEqual(
            DiskLedgerScanner.category(for: home.appendingPathComponent("Library/Developer/Xcode")),
            .appData
        )
        XCTAssertEqual(
            DiskLedgerScanner.category(for: home.appendingPathComponent("Library/Caches/com.example.app")),
            .cacheTemporary
        )
        XCTAssertEqual(
            DiskLedgerScanner.category(for: home.appendingPathComponent("Library/Containers/com.tencent.WeWorkMac")),
            .appData
        )
        XCTAssertEqual(
            DiskLedgerScanner.category(for: home.appendingPathComponent(".unknown-tool")),
            .appData
        )
    }

    func testWorkScenesAreDetectedWithoutChangingUniversalCategory() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let samples: [(String, StorageSceneKind)] = [
            (".ollama/models/llama.gguf", .aiModels),
            ("Library/Developer/Xcode/DerivedData", .developer),
            ("Library/Application Support/Adobe/Premiere", .creativeWork),
            ("Library/Application Support/Steam/steamapps", .games),
            ("Library/CloudStorage/OneDrive/report.xlsx", .cloudOffline),
            ("Library/Application Support/MobileSync/Backup/device", .deviceBackups),
            ("Downloads/Installer.dmg", .downloadsInstallers),
            ("Pictures/Photos Library.photoslibrary", .photosVideos),
            ("Library/Containers/com.tencent.WeWorkMac/Data", .communication),
            ("Library/Developer/CoreSimulator/Devices", .virtualMachines)
        ]

        for (path, expected) in samples {
            XCTAssertEqual(
                DiskLedgerScanner.scene(for: home.appendingPathComponent(path)),
                expected,
                path
            )
        }
    }

    func testRecentOrSmallCacheIsNotRecommendedAutomatically() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        XCTAssertFalse(FileScanner.shouldRecommendCache(
            modifiedAt: now,
            size: 500 * 1_024 * 1_024,
            now: now
        ))
        XCTAssertFalse(FileScanner.shouldRecommendCache(
            modifiedAt: Calendar.current.date(byAdding: .day, value: -60, to: now),
            size: 5 * 1_024 * 1_024,
            now: now
        ))
        XCTAssertTrue(FileScanner.shouldRecommendCache(
            modifiedAt: Calendar.current.date(byAdding: .day, value: -31, to: now),
            size: 500 * 1_024 * 1_024,
            now: now
        ))
    }

    func testCleanupLevelsExpandWithoutSelectingSensitiveData() {
        let lightItem = cleanupItem(risk: .disposable, level: .light)
        let recommendedItem = cleanupItem(risk: .regenerable, level: .recommended)
        let deepItem = cleanupItem(risk: .reacquirable, level: .deep)
        let sensitiveItem = cleanupItem(risk: .sensitive, level: .light)

        XCTAssertTrue(lightItem.isIncluded(in: .light))
        XCTAssertFalse(recommendedItem.isIncluded(in: .light))
        XCTAssertTrue(recommendedItem.isIncluded(in: .recommended))
        XCTAssertFalse(deepItem.isIncluded(in: .recommended))
        XCTAssertTrue(deepItem.isIncluded(in: .deep))
        XCTAssertFalse(sensitiveItem.isIncluded(in: .deep))
    }

    @MainActor
    func testCleanupLevelChangesSelectionWithoutRewritingScanResults() {
        let state = AppState(loadPersistedState: false)
        let lowImpact = cleanupItem(risk: .disposable, level: .light)
        let rebuildable = cleanupItem(risk: .regenerable, level: .deep)
        state.safeCleanupItems = [lowImpact, rebuildable]

        state.applyCleanupLevel(.light)
        XCTAssertEqual(Set(state.selectedSafeCleanupItems.map(\.id)), [lowImpact.id])

        state.applyCleanupLevel(.deep)
        XCTAssertEqual(Set(state.selectedSafeCleanupItems.map(\.id)), [lowImpact.id, rebuildable.id])
        XCTAssertTrue(state.safeCleanupItems.allSatisfy { !$0.isSelected })
    }

    @MainActor
    func testStagedCleanupCompactionDropsChildrenOfSelectedFolder() {
        let root = URL(fileURLWithPath: "/tmp/CandorCompaction", isDirectory: true)
        let parent = cleanupItem(url: root, risk: .regenerable, level: .deep)
        let child = cleanupItem(
            url: root.appendingPathComponent("nested/cache.bin"),
            risk: .regenerable,
            level: .deep
        )

        let compacted = AppState.compactCleanupItems([child, parent, child])

        XCTAssertEqual(compacted.map(\.id), [parent.id])
    }

    @MainActor
    func testStagedCleanupCompactionHandlesThousandsOfSiblingsQuickly() {
        let root = URL(fileURLWithPath: "/tmp/CandorCompactionSiblings", isDirectory: true)
        let candidates = (0..<5_000).map { index in
            cleanupItem(
                url: root.appendingPathComponent("cache-\(index)", isDirectory: true),
                risk: .regenerable,
                level: .deep
            )
        }
        let clock = ContinuousClock()
        let started = clock.now

        let compacted = AppState.compactCleanupItems(candidates)

        XCTAssertEqual(compacted.count, candidates.count)
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(1))
    }

    func testFolderDrillDownIncludesHiddenChildrenAndSortsBySize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuJingLedgerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let hidden = root.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16_384).write(to: hidden.appendingPathComponent("large.bin"))
        try Data(repeating: 2, count: 4_096).write(to: root.appendingPathComponent("small.bin"))

        let parent = StorageItem(
            url: root,
            name: root.lastPathComponent,
            size: 0,
            category: .personalFiles,
            scene: nil,
            isDirectory: true,
            canOpen: true,
            action: .unavailable,
            modifiedAt: nil,
            risk: .sensitive,
            explanation: "测试",
            actionReason: "测试目录"
        )
        let children = try DiskLedgerScanner.scanChildren(of: parent, accessMode: .full)

        XCTAssertEqual(Set(children.map(\.name)), Set([".hidden", "small"]))
        XCTAssertEqual(children.first?.name, ".hidden")
        XCTAssertGreaterThan(children.first?.size ?? 0, children.last?.size ?? 0)
    }

    func testInitialTraversalBuildsReusableDirectorySizeIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CandorDirectoryIndex-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 7, count: 2 * 1_024 * 1_024)
            .write(to: nested.appendingPathComponent("payload.bin"))

        let index = try DiskLedgerScanner.directorySizeIndex(at: root)

        XCTAssertGreaterThanOrEqual(index[nested.standardizedFileURL] ?? 0, 2 * 1_024 * 1_024)
        XCTAssertGreaterThanOrEqual(index[root.standardizedFileURL] ?? 0, 2 * 1_024 * 1_024)
    }

    func testLimitedModeSkipsProtectedRootsWithoutBlockingOrdinaryCaches() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertTrue(FileAccessService.shouldSkip(
            home.appendingPathComponent("Desktop/report.pdf"),
            in: .limited
        ))
        XCTAssertTrue(FileAccessService.shouldSkip(
            home.appendingPathComponent("Library/Containers/com.example.app/data"),
            in: .limited
        ))
        XCTAssertFalse(FileAccessService.shouldSkip(
            home.appendingPathComponent(".cache/tool/index"),
            in: .limited
        ))
        XCTAssertFalse(FileAccessService.shouldSkip(
            home.appendingPathComponent("Desktop/report.pdf"),
            in: .full
        ))
    }

    func testFreshUnchangedSourceCanBeReusedButDeepScanCannot() {
        let now = Date(timeIntervalSince1970: 10_000)
        let modifiedAt = now.addingTimeInterval(-120)
        let snapshot = sourceSnapshot(
            category: .applications,
            modifiedAt: modifiedAt,
            scannedAt: now.addingTimeInterval(-60)
        )

        XCTAssertTrue(DiskLedgerScanner.shouldReuse(
            snapshot,
            currentModifiedAt: modifiedAt,
            now: now
        ))
        XCTAssertFalse(DiskLedgerScanner.shouldReuse(
            snapshot,
            currentModifiedAt: modifiedAt,
            now: now,
            forceDeep: true
        ))
    }

    func testChangedOrExpiredSourceIsRescanned() {
        let now = Date(timeIntervalSince1970: 100_000)
        let modifiedAt = now.addingTimeInterval(-300)
        let changed = sourceSnapshot(
            category: .applications,
            modifiedAt: modifiedAt,
            scannedAt: now.addingTimeInterval(-60)
        )
        XCTAssertFalse(DiskLedgerScanner.shouldReuse(
            changed,
            currentModifiedAt: modifiedAt.addingTimeInterval(1),
            now: now
        ))

        let expired = sourceSnapshot(
            category: .cacheTemporary,
            modifiedAt: modifiedAt,
            scannedAt: now.addingTimeInterval(-DiskLedgerScanner.cacheLifetime(for: .cacheTemporary) - 1)
        )
        XCTAssertFalse(DiskLedgerScanner.shouldReuse(
            expired,
            currentModifiedAt: modifiedAt,
            now: now
        ))
    }

    func testPartialLedgerCheckpointRoundTrips() throws {
        let snapshot = sourceSnapshot(
            category: .personalFiles,
            modifiedAt: nil,
            scannedAt: Date(timeIntervalSince1970: 1_000)
        )
        let scan = StorageLedgerScan(
            categorySizes: [.personalFiles: snapshot.size],
            categorySourceCounts: [.personalFiles: 1],
            sceneSizes: [:],
            sceneSourceCounts: [:],
            largeItems: [],
            analyzedBytes: snapshot.size,
            scannedItemCount: snapshot.scannedItemCount,
            inaccessibleCount: 0,
            sourceSnapshots: [snapshot]
        )
        let record = CachedStorageLedger(
            updatedAt: Date(timeIntervalSince1970: 2_000),
            accessMode: .limited,
            isComplete: false,
            scan: scan
        )

        let decoded = try JSONDecoder().decode(
            CachedStorageLedger.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertFalse(decoded.isComplete)
        XCTAssertEqual(decoded.scan.sourceSnapshots, [snapshot])
    }

    private func sourceSnapshot(
        category: StorageCategoryKind,
        modifiedAt: Date?,
        scannedAt: Date
    ) -> StorageSourceSnapshot {
        StorageSourceSnapshot(
            url: URL(fileURLWithPath: "/tmp/test-source"),
            category: category,
            scene: nil,
            size: 42,
            scannedItemCount: 3,
            inaccessibleCount: 0,
            isDirectory: true,
            isPackage: false,
            modifiedAt: modifiedAt,
            scannedAt: scannedAt,
            largeItem: nil,
            directoryIndex: []
        )
    }

    private func cleanupItem(
        risk: CleanupRiskLevel,
        level: CleanupLevel?
    ) -> CleanupItem {
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")
        return cleanupItem(url: url, risk: risk, level: level)
    }

    private func cleanupItem(
        url: URL,
        risk: CleanupRiskLevel,
        level: CleanupLevel?
    ) -> CleanupItem {
        return CleanupItem(
            id: url,
            url: url,
            displayName: "测试",
            category: .cache,
            size: 1,
            modifiedAt: nil,
            risk: risk,
            recommendedLevel: level,
            explanation: "测试",
            impact: "测试",
            isSelected: false
        )
    }
}
