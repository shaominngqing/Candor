import Foundation

@MainActor
final class AppState: ObservableObject {
    private struct SafeCleanupSelectionState {
        var urls: Set<URL> = []
        var items: [CleanupItem] = []
        var bytes: Int64 = 0
    }

    enum CleanupContext: Equatable {
        case application
        case safeCleanup
        case largeItems
    }

    struct Feedback: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published var selectedSection: SidebarSection = .overview
    @Published private(set) var fileAccessMode: ScanAccessMode?
    @Published private(set) var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    @Published private(set) var isAccessSetupPresented = false
    @Published private(set) var accessSetupMessage = "开启后只读取文件名、路径、大小和日期，所有分析都在本机完成。"
    @Published private(set) var applications: [InstalledApplication] = []
    @Published var selectedApplicationID: URL?
    @Published var relatedItems: [CleanupItem] = []
    @Published var safeCleanupItems: [CleanupItem] = []
    @Published private var safeCleanupSelection = SafeCleanupSelectionState()
    @Published private(set) var cleanupLevel: CleanupLevel? = .recommended
    @Published private(set) var excludedCleanupPaths: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "CandorExcludedCleanupPaths") ?? []
    )
    @Published private(set) var storageCategories: [StorageCategory] = []
    @Published private(set) var storageScenes: [StorageScene] = []
    @Published private(set) var ledgerLargeItems: [StorageItem] = []
    @Published private(set) var largeItemPath: [StorageItem] = []
    @Published private(set) var selectedLargeItemURLs: Set<URL> = []
    @Published var selectedStorageCategory: StorageCategoryKind?
    @Published var selectedStorageScene: StorageSceneKind?
    @Published private(set) var storage = StorageSnapshot(total: 0, available: 0)
    @Published private(set) var analyzedBytes: Int64 = 0
    @Published private(set) var ledgerScannedItemCount = 0
    @Published private(set) var ledgerInaccessibleCount = 0
    @Published private(set) var completedLedgerSources = 0
    @Published private(set) var totalLedgerSources = 0
    @Published private(set) var reusedLedgerSources = 0
    @Published private(set) var rescannedLedgerSources = 0
    @Published private(set) var lastLedgerUpdatedAt: Date?
    @Published private(set) var hasCompletedStorageAnalysis = false
    @Published private(set) var isScanning = false
    @Published private(set) var isDeepScanning = false
    @Published private(set) var scanPhase = "准备分析"
    @Published private(set) var isScanningSafeCleanup = false
    @Published private(set) var hasScannedSafeCleanup = false
    @Published private(set) var hasScannedApplications = false
    @Published private(set) var isInspectingApplication = false
    @Published private(set) var isScanningLargeItemFolder = false
    @Published private(set) var isCleaning = false
    @Published var feedback: Feedback?

    private var refreshScanID: UUID?
    private var cleanupScanID: UUID?
    private var refreshWorkerTask: Task<Void, Never>?
    private var cleanupWorkerTask: Task<[CleanupItem], Never>?
    private var applicationInspectionTask: Task<[CleanupItem], Never>?
    private var largeItemWorkerTask: Task<[StorageItem], Error>?
    private var largeItemChildrenCache: [URL: [StorageItem]] = [:]
    private var selectedLargeItemIndex: [URL: StorageItem] = [:]
    private var cachedLedgerSources: [StorageSourceSnapshot] = []
    private var ledgerDirectorySizeIndex: [URL: Int64] = [:]
    private var latestLedgerProgress: StorageLedgerProgress?
    private var lastCheckpointAt = Date.distantPast
    private var isLedgerComplete = false

    init() {
        fullDiskAccessStatus = FileAccessService.fullDiskAccessStatus()
        if fullDiskAccessStatus == .granted {
            fileAccessMode = .full
        } else if UserDefaults.standard.string(forKey: "scanAccessMode") == ScanAccessMode.limited.rawValue {
            fileAccessMode = .limited
        }
        isAccessSetupPresented = fileAccessMode == nil
        storage = FileScanner.storageSnapshot()
        guard let cached = DiskLedgerCache.load(), cached.accessMode == fileAccessMode else { return }
        isLedgerComplete = cached.isComplete
        hasCompletedStorageAnalysis = cached.isComplete
        cachedLedgerSources = cached.scan.sourceSnapshots
        ledgerDirectorySizeIndex = Self.makeDirectorySizeIndex(from: cached.scan.sourceSnapshots)
        ledgerLargeItems = cached.scan.largeItems
        analyzedBytes = cached.scan.analyzedBytes
        ledgerScannedItemCount = cached.scan.scannedItemCount
        ledgerInaccessibleCount = cached.scan.inaccessibleCount
        completedLedgerSources = cached.scan.sourceSnapshots.count
        totalLedgerSources = completedLedgerSources
        lastLedgerUpdatedAt = cached.updatedAt
        storageCategories = makeStorageCategories(
            categorySizes: cached.scan.categorySizes,
            sourceCounts: cached.scan.categorySourceCounts,
            storage: storage,
            candidates: [],
            isComplete: cached.isComplete
        )
        storageScenes = makeStorageScenes(
            sceneSizes: cached.scan.sceneSizes,
            sourceCounts: cached.scan.sceneSourceCounts
        )
        scanPhase = cached.isComplete
            ? "已显示上次空间账本，正在核对变化"
            : "已恢复上次进度，正在继续分析"
    }

    var shouldPresentAccessSetup: Bool {
        fileAccessMode == nil || isAccessSetupPresented
    }

    var isLimitedAccess: Bool { fileAccessMode == .limited }

    var storageDataState: AnalysisDataState {
        Self.resolveAnalysisDataState(
            hasResults: hasCompletedStorageAnalysis,
            isAnalyzing: isScanning
        )
    }

    var cleanupDataState: AnalysisDataState {
        Self.resolveAnalysisDataState(
            hasResults: hasScannedSafeCleanup || !safeCleanupItems.isEmpty,
            isAnalyzing: isScanning || isScanningSafeCleanup
        )
    }

    var applicationDataState: AnalysisDataState {
        Self.resolveAnalysisDataState(
            hasResults: hasScannedApplications || !applications.isEmpty,
            isAnalyzing: isScanning
        )
    }

    static func resolveAnalysisDataState(
        hasResults: Bool,
        isAnalyzing: Bool
    ) -> AnalysisDataState {
        if hasResults { return .ready }
        return isAnalyzing ? .analyzing : .waiting
    }

    func beginInitialScanIfReady() {
        guard fileAccessMode != nil, !isScanning else { return }
        refreshAll()
    }

    func showAccessSetup() {
        fullDiskAccessStatus = FileAccessService.fullDiskAccessStatus()
        isAccessSetupPresented = true
        accessSetupMessage = fileAccessMode == .limited
            ? "当前使用有限扫描。补充完全磁盘访问权限后，才能一次覆盖受保护目录。"
            : "开启后只读取文件名、路径、大小和日期，所有分析都在本机完成。"
    }

    func dismissAccessSetup() {
        guard fileAccessMode != nil else { return }
        isAccessSetupPresented = false
    }

    func openFullDiskAccessSettings() {
        let opened = FileAccessService.openFullDiskAccessSettings()
        accessSetupMessage = opened
            ? "请点“+”加入 Candor 并打开开关；如果系统要求退出，请重新打开 Candor，扫描会自动开始。"
            : "无法打开系统设置，请手动前往“隐私与安全性 → 完全磁盘访问权限”。"
    }

    func recheckFullDiskAccess(silent: Bool = false) {
        fullDiskAccessStatus = FileAccessService.fullDiskAccessStatus()
        guard fullDiskAccessStatus == .granted else {
            if !silent {
                accessSetupMessage = "仍未检测到权限。请确认 Candor 的开关已经开启；若系统要求退出，请重新打开应用。"
            }
            return
        }
        fileAccessMode = .full
        cachedLedgerSources = []
        UserDefaults.standard.set(ScanAccessMode.full.rawValue, forKey: "scanAccessMode")
        isAccessSetupPresented = false
        accessSetupMessage = "完全磁盘访问权限已就绪。"
        refreshAll()
    }

    func useLimitedAccess() {
        fileAccessMode = .limited
        cachedLedgerSources = []
        UserDefaults.standard.set(ScanAccessMode.limited.rawValue, forKey: "scanAccessMode")
        isAccessSetupPresented = false
        accessSetupMessage = "有限扫描不会访问受保护目录，这部分容量会显示为未归类。"
        refreshAll()
    }

    var selectedApplication: InstalledApplication? {
        guard let selectedApplicationID else { return nil }
        return applications.first { $0.id == selectedApplicationID }
    }

    var safeCleanupTotal: Int64 {
        safeCleanupItems.filter { !isCleanupItemExcluded($0) }.reduce(0) { $0 + $1.size }
    }
    var safeCandidateBytes: Int64 {
        cleanupBytes(for: .recommended)
    }
    var reviewCandidateBytes: Int64 {
        safeCleanupItems.filter {
            !isCleanupItemExcluded($0)
                && ($0.recommendedLevel == nil || $0.recommendedLevel! > .recommended)
        }
            .reduce(0) { $0 + $1.size }
    }
    var selectedSafeCleanupBytes: Int64 {
        safeCleanupSelection.bytes
    }

    var selectedSafeCleanupItems: [CleanupItem] {
        safeCleanupSelection.items
    }
    var unexplainedBytes: Int64 {
        storageCategories.first { $0.kind == .unexplained }?.size ?? storage.used
    }
    var explainedBytes: Int64 {
        min(storageCategories.filter { $0.kind != .unexplained }.reduce(0) { $0 + $1.size }, storage.used)
    }
    var ledgerProgressFraction: Double {
        guard totalLedgerSources > 0 else { return isScanning ? 0 : 1 }
        return min(max(Double(completedLedgerSources) / Double(totalLedgerSources), 0), 1)
    }

    var prominentStorageScenes: [StorageScene] {
        let minimum = max(
            Int64(500 * 1_024 * 1_024),
            min(storage.used / 200, Int64(2 * 1_024 * 1_024 * 1_024))
        )
        let visibleKinds = Set(ledgerLargeItems.compactMap(\.scene))
        return storageScenes.filter {
            $0.size >= minimum && visibleKinds.contains($0.kind)
        }
    }

    var currentLargeItems: [StorageItem] {
        let items: [StorageItem]
        if let parent = largeItemPath.last {
            items = largeItemChildrenCache[parent.url.standardizedFileURL] ?? []
        } else {
            items = ledgerLargeItems
        }
        guard largeItemPath.isEmpty else { return items }
        if let selectedStorageScene {
            return items.filter { $0.scene == selectedStorageScene }
        }
        if let selectedStorageCategory {
            return items.filter { $0.category == selectedStorageCategory }
        }
        return items
    }

    var selectedLargeItems: [StorageItem] {
        selectedLargeItemURLs.compactMap { selectedLargeItemIndex[$0.standardizedFileURL] }
            .sorted {
                if $0.size != $1.size { return $0.size > $1.size }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var selectedLargeItemBytes: Int64 {
        selectedLargeItems.reduce(0) { $0 + $1.size }
    }

    var stagedCleanupItems: [CleanupItem] {
        var candidates = selectedSafeCleanupItems + relatedItems.filter(\.isSelected)
        candidates += selectedLargeItems.compactMap(\.cleanupItem)
        return Self.compactCleanupItems(candidates)
    }

    var stagedSelectionCount: Int {
        var urls = safeCleanupSelection.urls
        urls.formUnion(
            relatedItems.lazy
                .filter(\.isSelected)
                .map { $0.url.standardizedFileURL }
        )
        urls.formUnion(selectedLargeItemURLs.map(\.standardizedFileURL))
        return urls.count
    }

    static func compactCleanupItems(_ candidates: [CleanupItem]) -> [CleanupItem] {
        let ordered = candidates.sorted {
            if $0.url.pathComponents.count != $1.url.pathComponents.count {
                return $0.url.pathComponents.count < $1.url.pathComponents.count
            }
            return $0.size > $1.size
        }
        var includedPaths = Set<String>()
        var compacted: [CleanupItem] = []
        compacted.reserveCapacity(ordered.count)

        for item in ordered {
            let url = item.url.standardizedFileURL
            let path = url.path
            guard !includedPaths.contains(path) else { continue }

            var parent = url.deletingLastPathComponent()
            var previousPath = path
            var isCoveredByParent = false
            while parent.path != previousPath {
                if includedPaths.contains(parent.path) {
                    isCoveredByParent = true
                    break
                }
                previousPath = parent.path
                parent.deleteLastPathComponent()
            }
            guard !isCoveredByParent else { continue }

            includedPaths.insert(path)
            compacted.append(item)
        }

        return compacted.sorted {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func refreshAll(forceDeep: Bool = false) {
        guard let accessMode = fileAccessMode else {
            isAccessSetupPresented = true
            return
        }
        refreshWorkerTask?.cancel()
        cleanupWorkerTask?.cancel()
        cleanupWorkerTask = nil
        cleanupScanID = nil
        largeItemWorkerTask?.cancel()

        let scanID = UUID()
        refreshScanID = scanID
        isScanning = true
        isLedgerComplete = false
        isDeepScanning = forceDeep
        isScanningSafeCleanup = false
        hasScannedSafeCleanup = false
        scanPhase = "正在读取磁盘总量…"
        completedLedgerSources = 0
        totalLedgerSources = 0
        reusedLedgerSources = 0
        rescannedLedgerSources = 0
        latestLedgerProgress = nil
        lastCheckpointAt = .distantPast
        let reusableSources = cachedLedgerSources

        refreshWorkerTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let scannedStorage = FileScanner.storageSnapshot()
            guard !Task.isCancelled else { return }
            await self.receiveStorage(scannedStorage, scanID: scanID)

            await self.receiveRefreshPhase(
                forceDeep ? "正在深度校准全部来源…" : "正在快速核对磁盘变化…",
                scanID: scanID
            )
            let relay = LedgerProgressRelay(state: self, scanID: scanID)
            do {
                let ledger = try DiskLedgerScanner.scan(
                    accessMode: accessMode,
                    cachedSources: reusableSources,
                    forceDeep: forceDeep
                ) { relay.send($0) }
                guard !Task.isCancelled else { return }

                await self.receiveRefreshPhase("正在读取应用信息…", scanID: scanID)
                let sizeHints = Dictionary(uniqueKeysWithValues: ledger.sourceSnapshots.map {
                    ($0.url.standardizedFileURL, $0.size)
                })
                let scannedApplications = FileScanner.installedApplications(sizeHints: sizeHints)
                guard !Task.isCancelled else { return }
                await self.receiveApplications(scannedApplications, scanID: scanID)

                await self.finishRefresh(
                    applications: scannedApplications,
                    ledger: ledger,
                    storage: scannedStorage,
                    scanID: scanID,
                    wasDeepScan: forceDeep
                )
            } catch is CancellationError {
                await self.finishCancelledRefresh(scanID: scanID)
            } catch {
                await self.finishFailedRefresh(error, scanID: scanID)
            }
        }
    }

    private func receiveStorage(_ snapshot: StorageSnapshot, scanID: UUID) {
        guard refreshScanID == scanID else { return }
        storage = snapshot
        let existingSizes = Dictionary(uniqueKeysWithValues: storageCategories
            .filter { $0.kind != .unexplained }
            .map { ($0.kind, $0.size) })
        let existingCounts = Dictionary(uniqueKeysWithValues: storageCategories
            .filter { $0.kind != .unexplained }
            .map { ($0.kind, $0.sourceCount) })
        storageCategories = makeStorageCategories(
            categorySizes: existingSizes,
            sourceCounts: existingCounts,
            storage: snapshot,
            candidates: safeCleanupItems,
            isComplete: false
        )
    }

    private func receiveApplications(_ scannedApplications: [InstalledApplication], scanID: UUID) {
        guard refreshScanID == scanID else { return }
        applications = mergingInspectedApplication(into: scannedApplications)
        hasScannedApplications = true
    }

    private func receiveRefreshPhase(_ phase: String, scanID: UUID) {
        guard refreshScanID == scanID else { return }
        scanPhase = phase
    }

    fileprivate func receiveLedgerProgress(_ progress: StorageLedgerProgress, scanID: UUID) {
        guard refreshScanID == scanID else { return }
        analyzedBytes = progress.analyzedBytes
        ledgerScannedItemCount = progress.scannedItemCount
        ledgerInaccessibleCount = progress.inaccessibleCount
        completedLedgerSources = progress.completedSources
        totalLedgerSources = progress.totalSources
        reusedLedgerSources = progress.reusedSourceCount
        rescannedLedgerSources = progress.rescannedSourceCount
        ledgerLargeItems = progress.largeItems
        storageScenes = makeStorageScenes(
            sceneSizes: progress.sceneSizes,
            sourceCounts: progress.sceneSourceCounts
        )
        cachedLedgerSources = progress.sourceSnapshots
        latestLedgerProgress = progress
        isLedgerComplete = false
        storageCategories = makeStorageCategories(
            categorySizes: progress.categorySizes,
            sourceCounts: progress.categorySourceCounts,
            storage: storage,
            candidates: safeCleanupItems,
            isComplete: false
        )
        let currentName = URL(fileURLWithPath: progress.currentSource).lastPathComponent
        let sourceName = currentName.isEmpty ? progress.currentSource : currentName
        if isDeepScanning {
            scanPhase = "深度校准 \(sourceName) · \(progress.rescannedSourceCount)/\(progress.totalSources)"
        } else {
            scanPhase = "核对 \(sourceName) · 更新 \(progress.rescannedSourceCount)，复用 \(progress.reusedSourceCount)"
        }
        if Date().timeIntervalSince(lastCheckpointAt) >= 10 {
            lastCheckpointAt = Date()
            saveCheckpoint(progress)
        }
    }

    private func finishRefresh(
        applications scannedApplications: [InstalledApplication],
        ledger: StorageLedgerScan,
        storage scannedStorage: StorageSnapshot,
        scanID: UUID,
        wasDeepScan: Bool
    ) {
        guard refreshScanID == scanID else { return }
        let finalApplications = mergingInspectedApplication(into: scannedApplications)
        applications = finalApplications
        storage = scannedStorage
        analyzedBytes = ledger.analyzedBytes
        ledgerScannedItemCount = ledger.scannedItemCount
        ledgerInaccessibleCount = ledger.inaccessibleCount
        completedLedgerSources = max(totalLedgerSources, ledger.sourceSnapshots.count)
        totalLedgerSources = completedLedgerSources
        ledgerLargeItems = ledger.largeItems
        storageScenes = makeStorageScenes(
            sceneSizes: ledger.sceneSizes,
            sourceCounts: ledger.sceneSourceCounts
        )
        cachedLedgerSources = ledger.sourceSnapshots
        ledgerDirectorySizeIndex = Self.makeDirectorySizeIndex(from: ledger.sourceSnapshots)
        isLedgerComplete = true
        hasCompletedStorageAnalysis = true
        storageCategories = makeStorageCategories(
            categorySizes: ledger.categorySizes,
            sourceCounts: ledger.categorySourceCounts,
            storage: scannedStorage,
            candidates: safeCleanupItems,
            isComplete: true
        )
        lastLedgerUpdatedAt = Date()
        DiskLedgerCache.save(
            ledger,
            accessMode: fileAccessMode ?? .limited,
            isComplete: true,
            updatedAt: lastLedgerUpdatedAt ?? Date()
        )
        largeItemChildrenCache.removeAll()
        largeItemPath = []
        scanPhase = wasDeepScan ? "深度校准完成" : "快速更新完成"
        isScanning = false
        isDeepScanning = false
        refreshWorkerTask = nil
        refreshScanID = nil

        if let selectedApplicationID,
           !finalApplications.contains(where: { $0.id == selectedApplicationID }) {
            self.selectedApplicationID = nil
            relatedItems = []
        }
        loadSafeCleanupIfNeeded(force: true)
    }

    private func finishCancelledRefresh(scanID: UUID) {
        guard refreshScanID == scanID else { return }
        if let latestLedgerProgress { saveCheckpoint(latestLedgerProgress) }
        isScanning = false
        isLedgerComplete = false
        isDeepScanning = false
        scanPhase = "分析已停止，当前展示已完成部分"
        refreshWorkerTask = nil
        refreshScanID = nil
    }

    private func finishFailedRefresh(_ error: Error, scanID: UUID) {
        guard refreshScanID == scanID else { return }
        if let latestLedgerProgress { saveCheckpoint(latestLedgerProgress) }
        isScanning = false
        isLedgerComplete = false
        isDeepScanning = false
        scanPhase = "分析未完成"
        feedback = Feedback(title: "空间分析未完成", message: error.localizedDescription)
        refreshWorkerTask = nil
        refreshScanID = nil
    }

    func loadSafeCleanupIfNeeded(force: Bool = false) {
        guard !isScanning, !isScanningSafeCleanup else { return }
        guard force || !hasScannedSafeCleanup else { return }
        cleanupWorkerTask?.cancel()
        let scanID = UUID()
        cleanupScanID = scanID
        isScanningSafeCleanup = true
        let bundleIDs = Set(applications.compactMap(\.bundleIdentifier))
        let sizeHints = ledgerSizeHints
        let accessMode = fileAccessMode ?? .limited
        let worker = Task.detached(priority: .utility) {
            FileScanner.safeCleanupItems(
                installedBundleIDs: bundleIDs,
                sizeHints: sizeHints,
                accessMode: accessMode
            )
        }
        cleanupWorkerTask = worker
        Task { [weak self] in
            guard let self else { return }
            let candidates = await worker.value
            guard !Task.isCancelled, self.cleanupScanID == scanID else { return }
            self.safeCleanupItems = candidates
            self.applyCleanupLevel(.recommended)
            self.hasScannedSafeCleanup = true
            self.isScanningSafeCleanup = false
            self.cleanupWorkerTask = nil
            self.cleanupScanID = nil
            self.rebuildStorageCategoriesFromCurrentLedger()
        }
    }

    private var ledgerSizeHints: [URL: Int64] {
        var hints = ledgerDirectorySizeIndex
        for source in cachedLedgerSources {
            hints[source.url.standardizedFileURL] = source.size
        }
        return hints
    }

    func applyCleanupLevel(_ level: CleanupLevel) {
        cleanupLevel = level
        updateSafeCleanupSelection(
            safeCleanupItems.filter { self.shouldSelect($0, at: level) }
        )
    }

    func clearSafeCleanupSelection() {
        cleanupLevel = nil
        updateSafeCleanupSelection([])
    }

    func setSafeCleanupItem(_ item: CleanupItem, selected: Bool) {
        guard safeCleanupItems.contains(where: { $0.id == item.id }),
              !isCleanupItemExcluded(item) else { return }
        let url = item.url.standardizedFileURL
        var urls = safeCleanupSelection.urls
        if selected {
            urls.insert(url)
        } else {
            urls.remove(url)
        }
        updateSafeCleanupSelection(urls: urls)
        cleanupLevel = nil
    }

    func isSafeCleanupItemSelected(_ item: CleanupItem) -> Bool {
        safeCleanupSelection.urls.contains(item.url.standardizedFileURL)
    }

    func isCleanupItemExcluded(_ item: CleanupItem) -> Bool {
        excludedCleanupPaths.contains(item.url.standardizedFileURL.path)
    }

    func toggleCleanupExclusion(_ item: CleanupItem) {
        let path = item.url.standardizedFileURL.path
        if excludedCleanupPaths.contains(path) {
            excludedCleanupPaths.remove(path)
        } else {
            excludedCleanupPaths.insert(path)
        }
        persistCleanupExclusions()
        cleanupLevel = nil
        var urls = safeCleanupSelection.urls
        urls.remove(item.url.standardizedFileURL)
        updateSafeCleanupSelection(urls: urls)
        rebuildStorageCategoriesFromCurrentLedger()
    }

    func resetCleanupExclusions() {
        excludedCleanupPaths.removeAll()
        persistCleanupExclusions()
        applyCleanupLevel(cleanupLevel ?? .recommended)
        rebuildStorageCategoriesFromCurrentLedger()
    }

    func cleanupBytes(for level: CleanupLevel) -> Int64 {
        safeCleanupItems.filter { shouldSelect($0, at: level) }.reduce(0) { $0 + $1.size }
    }

    private func shouldSelect(_ item: CleanupItem, at level: CleanupLevel) -> Bool {
        !isCleanupItemExcluded(item) && item.isIncluded(in: level)
    }

    private func updateSafeCleanupSelection(_ items: [CleanupItem]) {
        safeCleanupSelection = SafeCleanupSelectionState(
            urls: Set(items.map { $0.url.standardizedFileURL }),
            items: items,
            bytes: items.reduce(0) { $0 + $1.size }
        )
    }

    private func updateSafeCleanupSelection(urls: Set<URL>) {
        updateSafeCleanupSelection(
            safeCleanupItems.filter { urls.contains($0.url.standardizedFileURL) }
        )
    }

    private func persistCleanupExclusions() {
        UserDefaults.standard.set(Array(excludedCleanupPaths).sorted(), forKey: "CandorExcludedCleanupPaths")
    }

    private static func makeDirectorySizeIndex(
        from sources: [StorageSourceSnapshot]
    ) -> [URL: Int64] {
        var index: [URL: Int64] = [:]
        for source in sources {
            if source.isDirectory {
                index[source.url.standardizedFileURL] = source.size
            }
            for directory in source.directoryIndex {
                index[directory.url.standardizedFileURL] = directory.size
            }
        }
        return index
    }

    private func saveCheckpoint(_ progress: StorageLedgerProgress) {
        let scan = StorageLedgerScan(
            categorySizes: progress.categorySizes,
            categorySourceCounts: progress.categorySourceCounts,
            sceneSizes: progress.sceneSizes,
            sceneSourceCounts: progress.sceneSourceCounts,
            largeItems: progress.largeItems,
            analyzedBytes: progress.analyzedBytes,
            scannedItemCount: progress.scannedItemCount,
            inaccessibleCount: progress.inaccessibleCount,
            sourceSnapshots: progress.sourceSnapshots
        )
        let updatedAt = Date()
        lastLedgerUpdatedAt = updatedAt
        DiskLedgerCache.save(
            scan,
            accessMode: fileAccessMode ?? .limited,
            isComplete: false,
            updatedAt: updatedAt
        )
    }

    private func rebuildStorageCategoriesFromCurrentLedger() {
        var sizes: [StorageCategoryKind: Int64] = [:]
        var counts: [StorageCategoryKind: Int] = [:]
        var sceneSizes: [StorageSceneKind: Int64] = [:]
        var sceneCounts: [StorageSceneKind: Int] = [:]
        for source in cachedLedgerSources {
            sizes[source.category, default: 0] += source.size
            counts[source.category, default: 0] += 1
            if let scene = source.scene {
                sceneSizes[scene, default: 0] += source.size
                sceneCounts[scene, default: 0] += 1
            }
        }
        storageScenes = makeStorageScenes(sceneSizes: sceneSizes, sourceCounts: sceneCounts)
        storageCategories = makeStorageCategories(
            categorySizes: sizes,
            sourceCounts: counts,
            storage: storage,
            candidates: safeCleanupItems,
            isComplete: isLedgerComplete
        )
    }

    private func mergingInspectedApplication(
        into scannedApplications: [InstalledApplication]
    ) -> [InstalledApplication] {
        var result = scannedApplications
        if let selectedApplicationID,
           let inspected = applications.first(where: { $0.id == selectedApplicationID }),
           !result.contains(where: { $0.id == inspected.id }) {
            result.append(inspected)
        }
        return result.sorted {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func showStorageCategory(_ kind: StorageCategoryKind) {
        selectedStorageCategory = kind == .unexplained ? nil : kind
        selectedStorageScene = nil
        largeItemPath = []
        selectedSection = .largeItems
    }

    func showStorageScene(_ kind: StorageSceneKind) {
        selectedStorageScene = kind
        selectedStorageCategory = nil
        largeItemPath = []
        selectedSection = .largeItems
    }

    func resetLargeItemNavigation() {
        largeItemWorkerTask?.cancel()
        largeItemPath = []
        isScanningLargeItemFolder = false
    }

    func enterLargeItem(_ item: StorageItem) {
        guard item.canOpen, !isScanningLargeItemFolder else { return }
        let key = item.url.standardizedFileURL
        if largeItemChildrenCache[key] != nil {
            largeItemPath.append(item)
            return
        }

        largeItemWorkerTask?.cancel()
        isScanningLargeItemFolder = true
        let accessMode = fileAccessMode ?? .limited
        let directorySizeHints = ledgerDirectorySizeIndex
        let worker = Task.detached(priority: .userInitiated) {
            try DiskLedgerScanner.scanChildren(
                of: item,
                accessMode: accessMode,
                directorySizeHints: directorySizeHints
            )
        }
        largeItemWorkerTask = worker
        Task { [weak self] in
            guard let self else { return }
            do {
                let children = try await worker.value
                guard !Task.isCancelled else { return }
                largeItemChildrenCache[key] = children
                largeItemPath.append(item)
            } catch is CancellationError {
                // A newer folder request replaced this one.
            } catch {
                feedback = Feedback(title: "无法分析此文件夹", message: error.localizedDescription)
            }
            isScanningLargeItemFolder = false
            largeItemWorkerTask = nil
        }
    }

    func navigateLargeItems(to depth: Int) {
        guard depth >= 0, depth <= largeItemPath.count else { return }
        largeItemWorkerTask?.cancel()
        largeItemPath = Array(largeItemPath.prefix(depth))
        isScanningLargeItemFolder = false
    }

    func isLargeItemSelected(_ item: StorageItem) -> Bool {
        selectedLargeItemURLs.contains(item.url.standardizedFileURL)
    }

    func setLargeItem(_ item: StorageItem, selected: Bool) {
        let url = item.url.standardizedFileURL
        guard item.canClean else { return }
        if selected {
            var urls = selectedLargeItemURLs
            let path = url.path
            let conflicting = urls.filter {
                let existingPath = $0.path
                return existingPath.hasPrefix(path + "/") || path.hasPrefix(existingPath + "/")
            }
            for existing in conflicting {
                urls.remove(existing)
                selectedLargeItemIndex[existing] = nil
            }
            urls.insert(url)
            selectedLargeItemURLs = urls
            selectedLargeItemIndex[url] = item
        } else {
            selectedLargeItemURLs.remove(url)
            selectedLargeItemIndex[url] = nil
        }
    }

    func selectAllCurrentLargeItems() {
        for item in currentLargeItems
            where item.action == .selectable && item.risk < .sensitive {
            setLargeItem(item, selected: true)
        }
    }

    func clearCurrentLargeItemSelection() {
        let currentURLs = Set(currentLargeItems.map { $0.url.standardizedFileURL })
        selectedLargeItemURLs.subtract(currentURLs)
        for url in currentURLs { selectedLargeItemIndex[url] = nil }
    }

    func inspectApplication(at url: URL) {
        let normalizedURL = url.standardizedFileURL
        guard normalizedURL.pathExtension.lowercased() == "app" else {
            feedback = Feedback(title: "这不是应用程序", message: "请拖入扩展名为 .app 的应用。")
            return
        }
        selectedSection = .applications
        isInspectingApplication = true
        Task {
            let application = await Task.detached(priority: .userInitiated) {
                FileScanner.application(at: normalizedURL)
            }.value
            guard let application else {
                isInspectingApplication = false
                feedback = Feedback(title: "无法读取应用", message: "这个应用包可能不完整，或当前没有读取权限。")
                return
            }
            if !applications.contains(where: { $0.id == application.id }) {
                applications.append(application)
                applications.sort {
                    if $0.size != $1.size { return $0.size > $1.size }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
            selectedApplicationID = application.id
            inspectSelectedApplication()
        }
    }

    func inspectSelectedApplication() {
        applicationInspectionTask?.cancel()
        guard let application = selectedApplication else {
            relatedItems = []
            isInspectingApplication = false
            return
        }
        isInspectingApplication = true
        relatedItems = []

        let accessMode = fileAccessMode ?? .limited
        let sizeHints = ledgerSizeHints
        let worker = Task.detached(priority: .userInitiated) {
            FileScanner.relatedItems(
                for: application,
                accessMode: accessMode,
                sizeHints: sizeHints
            )
        }
        applicationInspectionTask = worker
        Task {
            let items = await worker.value
            guard selectedApplicationID == application.id else { return }
            relatedItems = items
            isInspectingApplication = false
            applicationInspectionTask = nil
        }
    }

    func clearStagedSelection() {
        updateSafeCleanupSelection([])
        relatedItems = relatedItems.map { item in
            var updated = item
            updated.isSelected = false
            return updated
        }
        cleanupLevel = nil
        selectedLargeItemURLs = []
        selectedLargeItemIndex = [:]
    }

    func cleanStagedItems() {
        clean(items: stagedCleanupItems, context: nil)
    }

    func cleanSelected(_ context: CleanupContext) {
        let selected: [CleanupItem]
        switch context {
        case .application: selected = relatedItems.filter(\.isSelected)
        case .safeCleanup: selected = selectedSafeCleanupItems
        case .largeItems: selected = selectedLargeItems.compactMap(\.cleanupItem)
        }
        clean(items: selected, context: context)
    }

    private func clean(items: [CleanupItem], context: CleanupContext?) {
        guard !isCleaning else { return }
        guard !items.isEmpty else {
            feedback = Feedback(title: "还没有选择项目", message: "勾选确认要移到废纸篓的项目后再继续。")
            return
        }

        isCleaning = true
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                DeletionService.moveToTrash(items)
            }.value
            isCleaning = false
            storage = FileScanner.storageSnapshot()

            let failedURLs = Set(report.failures.map { $0.url.standardizedFileURL })
            updateSafeCleanupSelection(urls: failedURLs)
            relatedItems = relatedItems.map { item in
                var updated = item
                updated.isSelected = failedURLs.contains(item.url.standardizedFileURL)
                return updated
            }
            selectedLargeItemURLs = Set(selectedLargeItemURLs.filter { failedURLs.contains($0.standardizedFileURL) })
            selectedLargeItemIndex = selectedLargeItemIndex.filter { failedURLs.contains($0.key.standardizedFileURL) }

            if context == .application {
                let selectedURLs = Set(items.map(\.url))
                relatedItems.removeAll {
                    selectedURLs.contains($0.url) && !FileManager.default.fileExists(atPath: $0.url.path)
                }
                applications.removeAll {
                    selectedURLs.contains($0.url) && !FileManager.default.fileExists(atPath: $0.url.path)
                }
                if selectedApplication == nil {
                    selectedApplicationID = nil
                    relatedItems = []
                }
            }

            if report.failures.isEmpty {
                feedback = Feedback(
                    title: "已安全移到废纸篓",
                    message: "共移动 \(report.movedCount) 项，约 \(ByteFormatting.string(report.movedBytes))。这部分空间会在清空废纸篓后真正释放，之前仍可恢复。"
                )
            } else {
                let failures = report.failures.prefix(3).map {
                    "• \($0.url.lastPathComponent)：\($0.message)"
                }.joined(separator: "\n")
                feedback = Feedback(
                    title: "部分项目未能移动",
                    message: "已移动 \(report.movedCount) 项，失败项目仍保留选择。\n\(failures)"
                )
            }

            largeItemChildrenCache.removeAll()
            largeItemPath = []
            let movedURLs = items.map(\.url).filter {
                !failedURLs.contains($0.standardizedFileURL)
            }
            invalidateLedgerSources(containing: movedURLs)
            refreshAll()
        }
    }

    private func invalidateLedgerSources(containing changedURLs: [URL]) {
        guard !changedURLs.isEmpty else { return }
        let changedPaths = changedURLs.map { $0.standardizedFileURL.path }
        cachedLedgerSources.removeAll { source in
            let sourcePath = source.url.standardizedFileURL.path
            return changedPaths.contains { changedPath in
                changedPath == sourcePath
                    || changedPath.hasPrefix(sourcePath + "/")
                    || sourcePath.hasPrefix(changedPath + "/")
            }
        }
        ledgerDirectorySizeIndex = Self.makeDirectorySizeIndex(from: cachedLedgerSources)
    }

    private func makeStorageCategories(
        categorySizes: [StorageCategoryKind: Int64],
        sourceCounts: [StorageCategoryKind: Int],
        storage: StorageSnapshot,
        candidates: [CleanupItem],
        isComplete: Bool
    ) -> [StorageCategory] {
        var sizes = categorySizes
        let measuredBytes = sizes.values.reduce(0, +)
        sizes[.unexplained] = max(storage.used - measuredBytes, 0)

        var recommendedSizes: [StorageCategoryKind: Int64] = [:]
        var reviewSizes: [StorageCategoryKind: Int64] = [:]
        for item in candidates {
            let kind = DiskLedgerScanner.category(for: item.url)
            if shouldSelect(item, at: .recommended) {
                recommendedSizes[kind, default: 0] += item.size
            } else if !isCleanupItemExcluded(item) {
                reviewSizes[kind, default: 0] += item.size
            }
        }

        return StorageCategoryKind.allCases
            .map { kind in
                StorageCategory(
                    kind: kind,
                    size: sizes[kind, default: 0],
                    recommendedCleanupSize: recommendedSizes[kind, default: 0],
                    reviewCleanupSize: reviewSizes[kind, default: 0],
                    sourceCount: sourceCounts[kind, default: 0],
                    isComplete: kind == .unexplained ? isComplete : isComplete
                )
            }
            .filter { $0.size > 0 || $0.cleanupCandidateSize > 0 || $0.kind == .unexplained }
            .sorted {
                if $0.size != $1.size { return $0.size > $1.size }
                return $0.kind.title.localizedStandardCompare($1.kind.title) == .orderedAscending
            }
    }

    private func makeStorageScenes(
        sceneSizes: [StorageSceneKind: Int64],
        sourceCounts: [StorageSceneKind: Int]
    ) -> [StorageScene] {
        StorageSceneKind.allCases
            .compactMap { kind in
                let size = sceneSizes[kind, default: 0]
                guard size > 0 else { return nil }
                return StorageScene(
                    kind: kind,
                    size: size,
                    sourceCount: sourceCounts[kind, default: 0]
                )
            }
            .sorted {
                if $0.size != $1.size { return $0.size > $1.size }
                return $0.kind.title.localizedStandardCompare($1.kind.title) == .orderedAscending
            }
    }

}

private final class LedgerProgressRelay: @unchecked Sendable {
    private weak var state: AppState?
    private let scanID: UUID

    init(state: AppState, scanID: UUID) {
        self.state = state
        self.scanID = scanID
    }

    func send(_ progress: StorageLedgerProgress) {
        let state = state
        Task { @MainActor in
            state?.receiveLedgerProgress(progress, scanID: scanID)
        }
    }
}
