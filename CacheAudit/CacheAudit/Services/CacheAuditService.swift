import Foundation

struct ScanProgress: Sendable {
    enum Phase: Sendable {
        case findingCacheClipRoots
        case scanningRoot(URL)
        case findingDatabases
        case done
    }
    let phase: Phase

    var description: String {
        switch phase {
        case .findingCacheClipRoots: return "Looking for CacheClip folders…"
        case .scanningRoot(let url): return "Scanning \(url.path)…"
        case .findingDatabases: return "Reading Resolve project databases…"
        case .done: return "Done"
        }
    }
}

struct AuditResult: Sendable {
    let entries: [CacheEntry]
    let configs: [ProjectCacheConfig]
    let scannedAt: Date
}

/// The single seam between the UI layer and all filesystem/process work.
/// `DashboardViewModel` only ever talks to this actor — never directly to
/// `Process`/`FileManager` — so future capabilities (e.g. repointing a
/// project's configured cache path) can be added here without touching the
/// scanning logic or the view layer's contracts.
actor CacheAuditService {
    private let scanner = CacheScanner()
    private let dbReader = ProjectDatabaseReader()
    private let deleter = CacheDeleter()

    func runFullScan(onProgress: @escaping @Sendable (ScanProgress) -> Void) async -> AuditResult {
        let bases = scanner.searchBases()

        onProgress(ScanProgress(phase: .findingCacheClipRoots))
        let roots = await scanner.findCacheClipRoots(in: bases)

        var entries: [CacheEntry] = []
        for root in roots {
            if Task.isCancelled { break }
            onProgress(ScanProgress(phase: .scanningRoot(root)))
            let rootEntries = await scanner.scanCacheClipRoot(root)
            entries.append(contentsOf: rootEntries)
        }

        onProgress(ScanProgress(phase: .findingDatabases))
        let configs = Task.isCancelled ? [] : await dbReader.loadConfigs(bases: bases)

        onProgress(ScanProgress(phase: .done))
        return AuditResult(entries: entries, configs: configs, scannedAt: Date())
    }

    func trash(_ entries: [CacheEntry]) async -> [(entry: CacheEntry, result: Result<Void, Error>)] {
        await deleter.trashEntries(entries)
    }
}
