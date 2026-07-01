import Foundation

enum CacheEntryKind: String, Codable, Sendable {
    case project
    case sharedAudio
    case sharedOptimizedMedia

    var label: String {
        switch self {
        case .project: return "Project"
        case .sharedAudio: return "Audio cache (all projects)"
        case .sharedOptimizedMedia: return "Optimized Media (not render cache)"
        }
    }
}

struct CacheEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: CacheEntryKind
    let projectName: String
    let databaseName: String
    let driveType: DriveType
    let path: URL
    let sizeBytes: Int64

    init(
        id: UUID = UUID(),
        kind: CacheEntryKind,
        projectName: String,
        databaseName: String,
        driveType: DriveType,
        path: URL,
        sizeBytes: Int64
    ) {
        self.id = id
        self.kind = kind
        self.projectName = projectName
        self.databaseName = databaseName
        self.driveType = driveType
        self.path = path
        self.sizeBytes = sizeBytes
    }

    var isUnknownProject: Bool {
        projectName.hasPrefix("(unknown")
    }

    var displayName: String {
        kind == .project ? projectName : kind.label
    }
}
