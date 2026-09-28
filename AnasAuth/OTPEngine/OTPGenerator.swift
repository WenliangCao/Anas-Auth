import CryptoKit
import Foundation

/// RFC 4226 (HOTP) / RFC 6238 (TOTP) 验证码生成，外加 Steam 的 5 字符变体。
enum OTPGenerator {
    static let defaultDigits = 6
    static let steamDigits = 5
    static let defaultPeriod = 30

    private static let steamAlphabet = Array("23456789BCDFGHJKMNPQRTVWXY")

    static func hotp(
        secret: Data,
        counter: UInt64,
        digits: Int = defaultDigits,
        algorithm: OTPAlgorithm = .sha1
    ) -> String {
        let digits = max(1, min(digits, 10))
        let value = hotpValue(secret: secret, counter: counter, algorithm: algorithm)
        let modulus = UInt64(pow(10, Double(digits)))
        let digitsString = String(value % modulus)
        return String(repeating: "0", count: digits - digitsString.count) + digitsString
    }

    static func totp(
        secret: Data,
        at date: Date = .now,
        period: Int = defaultPeriod,
        digits: Int = defaultDigits,
        algorithm: OTPAlgorithm = .sha1
    ) -> String {
        let counter = counter(at: date, period: period)
        return hotp(secret: secret, counter: counter, digits: digits, algorithm: algorithm)
    }

    static func steam(
        secret: Data,
        at date: Date = .now,
        period: Int = defaultPeriod
    ) -> String {
        var value = hotpValue(secret: secret, counter: counter(at: date, period: period), algorithm: .sha1)
        var characters = ""
        for _ in 0..<steamDigits {
            characters.append(steamAlphabet[Int(value % UInt64(steamAlphabet.count))])
            value /= UInt64(steamAlphabet.count)
        }
        return characters
    }

    static func counter(at date: Date, period: Int) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970)) / UInt64(max(period, 1))
    }

    static func remainingSeconds(at date: Date = .now, period: Int) -> Int {
        let elapsed = Int(max(0, date.timeIntervalSince1970)) % max(period, 1)
        return max(period, 1) - elapsed
    }

    private static func hotpValue(secret: Data, counter: UInt64, algorithm: OTPAlgorithm) -> UInt64 {
        var bigEndianCounter = counter.bigEndian
        let message = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)
        let mac = authenticationCode(algorithm: algorithm, key: secret, message: message)
        let offset = Int(mac[mac.count - 1] & 0x0f)
        return (UInt64(mac[offset]) & 0x7f) << 24
            | UInt64(mac[offset + 1]) << 16
            | UInt64(mac[offset + 2]) << 8
            | UInt64(mac[offset + 3])
    }

    private static func authenticationCode(algorithm: OTPAlgorithm, key: Data, message: Data) -> Data {
        let key = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
    }
}
