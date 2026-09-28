import Foundation

/// Aegis Authenticator：设置 → 导出密码库（JSON，可加密）。
/// 加密格式：每个密码 slot 用 scrypt 派生密钥，AES-GCM 解出主密钥，
/// 再用主密钥 AES-GCM 解出 db。收藏转为置顶，分组转为标签，备注保留
enum AegisImporter {
    static func decode(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONInput.object(data) as? [String: Any],
              json["header"] is [String: Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t an Aegis vault export."))
        }
        return json
    }

    static func isEncrypted(_ vault: [String: Any]) -> Bool {
        ((vault["header"] as? [String: Any])?["slots"] as? [Any]) != nil
    }

    static func parse(_ vault: [String: Any], password: String?) throws -> [OTPCode] {
        let db: [String: Any]
        if isEncrypted(vault) {
            db = try decrypt(vault, password: password ?? "")
        } else {
            guard let plainDB = vault["db"] as? [String: Any] else {
                throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t an Aegis vault export."))
            }
            db = plainDB
        }
        return try parseEntries(db)
    }

    static func parseEntries(_ db: [String: Any]) throws -> [OTPCode] {
        var groupNames: [String: String] = [:]
        for group in db["groups"] as? [[String: Any]] ?? [] {
            if let id = JSONInput.string(group["uuid"]), let name = JSONInput.string(group["name"]) {
                groupNames[id] = name
            }
        }
        guard let entries = db["entries"] as? [Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The vault has no entries."))
        }
        return try entries.map { entry in
            try ImportEntry.parse(entry) {
                guard let entry = entry as? [String: Any],
                      let info = entry["info"] as? [String: Any] else { throw ImportFailure(String(localized: "Invalid entry format")) }
                let groupIDs = entry["groups"] as? [String] ?? []
                return try ImportedOTP.make(
                    kind: JSONInput.string(entry["type"]) ?? "",
                    issuer: JSONInput.string(entry["issuer"]) ?? "",
                    account: JSONInput.string(entry["name"]) ?? "",
                    secret: JSONInput.string(info["secret"]) ?? "",
                    algorithm: JSONInput.string(info["algo"]),
                    digits: info["digits"],
                    period: info["period"],
                    counter: info["counter"],
                    note: JSONInput.string(entry["note"]) ?? "",
                    pinned: entry["favorite"] as? Bool ?? false,
                    tags: groupIDs.compactMap { groupNames[$0] }
                )
            }
        }
    }

    private static func decrypt(_ vault: [String: Any], password: String) throws -> [String: Any] {
        guard let header = vault["header"] as? [String: Any],
              let slots = header["slots"] as? [[String: Any]],
              let params = header["params"] as? [String: Any],
              let dbNonce = Data(hexString: JSONInput.string(params["nonce"]) ?? ""),
              let dbTag = Data(hexString: JSONInput.string(params["tag"]) ?? ""),
              let db = Data(base64Encoded: JSONInput.string(vault["db"]) ?? "") else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t an Aegis vault export."))
        }
        // type 1 = 密码 slot（其余是生物识别等，无法在别的设备上解开）
        var masterKey: Data?
        for slot in slots where ImportedOTP.integer(slot["type"]) == 1 {
            guard let salt = Data(hexString: JSONInput.string(slot["salt"]) ?? ""),
                  let n = ImportedOTP.integer(slot["n"]), let r = ImportedOTP.integer(slot["r"]),
                  let p = ImportedOTP.integer(slot["p"]),
                  let keyParams = slot["key_params"] as? [String: Any],
                  let nonce = Data(hexString: JSONInput.string(keyParams["nonce"]) ?? ""),
                  let tag = Data(hexString: JSONInput.string(keyParams["tag"]) ?? ""),
                  let encryptedKey = Data(hexString: JSONInput.string(slot["key"]) ?? "") else { continue }
            let derived = try ImportCrypto.scrypt(
                password: password, salt: salt, n: UInt64(n), r: UInt32(r), p: UInt32(p), keyLength: 32
            )
            if let key = try? ImportCrypto.aesGCMOpen(key: derived, nonce: nonce, ciphertextAndTag: encryptedKey + tag) {
                masterKey = key
                break
            }
        }
        guard let masterKey else { throw ImportProviderError.incorrectPassword }
        let plaintext = try ImportCrypto.aesGCMOpen(key: masterKey, nonce: dbNonce, ciphertextAndTag: db + dbTag)
        guard let decoded = try JSONInput.object(plaintext) as? [String: Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The decrypted vault is invalid."))
        }
        return decoded
    }
}
