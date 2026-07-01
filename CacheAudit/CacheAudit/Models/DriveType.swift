import Foundation

enum DriveType: String, Codable, Sendable {
    case internalDrive
    case externalDrive
    case unknown

    var label: String {
        switch self {
        case .internalDrive: return "internal"
        case .externalDrive: return "external"
        case .unknown: return "?"
        }
    }
}
