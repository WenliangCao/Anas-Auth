import Foundation
import SwiftData

/// SwiftData 持久化模型。CloudKit 同步要求所有属性都有默认值、
/// 不能用唯一约束，所以唯一性靠逻辑层保证（secret + accountName + issuer）。
@Model
final class CodeEntry {
    var id: UUID = UUID()
    var issuer: String = ""
    var accountName: String = ""
    var secret: String = ""
    var algorithmRaw: String = OTPAlgorithm.sha1.rawValue
    var digits: Int = OTPGenerator.defaultDigits
    var period: Int = OTPGenerator.defaultPeriod
    var counter: Int = 0
    var typeRaw: String = OTPType.totp.rawValue
    var note: String = ""
    var pinned: Bool = false
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        issuer: String,
        accountName: String,
        secret: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = OTPGenerator.defaultDigits,
        period: Int = OTPGenerator.defaultPeriod,
        counter: Int = 0,
        type: OTPType = .totp,
        note: String = "",
        pinned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.issuer = issuer
        self.accountName = accountName
        self.secret = secret
        self.algorithmRaw = algorithm.rawValue
        self.digits = digits
        self.period = period
        self.counter = counter
        self.typeRaw = type.rawValue
        self.note = note
        self.pinned = pinned
        self.createdAt = createdAt
    }

    convenience init(code: OTPCode) {
        self.init(
            id: code.id,
            issuer: code.issuer,
            accountName: code.accountName,
            secret: code.secret,
            algorithm: code.algorithm,
            digits: code.digits,
            period: code.period,
            counter: code.counter,
            type: code.type,
            note: code.note,
            pinned: code.pinned
        )
    }

    var algorithm: OTPAlgorithm {
        get { OTPAlgorithm(rawValue: algorithmRaw) ?? .sha1 }
        set { algorithmRaw = newValue.rawValue }
    }

    var type: OTPType {
        get { OTPType(rawValue: typeRaw) ?? .totp }
        set { typeRaw = newValue.rawValue }
    }

    var displayName: String {
        accountName.isEmpty ? issuer : "\(issuer) (\(accountName))"
    }

    func generateCode(at date: Date = .now) throws -> String {
        try toOTPCode().generateCode(at: date)
    }

    func generateNextCode(at date: Date = .now) throws -> String {
        try toOTPCode().generateNextCode(at: date)
    }

    func toOTPCode() -> OTPCode {
        OTPCode(
            id: id,
            issuer: issuer,
            accountName: accountName,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            counter: counter,
            type: type,
            note: note,
            pinned: pinned
        )
    }
}
