import Foundation

/// Moves selected cache entries to the Trash. This is the only destructive
/// capability in v1, and it deliberately never hard-deletes — `trashItem` is
/// the safety net given the app runs unsandboxed.
struct CacheDeleter {
    enum DeleteError: Error, LocalizedError {
        case trashFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .trashFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    func trashEntries(_ entries: [CacheEntry]) async -> [(entry: CacheEntry, result: Result<Void, Error>)] {
        var results: [(CacheEntry, Result<Void, Error>)] = []

        for entry in entries {
            do {
                try FileManager.default.trashItem(at: entry.path, resultingItemURL: nil)
                results.append((entry, .success(())))
            } catch {
                results.append((entry, .failure(DeleteError.trashFailed(underlying: error))))
            }
        }

        return results
    }
}
