import Foundation

/// Raivo OTP：设置 → Export OTPs to ZIP archive，解压后的 JSON 数组
enum RaivoImporter {
    static func parse(_ data: Data) throws -> [OTPCode] {
        guard let items = try JSONInput.object(data) as? [Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t a Raivo JSON export."))
        }
        return try items.map { item in
            try ImportEntry.parse(item) {
                guard let item = item as? [String: Any] else { throw ImportFailure(String(localized: "Invalid entry format")) }
                return try ImportedOTP.make(
                    kind: JSONInput.string(item["kind"]) ?? "",
                    issuer: JSONInput.string(item["issuer"]) ?? "",
                    account: JSONInput.string(item["account"]) ?? "",
                    secret: JSONInput.string(item["secret"]) ?? "",
                    algorithm: JSONInput.string(item["algorithm"]),
                    digits: item["digits"],
                    period: item["timer"],
                    counter: item["counter"],
                    allowSteam: false
                )
            }
        }
    }
}
