import Foundation

enum FileSizeCalculator {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
    ]

    static func allocatedSize(of url: URL) -> Int64 {
        guard let initialValues = try? url.resourceValues(forKeys: keys) else { return 0 }

        if initialValues.isRegularFile == true || initialValues.isSymbolicLink == true {
            return Int64(initialValues.totalFileAllocatedSize ?? initialValues.fileAllocatedSize ?? 0)
        }

        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [],
                errorHandler: { _, _ in true }
            )
        else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
