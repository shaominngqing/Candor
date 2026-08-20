import Foundation

enum ResidueMatcher {
    static func normalizedStem(_ name: String) -> String {
        var result = name.lowercased()
        for suffix in [".savedstate", ".plist", ".cache", ".log"] where result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
        }
        return
            result
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    static func isRelated(candidateName: String, appName: String, bundleIdentifier: String?) -> Bool {
        let candidate = normalizedStem(candidateName)
        let normalizedApp = normalizedStem(appName)

        if normalizedApp.count >= 4, candidate == normalizedApp {
            return true
        }

        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        let bundle = bundleIdentifier.lowercased()
        let rawCandidate = candidateName.lowercased()

        return candidate == normalizedStem(bundle)
            || rawCandidate == bundle
            || rawCandidate.hasPrefix(bundle + ".")
            || rawCandidate.hasPrefix(bundle + "-")
    }

    static func looksLikeBundleIdentifier(_ name: String) -> Bool {
        let stem = normalizedStem(name)
        let parts = stem.split(separator: ".")
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }

    static func belongsToInstalledApp(_ candidateName: String, installedBundleIDs: Set<String>) -> Bool {
        let candidate = normalizedStem(candidateName)
        return installedBundleIDs.contains { installedID in
            let installed = installedID.lowercased()
            return candidate == normalizedStem(installed)
                || candidate.hasPrefix(normalizedStem(installed) + ".")
                || normalizedStem(installed).hasPrefix(candidate + ".")
        }
    }
}
