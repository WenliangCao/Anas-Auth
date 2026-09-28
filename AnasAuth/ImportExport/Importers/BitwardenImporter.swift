import Foundation

/// Bitwarden：工具 → 导出密码库（未加密 JSON）。只导入带 TOTP 的登录项，
/// 文件夹转为标签，备注保留
enum BitwardenImporter {
    static func parse(_ data: Data) throws -> [OTPCode] {
        guard let json = try JSONInput.object(data) as? [String: Any],
              let items = json["items"] as? [Any] else {
            throw ImportProviderError.invalidFile(String(localized: "The selected file isn’t an unencrypted Bitwarden JSON export."))
        }
        var folderNames: [String: String] = [:]
        for folder in json["folders"] as? [[String: Any]] ?? [] {
            if let id = JSONInput.string(folder["id"]), let name = JSONInput.string(folder["name"]) {
                folderNames[id] = name
            }
        }
        return try items.compactMap { item in
            guard let item = item as? [String: Any],
                  let login = item["login"] as? [String: Any],
                  let totp = JSONInput.string(login["totp"]) else { return nil }
            return try ImportEntry.parse(item) {
                let name = JSONInput.string(item["name"]) ?? ""
                let username = JSONInput.string(login["username"]) ?? ""
                var code: OTPCode
                if totp.contains("otpauth://") {
                    code = try OTPAuthURLParser.parse(totp)
                } else if let range = totp.range(of: "steam://") {
                    code = try ImportedOTP.make(
                        kind: "steam", issuer: name, account: username,
                        secret: String(totp[range.upperBound...]), algorithm: nil, digits: nil
                    )
                } else {
                    code = try ImportedOTP.make(
                        kind: "totp", issuer: name, account: username,
                        secret: totp, algorithm: nil, digits: nil
                    )
                }
                if let folderID = JSONInput.string(item["folderId"]), let folder = folderNames[folderID] {
                    code.tags = [folder]
                }
                if let notes = JSONInput.string(item["notes"]) {
                    code.note = notes
                }
                return code
            }
        }
    }
}
