import Foundation

/// andOTP：设置 → 备份。明文是 JSON 数组；加密备份（.aes）结构为
/// [迭代次数 4 字节大端][salt 12][iv 12][密文 + tag]，PBKDF2-SHA1 派生 + AES-GCM。
/// 不支持的类型（如 MOTP）跳过，标签保留
enum AndOTPImporter {
    /// 能直接读成 JSON 数组就是明文备份
    static func plainEntries(_ data: Data) -> [Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [Any]
    }

    static func decrypt(_ data: Data, password: String) throws -> [Any] {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 + 12 + 12 + 16 else {
            throw ImportProviderError.invalidFile("所选文件不是 andOTP 备份。")
        }
        let iterations = bytes[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        let salt = Data(bytes[4..<16])
        let iv = Data(bytes[16..<28])
        let ciphertext = Data(bytes[28...])
        guard iterations > 0 else { throw ImportProviderError.invalidFile("所选文件不是 andOTP 备份。") }
        let key = try ImportCrypto.pbkdf2(password: password, salt: salt, rounds: iterations, keyLength: 32, prf: .sha1)
        let plaintext: Data
        do {
            plaintext = try ImportCrypto.aesGCMOpen(key: key, nonce: iv, ciphertextAndTag: ciphertext)
        } catch {
            throw ImportProviderError.incorrectPassword
        }
        guard let entries = plainEntries(plaintext) else {
            throw ImportProviderError.invalidFile("andOTP 备份解密后的内容无效。")
        }
        return entries
    }

    static func parse(_ entries: [Any]) throws -> [OTPCode] {
        try entries.compactMap { entry in
            guard let entry = entry as? [String: Any] else { return nil }
            let type = (JSONInput.string(entry["type"]) ?? "").uppercased()
            guard ["TOTP", "HOTP", "STEAM"].contains(type) else { return nil }
            return try ImportEntry.parse(entry) {
                try ImportedOTP.make(
                    kind: type,
                    issuer: JSONInput.string(entry["issuer"]) ?? "",
                    account: JSONInput.string(entry["label"]) ?? "",
                    secret: JSONInput.string(entry["secret"]) ?? "",
                    algorithm: JSONInput.string(entry["algorithm"]) ?? "SHA1",
                    digits: entry["digits"] ?? 6,
                    period: entry["period"] ?? 30,
                    counter: entry["counter"] ?? 0,
                    tags: (entry["tags"] as? [Any])?.map { "\($0)" } ?? []
                )
            }
        }
    }
}
