import Foundation
import Testing
@testable import Auth

struct ImportExportTests {
    /// 手工拼一段 OtpParameters protobuf 字段
    private static func otpParameterBlob(
        secret: Data,
        name: String,
        issuer: String = "",
        algorithm: UInt64 = 1,
        digits: UInt64 = 1,
        type: UInt64 = 2,
        counter: UInt64 = 0
    ) -> Data {
        var blob = Data()
        func appendTag(_ field: UInt64, wire: UInt64) {
            blob.append(UInt8((field << 3) | wire))
        }
        func appendLengthDelimited(_ field: UInt64, _ data: Data) {
            appendTag(field, wire: 2)
            blob.append(UInt8(data.count))
            blob.append(data)
        }
        func appendVarint(_ field: UInt64, _ value: UInt64) {
            appendTag(field, wire: 0)
            blob.append(UInt8(value))
        }
        appendLengthDelimited(1, secret)
        appendLengthDelimited(2, Data(name.utf8))
        if !issuer.isEmpty { appendLengthDelimited(3, Data(issuer.utf8)) }
        appendVarint(4, algorithm)
        appendVarint(5, digits)
        appendVarint(6, type)
        if counter > 0 { appendVarint(7, counter) }
        return blob
    }

    private static func makeMigrationURL(blobs: [Data]) -> String {
        var payload = Data()
        for blob in blobs {
            payload.append(0x0A) // field 1, length-delimited
            payload.append(UInt8(blob.count))
            payload.append(blob)
        }
        let base64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "otpauth-migration://offline?data=\(base64)"
    }

    @Test func parsesGoogleMigrationURL() throws {
        let url = Self.makeMigrationURL(blobs: [
            Self.otpParameterBlob(
                secret: Data("Hello!\u{DE}\u{AD}\u{BE}\u{EF}".utf8),
                name: "Test:alice",
                algorithm: 2, digits: 2, type: 2
            ),
            Self.otpParameterBlob(
                secret: Data("second-secret".utf8),
                name: "bob",
                issuer: "Service",
                algorithm: 1, digits: 1, type: 1, counter: 5
            ),
        ])
        let codes = try GoogleMigrationParser.parse(url)
        #expect(codes.count == 2)

        #expect(codes[0].issuer == "Test")
        #expect(codes[0].accountName == "alice")
        #expect(codes[0].algorithm == .sha256)
        #expect(codes[0].digits == 8)
        #expect(codes[0].type == .totp)
        // 密钥是原始字节 → Base32 编码后可解码还原
        #expect(try Base32.decode(codes[0].secret) == Data("Hello!\u{DE}\u{AD}\u{BE}\u{EF}".utf8))

        #expect(codes[1].issuer == "Service")
        #expect(codes[1].accountName == "bob")
        #expect(codes[1].type == .hotp)
        #expect(codes[1].counter == 5)
    }

    @Test func rejectsNonMigrationURL() {
        #expect(throws: GoogleMigrationError.notMigrationURL) {
            try GoogleMigrationParser.parse("otpauth://totp/x:y?secret=ABC")
        }
    }

    @Test func importAutoDetectsPlainOTPAuthLines() throws {
        let text = """
        otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub
        这一行不是 otpauth，应被跳过
        otpauth://hotp/Service:bob?secret=ABCDEF234567&counter=3
        """
        let codes = try ImportService.importCodes(from: text)
        #expect(codes.count == 2)
        #expect(codes[0].issuer == "GitHub")
        #expect(codes[1].type == .hotp)
    }

    @Test func importRejectsGarbage() {
        #expect(throws: ImportError.noCodesFound) {
            try ImportService.importCodes(from: "完全无关的文本")
        }
        #expect(throws: ImportError.emptyInput) {
            try ImportService.importCodes(from: "   ")
        }
    }

    @Test func jsonExportImportRoundTrip() throws {
        let originals = [
            OTPCode(issuer: "GitHub", accountName: "alice", secret: "JBSWY3DPEHPK3PXP",
                    algorithm: .sha256, digits: 8, period: 45, note: "工作号", pinned: true),
            OTPCode(issuer: "Steam", accountName: "gaben", secret: "ABCDEF234567",
                    type: .steam),
        ]
        let json = try ExportService.makeJSON(from: originals)
        let text = String(decoding: json, as: UTF8.self)
        let imported = try ImportService.importCodes(from: text)
        #expect(imported.count == 2)
        #expect(imported[0].issuer == "GitHub")
        #expect(imported[0].algorithm == .sha256)
        #expect(imported[0].note == "工作号")
        #expect(imported[0].pinned)
        #expect(imported[1].type == .steam)
    }

    @Test func otpAuthTextExportParses() throws {
        let codes = [
            OTPCode(issuer: "A", accountName: "a", secret: "JBSWY3DPEHPK3PXP"),
            OTPCode(issuer: "B", accountName: "b", secret: "ABCDEF234567"),
        ]
        let text = ExportService.makeOTPAuthText(from: codes)
        let imported = try ImportService.importCodes(from: text)
        #expect(imported.count == 2)
        #expect(imported.map(\.secret) == codes.map(\.secret))
    }
}
