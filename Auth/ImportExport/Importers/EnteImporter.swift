import Foundation

/// ente Auth 的导出：
/// - 纯文本：每行（或逗号分隔）一个 otpauth:// URL，可带 codeDisplay 参数（置顶、标签、备注等）
/// - 纯文本 JSON：{"items": [{"rawData": "otpauth://…", "display": {…}}]}
/// - 加密导出：Argon2id 派生密钥 + libsodium secretstream，解密后为纯文本
enum EnteImporter {
    // MARK: - 纯文本

    /// 与 ente 的 parsePlainTextImport 一致：无效行跳过，保留其余有效条目
    static func parsePlainText(_ content: String) throws -> [OTPCode] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("otpauth://") {
            return splitOTPAuthLines(trimmed).compactMap { try? parseURL($0) }
        }
        guard let json = try? JSONInput.object(Data(trimmed.utf8)) as? [String: Any],
              let items = json["items"] as? [Any] else {
            throw ImportProviderError.invalidFile("无法解析选定的文件。")
        }
        return items.compactMap { item in
            guard let item = item as? [String: Any], let rawData = item["rawData"] as? String else { return nil }
            return try? parseURL(rawData, display: item["display"] as? [String: Any])
        }
    }

    /// 换行分隔，或逗号后紧跟 otpauth:// 的分隔（逗号也可能出现在 issuer 里）
    static func splitOTPAuthLines(_ content: String) -> [String] {
        content
            .replacingOccurrences(of: #",(?=\s*otpauth://)"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 解析一个 otpauth URL；display 为 nil 时读取 URL 自带的 codeDisplay 参数。
    /// 回收站里的条目本 App 没有对应概念，直接跳过
    static func parseURL(_ rawData: String, display: [String: Any]? = nil) throws -> OTPCode? {
        var code = try OTPAuthURLParser.parse(rawData)
        let display = display ?? codeDisplay(in: rawData)
        guard let display else { return code }
        if display["trashed"] as? Bool == true { return nil }
        code.pinned = display["pinned"] as? Bool ?? false
        code.tags = display["tags"] as? [String] ?? []
        code.note = display["note"] as? String ?? ""
        // ente 的图标名与本 App 图标库一致时沿用
        if let iconID = display["iconID"] as? String, BrandIconCatalog.icon(slug: iconID) != nil {
            code.iconID = iconID
        }
        return code
    }

    private static func codeDisplay(in rawData: String) -> [String: Any]? {
        let sanitized = rawData.replacingOccurrences(of: "#", with: "%23")
        guard let value = URLComponents(string: sanitized)?.queryItems?.first(where: { $0.name == "codeDisplay" })?.value,
              let data = value.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - 加密导出

    struct EncryptedExport: Decodable {
        struct KDFParams: Decodable {
            let memLimit: Int
            let opsLimit: Int
            let salt: String
        }

        let version: Int
        let kdfParams: KDFParams
        let encryptedData: String
        let encryptionNonce: String
    }

    static func decodeEncryptedExport(_ data: Data) throws -> EncryptedExport {
        guard let export = try? JSONDecoder().decode(EncryptedExport.self, from: data) else {
            throw ImportProviderError.invalidFile("无法解析选定的文件。")
        }
        return export
    }

    /// 解密后每行一个 otpauth URL（可带 codeDisplay）
    static func decrypt(_ export: EncryptedExport, password: String) throws -> [OTPCode] {
        guard let salt = Data(base64Encoded: export.kdfParams.salt),
              let ciphertext = Data(base64Encoded: export.encryptedData),
              let header = Data(base64Encoded: export.encryptionNonce) else {
            throw ImportProviderError.invalidFile("无法解析选定的文件。")
        }
        let key = try ImportCrypto.argon2id(
            password: password,
            salt: salt,
            opsLimit: export.kdfParams.opsLimit,
            memLimit: export.kdfParams.memLimit,
            keyLength: 32
        )
        let plaintext: Data
        do {
            plaintext = try ImportCrypto.secretStreamDecrypt(ciphertext, key: key, header: header)
        } catch {
            throw ImportProviderError.incorrectPassword
        }
        return String(decoding: plaintext, as: UTF8.self)
            .components(separatedBy: "\n")
            .compactMap { try? parseURL($0) }
    }
}
