import CryptoKit
import Foundation

/// 加密备份。格式自述、简单：
/// v2（当前）：magic + 16 字节随机盐 + Argon2id 参数（opsLimit、memLimit KiB，各 4 字节大端）
///            + AES-GCM 密文（12 字节 nonce + 密文 + 16 字节 tag）
/// v1（旧版，只解密）：magic + AES-GCM 密文，密钥由密码经 HKDF（固定盐）派生
/// Argon2id 是慢哈希且吃内存，备份文件泄露后暴力破解密码的成本远高于 HKDF。
enum BackupCrypto {
    static let magic = "AUTHENCRYPTED2"
    private static let legacyMagic = "AUTHENCRYPTED1"
    /// v1 加密格式常量：沿用改名前的旧值，改了会导致已有加密备份无法解密
    private static let legacySalt = Data("com.wenliang.auth.backup.v1".utf8)

    /// Argon2id 参数：3 次迭代、64 MiB 内存，手机上约零点几秒；写进文件头，以后可调整
    private static let opsLimit: UInt32 = 3
    private static let memLimitKiB: UInt32 = 64 * 1024
    private static let saltLength = 16
    /// 解密时参数上限：防止构造的文件要求离谱的内存或时间
    private static let maxOpsLimit: UInt32 = 10
    private static let maxMemLimitKiB: UInt32 = 256 * 1024

    enum CryptoError: Error, Equatable {
        case wrongPassword
        case notEncryptedFile
        case malformedFile
    }

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        let salt = SymmetricKey(size: SymmetricKeySize(bitCount: saltLength * 8)).withUnsafeBytes { Data($0) }
        let key = try deriveKey(password: password, salt: salt, opsLimit: opsLimit, memLimitKiB: memLimitKiB)
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw CryptoError.malformedFile
        }
        var file = Data(magic.utf8)
        file.append(salt)
        file.append(bigEndian: opsLimit)
        file.append(bigEndian: memLimitKiB)
        file.append(combined)
        return file
    }

    static func decrypt(_ file: Data, password: String) throws -> Data {
        if file.starts(with: Data(legacyMagic.utf8)) {
            let key = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
                salt: legacySalt,
                outputByteCount: 32
            )
            return try open(file.dropFirst(legacyMagic.utf8.count), key: key)
        }
        guard file.starts(with: Data(magic.utf8)) else { throw CryptoError.notEncryptedFile }
        var body = file.dropFirst(magic.utf8.count)
        guard body.count > saltLength + 8 else { throw CryptoError.malformedFile }
        let salt = Data(body.prefix(saltLength))
        body = body.dropFirst(saltLength)
        let ops = UInt32(bigEndianBytes: body.prefix(4))
        let memKiB = UInt32(bigEndianBytes: body.dropFirst(4).prefix(4))
        guard (1...maxOpsLimit).contains(ops), (8...maxMemLimitKiB).contains(memKiB) else {
            throw CryptoError.malformedFile
        }
        let key = try deriveKey(password: password, salt: salt, opsLimit: ops, memLimitKiB: memKiB)
        return try open(body.dropFirst(8), key: key)
    }

    static func isEncryptedFile(_ data: Data) -> Bool {
        data.starts(with: Data(magic.utf8)) || data.starts(with: Data(legacyMagic.utf8))
    }

    private static func open(_ combined: Data, key: SymmetricKey) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: combined) else { throw CryptoError.malformedFile }
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.wrongPassword
        }
    }

    private static func deriveKey(password: String, salt: Data, opsLimit: UInt32, memLimitKiB: UInt32) throws -> SymmetricKey {
        let key = try ImportCrypto.argon2id(
            password: password,
            salt: salt,
            opsLimit: Int(opsLimit),
            memLimit: Int(memLimitKiB) * 1024,
            keyLength: 32
        )
        return SymmetricKey(data: key)
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

private extension UInt32 {
    init(bigEndianBytes bytes: Data) {
        self = bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
