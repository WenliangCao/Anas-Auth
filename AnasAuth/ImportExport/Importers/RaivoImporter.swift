import Foundation

/// Raivo OTP：设置 → Export OTPs to ZIP archive，解压后的 JSON 数组
enum RaivoImporter {
    static func parse(_ data: Data) throws -> [OTPCode] {
        guard let items = try JSONInput.object(data) as? [Any] else {
            throw ImportProviderError.invalidFile("所选文件不是 Raivo 导出的 JSON。")
        }
        return try items.map { item in
            try ImportEntry.parse(item) {
                guard let item = item as? [String: Any] else { throw ImportFailure("条目格式不对") }
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
