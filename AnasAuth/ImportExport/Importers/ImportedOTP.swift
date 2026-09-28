import Foundation

/// 导入过程中的错误，文案直接展示给用户
enum ImportProviderError: Error, Equatable, LocalizedError {
    /// 文件格式不对（不是该 App 的导出文件）
    case invalidFile(String)
    /// 该 App 的导出版本不支持
    case unsupportedVersion(String)
    /// 密码错误（或文件被篡改）
    case incorrectPassword
    /// 某一条目解析失败：与 ente 一致，整批导入中止，并把出错条目给用户看
    case invalidEntry(entry: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let message): message
        case .unsupportedVersion(let message): message
        case .incorrectPassword: String(localized: "Incorrect password. Check it and try again.")
        case .invalidEntry(_, let reason): String(localized: "One entry couldn’t be read: \(reason)")
        }
    }
}

/// 各导入器共用的条目构造，规则与 ente 的 buildImportOtpUri 一致：
/// - digits 缺省或为 0 时取 6，超过 10 视为错误
/// - period 缺省或 ≤0 时取 30
/// - HOTP counter 缺省为 0，负数视为错误
/// - 类型只接受 totp / hotp / steam（allowSteam=false 时不接受 steam）
enum ImportedOTP {
    static let maxDigits = 10

    static func make(
        kind: String,
        issuer: String,
        account: String,
        secret: String,
        algorithm: String?,
        digits: Any?,
        period: Any? = nil,
        counter: Any? = nil,
        allowSteam: Bool = true,
        note: String = "",
        pinned: Bool = false,
        tags: [String] = []
    ) throws -> OTPCode {
        let type: OTPType
        switch kind.lowercased() {
        case "totp": type = .totp
        case "hotp": type = .hotp
        case "steam" where allowSteam: type = .steam
        default: throw ImportFailure(String(localized: "Unsupported code type: \(kind)"))
        }

        let sanitizedSecret = OTPAuthURLParser.sanitizeSecret(secret)
        guard !sanitizedSecret.isEmpty, (try? Base32.decode(sanitizedSecret)) != nil else {
            throw ImportFailure(String(localized: "The secret isn’t valid Base32"))
        }

        var parsedDigits = integer(digits) ?? 0
        if parsedDigits == 0 { parsedDigits = OTPGenerator.defaultDigits }
        guard (1...maxDigits).contains(parsedDigits) else {
            throw ImportFailure(String(localized: "Invalid number of digits: \(parsedDigits)"))
        }
        if type == .steam { parsedDigits = OTPGenerator.steamDigits }

        var parsedPeriod = integer(period) ?? 0
        if parsedPeriod <= 0 { parsedPeriod = OTPGenerator.defaultPeriod }

        let parsedCounter = integer(counter) ?? 0
        guard parsedCounter >= 0 else { throw ImportFailure(String(localized: "Invalid HOTP counter: \(parsedCounter)")) }

        return OTPCode(
            issuer: issuer,
            accountName: account,
            secret: sanitizedSecret,
            algorithm: parseAlgorithm(algorithm),
            digits: parsedDigits,
            period: parsedPeriod,
            counter: type == .hotp ? parsedCounter : 0,
            type: type,
            note: note,
            pinned: pinned,
            tags: tags
        )
    }

    /// 与 ente 一致：sha256 / sha512 以外一律按 SHA1
    static func parseAlgorithm(_ raw: String?) -> OTPAlgorithm {
        switch raw?.lowercased() {
        case "sha256", "algorithm.sha256": .sha256
        case "sha512", "algorithm.sha512": .sha512
        default: .sha1
        }
    }

    static func integer(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: int
        case let number as NSNumber: number.intValue
        case let string as String: Int(string)
        default: nil
        }
    }
}

/// 单条目解析失败的原因，由调用方包装成 ImportProviderError.invalidEntry
struct ImportFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum ImportEntry {
    /// 把单条目解析包起来：失败时附上条目原文，与 ente 的 "View entry" 一致
    static func parse<T>(_ entry: Any, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ImportProviderError {
            throw error
        } catch {
            throw ImportProviderError.invalidEntry(entry: describe(entry), reason: "\(error)")
        }
    }

    static func describe(_ entry: Any) -> String {
        let entry = redact(entry)
        if let string = entry as? String { return string }
        if JSONSerialization.isValidJSONObject(entry),
           let data = try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: entry)
    }

    /// 出错条目会展示给用户（可能被截图分享），密钥类字段与 URL 里的 secret 参数一律打码
    private static let sensitiveKeys = ["secret", "totp", "seed", "key", "password", "token"]

    static func redact(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            dictionary.reduce(into: [String: Any]()) { result, pair in
                let key = pair.key.lowercased()
                result[pair.key] = sensitiveKeys.contains(where: key.contains) ? "•••" : redact(pair.value)
            }
        case let array as [Any]:
            array.map(redact)
        case let string as String:
            string.replacingOccurrences(of: #"(?i)(secret=)[^&\s]*"#, with: "$1•••", options: .regularExpression)
        default:
            value
        }
    }
}

/// JSON 读取的小工具：导入文件都是弱类型 JSON
enum JSONInput {
    static func object(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ImportProviderError.invalidFile(String(localized: "The file isn’t valid JSON."))
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }
}
