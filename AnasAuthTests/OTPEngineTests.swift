import Foundation
import Testing
@testable import AnasAuth

struct OTPEngineTests {
    // RFC 4226 附录 D 的标准测试向量（密钥为 ASCII "12345678901234567890"）
    @Test func hotpRFC4226Vectors() throws {
        let secret = Data("12345678901234567890".utf8)
        let expected = [
            "755224", "287082", "359152", "969429", "338314",
            "254676", "287922", "162583", "399871", "520489",
        ]
        for (counter, code) in expected.enumerated() {
            #expect(OTPGenerator.hotp(secret: secret, counter: UInt64(counter)) == code)
        }
    }

    // RFC 6238 附录 B，8 位验证码，时间戳 59 / 1111111109 / 1234567890
    @Test(arguments: [
        (59.0, "94287082"),
        (1111111109.0, "07081804"),
        (1111111111.0, "14050471"),
        (1234567890.0, "89005924"),
        (2000000000.0, "69279037"),
    ])
    func totpRFC6238SHA1(timestamp: Double, expected: String) throws {
        let secret = Data("12345678901234567890".utf8)
        let date = Date(timeIntervalSince1970: timestamp)
        #expect(OTPGenerator.totp(secret: secret, at: date, digits: 8, algorithm: .sha1) == expected)
    }

    @Test func totpRFC6238SHA256() throws {
        let secret = Data("12345678901234567890123456789012".utf8)
        let date = Date(timeIntervalSince1970: 59)
        #expect(OTPGenerator.totp(secret: secret, at: date, digits: 8, algorithm: .sha256) == "46119246")
    }

    @Test func totpRFC6238SHA512() throws {
        let secret = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)
        let date = Date(timeIntervalSince1970: 59)
        #expect(OTPGenerator.totp(secret: secret, at: date, digits: 8, algorithm: .sha512) == "90693936")
    }

    @Test func steamFormat() throws {
        let secret = try #require(try? Base32.decode("JBSWY3DPEHPK3PXP"))
        let code = OTPGenerator.steam(secret: secret, at: Date(timeIntervalSince1970: 1234567890))
        #expect(code.count == 5)
        #expect(code.allSatisfy { "23456789BCDFGHJKMNPQRTVWXY".contains($0) })
        // 同一时间点结果必须确定
        #expect(code == OTPGenerator.steam(secret: secret, at: Date(timeIntervalSince1970: 1234567890)))
    }

    @Test func base32Decode() throws {
        // "Hello!\xDE\xAD\xBE\xEF" 的标准编码
        // 标准向量："Hello!\x21\xDE\xAD\xBE\xEF" 即 0x48 0x65 0x6C 0x6C 0x6F 0x21 0xDE 0xAD 0xBE 0xEF
        let decoded = try Base32.decode("JBSWY3DPEHPK3PXP")
        #expect(decoded == Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test func base32ToleratesPaddingLowercaseAndSpaces() throws {
        let reference = try Base32.decode("JBSWY3DPEHPK3PXP")
        #expect(try Base32.decode("JBSWY3DPEHPK3PXP==") == reference)
        #expect(try Base32.decode("jbsw y3dp ehpk 3pxp") == reference)
    }

    @Test func base32RoundTrip() throws {
        let original = Data((0..<64).map { UInt8($0) })
        #expect(try Base32.decode(Base32.encode(original)) == original)
    }

    @Test func base32RejectsInvalidCharacters() {
        #expect(throws: Base32Error.self) {
            try Base32.decode("JBSW!0189")
        }
    }

    @Test func remainingSeconds() {
        let date = Date(timeIntervalSince1970: 1234567890) // 1234567890 % 30 == 0… 验证边界
        let period = 30
        let expected = period - Int(date.timeIntervalSince1970) % period
        #expect(OTPGenerator.remainingSeconds(at: date, period: period) == expected)
    }
}

extension OTPEngineTests {
    @Test func hotpClampsInvalidDigits() {
        let secret = Data("12345678901234567890".utf8)
        #expect(OTPGenerator.hotp(secret: secret, counter: 0, digits: 0).count == 1)
        #expect(OTPGenerator.hotp(secret: secret, counter: 0, digits: 99).count == 10)
    }
}
