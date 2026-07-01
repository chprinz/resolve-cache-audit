import AppKit
import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    @State private var sortOrder: [KeyPathComparator<CacheEntry>] = [
        KeyPathComparator(\.sizeBytes, order: .reverse)
    ]
    @State private var showDeleteConfirmation = false
    @State private var showConfiguredPaths = false

    private struct EntryGroup: Identifiable {
        let key: String
        let entries: [CacheEntry]
        var id: String { key }
        var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }
    }

    private var sortedFilteredEntries: [CacheEntry] {
        viewModel.filteredEntries.sorted(using: sortOrder)
    }

    /// Groups rows by the Resolve disk database that wrote each cache entry
    /// (from Info.txt), so someone with several databases — e.g. one per
    /// drive — sees them separated instead of one flat mixed list.
    private var groupedEntries: [EntryGroup] {
        let grouped = Dictionary(grouping: sortedFilteredEntries) { entry -> String in
            switch entry.databaseName {
            case "—": return "Shared"
            case "?", "": return "Unknown database"
            default: return entry.databaseName
            }
        }
        return grouped
            .map { EntryGroup(key: $0.key, entries: $0.value) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .scanning(let description) = viewModel.scanState {
                ScanProgressView(description: description)
            }

            Table(of: CacheEntry.self, selection: $viewModel.selection, sortOrder: $sortOrder) {
                TableColumn("Project", value: \.projectName) { entry in
                    Text(entry.displayName)
                        .fontWeight(entry.kind == .project ? .semibold : .regular)
                        .foregroundStyle(entry.kind == .project ? .primary : .secondary)
                }
                TableColumn("Drive", value: \.driveType.label) { entry in
                    Text(entry.driveType.label)
                        .foregroundStyle(driveColor(entry.driveType))
                }
                .width(70)
                TableColumn("Size", value: \.sizeBytes) { entry in
                    Text(entry.sizeBytes.humanReadableSize)
                }
                .width(90)
                TableColumn("Path", value: \.path.path) { entry in
                    Text(entry.path.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } rows: {
                if groupedEntries.count <= 1 {
                    ForEach(sortedFilteredEntries) { entry in
                        TableRow(entry)
                    }
                } else {
                    ForEach(groupedEntries) { group in
                        Section("\(group.key) — \(group.totalBytes.humanReadableSize)") {
                            ForEach(group.entries) { entry in
                                TableRow(entry)
                            }
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: CacheEntry.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Reveal in Finder") { revealInFinder(ids) }
                    Button("Move to Trash…", role: .destructive) {
                        viewModel.selection = ids
                        showDeleteConfirmation = true
                    }
                }
            }

            Divider()

            bottomBar
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.startScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning)
            }
            ToolbarItem(placement: .principal) {
                TextField("Filter by project name", text: $viewModel.filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showConfiguredPaths = true
                } label: {
                    Label("Configured Paths", systemImage: "externaldrive.badge.checkmark")
                }
            }
        }
        .sheet(isPresented: $showConfiguredPaths) {
            ConfiguredPathsView(configs: viewModel.configs)
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteConfirmationView(
                entries: viewModel.selectedEntries,
                isResolveRunning: viewModel.isResolveRunning
            ) {
                Task { await viewModel.deleteSelected() }
            }
        }
        .alert("Cache Audit", isPresented: Binding(
            get: { viewModel.deleteResultMessage != nil },
            set: { newValue in if !newValue { viewModel.deleteResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.deleteResultMessage ?? "")
        }
        .onAppear {
            if case .idle = viewModel.scanState {
                viewModel.startScan()
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Label(viewModel.totalInternalBytes.humanReadableSize, systemImage: "internaldrive")
                .foregroundStyle(.red)
            Label(viewModel.totalExternalBytes.humanReadableSize, systemImage: "externaldrive")
                .foregroundStyle(.green)

            Spacer()

            if !viewModel.selection.isEmpty {
                Text("\(viewModel.selection.count) selected — \(viewModel.selectedTotalBytes.humanReadableSize)")
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Move to Trash…", systemImage: "trash")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func driveColor(_ type: DriveType) -> Color {
        switch type {
        case .internalDrive: return .red
        case .externalDrive: return .green
        case .unknown: return .secondary
        }
    }

    private func revealInFinder(_ ids: Set<CacheEntry.ID>) {
        let urls = viewModel.entries.filter { ids.contains($0.id) }.map(\.path)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
