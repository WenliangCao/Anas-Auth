import Foundation

/// 2FAS Authenticator：设置 → 备份 → 导出（.2fas，JSON，可加密）。
/// 只支持 schemaVersion 3 / 4；加密格式为 PBKDF2-SHA256(10000) + AES-GCM。
/// 分组转为标签。也兼容导出成 otpauth 文本的情况
enum TwoFASImporter {
    static func decode(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONInput.object(data) as? [String: Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t a valid 2FAS Authenticator export."))
        }
        let version = ImportedOTP.integer(json["schemaVersion"]) ?? 0
        guard version == 3 || version == 4 else {
            throw version == 0
                ? ImportProviderError.invalidFile(String(localized: "The selected file isn’t a valid 2FAS Authenticator export."))
                : ImportProviderError.unsupportedVersion(String(localized: "This version of the 2FAS export isn’t supported yet (schemaVersion \(version))."))
        }
        return json
    }

    /// 带 reference 字段的是加密备份
    static func isEncrypted(_ backup: [String: Any]) -> Bool {
        backup["reference"] != nil && !(backup["reference"] is NSNull)
    }

    static func parse(_ backup: [String: Any], password: String?) throws -> [OTPCode] {
        var groupNames: [String: String] = [:]
        for group in backup["groups"] as? [[String: Any]] ?? [] {
            if let id = JSONInput.string(group["id"]), let name = JSONInput.string(group["name"]) {
                groupNames[id] = name
            }
        }
        let services: [Any]
        if isEncrypted(backup) {
            services = try decryptServices(backup, password: password ?? "")
        } else {
            services = backup["services"] as? [Any] ?? []
        }
        return try services.map { service in
            try ImportEntry.parse(service) {
                guard let service = service as? [String: Any],
                      let otp = service["otp"] as? [String: Any] else { throw ImportFailure(String(localized: "Invalid entry format")) }
                let kind = JSONInput.string(otp["tokenType"]) ?? "TOTP"
                var issuer = JSONInput.string(otp["issuer"]) ?? ""
                if issuer.isEmpty { issuer = JSONInput.string(service["name"]) ?? "" }
                var algorithm = JSONInput.string(otp["algorithm"])
                var digits = otp["digits"]
                if kind == "TOTP" {
                    algorithm = algorithm ?? "SHA1"
                    digits = digits ?? OTPGenerator.defaultDigits
                }
                let tags = JSONInput.string(service["groupId"]).flatMap { groupNames[$0] }.map { [$0] } ?? []
                return try ImportedOTP.make(
                    kind: kind,
                    issuer: issuer,
                    account: JSONInput.string(otp["account"]) ?? "",
                    secret: JSONInput.string(service["secret"]) ?? "",
                    algorithm: algorithm,
                    digits: digits,
                    period: otp["period"],
                    counter: otp["counter"],
                    tags: tags
                )
            }
        }
    }

    /// servicesEncrypted = base64(密文+tag):base64(salt):base64(iv)
    private static func decryptServices(_ backup: [String: Any], password: String) throws -> [Any] {
        let parts = (JSONInput.string(backup["servicesEncrypted"]) ?? "").split(separator: ":").map(String.init)
        guard parts.count >= 3,
              let ciphertext = Data(base64Encoded: parts[0]),
              let salt = Data(base64Encoded: parts[1]),
              let iv = Data(base64Encoded: parts[2]) else {
            throw ImportProviderError.invalidFile(String(localized: "The encrypted 2FAS backup has an invalid format."))
        }
        let key = try ImportCrypto.pbkdf2(password: password, salt: salt, rounds: 10_000, keyLength: 32, prf: .sha256)
        let plaintext: Data
        do {
            plaintext = try ImportCrypto.aesGCMOpen(key: key, nonce: iv, ciphertextAndTag: ciphertext)
        } catch {
            throw ImportProviderError.incorrectPassword
        }
        guard let services = try JSONInput.object(plaintext) as? [Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The decrypted 2FAS backup is invalid."))
        }
        return services
    }
}
