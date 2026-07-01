import SwiftUI

struct DeleteConfirmationView: View {
    let entries: [CacheEntry]
    let isResolveRunning: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var totalBytes: Int64 {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Move \(entries.count) item\(entries.count == 1 ? "" : "s") to Trash?", systemImage: "trash")
                .font(.headline)

            warningBanner

            List(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .fontWeight(.medium)
                    Text(entry.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .badge(entry.sizeBytes.humanReadableSize)
            }
            .frame(minHeight: 200, maxHeight: 320)

            HStack {
                Text("Total: \(totalBytes.humanReadableSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Move to Trash") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .tint(.red)
            }
        }
        .padding()
        .frame(minWidth: 520)
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isResolveRunning {
                Label("DaVinci Resolve is currently running. Close it before deleting cache manually.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
            }
            Text("Close DaVinci Resolve before deleting cache manually. The safer route is Resolve → Playback → Delete Render Cache → All. Use this only for cache you've identified as orphaned via this audit.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isResolveRunning ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
