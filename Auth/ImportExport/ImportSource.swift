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
        case .plainText: "纯文本"
        case .enteEncrypted: "Ente 加密导出"
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
            "请选择一个包含以下格式的代码列表的文件：\n\notpauth://totp/provider.com:you@email.com?secret=YOUR_SECRET\n\n代码可以用逗号或换行符分隔。"
        case .enteEncrypted:
            "选择从 Ente 导出的 JSON 加密文件。"
        case .twoFAS:
            "使用 2FAS 中的「设置 → 备份 → 导出」选项。\n\n如果备份已加密，需要输入密码来解密。"
        case .aegis:
            "使用 Aegis 设置中的「导出密码库」选项。\n\n如果密码库已加密，需要输入密码库密码才能解密。"
        case .andOTP:
            "使用 andOTP 设置中的「备份」选项导出备份。\n\n如果备份已加密，需要输入备份密码才能解密。"
        case .bitwarden:
            "使用 Bitwarden 工具中的「导出密码库」选项，导入未加密的 JSON 文件。"
        case .googleAuthenticator:
            "在 Google Authenticator 中使用「转移账号」把账号导出为二维码，然后扫描二维码或从图片导入。账号较多时会生成多张二维码，需要全部扫完。"
        case .proton:
            "使用 Proton Authenticator 设置中的「导出」选项导出验证码。\n\n如果导出文件设置了密码，需要输入密码才能解密。"
        case .raivo:
            "使用 Raivo 设置中的「Export OTPs to ZIP archive」选项。\n\n解压 zip 文件后导入其中的 JSON 文件。"
        case .lastPass:
            "使用 LastPass Authenticator 设置中的「转移账户」选项，然后点「将账户导出到文件」，导入下载的 JSON。"
        case .otpAuth:
            "从 OTP Auth 导出加密备份，然后选择 .otpauthdb 或 .otpauthdp 文件。也支持单账户的 .otpauth 文件。"
        }
    }

    var passwordPrompt: String {
        switch self {
        case .aegis: "请输入 Aegis 密码库的密码"
        case .twoFAS: "请输入密码以解密 2FAS 备份"
        case .andOTP: "请输入密码以解密 andOTP 备份"
        default: "用来解密导出的密码"
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
                throw ImportProviderError.invalidFile("暂不支持 zip 文件，请先解压再导入其中的 JSON 文件。")
            }
            return .codes(try RaivoImporter.parse(data))
        case .lastPass:
            return .codes(try LastPassImporter.parse(data))
        case .otpAuth:
            guard let password else { return .needsPassword }
            return .codes(try OTPAuthAppImporter.parse(data, password: password))
        case .googleAuthenticator:
            // 走扫码 / 图片流程，不读文件
            throw ImportProviderError.invalidFile("请扫描二维码或选择二维码图片。")
        }
    }

    private func text(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportProviderError.invalidFile("无法解析选定的文件。")
        }
        return text
    }
}
