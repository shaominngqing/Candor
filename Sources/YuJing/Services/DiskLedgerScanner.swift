import Foundation

enum DiskLedgerScanner {
    enum ScanError: LocalizedError {
        case unavailable(URL)

        var errorDescription: String? {
            switch self {
            case .unavailable(let url): "无法读取：\(url.path)"
            }
        }
    }

    private struct Source: Sendable {
        let url: URL
        let category: StorageCategoryKind
        let scene: StorageSceneKind?
    }

    private struct MeasuredSource {
        let size: Int64
        let scannedItemCount: Int
        let inaccessibleCount: Int
        let isDirectory: Bool
        let isPackage: Bool
        let modifiedAt: Date?
    }

    private static let largeItemThreshold: Int64 = 100 * 1_024 * 1_024
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey
    ]

    static func scan(
        accessMode: ScanAccessMode,
        cachedSources: [StorageSourceSnapshot] = [],
        forceDeep: Bool = false,
        progress: @escaping @Sendable (StorageLedgerProgress) -> Void = { _ in }
    ) throws -> StorageLedgerScan {
        let sources = scanSources(accessMode: accessMode)
        let sourceIndex = Dictionary(uniqueKeysWithValues: sources.map {
            (
                $0.url.standardizedFileURL,
                "\($0.category.rawValue)|\($0.scene?.rawValue ?? "")"
            )
        })
        var snapshots: [URL: StorageSourceSnapshot] = Dictionary(
            uniqueKeysWithValues: cachedSources.compactMap { snapshot -> (URL, StorageSourceSnapshot)? in
            let url = snapshot.url.standardizedFileURL
            let fingerprint = "\(snapshot.category.rawValue)|\(snapshot.scene?.rawValue ?? "")"
            guard sourceIndex[url] == fingerprint,
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return (url, snapshot)
            }
        )
        var reusedSourceCount = 0
        var rescannedSourceCount = 0
        var lastEmission = Date.distantPast

        for (index, source) in sources.enumerated() {
            try checkCancellation()
            let key = source.url.standardizedFileURL
            let cached = snapshots[key]
            let currentModifiedAt = modificationDate(of: source.url)
            if let cached,
               shouldReuse(
                   cached,
                   currentModifiedAt: currentModifiedAt,
                   now: Date(),
                   forceDeep: forceDeep
               ) {
                reusedSourceCount += 1
            } else {
                let measured = try measure(source.url)
                let item = measured.size >= largeItemThreshold
                    ? storageItem(source: source, measured: measured)
                    : nil
                snapshots[key] = StorageSourceSnapshot(
                    url: source.url,
                    category: source.category,
                    scene: source.scene,
                    size: measured.size,
                    scannedItemCount: measured.scannedItemCount,
                    inaccessibleCount: measured.inaccessibleCount,
                    isDirectory: measured.isDirectory,
                    isPackage: measured.isPackage,
                    modifiedAt: measured.modifiedAt,
                    scannedAt: Date(),
                    largeItem: item
                )
                rescannedSourceCount += 1
            }

            let now = Date()
            let shouldEmit = index == sources.count - 1
                || index % 4 == 0
                || now.timeIntervalSince(lastEmission) >= 0.2
            if shouldEmit {
                lastEmission = now
                let aggregate = aggregate(Array(snapshots.values))
                progress(StorageLedgerProgress(
                    categorySizes: aggregate.categorySizes,
                    categorySourceCounts: aggregate.categorySourceCounts,
                    sceneSizes: aggregate.sceneSizes,
                    sceneSourceCounts: aggregate.sceneSourceCounts,
                    largeItems: aggregate.largeItems,
                    analyzedBytes: aggregate.analyzedBytes,
                    scannedItemCount: aggregate.scannedItemCount,
                    inaccessibleCount: aggregate.inaccessibleCount,
                    completedSources: index + 1,
                    totalSources: sources.count,
                    currentSource: source.url.path,
                    reusedSourceCount: reusedSourceCount,
                    rescannedSourceCount: rescannedSourceCount,
                    sourceSnapshots: aggregate.sourceSnapshots
                ))
            }
        }

        return aggregate(Array(snapshots.values))
    }

    static func scanChildren(
        of parent: StorageItem,
        accessMode: ScanAccessMode
    ) throws -> [StorageItem] {
        guard parent.canOpen, !FileAccessService.shouldSkip(parent.url, in: accessMode) else { return [] }
        let childURLs = try FileManager.default.contentsOfDirectory(
            at: parent.url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        var items: [StorageItem] = []
        for url in childURLs {
            try checkCancellation()
            guard !isSymbolicLink(url), !FileAccessService.shouldSkip(url, in: accessMode) else { continue }
            let category = category(for: url, fallback: parent.category)
            let source = Source(
                url: url,
                category: category,
                scene: scene(for: url) ?? parent.scene
            )
            let measured = try measure(url)
            guard measured.size > 0 || measured.inaccessibleCount > 0 else { continue }
            items.append(storageItem(source: source, measured: measured))
        }
        return items.sorted(by: itemSort)
    }

    static func category(for url: URL) -> StorageCategoryKind {
        category(for: url, fallback: .appData)
    }

    private static func scanSources(accessMode: ScanAccessMode) -> [Source] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        var sources: [Source] = []
        var insertedPaths = Set<String>()

        func append(_ url: URL, category: StorageCategoryKind) {
            let normalized = url.standardizedFileURL
            guard fileManager.fileExists(atPath: normalized.path),
                  !FileAccessService.shouldSkip(normalized, in: accessMode),
                  insertedPaths.insert(normalized.path).inserted,
                  !isSymbolicLink(normalized) else { return }
            sources.append(Source(
                url: normalized,
                category: category,
                scene: scene(for: normalized)
            ))
        }

        func appendChildren(
            of directory: URL,
            fallback: StorageCategoryKind,
            excluding excludedNames: Set<String> = []
        ) {
            guard !FileAccessService.shouldSkip(directory, in: accessMode) else { return }
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            ) else {
                append(directory, category: fallback)
                return
            }
            for child in children where !excludedNames.contains(child.lastPathComponent) {
                append(child, category: category(for: child, fallback: fallback))
            }
        }

        appendChildren(
            of: URL(fileURLWithPath: "/Applications", isDirectory: true),
            fallback: .applications
        )
        appendChildren(
            of: home.appendingPathComponent("Applications", isDirectory: true),
            fallback: .applications
        )

        if let homeChildren = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) {
            for child in homeChildren {
                let name = child.lastPathComponent
                if name == "Applications" { continue }
                if name == "Library" {
                    appendLibrarySources(at: child, append: append, appendChildren: appendChildren)
                } else if ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].contains(name) {
                    appendChildren(of: child, fallback: .personalFiles)
                } else if [".codex", ".cache", ".gradle", ".android"].contains(name) {
                    appendChildren(of: child, fallback: category(for: child, fallback: .appData))
                } else {
                    append(child, category: category(for: child, fallback: .personalFiles))
                }
            }
        }

        append(
            URL(fileURLWithPath: "/Users/Shared", isDirectory: true),
            category: .personalFiles
        )
        append(
            URL(fileURLWithPath: "/Library", isDirectory: true),
            category: .systemProtected
        )
        append(
            URL(fileURLWithPath: "/private", isDirectory: true),
            category: .systemProtected
        )
        append(
            URL(fileURLWithPath: "/usr", isDirectory: true),
            category: .systemProtected
        )
        append(
            URL(fileURLWithPath: "/opt", isDirectory: true),
            category: .systemProtected
        )
        appendChildren(
            of: URL(fileURLWithPath: "/System", isDirectory: true),
            fallback: .systemProtected,
            excluding: ["Volumes"]
        )

        return sources.sorted {
            let leftPriority = categoryPriority($0.category)
            let rightPriority = categoryPriority($1.category)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    private static func appendLibrarySources(
        at library: URL,
        append: (URL, StorageCategoryKind) -> Void,
        appendChildren: (URL, StorageCategoryKind, Set<String>) -> Void
    ) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: library,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) else {
            append(library, .appData)
            return
        }

        let expanded = Set([
            "Application Support", "Containers", "Group Containers", "Caches",
            "Developer", "CloudStorage", "Mobile Documents", "Mail"
        ])
        for child in children {
            let fallback = category(for: child, fallback: .appData)
            if expanded.contains(child.lastPathComponent) {
                appendChildren(child, fallback, [])
            } else {
                append(child, fallback)
            }
        }
    }

    private static func measure(_ url: URL) throws -> MeasuredSource {
        guard let rootValues = try? url.resourceValues(forKeys: resourceKeys) else {
            return MeasuredSource(
                size: 0,
                scannedItemCount: 1,
                inaccessibleCount: 1,
                isDirectory: false,
                isPackage: false,
                modifiedAt: nil
            )
        }

        let isDirectory = rootValues.isDirectory == true
        let isPackage = rootValues.isPackage == true
        let modifiedAt = rootValues.contentModificationDate
        if rootValues.isRegularFile == true {
            return MeasuredSource(
                size: allocatedSize(rootValues),
                scannedItemCount: 1,
                inaccessibleCount: 0,
                isDirectory: false,
                isPackage: false,
                modifiedAt: modifiedAt
            )
        }
        guard isDirectory else {
            return MeasuredSource(
                size: 0,
                scannedItemCount: 1,
                inaccessibleCount: 0,
                isDirectory: false,
                isPackage: false,
                modifiedAt: modifiedAt
            )
        }

        var inaccessibleCount = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in
                inaccessibleCount += 1
                return true
            }
        ) else {
            return MeasuredSource(
                size: 0,
                scannedItemCount: 1,
                inaccessibleCount: 1,
                isDirectory: true,
                isPackage: isPackage,
                modifiedAt: modifiedAt
            )
        }

        var total: Int64 = 0
        var itemCount = 1
        for case let itemURL as URL in enumerator {
            try checkCancellation()
            itemCount += 1
            guard let values = try? itemURL.resourceValues(forKeys: resourceKeys) else {
                inaccessibleCount += 1
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true { total += allocatedSize(values) }
        }
        return MeasuredSource(
            size: total,
            scannedItemCount: itemCount,
            inaccessibleCount: inaccessibleCount,
            isDirectory: true,
            isPackage: isPackage,
            modifiedAt: modifiedAt
        )
    }

    static func shouldReuse(
        _ snapshot: StorageSourceSnapshot,
        currentModifiedAt: Date?,
        now: Date = Date(),
        forceDeep: Bool = false
    ) -> Bool {
        guard !forceDeep,
              now.timeIntervalSince(snapshot.scannedAt) < cacheLifetime(for: snapshot.category),
              modificationDatesMatch(snapshot.modifiedAt, currentModifiedAt) else { return false }
        return true
    }

    static func cacheLifetime(for category: StorageCategoryKind) -> TimeInterval {
        switch category {
        case .cacheTemporary, .trash: 30 * 60
        case .appData: 2 * 60 * 60
        case .personalFiles: 6 * 60 * 60
        case .applications: 12 * 60 * 60
        case .systemProtected, .unexplained: 24 * 60 * 60
        }
    }

    private static func modificationDatesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): abs(lhs.timeIntervalSince(rhs)) < 0.001
        case (nil, nil): true
        default: false
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func aggregate(_ snapshots: [StorageSourceSnapshot]) -> StorageLedgerScan {
        var categorySizes: [StorageCategoryKind: Int64] = [:]
        var categorySourceCounts: [StorageCategoryKind: Int] = [:]
        var sceneSizes: [StorageSceneKind: Int64] = [:]
        var sceneSourceCounts: [StorageSceneKind: Int] = [:]
        var analyzedBytes: Int64 = 0
        var scannedItemCount = 0
        var inaccessibleCount = 0

        for snapshot in snapshots {
            categorySizes[snapshot.category, default: 0] += snapshot.size
            categorySourceCounts[snapshot.category, default: 0] += 1
            if let scene = snapshot.scene {
                sceneSizes[scene, default: 0] += snapshot.size
                sceneSourceCounts[scene, default: 0] += 1
            }
            analyzedBytes += snapshot.size
            scannedItemCount += snapshot.scannedItemCount
            inaccessibleCount += snapshot.inaccessibleCount
        }
        let sortedSnapshots = snapshots.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
        return StorageLedgerScan(
            categorySizes: categorySizes,
            categorySourceCounts: categorySourceCounts,
            sceneSizes: sceneSizes,
            sceneSourceCounts: sceneSourceCounts,
            largeItems: snapshots.compactMap(\.largeItem).sorted(by: itemSort),
            analyzedBytes: analyzedBytes,
            scannedItemCount: scannedItemCount,
            inaccessibleCount: inaccessibleCount,
            sourceSnapshots: sortedSnapshots
        )
    }

    private static func storageItem(source: Source, measured: MeasuredSource) -> StorageItem {
        let canClean: Bool
        if [.applications, .trash, .systemProtected].contains(source.category) {
            canClean = false
        } else {
            canClean = (try? DeletionService.validate(source.url)) != nil
        }
        return StorageItem(
            url: source.url,
            name: displayName(for: source.url),
            size: measured.size,
            category: source.category,
            scene: source.scene,
            isDirectory: measured.isDirectory,
            canOpen: measured.isDirectory && !measured.isPackage,
            canClean: canClean,
            modifiedAt: measured.modifiedAt,
            safety: safety(for: source.category),
            explanation: source.category.explanation
        )
    }

    private static func category(
        for url: URL,
        fallback: StorageCategoryKind
    ) -> StorageCategoryKind {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let lowerPath = path.lowercased()
        let name = url.lastPathComponent.lowercased()

        if lowerPath == home.lowercased() + "/.trash" || lowerPath.contains("/.trash/") {
            return .trash
        }
        if path.hasPrefix("/System/") || path == "/System"
            || path.hasPrefix("/Library/") || path == "/Library"
            || path.hasPrefix("/private/") || path == "/private"
            || path.hasPrefix("/usr/") || path == "/usr"
            || path.hasPrefix("/opt/") || path == "/opt" {
            return .systemProtected
        }
        if lowerPath.hasPrefix("/applications/")
            || lowerPath.hasPrefix(home.lowercased() + "/applications/") {
            return .applications
        }
        if containsAny(lowerPath, [
            "/library/caches/", "/library/logs/", "/library/httpstorages/",
            "/library/saved application state/", "/.cache/", "/.codex/.tmp/",
            "/.gradle/caches/"
        ]) || ["caches", "logs", ".cache", ".tmp", "tmp"].contains(name) {
            return .cacheTemporary
        }
        if lowerPath.contains("/library/mobile documents/")
            || lowerPath.contains("/library/cloudstorage/")
            || lowerPath.contains("/library/mail/") {
            return .personalFiles
        }
        if lowerPath.contains("/library/") || name.hasPrefix(".") {
            return fallback == .personalFiles ? .appData : fallback
        }
        return fallback
    }

    static func scene(for url: URL) -> StorageSceneKind? {
        let normalized = url.standardizedFileURL
        let path = normalized.path.lowercased()
        let name = normalized.deletingPathExtension().lastPathComponent.lowercased()
        let pathExtension = normalized.pathExtension.lowercased()
        return sceneRules.first {
            $0.matches(path: path, name: name, pathExtension: pathExtension)
        }?.kind
    }

    private struct SceneRule: Sendable {
        let kind: StorageSceneKind
        let pathFragments: [String]
        let nameFragments: [String]
        let extensions: Set<String>

        func matches(path: String, name: String, pathExtension: String) -> Bool {
            pathFragments.contains(where: path.contains)
                || nameFragments.contains(where: name.contains)
                || extensions.contains(pathExtension)
        }
    }

    private static let sceneRules: [SceneRule] = [
        SceneRule(
            kind: .deviceBackups,
            pathFragments: [
                "/library/application support/mobilesync",
                "/mobile backups/"
            ],
            nameFragments: ["iphone backup", "ipad backup", "手机备份"],
            extensions: []
        ),
        SceneRule(
            kind: .aiModels,
            pathFragments: [
                "/.ollama", "/huggingface/", "/huggingface_hub/", "/models--",
                "/stable-diffusion", "/comfyui/models", "/lm studio/"
            ],
            nameFragments: ["ollama", "huggingface", "lm studio", "comfyui"],
            extensions: ["gguf", "safetensors", "ckpt"]
        ),
        SceneRule(
            kind: .virtualMachines,
            pathFragments: [
                "/parallels/", "/vmware/", "/utm/", "/virtualbox/", "/docker/",
                "/library/developer/coresimulator/", "/containers/com.utmapp.utm/"
            ],
            nameFragments: ["parallels", "vmware", "virtualbox", "docker", "模拟器"],
            extensions: ["pvm", "vmdk", "qcow2", "utm", "vmwarevm", "vdi"]
        ),
        SceneRule(
            kind: .games,
            pathFragments: [
                "/steam/", "/steamapps/", "/epic games/", "/battle.net/",
                "/riot games/", "/gog.com/", "/minecraft/"
            ],
            nameFragments: ["steam", "epic games", "battle.net", "minecraft", "游戏"],
            extensions: []
        ),
        SceneRule(
            kind: .creativeWork,
            pathFragments: [
                "/adobe/", "/final cut", "/davinci resolve/", "/logic/",
                "/blender/", "/affinity/", "/capture one/"
            ],
            nameFragments: [
                "photoshop", "illustrator", "premiere", "after effects", "final cut",
                "davinci", "lightroom", "blender", "affinity", "剪映"
            ],
            extensions: [
                "psd", "psb", "ai", "aep", "prproj", "fcpxlibrary", "imovielibrary",
                "logicx", "blend"
            ]
        ),
        SceneRule(
            kind: .communication,
            pathFragments: [
                "/library/mail", "/messages/", "wechat", "wework", "xinwechat",
                "lark", "feishu", "telegram", "whatsapp", "dingtalk", "tencent.qq"
            ],
            nameFragments: [
                "wechat", "wework", "lark", "feishu", "telegram", "whatsapp",
                "dingtalk", "tencent.qq", "微信", "企业微信", "飞书", "钉钉"
            ],
            extensions: []
        ),
        SceneRule(
            kind: .cloudOffline,
            pathFragments: [
                "/library/cloudstorage", "/library/mobile documents", "/onedrive/",
                "/dropbox/", "/google drive/", "/icloud drive/", "/baidunetdisk/"
            ],
            nameFragments: ["onedrive", "dropbox", "google drive", "百度网盘", "坚果云"],
            extensions: []
        ),
        SceneRule(
            kind: .developer,
            pathFragments: [
                "/library/developer", "/library/android", "/.gradle", "/.android",
                "/.cargo", "/.rustup", "/.pub-cache", "/.cocoapods", "/.dartserver",
                "/.cursor", "/node_modules/", "/flutter/", "/androidstudioprojects/"
            ],
            nameFragments: [
                "xcode", "android studio", "jetbrains", "visual studio code", "vscode",
                "cursor", "qoder", "kiro", "trae"
            ],
            extensions: ["xcodeproj", "xcworkspace"]
        ),
        SceneRule(
            kind: .photosVideos,
            pathFragments: ["/pictures/", "/movies/", "/photos library.photoslibrary/"],
            nameFragments: ["photos library", "照片图库"],
            extensions: [
                "jpg", "jpeg", "png", "heic", "tiff", "gif", "raw", "cr2", "nef",
                "mov", "mp4", "mkv", "avi", "m4v", "photoslibrary"
            ]
        ),
        SceneRule(
            kind: .downloadsInstallers,
            pathFragments: ["/downloads/"],
            nameFragments: [],
            extensions: ["dmg", "pkg", "iso", "zip", "rar", "7z", "tar", "gz"]
        )
    ]

    private static func safety(for category: StorageCategoryKind) -> SafetyLevel {
        switch category {
        case .cacheTemporary: .safe
        case .applications, .trash: .review
        case .appData, .personalFiles, .systemProtected, .unexplained: .sensitive
        }
    }

    private static func displayName(for url: URL) -> String {
        if url.path == "/Library" { return "系统资源库" }
        if url.path == "/private" { return "系统运行数据" }
        if url.path == "/usr" { return "Unix 系统组件" }
        if url.path == "/opt" { return "第三方命令行工具" }
        if url.path == "/Users/Shared" { return "共享文件" }
        return url.deletingPathExtension().lastPathComponent.isEmpty
            ? url.path
            : url.deletingPathExtension().lastPathComponent
    }

    private static func categoryPriority(_ category: StorageCategoryKind) -> Int {
        switch category {
        case .cacheTemporary: 0
        case .applications: 1
        case .appData: 2
        case .personalFiles: 3
        case .trash: 4
        case .systemProtected: 5
        case .unexplained: 6
        }
    }

    private static func containsAny(_ value: String, _ fragments: [String]) -> Bool {
        fragments.contains { value.contains($0) }
    }

    private static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func itemSort(_ lhs: StorageItem, _ rhs: StorageItem) -> Bool {
        if lhs.size != rhs.size { return lhs.size > rhs.size }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw CancellationError() }
    }
}
