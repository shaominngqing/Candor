import XCTest
@testable import YuJing

final class ResidueMatcherTests: XCTestCase {
    func testMatchesBundleIdentifierAndDerivedFiles() {
        XCTAssertTrue(ResidueMatcher.isRelated(
            candidateName: "com.example.Writer.savedState",
            appName: "Writer",
            bundleIdentifier: "com.example.Writer"
        ))
        XCTAssertTrue(ResidueMatcher.isRelated(
            candidateName: "com.example.Writer.plist",
            appName: "Writer",
            bundleIdentifier: "com.example.Writer"
        ))
    }

    func testDoesNotUseVeryShortAppNames() {
        XCTAssertFalse(ResidueMatcher.isRelated(
            candidateName: "Go",
            appName: "Go",
            bundleIdentifier: nil
        ))
    }

    func testRecognizesPlausibleOrphanBundleID() {
        XCTAssertTrue(ResidueMatcher.looksLikeBundleIdentifier("com.example.oldapp"))
        XCTAssertTrue(ResidueMatcher.looksLikeBundleIdentifier("com.example.oldapp.savedState"))
        XCTAssertFalse(ResidueMatcher.looksLikeBundleIdentifier("Application Support"))
    }

    func testInstalledParentBundleCoversHelpers() {
        XCTAssertTrue(ResidueMatcher.belongsToInstalledApp(
            "com.example.Writer.helper",
            installedBundleIDs: ["com.example.Writer"]
        ))
        XCTAssertFalse(ResidueMatcher.belongsToInstalledApp(
            "com.other.Legacy",
            installedBundleIDs: ["com.example.Writer"]
        ))
    }
}

final class DeletionSafetyTests: XCTestCase {
    func testRejectsBroadAndSystemPaths() {
        XCTAssertThrowsError(try DeletionService.validate(URL(fileURLWithPath: "/System/Library")))
        XCTAssertThrowsError(try DeletionService.validate(FileManager.default.homeDirectoryForCurrentUser))
    }

    func testAcceptsChildOfUserCacheButNotCacheRoot() {
        let cacheRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
        XCTAssertThrowsError(try DeletionService.validate(cacheRoot))
        XCTAssertNoThrow(try DeletionService.validate(cacheRoot.appendingPathComponent("com.example.test")))
    }

    func testAcceptsPersonalFileButRejectsPersonalFolderRoot() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        XCTAssertThrowsError(try DeletionService.validate(downloads))
        XCTAssertNoThrow(try DeletionService.validate(downloads.appendingPathComponent("archive.dmg")))
    }

    func testAcceptsKnownRebuildableChildrenButProtectsTheirRoots() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexStagingRoot = home.appendingPathComponent(
            ".codex/.tmp/bundled-marketplaces",
            isDirectory: true
        )
        XCTAssertThrowsError(try DeletionService.validate(codexStagingRoot))
        XCTAssertNoThrow(try DeletionService.validate(
            codexStagingRoot.appendingPathComponent("openai-bundled.staging-example")
        ))

        let gradleCacheRoot = home.appendingPathComponent(".gradle/caches", isDirectory: true)
        XCTAssertThrowsError(try DeletionService.validate(gradleCacheRoot))
        XCTAssertNoThrow(try DeletionService.validate(gradleCacheRoot.appendingPathComponent("8.12")))
    }

    func testAndroidSDKUsesWholeComponentsAsRemovalUnits() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let ndkRoot = home.appendingPathComponent("Library/Android/sdk/ndk", isDirectory: true)
        let version = ndkRoot.appendingPathComponent("21.4.7075529", isDirectory: true)
        let leaf = version.appendingPathComponent(
            "toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/liblog.a"
        )

        XCTAssertNil(DeletionService.managedRemovalUnit(containing: ndkRoot))
        XCTAssertEqual(
            DeletionService.managedRemovalUnit(containing: version)?.url,
            version.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            DeletionService.managedRemovalUnit(containing: leaf)?.url,
            version.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertThrowsError(
            try DeletionService.validate(leaf, checkRunningApplications: false)
        ) { error in
            guard case DeletionService.SafetyError.managedUnitRequiresWholeRemoval = error else {
                return XCTFail("NDK 内部文件必须要求整体处理")
            }
        }
    }
}
