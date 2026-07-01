import Foundation

/// Ports step 3 of the bash script: finds Resolve Disk Database `Project.db`
/// files and reads each project's *configured* cache path
/// (`SM_UserSetup.CachePath`) via sqlite3.
struct ProjectDatabaseReader {
    private static let excludedPathComponents: Set<String> = [".Trashes"]

    func findProjectDatabases(in bases: [URL], maxDepth: Int = 10) async -> [URL] {
        var results: Set<URL> = []

        for base in bases {
            if Task.isCancelled { break }
            results.formUnion(findProjectDatabases(under: base, maxDepth: maxDepth))
        }

        return results.sorted { $0.path < $1.path }
    }

    private func findProjectDatabases(under base: URL, maxDepth: Int) -> [URL] {
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
            if name == "_TEMPLATES" || name == "ARCHIVED" {
                enumerator.skipDescendants()
                continue
            }

            let depth = url.pathComponents.count - baseDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory,
               name == "Project.db",
               url.pathComponents.contains("Resolve Projects") {
                results.append(url)
            }
        }

        return results
    }

    /// The path component immediately preceding "Resolve Projects" — mirrors
    /// the bash script's `sed -E 's#.*/([^/]+)/Resolve Projects/.*#\1#'`.
    func databaseLabel(for dbURL: URL) -> String {
        let components = dbURL.pathComponents
        guard let index = components.firstIndex(of: "Resolve Projects"), index > 0 else { return "?" }
        return components[index - 1]
    }

    func readCachePath(from dbURL: URL) -> String? {
        guard let output = ShellRunner.run(
            "/usr/bin/sqlite3", [dbURL.path, "SELECT CachePath FROM SM_UserSetup LIMIT 1;"]
        ) else { return nil }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func loadConfigs(bases: [URL]) async -> [ProjectCacheConfig] {
        let dbs = await findProjectDatabases(in: bases)
        var configs: [ProjectCacheConfig] = []

        for db in dbs {
            if Task.isCancelled { break }
            let projectName = db.deletingLastPathComponent().lastPathComponent
            let label = databaseLabel(for: db)
            let cachePath = readCachePath(from: db)
            configs.append(ProjectCacheConfig(
                projectName: projectName,
                databaseLabel: label,
                configuredPath: cachePath
            ))
        }

        return configs
    }
}
