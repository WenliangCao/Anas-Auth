import Foundation

/// OTP Auth（Roland Moers）：导出加密备份 .otpauthdb / .otpauthdp，或单账户 .otpauth。
/// 外层：AES-CBC（密钥 = SHA256("Authenticator" 或 "OTPAuth")，IV 全 0）包着一个 NSKeyedArchiver 字典；
/// 内层按版本二选一：
/// - 旧版（备份 1.0 / 单账户 1.1）：密钥 = SHA256("<Salt>-<密码>")，IV = SHA1(IV)[0..<16]，AES-CBC
/// - 新版（备份 1.1 / 单账户 1.2）：RNCryptor v3（PBKDF2-SHA1 10000 次 + AES-CBC + HMAC-SHA256）
/// 解出来又是 NSKeyedArchiver：ACOTPFolder / ACOTPAccount
enum OTPAuthAppImporter {
    static let fileExtensions = ["otpauthdb", "otpauthdp", "otpauth"]

    static func parse(_ fileData: Data, password: String) throws -> [OTPCode] {
        let outer = try decryptOuterArchive(fileData)
        let isBackup = outer["WrappedData"] != nil
        guard let encrypted = (outer[isBackup ? "WrappedData" : "Data"]) as? Data else {
            throw ImportProviderError.invalidFile("所选文件不是有效的 OTP Auth 导出。")
        }
        let version = (outer["Version"] as? NSNumber)?.doubleValue
        let isLegacy = (isBackup && version == 1.0) || (!isBackup && version == 1.1)
        let isModern = (isBackup && version == 1.1) || (!isBackup && version == 1.2)

        let decrypted: Data
        if isLegacy {
            decrypted = try decryptLegacy(encrypted, outer: outer, isBackup: isBackup, password: password)
        } else if isModern {
            decrypted = try decryptRNCryptor(encrypted, password: password)
        } else {
            throw ImportProviderError.unsupportedVersion("暂不支持该版本的 OTP Auth 导出（\(version.map { "\($0)" } ?? "未知")）。")
        }

        let accounts: [OTPAuthArchivedAccount]
        do {
            accounts = try unarchiveAccounts(decrypted, isBackup: isBackup)
        } catch {
            // 旧版没有完整性校验，密码错时解出来是乱码
            if isLegacy { throw ImportProviderError.incorrectPassword }
            throw error
        }
        return try accounts.map { account in
            try ImportEntry.parse(account.summary) { try account.toOTPCode() }
        }
    }

    // MARK: - 解密

    private static func decryptOuterArchive(_ data: Data) throws -> [String: Any] {
        for magic in ["Authenticator", "OTPAuth"] {
            guard let plain = try? ImportCrypto.aesCBCDecrypt(
                data, key: ImportCrypto.sha256(Data(magic.utf8)), iv: Data(count: 16)
            ) else { continue }
            let archive = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSData.self], from: plain
            ) as? [String: Any]
            if let archive, archive["WrappedData"] != nil || archive["Data"] != nil {
                return archive
            }
        }
        throw ImportProviderError.invalidFile("所选文件不是有效的 OTP Auth 导出。")
    }

    private static func decryptLegacy(_ data: Data, outer: [String: Any], isBackup: Bool, password: String) throws -> Data {
        let ivSource: Data? = isBackup ? (outer["IV"] as? String).map { Data($0.utf8) } : outer["IV"] as? Data
        guard let ivSource, let salt = outer["Salt"] else {
            throw ImportProviderError.invalidFile("所选文件不是有效的 OTP Auth 导出。")
        }
        let key = ImportCrypto.sha256(Data("\(salt)-\(password)".utf8))
        let iv = ImportCrypto.sha1(ivSource).prefix(16)
        do {
            return try ImportCrypto.aesCBCDecrypt(data, key: key, iv: iv)
        } catch {
            throw ImportProviderError.incorrectPassword
        }
    }

    /// RNCryptor v3：[3][1][加密盐 8][HMAC 盐 8][IV 16][密文][HMAC 32]
    private static func decryptRNCryptor(_ data: Data, password: String) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 34 + 16 + 32, bytes[0] == 3, bytes[1] == 1 else {
            throw ImportProviderError.invalidFile("OTP Auth 导出的加密格式不对。")
        }
        let encryptionKey = try ImportCrypto.pbkdf2(
            password: password, salt: Data(bytes[2..<10]), rounds: 10_000, keyLength: 32, prf: .sha1
        )
        let hmacKey = try ImportCrypto.pbkdf2(
            password: password, salt: Data(bytes[10..<18]), rounds: 10_000, keyLength: 32, prf: .sha1
        )
        let authenticated = Data(bytes[..<(bytes.count - 32)])
        let mac = Data(bytes[(bytes.count - 32)...])
        guard ImportCrypto.verifyHMACSHA256(mac, for: authenticated, key: hmacKey) else {
            throw ImportProviderError.incorrectPassword
        }
        return try ImportCrypto.aesCBCDecrypt(
            Data(bytes[34..<(bytes.count - 32)]), key: encryptionKey, iv: Data(bytes[18..<34])
        )
    }

    // MARK: - 反归档

    private static func unarchiveAccounts(_ data: Data, isBackup: Bool) throws -> [OTPAuthArchivedAccount] {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.setClass(OTPAuthArchivedAccount.self, forClassName: "ACOTPAccount")
        unarchiver.setClass(OTPAuthArchivedFolder.self, forClassName: "ACOTPFolder")
        defer { unarchiver.finishDecoding() }
        let root = unarchiver.decodeObject(
            of: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self,
                 OTPAuthArchivedFolder.self, OTPAuthArchivedAccount.self],
            forKey: NSKeyedArchiveRootObjectKey
        )
        if isBackup {
            guard let folders = (root as? [String: Any])?["Folders"] as? [OTPAuthArchivedFolder] else {
                throw ImportProviderError.invalidFile("OTP Auth 备份内容无效。")
            }
            return folders.flatMap(\.accounts)
        }
        guard let account = root as? OTPAuthArchivedAccount else {
            throw ImportProviderError.invalidFile("OTP Auth 导出内容无效。")
        }
        return [account]
    }
}

/// OTP Auth 归档里的 ACOTPFolder，只取账户列表
final class OTPAuthArchivedFolder: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let accounts: [OTPAuthArchivedAccount]

    init?(coder: NSCoder) {
        accounts = coder.decodeObject(
            of: [NSArray.self, OTPAuthArchivedAccount.self], forKey: "accounts"
        ) as? [OTPAuthArchivedAccount] ?? []
    }

    func encode(with coder: NSCoder) {}
}

/// OTP Auth 归档里的 ACOTPAccount
final class OTPAuthArchivedAccount: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    /// 1 = HOTP，2 = TOTP
    let type: Int
    /// 0/1 = SHA1，2 = SHA256，3 = SHA512
    let algorithm: Int
    let digits: Int
    let period: Int
    let counter: Int
    let issuer: String
    let label: String?
    let secret: Data?

    init?(coder: NSCoder) {
        type = coder.decodeInteger(forKey: "type")
        algorithm = coder.decodeInteger(forKey: "algorithm")
        digits = coder.decodeInteger(forKey: "digits")
        period = coder.decodeInteger(forKey: "period")
        counter = coder.decodeInteger(forKey: "counter")
        issuer = coder.decodeObject(of: NSString.self, forKey: "issuer") as String? ?? ""
        label = coder.decodeObject(of: NSString.self, forKey: "label") as String?
        secret = coder.decodeObject(of: NSData.self, forKey: "secret") as Data?
    }

    func encode(with coder: NSCoder) {}

    /// 出错时展示给用户的条目内容（不含密钥）
    var summary: [String: Any] {
        ["type": type, "algorithm": algorithm, "issuer": issuer, "label": label ?? "", "digits": digits, "period": period]
    }

    func toOTPCode() throws -> OTPCode {
        let kind = switch type {
        case 1: "hotp"
        case 2: "totp"
        default: throw ImportFailure("不支持的验证码类型")
        }
        let algorithmName = switch algorithm {
        case 0, 1: "SHA1"
        case 2: "SHA256"
        case 3: "SHA512"
        default: throw ImportFailure("不支持的算法")
        }
        guard let label, let secret else { throw ImportFailure("缺少账号或密钥") }
        return try ImportedOTP.make(
            kind: kind,
            issuer: issuer,
            account: label,
            secret: Base32.encode(secret),
            algorithm: algorithmName,
            digits: digits,
            period: period,
            counter: counter
        )
    }
}
