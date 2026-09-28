import Foundation

enum ImportError: Error {
    case emptyInput
    case noCodesFound
    case malformedJSON
}

extension OTPCode {
    /// issuer + 账号 + 密钥相同即视为同一条验证码
    var dedupeKey: String {
        "\(issuer)\u{1F}\(accountName)\u{1F}\(secret)"
    }
}

extension CodeEntry {
    var dedupeKey: String {
        "\(issuer)\u{1F}\(accountName)\u{1F}\(secret)"
    }
}

/// 统一导入入口：自动识别四种来源
/// 1. Google Authenticator 迁移二维码内容（otpauth-migration://…）
/// 2. 本 App 导出的 JSON 备份（明文或加密）
/// 3. 一行一个 otpauth:// URL 的纯文本
/// 4. 加密备份文件内容（AUTHENCRYPTED1 magic 开头）
enum ImportService {
    static func importCodes(from text: String) throws -> [OTPCode] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyInput }

        if trimmed.hasPrefix("otpauth-migration://") {
            return try GoogleMigrationParser.parse(trimmed)
        }

        if trimmed.hasPrefix("{") {
            return try importJSON(Data(trimmed.utf8))
        }

        var codes: [OTPCode] = []
        for line in trimmed.components(separatedBy: .newlines) {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            guard candidate.hasPrefix("otpauth://") else { continue }
            if let code = try? OTPAuthURLParser.parse(candidate) {
                codes.append(code)
            }
        }
        guard !codes.isEmpty else { throw ImportError.noCodesFound }
        return codes
    }

    /// 从文件导入：自动识别明文 JSON / 加密备份 / otpauth 文本
    static func importCodes(fromFileContents data: Data, password: String?) throws -> [OTPCode] {
        if BackupCrypto.isEncryptedFile(data) {
            let plaintext = try BackupCrypto.decrypt(data, password: password ?? "")
            return try importJSON(plaintext)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportError.malformedJSON
        }
        return try importCodes(from: text)
    }

    static func isEncryptedBackup(_ data: Data) -> Bool {
        BackupCrypto.isEncryptedFile(data)
    }

    private static func importJSON(_ data: Data) throws -> [OTPCode] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(AuthExportFile.self, from: data) else {
            throw ImportError.malformedJSON
        }
        let codes = file.codes.compactMap { exported -> OTPCode? in
            let secret = OTPAuthURLParser.sanitizeSecret(exported.secret)
            guard (try? Base32.decode(secret)) != nil else { return nil }
            return OTPCode(
                issuer: exported.issuer,
                accountName: exported.accountName,
                secret: secret,
                algorithm: OTPAlgorithm(rawValue: exported.algorithm.lowercased()) ?? .sha1,
                digits: exported.digits,
                period: exported.period,
                counter: exported.counter,
                type: OTPType(rawValue: exported.type.lowercased()) ?? .totp,
                note: exported.note,
                pinned: exported.pinned,
                tags: exported.tags ?? []
            )
        }
        guard !codes.isEmpty else { throw ImportError.noCodesFound }
        return codes
    }

    /// 过滤掉已存在的条目（含导入内容自身的重复），返回新条目与被跳过的数量
    static func filteringExisting(
        _ codes: [OTPCode],
        in existing: [CodeEntry]
    ) -> (unique: [OTPCode], skipped: Int) {
        var seen = Set(existing.map(\.dedupeKey))
        var unique: [OTPCode] = []
        for code in codes where seen.insert(code.dedupeKey).inserted {
            unique.append(code)
        }
        return (unique, codes.count - unique.count)
    }
}
