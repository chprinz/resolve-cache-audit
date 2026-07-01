import Foundation

struct ProjectCacheConfig: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let projectName: String
    let databaseLabel: String
    let configuredPath: String?

    init(
        id: UUID = UUID(),
        projectName: String,
        databaseLabel: String,
        configuredPath: String?
    ) {
        self.id = id
        self.projectName = projectName
        self.databaseLabel = databaseLabel
        self.configuredPath = configuredPath
    }

    /// Whether the configured path existed on disk at scan time. `true` for the
    /// "no explicit path" default case, since there's nothing to be disconnected from.
    var isPathConnected: Bool {
        guard let configuredPath, !configuredPath.isEmpty else { return true }
        return FileManager.default.fileExists(atPath: configuredPath)
    }
}
