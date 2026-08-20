import Foundation

enum ScanAccessMode: String, Codable, Sendable {
    case full
    case limited

    var title: String {
        switch self {
        case .full: "完整磁盘分析"
        case .limited: "有限扫描"
        }
    }
}

enum FullDiskAccessStatus: Sendable {
    case granted
    case notGranted
    case unknown

    var title: String {
        switch self {
        case .granted: "已获得完全磁盘访问权限"
        case .notGranted: "尚未获得完全磁盘访问权限"
        case .unknown: "暂时无法确认授权状态"
        }
    }
}

enum AnalysisDataState: Equatable, Sendable {
    case waiting
    case analyzing
    case ready

    var isReady: Bool { self == .ready }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case largeItems
    case safeCleanup
    case applications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "存储"
        case .largeItems: "大文件与目录"
        case .safeCleanup: "清理建议"
        case .applications: "应用卸载"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "internaldrive.fill"
        case .largeItems: "list.bullet.rectangle.portrait"
        case .safeCleanup: "checkmark.shield.fill"
        case .applications: "square.grid.2x2"
        }
    }
}

struct InstalledApplication: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let searchTerms: [String]
    let size: Int64
    let modifiedAt: Date?

    var subtitle: String {
        if let version, !version.isEmpty { return "版本 \(version)" }
        return bundleIdentifier ?? url.path
    }
}

enum CleanupCategory: String, CaseIterable, Sendable {
    case application = "应用本体"
    case cache = "缓存"
    case log = "日志"
    case savedState = "窗口状态"
    case webData = "网络缓存"
    case preferences = "偏好设置"
    case support = "应用数据"
    case container = "沙盒数据"
    case launchItem = "启动项"
    case personalFile = "个人文件"
    case unknown = "其他"

    var systemImage: String {
        switch self {
        case .application: "app.dashed"
        case .cache: "shippingbox"
        case .log: "doc.plaintext"
        case .savedState: "macwindow"
        case .webData: "network"
        case .preferences: "slider.horizontal.3"
        case .support: "externaldrive"
        case .container: "cube"
        case .launchItem: "bolt"
        case .personalFile: "doc.fill"
        case .unknown: "questionmark.folder"
        }
    }
}

enum CleanupLevel: Int, CaseIterable, Comparable, Identifiable, Sendable, Codable {
    case light = 0
    case recommended = 1
    case deep = 2

    var id: Int { rawValue }

    static func < (lhs: CleanupLevel, rhs: CleanupLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .light: "低影响"
        case .recommended: "标准"
        case .deep: "更多空间"
        }
    }

    var detail: String {
        switch self {
        case .light: "只选旧日志和临时状态"
        case .recommended: "增加长期未使用的应用缓存，首次启动可能稍慢"
        case .deep: "增加大型可重建缓存和可重新获取资源"
        }
    }
}

enum CleanupRiskLevel: Int, Comparable, Sendable, Codable {
    case disposable = 0
    case regenerable = 1
    case reacquirable = 2
    case sensitive = 3

    static func < (lhs: CleanupRiskLevel, rhs: CleanupRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .disposable: "可直接清理"
        case .regenerable: "可再生成"
        case .reacquirable: "可重新获取"
        case .sensitive: "可能含数据"
        }
    }

    var symbol: String {
        switch self {
        case .disposable: "checkmark.circle.fill"
        case .regenerable: "arrow.clockwise.circle.fill"
        case .reacquirable: "arrow.down.circle.fill"
        case .sensitive: "exclamationmark.triangle.fill"
        }
    }

    var defaultImpact: String {
        switch self {
        case .disposable: "删除后通常不会影响应用和个人文件。"
        case .regenerable: "删除后可重新生成，应用下次启动或处理任务时可能稍慢。"
        case .reacquirable: "删除后需要重新下载、安装或创建。"
        case .sensitive: "可能包含设置、数据库或用户创建的内容。"
        }
    }
}

struct CleanupItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let displayName: String
    let category: CleanupCategory
    let size: Int64
    let modifiedAt: Date?
    let risk: CleanupRiskLevel
    var recommendedLevel: CleanupLevel?
    let explanation: String
    let impact: String
    var isSelected: Bool

    func isIncluded(in level: CleanupLevel) -> Bool {
        guard risk < .sensitive, let recommendedLevel else { return false }
        return recommendedLevel <= level
    }
}

struct StorageSnapshot: Sendable {
    let total: Int64
    let available: Int64

    var used: Int64 { max(total - available, 0) }
}

enum StorageCategoryKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case applications
    case appData
    case personalFiles
    case cacheTemporary
    case trash
    case systemProtected
    case unexplained

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "应用本体"
        case .appData: "应用数据"
        case .personalFiles: "个人文件"
        case .cacheTemporary: "缓存与临时文件"
        case .trash: "废纸篓"
        case .systemProtected: "macOS 与受保护文件"
        case .unexplained: "未归类"
        }
    }

    var explanation: String {
        switch self {
        case .applications: "安装在 Applications 目录中的应用程序本体。"
        case .appData: "应用配置、数据库、扩展和下载内容，部分可能包含用户数据。"
        case .personalFiles: "文稿、下载、照片、视频以及放在用户目录中的其他文件。"
        case .cacheTemporary: "缓存、日志和临时副本；只把有明确依据的项目列为清理候选。"
        case .trash: "已经移入废纸篓、但尚未永久释放的空间。"
        case .systemProtected: "macOS、共享资源和不应由清理工具直接修改的内容。"
        case .unexplained: "分析中、访问受限或 APFS 暂时无法归类的空间。"
        }
    }

    var systemImage: String {
        switch self {
        case .applications: "square.grid.2x2.fill"
        case .appData: "externaldrive.fill"
        case .personalFiles: "folder.fill"
        case .cacheTemporary: "shippingbox.fill"
        case .trash: "trash.fill"
        case .systemProtected: "lock.shield.fill"
        case .unexplained: "questionmark.folder.fill"
        }
    }
}

enum StorageSceneKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case photosVideos
    case downloadsInstallers
    case communication
    case cloudOffline
    case games
    case virtualMachines
    case creativeWork
    case developer
    case aiModels
    case deviceBackups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photosVideos: "照片与视频"
        case .downloadsInstallers: "下载与安装包"
        case .communication: "邮件与聊天"
        case .cloudOffline: "云盘与离线文件"
        case .games: "游戏内容"
        case .virtualMachines: "虚拟机与模拟器"
        case .creativeWork: "设计与创作"
        case .developer: "开发环境"
        case .aiModels: "本地 AI 模型"
        case .deviceBackups: "设备备份"
        }
    }

    var explanation: String {
        switch self {
        case .photosVideos: "照片图库、视频素材和媒体文件。"
        case .downloadsInstallers: "下载内容、压缩包以及应用安装文件。"
        case .communication: "邮件、聊天记录与接收的附件。"
        case .cloudOffline: "云盘同步到本机或设置为离线可用的内容。"
        case .games: "游戏平台、游戏本体、资源包和存档。"
        case .virtualMachines: "虚拟机磁盘、容器镜像与模拟器数据。"
        case .creativeWork: "设计、剪辑、音频制作软件的素材与渲染内容。"
        case .developer: "SDK、依赖、编译产物和开发工具数据。"
        case .aiModels: "下载到本机运行的模型、权重与推理资源。"
        case .deviceBackups: "iPhone、iPad 或其他设备保存在 Mac 上的备份。"
        }
    }

    var systemImage: String {
        switch self {
        case .photosVideos: "photo.on.rectangle.angled"
        case .downloadsInstallers: "arrow.down.circle.fill"
        case .communication: "bubble.left.and.bubble.right.fill"
        case .cloudOffline: "icloud.fill"
        case .games: "gamecontroller.fill"
        case .virtualMachines: "server.rack"
        case .creativeWork: "paintbrush.pointed.fill"
        case .developer: "hammer.fill"
        case .aiModels: "brain.head.profile.fill"
        case .deviceBackups: "iphone.and.arrow.forward"
        }
    }
}

struct StorageScene: Identifiable, Hashable, Sendable {
    let kind: StorageSceneKind
    let size: Int64
    let sourceCount: Int

    var id: StorageSceneKind { kind }
}

struct StorageCategory: Identifiable, Hashable, Sendable {
    let kind: StorageCategoryKind
    let size: Int64
    let recommendedCleanupSize: Int64
    let reviewCleanupSize: Int64
    let sourceCount: Int
    let isComplete: Bool

    var id: StorageCategoryKind { kind }
    var cleanupCandidateSize: Int64 { recommendedCleanupSize + reviewCleanupSize }
}

enum StorageItemAction: String, Sendable, Codable {
    case selectable
    case removeAsUnit
    case inspectDeeper
    case partOfManagedUnit
    case manageInApp
    case applicationUninstall
    case trash
    case systemProtected
    case unavailable

    var canSelect: Bool {
        self == .selectable || self == .removeAsUnit
    }

    var title: String {
        switch self {
        case .selectable: "可选择"
        case .removeAsUnit: "整体处理"
        case .inspectDeeper: "进入下一层"
        case .partOfManagedUnit: "属于上层组件"
        case .manageInApp: "在对应应用中管理"
        case .applicationUninstall: "前往应用卸载"
        case .trash: "已在废纸篓"
        case .systemProtected: "系统保护"
        case .unavailable: "暂不支持"
        }
    }

    var symbol: String {
        switch self {
        case .selectable: "checkmark.circle"
        case .removeAsUnit: "shippingbox"
        case .inspectDeeper: "folder"
        case .partOfManagedUnit: "arrow.uturn.backward.circle"
        case .manageInApp: "arrow.up.forward.app"
        case .applicationUninstall: "app.badge"
        case .trash: "trash"
        case .systemProtected: "lock.fill"
        case .unavailable: "minus.circle"
        }
    }
}

struct StorageItem: Identifiable, Hashable, Sendable, Codable {
    let url: URL
    let name: String
    let size: Int64
    let category: StorageCategoryKind
    let scene: StorageSceneKind?
    let isDirectory: Bool
    let canOpen: Bool
    let action: StorageItemAction
    let modifiedAt: Date?
    let risk: CleanupRiskLevel
    let explanation: String
    let actionReason: String?

    var id: URL { url }
    var canClean: Bool { action.canSelect }

    var cleanupItem: CleanupItem? {
        guard canClean else { return nil }
        return CleanupItem(
            id: url,
            url: url,
            displayName: name,
            category: .personalFile,
            size: size,
            modifiedAt: modifiedAt,
            risk: risk,
            recommendedLevel: nil,
            explanation: explanation,
            impact: risk.defaultImpact,
            isSelected: true
        )
    }
}

struct StorageDirectorySnapshot: Hashable, Sendable, Codable {
    let url: URL
    let size: Int64
}

struct StorageSourceSnapshot: Hashable, Sendable, Codable {
    let url: URL
    let category: StorageCategoryKind
    let scene: StorageSceneKind?
    let size: Int64
    let scannedItemCount: Int
    let inaccessibleCount: Int
    let isDirectory: Bool
    let isPackage: Bool
    let modifiedAt: Date?
    let scannedAt: Date
    let largeItem: StorageItem?
    let directoryIndex: [StorageDirectorySnapshot]
}

struct StorageLedgerScan: Sendable, Codable {
    let categorySizes: [StorageCategoryKind: Int64]
    let categorySourceCounts: [StorageCategoryKind: Int]
    let sceneSizes: [StorageSceneKind: Int64]
    let sceneSourceCounts: [StorageSceneKind: Int]
    let largeItems: [StorageItem]
    let analyzedBytes: Int64
    let scannedItemCount: Int
    let inaccessibleCount: Int
    let sourceSnapshots: [StorageSourceSnapshot]
}

struct StorageLedgerProgress: Sendable {
    let categorySizes: [StorageCategoryKind: Int64]
    let categorySourceCounts: [StorageCategoryKind: Int]
    let sceneSizes: [StorageSceneKind: Int64]
    let sceneSourceCounts: [StorageSceneKind: Int]
    let largeItems: [StorageItem]
    let analyzedBytes: Int64
    let scannedItemCount: Int
    let inaccessibleCount: Int
    let completedSources: Int
    let totalSources: Int
    let currentSource: String
    let reusedSourceCount: Int
    let rescannedSourceCount: Int
    let sourceSnapshots: [StorageSourceSnapshot]
}

struct DeletionFailure: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let message: String
}

struct DeletionReport: Sendable {
    let movedCount: Int
    let movedBytes: Int64
    let failures: [DeletionFailure]
}

enum ByteFormatting {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }
}

extension Date {
    var shortChineseText: String {
        formatted(.dateTime.year().month().day())
    }
}
