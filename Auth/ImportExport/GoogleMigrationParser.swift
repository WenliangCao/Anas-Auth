import Foundation

enum GoogleMigrationError: Error {
    case notMigrationURL
    case missingData
    case invalidBase64
    case emptyPayload
}

/// 解析 Google Authenticator 的迁移二维码：
/// `otpauth-migration://offline?data=<base64url 编码的 protobuf>`
/// protobuf schema 见 https://github.com/google/google-authenticator-android 的 MigrationPayload。
enum GoogleMigrationParser {
    static func parse(_ rawURL: String) throws -> [OTPCode] {
        guard let components = URLComponents(string: rawURL),
              components.scheme == "otpauth-migration" else {
            throw GoogleMigrationError.notMigrationURL
        }
        guard let encoded = components.queryItems?.first(where: { $0.name == "data" })?.value,
              !encoded.isEmpty else {
            throw GoogleMigrationError.missingData
        }
        guard let payload = base64URLDecode(encoded) else {
            throw GoogleMigrationError.invalidBase64
        }

        let fields = try ProtobufReader.readFields(from: payload)
        let otpParameterBlobs = fields.filter { $0.number == 1 }.compactMap(\.data)
        guard !otpParameterBlobs.isEmpty else {
            throw GoogleMigrationError.emptyPayload
        }
        return otpParameterBlobs.compactMap(parseOtpParameters(_:))
    }

    private static func parseOtpParameters(_ blob: Data) -> OTPCode? {
        guard let fields = try? ProtobufReader.readFields(from: blob) else { return nil }

        var secret: Data?
        var name = ""
        var issuer = ""
        var algorithm: OTPAlgorithm = .sha1
        var digits = OTPGenerator.defaultDigits
        var type: OTPType = .totp
        var counter = 0

        for field in fields {
            switch field.number {
            case 1: secret = field.data
            case 2: name = field.data.flatMap { String(data: Data($0), encoding: .utf8) } ?? name
            case 3: issuer = field.data.flatMap { String(data: Data($0), encoding: .utf8) } ?? issuer
            case 4:
                switch field.varintValue {
                case 2: algorithm = .sha256
                case 3: algorithm = .sha512
                case 4: return nil // MD5 不支持
                default: algorithm = .sha1
                }
            case 5:
                digits = field.varintValue == 2 ? 8 : OTPGenerator.defaultDigits
            case 6:
                type = field.varintValue == 1 ? .hotp : .totp
            case 7:
                counter = Int(field.varintValue ?? 0)
            default:
                break
            }
        }

        guard let secret, !secret.isEmpty else { return nil }

        // name 可能是 "Issuer:account" 形式；issuer 字段优先
        var accountName = name
        if issuer.isEmpty, let colonIndex = name.firstIndex(of: ":") {
            issuer = String(name[name.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            accountName = String(name[name.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
        }

        return OTPCode(
            issuer: issuer,
            accountName: accountName,
            secret: Base32.encode(secret),
            algorithm: algorithm,
            digits: digits,
            counter: counter,
            type: type
        )
    }

    /// Google 的 data 参数是 URL 安全的 base64，且常省略填充
    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
