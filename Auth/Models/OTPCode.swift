import Foundation

/// 一条验证码账号的全部信息。值类型，用于解析、导入导出与 UI 展示；
/// 持久化层（CodeEntry）与它可以互转。
struct OTPCode: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var issuer: String
    var accountName: String
    /// 规范化后的 Base32 密钥（大写、无空格无填充）
    var secret: String
    var algorithm: OTPAlgorithm = .sha1
    var digits: Int = OTPGenerator.defaultDigits
    var period: Int = OTPGenerator.defaultPeriod
    var counter: Int = 0
    var type: OTPType = .totp
    var note: String = ""
    var pinned: Bool = false

    var displayName: String {
        accountName.isEmpty ? issuer : "\(issuer) (\(accountName))"
    }

    /// Steam 条目可能以普通 TOTP 的身份进来（手动输入时），生成时统一按 Steam 处理
    var effectiveType: OTPType {
        issuer.lowercased() == "steam" ? .steam : type
    }

    /// 当前时刻的验证码
    func generateCode(at date: Date = .now) throws -> String {
        let secretData = try Base32.decode(secret)
        switch effectiveType {
        case .totp:
            return OTPGenerator.totp(secret: secretData, at: date, period: period, digits: digits, algorithm: algorithm)
        case .hotp:
            return OTPGenerator.hotp(secret: secretData, counter: UInt64(counter), digits: digits, algorithm: algorithm)
        case .steam:
            return OTPGenerator.steam(secret: secretData, at: date, period: period)
        }
    }

    /// 当前周期的下一个验证码（用于临近到期时提前展示）
    func generateNextCode(at date: Date = .now) throws -> String {
        let secretData = try Base32.decode(secret)
        switch effectiveType {
        case .totp:
            let next = date.addingTimeInterval(TimeInterval(period))
            return OTPGenerator.totp(secret: secretData, at: next, period: period, digits: digits, algorithm: algorithm)
        case .hotp:
            return OTPGenerator.hotp(secret: secretData, counter: UInt64(counter + 1), digits: digits, algorithm: algorithm)
        case .steam:
            let next = date.addingTimeInterval(TimeInterval(period))
            return OTPGenerator.steam(secret: secretData, at: next, period: period)
        }
    }
}
