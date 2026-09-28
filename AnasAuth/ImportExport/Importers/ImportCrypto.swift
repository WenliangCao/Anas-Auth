import Clibsodium
import CommonCrypto
import CryptoKit
import Foundation
import os

/// 解密其他 App 导出文件所需的密码学原语。
/// 系统自带的（PBKDF2、AES、SHA、HMAC）用 CommonCrypto / CryptoKit；
/// Argon2id、scrypt、XChaCha20 secretstream 系统没有，用 libsodium。
enum ImportCrypto {
    enum CryptoError: Error, Equatable {
        /// 认证失败或填充错误：几乎总是密码不对
        case authenticationFailed
        case invalidInput(String)
        case kdfFailed
    }

    enum PRF {
        case sha1, sha256

        var ccValue: CCPseudoRandomAlgorithm {
            switch self {
            case .sha1: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            case .sha256: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            }
        }
    }

    // MARK: - 参数上限

    /// KDF 参数都写在导入文件里，必须限幅：否则构造的文件能让 App 分配数 GB 内存或算上几小时
    enum Limits {
        /// andOTP 用 14～16 万次，其余来源固定 1 万次
        static let maxPBKDF2Rounds = 1_000_000
        /// scrypt 内存约 128·N·r 字节（Aegis 默认 N=2^15、r=8，即 32 MiB）
        static let maxScryptMemory: UInt64 = 256 * 1024 * 1024
        /// scrypt 计算量 N·r·p（Aegis 默认的 16 倍）
        static let maxScryptWork: UInt64 = 1 << 22
        /// ente 最高档：1 GiB 内存 × 4 次；内存不够时 ente 减半内存、加倍次数，乘积不变
        static let maxArgon2Memory = 1024 * 1024 * 1024
        static let maxArgon2Work = 4 * maxArgon2Memory
    }

    // MARK: - 密钥派生

    static func pbkdf2(password: String, salt: Data, rounds: Int, keyLength: Int, prf: PRF) throws -> Data {
        guard (1...Limits.maxPBKDF2Rounds).contains(rounds) else {
            throw CryptoError.invalidInput("PBKDF2 rounds out of range")
        }
        let passwordBytes = Array(password.utf8)
        var key = Data(count: keyLength)
        let status = key.withUnsafeMutableBytes { keyBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes, passwordBytes.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    prf.ccValue, UInt32(rounds),
                    keyBuffer.bindMemory(to: UInt8.self).baseAddress, keyLength
                )
            }
        }
        guard status == kCCSuccess else { throw CryptoError.kdfFailed }
        return key
    }

    /// 通用 scrypt（Aegis 使用 N=32768, r=8, p=1）
    static func scrypt(password: String, salt: Data, n: UInt64, r: UInt32, p: UInt32, keyLength: Int) throws -> Data {
        guard n > 1, n & (n - 1) == 0, r > 0, p > 0,
              n <= Limits.maxScryptMemory / 128 / UInt64(r),
              n * UInt64(r) * UInt64(p) <= Limits.maxScryptWork else {
            throw CryptoError.invalidInput("scrypt parameters out of range")
        }
        try ensureSodium()
        let passwordBytes = Array(password.utf8)
        let saltBytes = [UInt8](salt)
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = crypto_pwhash_scryptsalsa208sha256_ll(
            passwordBytes, passwordBytes.count, saltBytes, saltBytes.count, n, r, p, &key, keyLength
        )
        guard status == 0 else { throw CryptoError.kdfFailed }
        return Data(key)
    }

    /// Argon2id v1.3，单线程（libsodium crypto_pwhash 固定 p=1，与 ente / Proton 一致）
    static func argon2id(password: String, salt: Data, opsLimit: Int, memLimit: Int, keyLength: Int) throws -> Data {
        try ensureSodium()
        guard salt.count == Int(crypto_pwhash_saltbytes()) else {
            throw CryptoError.invalidInput("salt must be \(crypto_pwhash_saltbytes()) bytes")
        }
        guard opsLimit >= 1, (8 * 1024...Limits.maxArgon2Memory).contains(memLimit),
              opsLimit <= Limits.maxArgon2Work / memLimit else {
            throw CryptoError.invalidInput("Argon2 parameters out of range")
        }
        // 内存不够时 iOS 会直接杀掉进程而不是让分配失败，提前按可用内存拒绝（模拟器上返回 0，跳过）
        let available = os_proc_available_memory()
        if available > 0, memLimit + 64 * 1024 * 1024 > available {
            throw CryptoError.kdfFailed
        }
        let passwordBytes = Array(password.utf8).map { CChar(bitPattern: $0) }
        let saltBytes = [UInt8](salt)
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = crypto_pwhash(
            &key, UInt64(keyLength),
            passwordBytes, UInt64(passwordBytes.count),
            saltBytes, UInt64(opsLimit), memLimit,
            crypto_pwhash_ALG_ARGON2ID13
        )
        // 非 0 通常是内存不足
        guard status == 0 else { throw CryptoError.kdfFailed }
        return Data(key)
    }

    // MARK: - 对称解密

    /// AES-GCM，密文末尾带 16 字节 tag
    static func aesGCMOpen(key: Data, nonce: Data, ciphertextAndTag: Data, aad: Data = Data()) throws -> Data {
        guard ciphertextAndTag.count >= 16 else { throw CryptoError.invalidInput("ciphertext is too short") }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertextAndTag.dropLast(16),
                tag: ciphertextAndTag.suffix(16)
            )
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
        } catch {
            throw CryptoError.authenticationFailed
        }
    }

    /// AES-CBC + PKCS#7 填充；填充校验失败视为密码错误
    static func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        guard !data.isEmpty, data.count % kCCBlockSizeAES128 == 0 else {
            throw CryptoError.invalidInput("ciphertext length is not a multiple of 16")
        }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var outputLength = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { outBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, key.count,
                            ivBuffer.baseAddress,
                            dataBuffer.baseAddress, data.count,
                            outBuffer.baseAddress, outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.authenticationFailed }
        return output.prefix(outputLength)
    }

    /// libsodium crypto_secretstream_xchacha20poly1305 解密（ente 的 encryptData / decryptData）。
    /// 按 ente 的 4 MiB 分块逐块解开，最后一块必须带 FINAL 标记
    static func secretStreamDecrypt(_ ciphertext: Data, key: Data, header: Data) throws -> Data {
        try ensureSodium()
        guard key.count == Int(crypto_secretstream_xchacha20poly1305_keybytes()),
              header.count == Int(crypto_secretstream_xchacha20poly1305_headerbytes()) else {
            throw CryptoError.invalidInput("invalid key or header length")
        }
        var state = crypto_secretstream_xchacha20poly1305_state()
        guard crypto_secretstream_xchacha20poly1305_init_pull(&state, [UInt8](header), [UInt8](key)) == 0 else { throw CryptoError.authenticationFailed }

        let overhead = Int(crypto_secretstream_xchacha20poly1305_abytes())
        let chunkSize = 4 * 1024 * 1024 + overhead
        var plaintext = Data()
        var offset = ciphertext.startIndex
        var finished = false
        while offset < ciphertext.endIndex {
            let chunk = [UInt8](ciphertext[offset..<min(offset + chunkSize, ciphertext.endIndex)])
            var message = [UInt8](repeating: 0, count: chunk.count)
            var messageLength: UInt64 = 0
            var tag: UInt8 = 0
            let status = crypto_secretstream_xchacha20poly1305_pull(
                &state, &message, &messageLength, &tag, chunk, UInt64(chunk.count), nil, 0
            )
            guard status == 0 else { throw CryptoError.authenticationFailed }
            plaintext.append(contentsOf: message.prefix(Int(messageLength)))
            offset += chunk.count
            finished = tag == crypto_secretstream_xchacha20poly1305_tag_final()
        }
        guard finished else { throw CryptoError.authenticationFailed }
        return plaintext
    }

    // MARK: - 摘要

    static func sha1(_ data: Data) -> Data { Data(Insecure.SHA1.hash(data: data)) }
    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// 常数时间比较 HMAC-SHA256
    static func verifyHMACSHA256(_ mac: Data, for data: Data, key: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: data, using: SymmetricKey(data: key))
    }

    private static func ensureSodium() throws {
        guard sodium_init() >= 0 else { throw CryptoError.kdfFailed }
    }
}

extension Data {
    /// 十六进制字符串 → 字节，非法输入返回 nil
    init?(hexString: String) {
        let characters = Array(hexString.utf8)
        guard characters.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(decoding: characters[index...index + 1], as: UTF8.self), radix: 16) else {
                return nil
            }
            bytes.append(byte)
        }
        self.init(bytes)
    }
}
