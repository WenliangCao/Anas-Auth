import Foundation

enum OTPType: String, Codable, CaseIterable, Sendable {
    case totp
    case hotp
    case steam

    var isTimeBased: Bool {
        self != .hotp
    }
}
