import Foundation

extension Int64 {
    var humanReadableSize: String {
        ByteCountFormatter.cacheAuditFormatter.string(fromByteCount: self)
    }
}

extension ByteCountFormatter {
    static let cacheAuditFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()
}
