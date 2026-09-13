import Foundation

/// 导出的 JSON 文件格式。结构简单直白，方便用户自己也能读、能改。
struct AuthExportFile: Codable {
    struct ExportedCode: Codable {
        var issuer: String
        var accountName: String
        var secret: String
        var algorithm: String
        var digits: Int
        var period: Int
        var counter: Int
        var type: String
        var note: String
        var pinned: Bool
    }

    var version: Int
    var exportedAt: Date
    var codes: [ExportedCode]
}

enum ExportService {
    static func makeJSON(from codes: [OTPCode]) throws -> Data {
        let file = AuthExportFile(
            version: 1,
            exportedAt: .now,
            codes: codes.map { code in
                AuthExportFile.ExportedCode(
                    issuer: code.issuer,
                    accountName: code.accountName,
                    secret: code.secret,
                    algorithm: code.algorithm.rawValue,
                    digits: code.digits,
                    period: code.period,
                    counter: code.counter,
                    type: code.type.rawValue,
                    note: code.note,
                    pinned: code.pinned
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func makeOTPAuthText(from codes: [OTPCode]) -> String {
        codes.map { OTPAuthURLParser.makeURL(for: $0) }.joined(separator: "\n")
    }
}
