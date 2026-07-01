import Foundation

/// Determines whether a path lives on the internal boot drive or an external
/// volume. Prefers the native `volumeIsInternalKey` resource value; falls back
/// to shelling out to `df`/`diskutil` (matching the original bash script) only
/// if that key can't be resolved.
enum DriveTypeResolver {
    static func driveType(for url: URL) -> DriveType {
        if let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey]),
           let isInternal = values.volumeIsInternal {
            return isInternal ? .internalDrive : .externalDrive
        }
        return driveTypeViaShellOut(path: url.path)
    }

    private static func driveTypeViaShellOut(path: String) -> DriveType {
        guard FileManager.default.fileExists(atPath: path) else { return .unknown }

        guard let dfOutput = ShellRunner.run("/bin/df", ["-P", path]) else { return .unknown }
        let lines = dfOutput.split(separator: "\n")
        guard let lastLine = lines.last else { return .unknown }
        let columns = lastLine.split(separator: " ", omittingEmptySubsequences: true)
        guard let device = columns.first else { return .unknown }

        if let diskutilOutput = ShellRunner.run("/usr/sbin/diskutil", ["info", String(device)]) {
            for line in diskutilOutput.split(separator: "\n") {
                if line.contains("Device Location:") {
                    if line.contains("Internal") { return .internalDrive }
                    if line.contains("External") { return .externalDrive }
                }
            }
        }

        // Fallback matching the bash script: anything under /Volumes is
        // treated as external if diskutil couldn't say otherwise.
        return path.hasPrefix("/Volumes/") ? .externalDrive : .internalDrive
    }
}
