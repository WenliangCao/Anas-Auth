import Foundation

/// 「从其他应用导入」支持的来源，顺序、文案与 ente 一致
enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case plainText
    case enteEncrypted
    case twoFAS
    case aegis
    case andOTP
    case bitwarden
    case googleAuthenticator
    case proton
    case raivo
    case lastPass
    case otpAuth

    var id: Self { self }

    var title: String {
        switch self {
        case .plainText: String(localized: "Plain Text")
        case .enteEncrypted: String(localized: "Ente Encrypted Export")
        case .twoFAS: "2FAS Authenticator"
        case .aegis: "Aegis Authenticator"
        case .andOTP: "andOTP"
        case .bitwarden: "Bitwarden"
        case .googleAuthenticator: "Google Authenticator"
        case .proton: "Proton Authenticator"
        case .raivo: "Raivo OTP"
        case .lastPass: "LastPass Authenticator"
        case .otpAuth: "OTP Auth"
        }
    }

    /// 导出步骤说明
    var guide: String {
        switch self {
        case .plainText:
            String(localized: "Select a file that contains a list of codes in this format:\n\notpauth://totp/provider.com:you@email.com?secret=YOUR_SECRET\n\nCodes can be separated by commas or line breaks.")
        case .enteEncrypted:
            String(localized: "Select the encrypted JSON file exported from Ente.")
        case .twoFAS:
            String(localized: "In 2FAS, use “Settings → Backup → Export”.\n\nIf the backup is encrypted, you’ll need its password to decrypt it.")
        case .aegis:
            String(localized: "In Aegis settings, use “Export the vault”.\n\nIf the vault is encrypted, you’ll need the vault password to decrypt it.")
        case .andOTP:
            String(localized: "In andOTP settings, use “Backup” to export a backup.\n\nIf the backup is encrypted, you’ll need the backup password to decrypt it.")
        case .bitwarden:
            String(localized: "In Bitwarden tools, use “Export vault”, then import the unencrypted JSON file.")
        case .googleAuthenticator:
            String(localized: "In Google Authenticator, use “Transfer accounts” to export your accounts as QR codes, then scan them or import them from images. Many accounts produce several QR codes; scan all of them.")
        case .proton:
            String(localized: "In Proton Authenticator settings, use “Export”.\n\nIf the export is password-protected, you’ll need the password to decrypt it.")
        case .raivo:
            String(localized: "In Raivo settings, use “Export OTPs to ZIP archive”.\n\nUnzip the file and import the JSON file inside.")
        case .lastPass:
            String(localized: "In LastPass Authenticator settings, choose “Transfer accounts”, then “Export accounts to file”, and import the downloaded JSON.")
        case .otpAuth:
            String(localized: "Export an encrypted backup from OTP Auth, then select the .otpauthdb or .otpauthdp file. Single-account .otpauth files are also supported.")
        }
    }

    var passwordPrompt: String {
        switch self {
        case .aegis: String(localized: "Enter the password for your Aegis vault")
        case .twoFAS: String(localized: "Enter the password to decrypt the 2FAS backup")
        case .andOTP: String(localized: "Enter the password to decrypt the andOTP backup")
        default: String(localized: "The password used to encrypt the export")
        }
    }

    enum Outcome: Sendable {
        case codes([OTPCode])
        case needsPassword
    }

    /// 解析选中的文件；需要密码而 password 为 nil 时返回 .needsPassword。
    /// 解密可能要几秒（Argon2 / scrypt），调用方应放在后台执行
    func process(_ data: Data, fileName: String, password: String?) throws -> Outcome {
        switch self {
        case .plainText:
            return .codes(try EnteImporter.parsePlainText(text(data)))
        case .enteEncrypted:
            let export = try EnteImporter.decodeEncryptedExport(data)
            guard let password else { return .needsPassword }
            return .codes(try EnteImporter.decrypt(export, password: password))
        case .twoFAS:
            let content = try text(data)
            if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("otpauth://") {
                return .codes(try EnteImporter.parsePlainText(content))
            }
            let backup = try TwoFASImporter.decode(data)
            if TwoFASImporter.isEncrypted(backup) && password == nil { return .needsPassword }
            return .codes(try TwoFASImporter.parse(backup, password: password))
        case .aegis:
            let vault = try AegisImporter.decode(data)
            if AegisImporter.isEncrypted(vault) && password == nil { return .needsPassword }
            return .codes(try AegisImporter.parse(vault, password: password))
        case .andOTP:
            if let entries = AndOTPImporter.plainEntries(data) {
                return .codes(try AndOTPImporter.parse(entries))
            }
            guard let password else { return .needsPassword }
            return .codes(try AndOTPImporter.parse(AndOTPImporter.decrypt(data, password: password)))
        case .bitwarden:
            return .codes(try BitwardenImporter.parse(data))
        case .proton:
            let export = try ProtonImporter.decode(data)
            guard ProtonImporter.isEncrypted(export) else { return .codes(try ProtonImporter.parse(export)) }
            guard let password else { return .needsPassword }
            return .codes(try ProtonImporter.parse(ProtonImporter.decrypt(export, password: password)))
        case .raivo:
            if fileName.lowercased().hasSuffix(".zip") {
                throw ImportProviderError.invalidFile(String(localized: "ZIP files aren’t supported yet. Unzip it first, then import the JSON file inside."))
            }
            return .codes(try RaivoImporter.parse(data))
        case .lastPass:
            return .codes(try LastPassImporter.parse(data))
        case .otpAuth:
            guard let password else { return .needsPassword }
            return .codes(try OTPAuthAppImporter.parse(data, password: password))
        case .googleAuthenticator:
            // 走扫码 / 图片流程，不读文件
            throw ImportProviderError.invalidFile(String(localized: "Scan a QR code or choose a QR code image."))
        }
    }

    private func text(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportProviderError.invalidFile(String(localized: "Couldn’t parse the selected file."))
        }
        return text
    }
}
