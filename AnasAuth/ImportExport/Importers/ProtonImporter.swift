import Foundation

/// Proton Authenticator：设置 → 导出（JSON，可设密码）。
/// 加密格式：Argon2id(t=2, m=19 MiB, p=1) 派生密钥，
/// content = 12 字节 nonce + AES-GCM 密文，附加数据为固定字符串。备注保留
enum ProtonImporter {
    private static let exportVersion = 1
    private static let additionalData = Data("proton.authenticator.export.v1".utf8)

    static func decode(_ data: Data) throws -> [String: Any] {
        guard let json = try? JSONInput.object(data) as? [String: Any],
              ImportedOTP.integer(json["version"]) == exportVersion else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t a valid Proton Authenticator export."))
        }
        return json
    }

    static func isEncrypted(_ export: [String: Any]) -> Bool {
        export["salt"] != nil && export["content"] != nil && export["entries"] == nil
    }

    static func decrypt(_ export: [String: Any], password: String) throws -> [String: Any] {
        guard let salt = Data(base64Encoded: JSONInput.string(export["salt"]) ?? ""), salt.count == 16,
              let content = Data(base64Encoded: JSONInput.string(export["content"]) ?? ""), content.count > 12 else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t a valid Proton Authenticator export."))
        }
        let key = try ImportCrypto.argon2id(
            password: password, salt: salt, opsLimit: 2, memLimit: 19 * 1024 * 1024, keyLength: 32
        )
        let plaintext: Data
        do {
            plaintext = try ImportCrypto.aesGCMOpen(
                key: key, nonce: content.prefix(12), ciphertextAndTag: content.dropFirst(12), aad: additionalData
            )
        } catch {
            throw ImportProviderError.incorrectPassword
        }
        return try decode(plaintext)
    }

    /// 只导入 Totp / Steam 条目，单条出错跳过（与 ente 一致）
    static func parse(_ export: [String: Any]) throws -> [OTPCode] {
        guard !isEncrypted(export), let entries = export["entries"] as? [Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t a valid Proton Authenticator export."))
        }
        return entries.compactMap { entry -> OTPCode? in
            guard let entry = entry as? [String: Any],
                  let content = entry["content"] as? [String: Any],
                  let uri = JSONInput.string(content["uri"]) else { return nil }
            var code: OTPCode?
            switch JSONInput.string(content["entry_type"]) {
            case "Totp" where uri.hasPrefix("otpauth://"):
                code = try? OTPAuthURLParser.parse(uri)
            case "Steam" where uri.hasPrefix("steam://"):
                let name = (JSONInput.string(content["name"]) ?? "").trimmingCharacters(in: .whitespaces)
                code = try? ImportedOTP.make(
                    kind: "steam", issuer: name.isEmpty ? "Steam" : name, account: "",
                    secret: String(uri.dropFirst("steam://".count)), algorithm: nil, digits: nil
                )
            default:
                return nil
            }
            if let note = JSONInput.string(entry["note"]), !note.isEmpty {
                code?.note = note
            }
            return code
        }
    }
}
