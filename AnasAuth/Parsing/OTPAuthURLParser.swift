import Foundation

enum OTPAuthURLError: Error, Equatable {
    case notOTPAuth
    case unsupportedType(String)
    case missingSecret
    case invalidSecret
}

/// 解析与生成 `otpauth://` URL（Google Key Uri Format 开放规范）。
/// 解析时兼容真实世界里各种不规范的写法：issuer 前缀、未转义的 `#`、
/// Steam 的自定义 host、密钥里的空格与小写等。
enum OTPAuthURLParser {
    static func parse(_ rawURL: String) throws -> OTPCode {
        // 部分服务未转义 label 里的 `#`，先整体替换再解析
        let sanitized = rawURL.replacingOccurrences(of: "#", with: "%23")
        guard let components = URLComponents(string: sanitized),
              components.scheme == "otpauth" else {
            throw OTPAuthURLError.notOTPAuth
        }

        let type: OTPType
        switch components.host?.lowercased() {
        case "totp": type = .totp
        case "hotp": type = .hotp
        case "steam": type = .steam
        case let other?: throw OTPAuthURLError.unsupportedType(other)
        case nil: throw OTPAuthURLError.notOTPAuth
        }

        let queryItems = Dictionary(
            components.queryItems?.map { ($0.name.lowercased(), $0.value ?? "") } ?? []
        ) { _, last in last }

        guard let rawSecret = queryItems["secret"], !rawSecret.isEmpty else {
            throw OTPAuthURLError.missingSecret
        }
        let secret = sanitizeSecret(rawSecret)
        guard (try? Base32.decode(secret)) != nil else {
            throw OTPAuthURLError.invalidSecret
        }

        let label = components.path.removingPercentEncoding ?? components.path
        let labelWithoutSlash = label.hasPrefix("/") ? String(label.dropFirst()) : label
        let issuer = parseIssuer(queryItems: queryItems, label: labelWithoutSlash)
        let accountName = parseAccount(label: labelWithoutSlash, issuer: issuer, hasIssuerParam: queryItems["issuer"] != nil)

        // Steam 的二维码经常伪装成普通 TOTP（host=totp、issuer=Steam），
        // 但算法完全不同（5 位自定义字母表），识别规则只认：
        // host=steam，或 issuer 精确等于 "Steam"（大小写不敏感）。
        // 不做子串匹配：避免 "Steam市场"、"SteamSupport" 等普通条目被误伤
        let isSteam = type == .steam
            || issuer.compare("Steam", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        let effectiveType: OTPType = isSteam ? .steam : type

        let digits = effectiveType == .steam
            ? OTPGenerator.steamDigits
            : (Int(queryItems["digits"] ?? "") ?? OTPGenerator.defaultDigits)
        let period = Int(queryItems["period"] ?? "") ?? OTPGenerator.defaultPeriod
        let counter = Int(queryItems["counter"] ?? "") ?? 0
        let algorithm = OTPAlgorithm(rawValue: (queryItems["algorithm"] ?? "sha1").lowercased()) ?? .sha1

        return OTPCode(
            issuer: issuer,
            accountName: accountName,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            counter: counter,
            type: effectiveType
        )
    }

    static func makeURL(for code: OTPCode) -> String {
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = code.type.rawValue
        let label = code.issuer.isEmpty ? code.accountName : "\(code.issuer):\(code.accountName)"
        components.path = "/" + label
        var items = [
            URLQueryItem(name: "secret", value: code.secret),
            URLQueryItem(name: "algorithm", value: code.algorithm.displayName),
            URLQueryItem(name: "digits", value: String(code.digits)),
        ]
        if !code.issuer.isEmpty {
            items.append(URLQueryItem(name: "issuer", value: code.issuer))
        }
        if code.type.isTimeBased {
            items.append(URLQueryItem(name: "period", value: String(code.period)))
        } else {
            items.append(URLQueryItem(name: "counter", value: String(code.counter)))
        }
        components.queryItems = items
        return components.string ?? "otpauth://\(code.type.rawValue)/\(label)"
    }

    static func sanitizeSecret(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func parseIssuer(queryItems: [String: String], label: String) -> String {
        if let issuer = queryItems["issuer"], !issuer.isEmpty {
            // 兼容把 "?period=" 误拼进 issuer 的脏数据
            if let range = issuer.range(of: "period=") {
                return String(issuer[issuer.startIndex..<range.lowerBound])
            }
            return issuer
        }
        if let colonIndex = label.firstIndex(of: ":") {
            return String(label[label.startIndex..<colonIndex])
        }
        return ""
    }

    private static func parseAccount(label: String, issuer: String, hasIssuerParam: Bool) -> String {
        if hasIssuerParam && !label.contains(":") {
            return label
        }
        if let colonIndex = label.firstIndex(of: ":") {
            return String(label[label.index(after: colonIndex)...])
        }
        return label
    }
}
