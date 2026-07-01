import SwiftUI

struct ConfiguredPathsView: View {
    let configs: [ProjectCacheConfig]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Configured Cache Path per Project")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if configs.isEmpty {
                Spacer()
                Text("No Resolve disk databases found.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Table(configs) {
                    TableColumn("Project", value: \.projectName)
                        .width(min: 140, ideal: 180, max: 260)
                    TableColumn("Database", value: \.databaseLabel)
                        .width(min: 90, ideal: 110, max: 160)
                    TableColumn("Configured Path") { config in
                        pathCell(for: config)
                    }
                    .width(min: 360, ideal: 480)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 420)
    }

    @ViewBuilder
    private func pathCell(for config: ProjectCacheConfig) -> some View {
        if let path = config.configuredPath, !path.isEmpty {
            if config.isPathConnected {
                Text(path)
            } else {
                Text("\(path) (drive not connected)")
                    .foregroundStyle(.red)
            }
        } else {
            Text("Default (follows Media Storage priority)")
                .foregroundStyle(.orange)
        }
    }
}
