import Foundation
import Testing
@testable import Auth

struct OTPAuthURLParserTests {
    @Test func parsesStandardTOTP() throws {
        let code = try OTPAuthURLParser.parse(
            "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        )
        #expect(code.type == .totp)
        #expect(code.issuer == "Example")
        #expect(code.accountName == "alice@example.com")
        #expect(code.secret == "JBSWY3DPEHPK3PXP")
        #expect(code.algorithm == .sha1)
        #expect(code.digits == 6)
        #expect(code.period == 30)
    }

    @Test func parsesAllParameters() throws {
        let code = try OTPAuthURLParser.parse(
            "otpauth://totp/GitHub:bob?secret=ABCDEF234567&issuer=GitHub&algorithm=SHA256&digits=8&period=60"
        )
        #expect(code.algorithm == .sha256)
        #expect(code.digits == 8)
        #expect(code.period == 60)
    }

    @Test func parsesHOTPWithCounter() throws {
        let code = try OTPAuthURLParser.parse(
            "otpauth://hotp/Service:carol?secret=ABCDEF234567&issuer=Service&counter=42"
        )
        #expect(code.type == .hotp)
        #expect(code.counter == 42)
    }

    @Test func steamDefaultsToFiveDigits() throws {
        let code = try OTPAuthURLParser.parse("otpauth://steam/Steam:gaben?secret=ABCDEF234567")
        #expect(code.type == .steam)
        #expect(code.digits == 5)
    }

    @Test func handlesUnescapedHashInAccount() throws {
        let code = try OTPAuthURLParser.parse(
            "otpauth://totp/Issuer:user#name?secret=JBSWY3DPEHPK3PXP&issuer=Issuer"
        )
        #expect(code.accountName == "user#name")
    }

    @Test func handlesIssuerWithPeriodJunk() throws {
        let code = try OTPAuthURLParser.parse(
            "otpauth://totp/Broken:dan?secret=JBSWY3DPEHPK3PXP&issuer=Brokenperiod=30"
        )
        #expect(code.issuer == "Broken")
    }

    @Test func normalizesMessySecret() throws {
        let code = try OTPAuthURLParser.parse(
            "otpauth://totp/x:y?secret=jbsw y3dp-ehpk=3pxp"
        )
        #expect(code.secret == "JBSWY3DPEHPK3PXP")
    }

    @Test func labelWithoutIssuerParam() throws {
        let code = try OTPAuthURLParser.parse("otpauth://totp/OnlyLabel?secret=JBSWY3DPEHPK3PXP")
        #expect(code.issuer == "")
        #expect(code.accountName == "OnlyLabel")
    }

    @Test func rejectsNonOTPAuthScheme() {
        #expect(throws: OTPAuthURLError.notOTPAuth) {
            try OTPAuthURLParser.parse("https://example.com")
        }
    }

    @Test func rejectsMissingSecret() {
        #expect(throws: OTPAuthURLError.missingSecret) {
            try OTPAuthURLParser.parse("otpauth://totp/x:y?issuer=x")
        }
    }

    @Test func rejectsGarbageSecret() {
        #expect(throws: OTPAuthURLError.invalidSecret) {
            try OTPAuthURLParser.parse("otpauth://totp/x:y?secret=!!!invalid0189")
        }
    }

    @Test func makeURLRoundTrips() throws {
        let original = OTPCode(
            issuer: "Example",
            accountName: "alice@example.com",
            secret: "JBSWY3DPEHPK3PXP",
            algorithm: .sha512,
            digits: 8,
            period: 45,
            type: .totp
        )
        let url = OTPAuthURLParser.makeURL(for: original)
        let parsed = try OTPAuthURLParser.parse(url)
        #expect(parsed.issuer == original.issuer)
        #expect(parsed.accountName == original.accountName)
        #expect(parsed.secret == original.secret)
        #expect(parsed.algorithm == original.algorithm)
        #expect(parsed.digits == original.digits)
        #expect(parsed.period == original.period)
    }

    @Test func generatedCodeMatchesGenerator() throws {
        let code = try OTPAuthURLParser.parse(
            "otpauth://totp/x:y?secret=JBSWY3DPEHPK3PXP&digits=8"
        )
        let date = Date(timeIntervalSince1970: 59)
        let secretData = try Base32.decode("JBSWY3DPEHPK3PXP")
        #expect(try code.generateCode(at: date) == OTPGenerator.totp(secret: secretData, at: date, digits: 8))
        #expect(try code.generateNextCode(at: date) == OTPGenerator.totp(secret: secretData, at: date.addingTimeInterval(30), digits: 8))
    }
}
