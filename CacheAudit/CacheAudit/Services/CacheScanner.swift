import Foundation

/// Ports the discovery logic from `DaVinci Cache Audit.command`: finds every
/// `CacheClip` render-cache folder under $HOME and any mounted volume, and
/// reads each UUID-named subfolder's `Info.txt` to resolve it back to a
/// project name.
struct CacheScanner {
    private static let uuidRegex = try! NSRegularExpression(
        pattern: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
    )

    private static let excludedPathComponents: Set<String> = [
        ".Trashes", ".Spotlight-V100", ".fseventsd", "Backups.backupdb"
    ]

    /// $HOME plus every mounted volume under /Volumes, excluding the boot
    /// volume itself and Time Machine backup volumes.
    func searchBases() -> [URL] {
        var bases: [URL] = [FileManager.default.homeDirectoryForCurrentUser]

        let bootVolumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName

        guard let volumes = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return bases }

        for volume in volumes {
            guard (try? volume.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let name = volume.lastPathComponent
            if let bootVolumeName, name == bootVolumeName { continue }
            if name.localizedCaseInsensitiveContains("TimeMachine") { continue }
            if name.localizedCaseInsensitiveContains("Backups.backupdb") { continue }
            bases.append(volume)
        }

        return bases
    }

    func isUUIDDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return Self.uuidRegex.firstMatch(in: name, range: range) != nil
    }

    private func isSharedFolderName(_ name: String) -> CacheEntryKind? {
        if name.caseInsensitiveCompare("audio") == .orderedSame { return .sharedAudio }
        if name.caseInsensitiveCompare("OptimizedMedia") == .orderedSame { return .sharedOptimizedMedia }
        return nil
    }

    /// A `CacheClip` directory only counts as "real" if it directly contains a
    /// UUID-named subfolder or one of the shared `audio`/`OptimizedMedia`
    /// folders. Filters out nesting mistakes like `CacheClip/CacheClip`.
    func isRealCacheClipRoot(_ dir: URL) -> Bool {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return false }

        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if isUUIDDirectory(child) { return true }
            if isSharedFolderName(child.lastPathComponent) != nil { return true }
        }
        return false
    }

    /// Finds every real `CacheClip` root under the given search bases.
    func findCacheClipRoots(in bases: [URL], maxDepth: Int = 8) async -> [URL] {
        var candidates: Set<URL> = []

        for base in bases {
            if Task.isCancelled { break }
            let found = findDirectories(named: "cacheclip", under: base, maxDepth: maxDepth)
            candidates.formUnion(found)
        }

        return candidates.filter { isRealCacheClipRoot($0) }.sorted { $0.path < $1.path }
    }

    private func findDirectories(named targetName: String, under base: URL, maxDepth: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let baseDepth = base.pathComponents.count
        var results: [URL] = []

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if Self.excludedPathComponents.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let depth = url.pathComponents.count - baseDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            if name.caseInsensitiveCompare(targetName) == .orderedSame {
                results.append(url)
                enumerator.skipDescendants()
            }
        }

        return results
    }

    /// Reads Database Name / Project Name out of a UUID folder's Info.txt.
    func parseInfoTxt(at folder: URL) -> (project: String?, database: String?) {
        let infoFile = folder.appendingPathComponent("Info.txt")
        guard let contents = try? String(contentsOf: infoFile, encoding: .utf8) else {
            return (nil, nil)
        }

        var project: String?
        var database: String?
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            if project == nil, line.hasPrefix("Project Name: ") {
                project = String(line.dropFirst("Project Name: ".count)).trimmingCharacters(in: .whitespaces)
            }
            if database == nil, line.hasPrefix("Database Name: ") {
                database = String(line.dropFirst("Database Name: ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return (project, database)
    }

    /// Disk usage in bytes, shelling out to `du -sk` (matches the bash
    /// script's numbers and is faster than a pure-Swift walk of thousands of
    /// small cache files).
    func directorySize(at url: URL) -> Int64 {
        guard let output = ShellRunner.run("/usr/bin/du", ["-sk", url.path]) else { return 0 }
        let firstField = output.split(separator: "\t").first ?? output.split(separator: " ").first ?? ""
        guard let kb = Int64(firstField.trimmingCharacters(in: .whitespaces)) else { return 0 }
        return kb * 1024
    }

    /// Scans one CacheClip root's direct children into cache entries.
    func scanCacheClipRoot(_ root: URL) async -> [CacheEntry] {
        let driveType = DriveTypeResolver.driveType(for: root)

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [CacheEntry] = []

        for child in children {
            if Task.isCancelled { break }
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            if isUUIDDirectory(child) {
                let size = directorySize(at: child)
                let (project, database) = parseInfoTxt(at: child)
                entries.append(CacheEntry(
                    kind: .project,
                    projectName: project ?? "(unknown — project possibly deleted)",
                    databaseName: project == nil ? "?" : (database ?? "?"),
                    driveType: driveType,
                    path: child,
                    sizeBytes: size
                ))
            } else if let sharedKind = isSharedFolderName(child.lastPathComponent) {
                let size = directorySize(at: child)
                entries.append(CacheEntry(
                    kind: sharedKind,
                    projectName: sharedKind.label,
                    databaseName: "—",
                    driveType: driveType,
                    path: child,
                    sizeBytes: size
                ))
            }
        }

        return entries
    }
}
