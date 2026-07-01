import AppKit
import Foundation
import Observation

enum ScanState: Equatable {
    case idle
    case scanning(String)
    case done(Date)
    case failed(String)
}

@MainActor
@Observable
final class DashboardViewModel {
    private let service = CacheAuditService()
    private var scanTask: Task<Void, Never>?

    var entries: [CacheEntry] = []
    var configs: [ProjectCacheConfig] = []
    var scanState: ScanState = .idle
    var filterText: String = ""
    var selection: Set<CacheEntry.ID> = []
    var deleteResultMessage: String?

    var isResolveRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.blackmagic-design.DaVinciResolve"
        }
    }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    var filteredEntries: [CacheEntry] {
        guard !filterText.isEmpty else { return entries }
        return entries.filter { $0.projectName.localizedCaseInsensitiveContains(filterText) }
    }

    var totalInternalBytes: Int64 {
        entries.filter { $0.driveType == .internalDrive }.reduce(0) { $0 + $1.sizeBytes }
    }

    var totalExternalBytes: Int64 {
        entries.filter { $0.driveType == .externalDrive }.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedEntries: [CacheEntry] {
        entries.filter { selection.contains($0.id) }
    }

    var selectedTotalBytes: Int64 {
        selectedEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    func startScan() {
        scanTask?.cancel()
        selection.removeAll()
        deleteResultMessage = nil
        scanState = .scanning("Starting…")

        let service = self.service
        scanTask = Task { [weak self] in
            let result = await service.runFullScan { progress in
                Task { @MainActor [weak self] in
                    self?.scanState = .scanning(progress.description)
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.entries = result.entries
            self.configs = result.configs
            self.scanState = .done(result.scannedAt)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanState = .idle
    }

    func deleteSelected() async {
        let toDelete = selectedEntries
        guard !toDelete.isEmpty else { return }

        let results = await service.trash(toDelete)

        var succeededIDs: Set<CacheEntry.ID> = []
        var failures: [(CacheEntry, Error)] = []
        for (entry, result) in results {
            switch result {
            case .success: succeededIDs.insert(entry.id)
            case .failure(let error): failures.append((entry, error))
            }
        }

        entries.removeAll { succeededIDs.contains($0.id) }
        selection.subtract(succeededIDs)

        if failures.isEmpty {
            deleteResultMessage = "\(succeededIDs.count) moved to Trash."
        } else {
            let failedNames = failures.map { $0.0.displayName }.joined(separator: ", ")
            deleteResultMessage = "\(succeededIDs.count) of \(toDelete.count) moved to Trash. Failed: \(failedNames)"
        }
    }
}
