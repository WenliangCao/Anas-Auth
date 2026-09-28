import Foundation

enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1
    case sha256
    case sha512

    var displayName: String {
        rawValue.uppercased()
    }
}
