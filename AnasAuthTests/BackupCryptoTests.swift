import Foundation
import Testing
@testable import AnasAuth

struct BackupCryptoTests {
    private let plaintext = Data(#"{"hello":"world"}"#.utf8)

    @Test func roundTrip() throws {
        let file = try BackupCrypto.encrypt(plaintext, password: "correct horse")
        #expect(BackupCrypto.isEncryptedFile(file))
        #expect(try BackupCrypto.decrypt(file, password: "correct horse") == plaintext)
    }

    /// 每次加密用随机盐：同一密码同一内容，两次结果不同
    @Test func usesRandomSalt() throws {
        let first = try BackupCrypto.encrypt(plaintext, password: "pw")
        let second = try BackupCrypto.encrypt(plaintext, password: "pw")
        #expect(first != second)
    }

    @Test func wrongPassword() throws {
        let file = try BackupCrypto.encrypt(plaintext, password: "right")
        #expect(throws: BackupCrypto.CryptoError.wrongPassword) {
            try BackupCrypto.decrypt(file, password: "wrong")
        }
    }

    /// 构造的文件要求离谱的 Argon2 参数时直接拒绝
    @Test func rejectsAbsurdParameters() throws {
        var file = try BackupCrypto.encrypt(plaintext, password: "pw")
        let memOffset = BackupCrypto.magic.utf8.count + 16 + 4
        file.replaceSubrange(memOffset..<(memOffset + 4), with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: BackupCrypto.CryptoError.malformedFile) {
            try BackupCrypto.decrypt(file, password: "pw")
        }
    }

    /// 旧版（v1，HKDF）加密备份仍能导入
    @Test func decryptsLegacyV1Backup() throws {
        let legacy = try #require(Data(base64Encoded: "QVVUSEVOQ1JZUFRFRDEuLzPNzAoSiaHus+q1ua0YjS/Clsr0uEuZR1fxv3yVpsf8YlE6xeRJcmkWiFNkhGY1r4jM8PCUbgZDU8zP3UbBduqWM08TsStSnnu9dqvpLKGAxnXIPfyT5dBi6QvT3zQPgtNiMxIiM+vEa7nlJNBDf2WfZ/oT3B+jAylj48a7is6kvFYmH95lLi9R2wKvkv4bxDltdjMnJKzcmxYN4ud3sxK5LrsL2VWOZiVnt+XpWC47XB+EzW5FGKS9hOmQ62U2z2OrSnnF91aR1BbH54lFfGWCqr2YzrIx8RAlTytkHTW8AdkhUiD+ZZDvslboJACN0M82LahyRYUU"))
        #expect(ImportService.isEncryptedBackup(legacy))
        let codes = try ImportService.importCodes(fromFileContents: legacy, password: "legacy-pass")
        #expect(codes.map(\.issuer) == ["GitHub"])
        #expect(throws: BackupCrypto.CryptoError.wrongPassword) {
            try BackupCrypto.decrypt(legacy, password: "nope")
        }
    }

    @Test func encryptedExportImportRoundTrip() throws {
        let codes = [OTPCode(issuer: "GitHub", accountName: "alice", secret: "JBSWY3DPEHPK3PXP")]
        let file = try ExportService.makeEncryptedJSON(from: codes, password: "pw")
        let imported = try ImportService.importCodes(fromFileContents: file, password: "pw")
        #expect(imported.map(\.secret) == ["JBSWY3DPEHPK3PXP"])
    }
}
