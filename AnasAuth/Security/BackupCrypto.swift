import CryptoKit
import Foundation

/// 加密备份。格式自述、简单、无依赖：
/// 1. 密码 → HKDF-SHA256 派生 256 位密钥（固定盐 = bundle id，防彩虹表）
/// 2. AES-GCM 加密 JSON 备份
/// 3. 文件 = 12 字节随机 nonce + GCM 密文（含认证标签）
/// 头部一个 magic 前缀便于导入时区分明文/密文。
enum BackupCrypto {
    static let magic = "AUTHENCRYPTED1"
    /// 加密格式常量：沿用改名前的旧值，改了会导致已有加密备份无法解密
    private static let salt = Data("com.wenliang.auth.backup.v1".utf8)

    enum CryptoError: Error, Equatable {
        case wrongPassword
        case notEncryptedFile
        case malformedFile
    }

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        let key = deriveKey(password: password)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.malformedFile }
        var file = Data(magic.utf8)
        file.append(combined) // nonce(12) + ciphertext + tag(16)
        return file
    }

    static func decrypt(_ file: Data, password: String) throws -> Data {
        let magicBytes = Data(magic.utf8)
        guard file.count > magicBytes.count,
              file.prefix(magicBytes.count) == magicBytes else {
            throw CryptoError.notEncryptedFile
        }
        let box = try AES.GCM.SealedBox(combined: file.dropFirst(magicBytes.count))
        let key = deriveKey(password: password)
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.wrongPassword
        }
    }

    static func isEncryptedFile(_ data: Data) -> Bool {
        data.prefix(magic.utf8.count) == Data(magic.utf8)
    }

    /// HKDF 而非 PBKDF2：用户会输入强口令（我们自己提示），HKDF 足够且快；
    /// 不做慢哈希迭代是权衡：备份文件离线场景，暴力破解成本已由口令强度决定
    private static func deriveKey(password: String) -> SymmetricKey {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
            salt: salt,
            outputByteCount: 32
        )
        return key
    }
}
