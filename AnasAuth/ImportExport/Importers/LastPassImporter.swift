import Foundation

/// LastPass Authenticator：设置 → 转移账户 → 将账户导出到文件（JSON）
enum LastPassImporter {
    static func parse(_ data: Data) throws -> [OTPCode] {
        guard let json = try JSONInput.object(data) as? [String: Any],
              let accounts = json["accounts"] as? [Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t a LastPass Authenticator JSON export."))
        }
        return try accounts.map { item in
            try ImportEntry.parse(item) {
                guard let item = item as? [String: Any] else { throw ImportFailure(String(localized: "Invalid entry format")) }
                return try ImportedOTP.make(
                    kind: "totp",
                    issuer: JSONInput.string(item["issuerName"]) ?? "",
                    account: JSONInput.string(item["userName"]) ?? "",
                    secret: JSONInput.string(item["secret"]) ?? "",
                    algorithm: JSONInput.string(item["algorithm"]),
                    digits: item["digits"],
                    period: item["timeStep"]
                )
            }
        }
    }
}
