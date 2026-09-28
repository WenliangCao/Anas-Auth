import Foundation

enum ImportError: Error {
    case emptyInput
    case noCodesFound
    case malformedJSON
    case fileTooLarge
}

extension OTPCode {
    var dedupeKey: String { ImportService.dedupeKey(issuer: issuer, accountName: accountName, secret: secret) }
}

extension CodeEntry {
    var dedupeKey: String { ImportService.dedupeKey(issuer: issuer, accountName: accountName, secret: secret) }
}

/// 统一导入入口：自动识别四种来源
/// 1. Google Authenticator 迁移二维码内容（otpauth-migration://…）
/// 2. 本 App 导出的 JSON 备份（明文或加密）
/// 3. 一行一个 otpauth:// URL 的纯文本
/// 4. 加密备份文件内容（AUTHENCRYPTED magic 开头）
enum ImportService {
    /// 导入文件大小上限：验证码导出通常只有几十 KB，超大文件多半是选错了，直接拒绝以免读爆内存
    static let maxFileSize = 10 * 1024 * 1024

    /// 读取用户选中的文件（先查大小再读），会阻塞，调用方放在后台执行
    static func readFile(at url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileSize {
            throw ImportError.fileTooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maxFileSize else { throw ImportError.fileTooLarge }
        return data
    }

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
        // 参数校验与其他导入器一致，跳过无效条目（如负数计数器、非法位数）
        let codes = file.codes.compactMap { exported -> OTPCode? in
            var code = try? ImportedOTP.make(
                kind: exported.type,
                issuer: exported.issuer,
                account: exported.accountName,
                secret: exported.secret,
                algorithm: exported.algorithm,
                digits: exported.digits,
                period: exported.period,
                counter: exported.counter,
                note: exported.note,
                pinned: exported.pinned,
                tags: exported.tags ?? []
            )
            code?.iconID = exported.iconID ?? ""
            return code
        }
        guard !codes.isEmpty else { throw ImportError.noCodesFound }
        return codes
    }

    /// issuer + 账号 + 密钥相同即视为同一条验证码
    static func dedupeKey(issuer: String, accountName: String, secret: String) -> String {
        "\(issuer)\u{1F}\(accountName)\u{1F}\(secret)"
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
