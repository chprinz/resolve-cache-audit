import XCTest
@testable import CacheAudit

final class CacheScannerTests: XCTestCase {
    private var tempDir: URL!
    private let scanner = CacheScanner()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - isUUIDDirectory

    func testIsUUIDDirectory_acceptsValidUUID() {
        let url = tempDir.appendingPathComponent("eee02c2c-325d-460f-9aeb-0e28aac8b45f")
        XCTAssertTrue(scanner.isUUIDDirectory(url))
    }

    func testIsUUIDDirectory_rejectsNonUUIDName() {
        let url = tempDir.appendingPathComponent("audio")
        XCTAssertFalse(scanner.isUUIDDirectory(url))

        let malformed = tempDir.appendingPathComponent("eee02c2c-325d-460f-9aeb")
        XCTAssertFalse(scanner.isUUIDDirectory(malformed))
    }

    // MARK: - isRealCacheClipRoot

    func testIsRealCacheClipRoot_trueWhenContainsUUIDFolder() throws {
        let root = tempDir.appendingPathComponent("CacheClip")
        let uuidFolder = root.appendingPathComponent("eee02c2c-325d-460f-9aeb-0e28aac8b45f")
        try FileManager.default.createDirectory(at: uuidFolder, withIntermediateDirectories: true)

        XCTAssertTrue(scanner.isRealCacheClipRoot(root))
    }

    func testIsRealCacheClipRoot_trueWhenContainsAudioFolder() throws {
        let root = tempDir.appendingPathComponent("CacheClip")
        let audioFolder = root.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)

        XCTAssertTrue(scanner.isRealCacheClipRoot(root))
    }

    func testIsRealCacheClipRoot_falseForNestedWrapperOnly() throws {
        // A common manual-setup mistake: CacheClip/CacheClip/<uuid> — the outer
        // folder only wraps another CacheClip folder, so it should NOT count
        // as a real root itself.
        let outer = tempDir.appendingPathComponent("CacheClip")
        let inner = outer.appendingPathComponent("CacheClip")
        let uuidFolder = inner.appendingPathComponent("eee02c2c-325d-460f-9aeb-0e28aac8b45f")
        try FileManager.default.createDirectory(at: uuidFolder, withIntermediateDirectories: true)

        XCTAssertFalse(scanner.isRealCacheClipRoot(outer))
        XCTAssertTrue(scanner.isRealCacheClipRoot(inner))
    }

    // MARK: - parseInfoTxt

    func testParseInfoTxt_extractsProjectAndDatabaseName() throws {
        let folder = tempDir.appendingPathComponent("eee02c2c-325d-460f-9aeb-0e28aac8b45f")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let infoContents = """
        Database Name: X9Pro
        User Name: guest
        Project Name: My Project Name
        """
        try infoContents.write(to: folder.appendingPathComponent("Info.txt"), atomically: true, encoding: .utf8)

        let (project, database) = scanner.parseInfoTxt(at: folder)
        XCTAssertEqual(project, "My Project Name")
        XCTAssertEqual(database, "X9Pro")
    }

    func testParseInfoTxt_returnsNilWhenFileMissing() throws {
        let folder = tempDir.appendingPathComponent("eee02c2c-325d-460f-9aeb-0e28aac8b45f")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let (project, database) = scanner.parseInfoTxt(at: folder)
        XCTAssertNil(project)
        XCTAssertNil(database)
    }

    // MARK: - scanCacheClipRoot

    func testScanCacheClipRoot_producesProjectAndSharedEntries() async throws {
        let root = tempDir.appendingPathComponent("CacheClip")
        let uuidFolder = root.appendingPathComponent("eee02c2c-325d-460f-9aeb-0e28aac8b45f")
        try FileManager.default.createDirectory(at: uuidFolder, withIntermediateDirectories: true)
        try "Database Name: Mac\nProject Name: Test Project\n".write(
            to: uuidFolder.appendingPathComponent("Info.txt"), atomically: true, encoding: .utf8
        )
        try "some cached bytes".write(
            to: uuidFolder.appendingPathComponent("clip.dat"), atomically: true, encoding: .utf8
        )

        let audioFolder = root.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        try "audio bytes".write(
            to: audioFolder.appendingPathComponent("a.dat"), atomically: true, encoding: .utf8
        )

        let entries = await scanner.scanCacheClipRoot(root)

        XCTAssertEqual(entries.count, 2)

        let projectEntry = try XCTUnwrap(entries.first { $0.kind == .project })
        XCTAssertEqual(projectEntry.projectName, "Test Project")
        XCTAssertEqual(projectEntry.databaseName, "Mac")
        XCTAssertGreaterThan(projectEntry.sizeBytes, 0)

        let audioEntry = try XCTUnwrap(entries.first { $0.kind == .sharedAudio })
        XCTAssertEqual(audioEntry.databaseName, "—")
    }

    func testScanCacheClipRoot_missingInfoTxtFallsBackToUnknownProject() async throws {
        let root = tempDir.appendingPathComponent("CacheClip")
        let uuidFolder = root.appendingPathComponent("eee02c2c-325d-460f-9aeb-0e28aac8b45f")
        try FileManager.default.createDirectory(at: uuidFolder, withIntermediateDirectories: true)

        let entries = await scanner.scanCacheClipRoot(root)

        let projectEntry = try XCTUnwrap(entries.first { $0.kind == .project })
        XCTAssertTrue(projectEntry.isUnknownProject)
        XCTAssertEqual(projectEntry.databaseName, "?")
    }
}
