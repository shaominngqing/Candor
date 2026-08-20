import Foundation

enum FileScanner {
    private struct SearchLocation {
        let relativePath: String
        let category: CleanupCategory
        let risk: CleanupRiskLevel
        let explanation: String
        let impact: String
        let recommendedLevel: CleanupLevel?
    }

    private static let relatedLocations: [SearchLocation] = [
        .init(
            relativePath: "Library/Caches",
            category: .cache,
            risk: .regenerable,
            explanation: "应用运行时生成的临时文件，重新打开应用后可再生成。",
            impact: "应用下次启动时可能重新生成缓存，首次打开可能稍慢。",
            recommendedLevel: .recommended
        ),
        .init(
            relativePath: "Library/Logs",
            category: .log,
            risk: .disposable,
            explanation: "应用的诊断日志，通常不包含工作文件。",
            impact: "不影响应用设置和个人文件。",
            recommendedLevel: .light
        ),
        .init(
            relativePath: "Library/Saved Application State",
            category: .savedState,
            risk: .disposable,
            explanation: "窗口位置和上次退出状态，可由系统重新生成。",
            impact: "应用下次启动时可能不会恢复之前的窗口位置。",
            recommendedLevel: .light
        ),
        .init(
            relativePath: "Library/HTTPStorages",
            category: .webData,
            risk: .regenerable,
            explanation: "应用的网络请求缓存，可重新下载。",
            impact: "应用可能重新下载网络内容。",
            recommendedLevel: .recommended
        ),
        .init(
            relativePath: "Library/WebKit",
            category: .webData,
            risk: .sensitive,
            explanation: "内嵌网页数据，可能包含登录状态。",
            impact: "可能需要重新登录，部分离线网页数据会消失。",
            recommendedLevel: nil
        ),
        .init(
            relativePath: "Library/Preferences",
            category: .preferences,
            risk: .sensitive,
            explanation: "应用设置；删除后会恢复默认配置。",
            impact: "应用设置会恢复默认，可能需要重新配置。",
            recommendedLevel: nil
        ),
        .init(
            relativePath: "Library/Application Support",
            category: .support,
            risk: .sensitive,
            explanation: "可能包含插件、下载内容或本地数据库，请确认不再需要。",
            impact: "可能删除账号状态、数据库、插件或用户下载的内容。",
            recommendedLevel: nil
        ),
        .init(
            relativePath: "Library/Containers",
            category: .container,
            risk: .sensitive,
            explanation: "沙盒应用的完整数据容器，可能含用户创建的内容。",
            impact: "可能清除应用的全部本地数据和设置。",
            recommendedLevel: nil
        ),
        .init(
            relativePath: "Library/Group Containers",
            category: .container,
            risk: .sensitive,
            explanation: "可能被同一开发者的多个应用共享，默认不选择。",
            impact: "可能同时影响同一开发者的多个应用。",
            recommendedLevel: nil
        ),
        .init(
            relativePath: "Library/LaunchAgents",
            category: .launchItem,
            risk: .sensitive,
            explanation: "应用的用户级后台启动项。",
            impact: "相关后台服务将不再自动启动。",
            recommendedLevel: nil
        ),
    ]

    private static let orphanLocations: [SearchLocation] = [
        .init(
            relativePath: "Library/Caches",
            category: .cache,
            risk: .regenerable,
            explanation: "未匹配到现有应用的缓存候选；请按路径再次确认。",
            impact: "若对应应用仍在使用其他名称识别，可能需要重新生成缓存。",
            recommendedLevel: .deep
        ),
        .init(
            relativePath: "Library/HTTPStorages",
            category: .webData,
            risk: .regenerable,
            explanation: "未匹配到现有应用的网络缓存候选。",
            impact: "若仍有应用使用它，相关网络内容需要重新下载。",
            recommendedLevel: .deep
        ),
        .init(
            relativePath: "Library/Saved Application State",
            category: .savedState,
            risk: .disposable,
            explanation: "未匹配到现有应用的窗口状态候选。",
            impact: "若仍有应用使用它，窗口状态会被重置。",
            recommendedLevel: .deep
        ),
    ]

    static func installedApplications(sizeHints: [URL: Int64] = [:]) -> [InstalledApplication] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
        let currentExecutable = Bundle.main.bundleURL.standardizedFileURL
        var foundURLs = Set<URL>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            if Task.isCancelled { break }
            guard
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                )
            else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                if Task.isCancelled { break }
                guard url.standardizedFileURL != currentExecutable else { continue }
                foundURLs.insert(url.standardizedFileURL)
            }
        }

        return foundURLs.compactMap { url in
            application(at: url, sizeHint: sizeHints[url.standardizedFileURL])
        }
        .sorted {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func application(at sourceURL: URL) -> InstalledApplication? {
        application(at: sourceURL, sizeHint: nil)
    }

    private static func application(at sourceURL: URL, sizeHint: Int64?) -> InstalledApplication? {
        let url = sourceURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let displayName =
            (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version =
            (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        let terms = [
            displayName,
            info["CFBundleName"] as? String,
            info["CFBundleExecutable"] as? String,
            url.deletingPathExtension().lastPathComponent,
        ].compactMap { $0 }
            .filter { !$0.isEmpty }
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        return InstalledApplication(
            id: url,
            url: url,
            name: displayName,
            bundleIdentifier: bundle.bundleIdentifier,
            version: version,
            searchTerms: Array(Set(terms)),
            size: sizeHint ?? FileSizeCalculator.allocatedSize(of: url),
            modifiedAt: modifiedAt
        )
    }

    static func relatedItems(
        for application: InstalledApplication,
        accessMode: ScanAccessMode,
        sizeHints: [URL: Int64] = [:]
    ) -> [CleanupItem] {
        let applicationCanBeRemoved = (try? DeletionService.validate(application.url)) != nil
        var result: [CleanupItem] = [
            CleanupItem(
                id: application.url,
                url: application.url,
                displayName: application.name,
                category: .application,
                size: application.size,
                modifiedAt: application.modifiedAt,
                risk: .reacquirable,
                recommendedLevel: .recommended,
                explanation: applicationCanBeRemoved
                    ? "应用程序本体。若开发者提供专用卸载器，应优先使用它。"
                    : "此应用不在 Candor 允许清理的位置，只分析关联文件，不会删除应用本体。",
                impact: "应用将从 Mac 移除，需要重新安装才能再次使用。",
                isSelected: applicationCanBeRemoved
            )
        ]

        for location in relatedLocations {
            if Task.isCancelled { break }
            let root = locationURL(relativePath: location.relativePath)
            guard !FileAccessService.shouldSkip(root, in: accessMode) else { continue }
            for url in immediateChildren(of: root) {
                if Task.isCancelled { break }
                let matchesName = application.searchTerms.contains {
                    ResidueMatcher.isRelated(
                        candidateName: url.lastPathComponent,
                        appName: $0,
                        bundleIdentifier: application.bundleIdentifier
                    )
                }
                guard matchesName else { continue }
                result.append(cleanupItem(url: url, location: location, sizeHints: sizeHints))
            }
        }

        return Array(Dictionary(grouping: result, by: \.url).compactMap { $0.value.first })
            .sorted { $0.size > $1.size }
    }

    static func cacheItems(sizeHints: [URL: Int64] = [:]) -> [CleanupItem] {
        let location = relatedLocations.first { $0.category == .cache }!
        return immediateChildren(of: locationURL(relativePath: location.relativePath))
            .prefix { _ in !Task.isCancelled }
            .filter { !$0.lastPathComponent.lowercased().hasPrefix("com.apple.") }
            .map { url in
                var item = cleanupItem(url: url, location: location, sizeHints: sizeHints)
                let shouldRecommend = shouldRecommendCache(
                    modifiedAt: item.modifiedAt,
                    size: item.size
                )
                item.recommendedLevel = shouldRecommend ? .recommended : nil
                item.isSelected = shouldRecommend
                return item
            }
            .sorted { $0.size > $1.size }
    }

    static func orphanedItems(
        installedBundleIDs: Set<String>,
        sizeHints: [URL: Int64] = [:]
    ) -> [CleanupItem] {
        orphanLocations.flatMap { location in
            immediateChildren(of: locationURL(relativePath: location.relativePath))
                .filter { url in
                    let name = url.lastPathComponent
                    let lowercased = name.lowercased()
                    return !lowercased.hasPrefix("com.apple.")
                        && !lowercased.hasPrefix("group.com.apple.")
                        && ResidueMatcher.looksLikeBundleIdentifier(name)
                        && !ResidueMatcher.belongsToInstalledApp(name, installedBundleIDs: installedBundleIDs)
                }
                .map { cleanupItem(url: $0, location: location, sizeHints: sizeHints) }
        }
        .sorted { $0.size > $1.size }
    }

    static func safeCleanupItems(
        installedBundleIDs: Set<String>,
        sizeHints: [URL: Int64] = [:],
        accessMode: ScanAccessMode = .full
    ) -> [CleanupItem] {
        let candidates =
            cacheItems(sizeHints: sizeHints)
            + oldLogItems(sizeHints: sizeHints)
            + oldInstallerItems(sizeHints: sizeHints, accessMode: accessMode)
            + orphanedItems(installedBundleIDs: installedBundleIDs, sizeHints: sizeHints)
            + rebuildableDeveloperItems(sizeHints: sizeHints)
            + staleCodexStagingItems(sizeHints: sizeHints)

        return Array(
            Dictionary(grouping: candidates, by: { $0.url.standardizedFileURL })
                .compactMap { $0.value.first }
        )
        .sorted {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    static func storageSnapshot() -> StorageSnapshot {
        let fileManager = FileManager.default
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: homePath),
            let totalNumber = attributes[.systemSize] as? NSNumber,
            let freeNumber = attributes[.systemFreeSize] as? NSNumber
        else {
            return StorageSnapshot(total: 0, available: 0)
        }
        return StorageSnapshot(total: totalNumber.int64Value, available: freeNumber.int64Value)
    }

    static func shouldRecommendCache(
        modifiedAt: Date?,
        size: Int64,
        now: Date = Date()
    ) -> Bool {
        guard let modifiedAt,
            size >= 10 * 1_024 * 1_024,
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now)
        else {
            return false
        }
        return modifiedAt < cutoff
    }

    private static func locationURL(relativePath: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath, isDirectory: true)
    }

    private static func immediateChildren(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey],
            options: []
        ))?.filter { url in
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            return values?.isSymbolicLink != true
        } ?? []
    }

    private static func cleanupItem(
        url: URL,
        location: SearchLocation,
        sizeHints: [URL: Int64] = [:]
    ) -> CleanupItem {
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return CleanupItem(
            id: url,
            url: url,
            displayName: url.lastPathComponent,
            category: location.category,
            size: sizeHints[url.standardizedFileURL] ?? FileSizeCalculator.allocatedSize(of: url),
            modifiedAt: modifiedAt,
            risk: location.risk,
            recommendedLevel: location.recommendedLevel,
            explanation: location.explanation,
            impact: location.impact,
            isSelected: location.recommendedLevel.map { $0 <= .recommended } ?? false
        )
    }

    private static func rebuildableDeveloperItems(sizeHints: [URL: Int64]) -> [CleanupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations: [(URL, SearchLocation)] = [
            (
                home.appendingPathComponent(".cache", isDirectory: true),
                .init(
                    relativePath: ".cache",
                    category: .cache,
                    risk: .regenerable,
                    explanation: "开发工具和命令行程序生成的缓存；删除后可能需要重新下载依赖。",
                    impact: "相关工具下次运行时可能重新下载依赖或重建索引。",
                    recommendedLevel: .deep
                )
            ),
            (
                home.appendingPathComponent(".gradle/caches", isDirectory: true),
                .init(
                    relativePath: ".gradle/caches",
                    category: .cache,
                    risk: .regenerable,
                    explanation: "Gradle 构建缓存，可以重新生成，但下次构建会更慢并可能重新下载依赖。",
                    impact: "下次构建会变慢，并可能重新下载依赖。",
                    recommendedLevel: .deep
                )
            ),
            (
                home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
                .init(
                    relativePath: "Library/Developer/Xcode/DerivedData",
                    category: .cache,
                    risk: .regenerable,
                    explanation: "Xcode 编译产物，可以重新生成；请先退出正在构建的项目。",
                    impact: "项目下次编译会重新生成索引和构建产物。",
                    recommendedLevel: .deep
                )
            ),
        ]

        return locations.flatMap { root, location in
            immediateChildren(of: root).map {
                cleanupItem(url: $0, location: location, sizeHints: sizeHints)
            }
        }
    }

    private static func oldLogItems(sizeHints: [URL: Int64]) -> [CleanupItem] {
        guard let base = relatedLocations.first(where: { $0.category == .log }) else { return [] }
        let location = SearchLocation(
            relativePath: base.relativePath,
            category: base.category,
            risk: .disposable,
            explanation: "超过 30 天的应用诊断日志，通常不包含工作文件；应用需要时会重新生成。",
            impact: "不会影响应用设置和个人文件。",
            recommendedLevel: .light
        )
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return immediateChildren(of: locationURL(relativePath: location.relativePath))
            .map { cleanupItem(url: $0, location: location, sizeHints: sizeHints) }
            .filter { ($0.modifiedAt ?? Date()) < cutoff && $0.size >= 5 * 1_024 * 1_024 }
    }

    private static func oldInstallerItems(
        sizeHints: [URL: Int64],
        accessMode: ScanAccessMode
    ) -> [CleanupItem] {
        let downloads = locationURL(relativePath: "Downloads")
        guard !FileAccessService.shouldSkip(downloads, in: accessMode) else { return [] }
        let extensions = Set(["dmg", "pkg", "iso"])
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let location = SearchLocation(
            relativePath: "Downloads",
            category: .personalFile,
            risk: .reacquirable,
            explanation: "下载超过 90 天的安装文件。确认对应应用已经安装且不再需要离线安装后再处理。",
            impact: "需要再次下载安装文件才能离线重装。",
            recommendedLevel: .deep
        )
        return immediateChildren(of: downloads)
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .map { cleanupItem(url: $0, location: location, sizeHints: sizeHints) }
            .filter { ($0.modifiedAt ?? Date()) < cutoff }
    }

    private static func staleCodexStagingItems(sizeHints: [URL: Int64]) -> [CleanupItem] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.tmp/bundled-marketplaces", isDirectory: true)
        let cutoff = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let location = SearchLocation(
            relativePath: ".codex/.tmp/bundled-marketplaces",
            category: .cache,
            risk: .regenerable,
            explanation: "Codex 遗留的市场暂存副本。仅列出超过 24 小时的 staging 目录；移动前请先退出 Codex。",
            impact: "Codex 需要时会重新生成或下载市场数据。",
            recommendedLevel: .deep
        )

        return immediateChildren(of: root)
            .filter { $0.lastPathComponent.hasPrefix("openai-bundled.staging-") }
            .compactMap { url in
                var item = cleanupItem(url: url, location: location, sizeHints: sizeHints)
                guard (item.modifiedAt ?? Date()) < cutoff else { return nil }
                item.isSelected = false
                return item
            }
    }
}
