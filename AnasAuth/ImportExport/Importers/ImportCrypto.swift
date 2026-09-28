import Clibsodium
import CommonCrypto
import CryptoKit
import Foundation

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

    // MARK: - 密钥派生

    static func pbkdf2(password: String, salt: Data, rounds: Int, keyLength: Int, prf: PRF) throws -> Data {
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
            throw CryptoError.invalidInput("salt 长度应为 \(crypto_pwhash_saltbytes()) 字节")
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
        // 非 0 通常是内存不足（ente 的导出可能用到 1 GiB）
        guard status == 0 else { throw CryptoError.kdfFailed }
        return Data(key)
    }

    // MARK: - 对称解密

    /// AES-GCM，密文末尾带 16 字节 tag
    static func aesGCMOpen(key: Data, nonce: Data, ciphertextAndTag: Data, aad: Data = Data()) throws -> Data {
        guard ciphertextAndTag.count >= 16 else { throw CryptoError.invalidInput("密文过短") }
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
            throw CryptoError.invalidInput("密文长度不是 16 的倍数")
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
            throw CryptoError.invalidInput("密钥或 header 长度不对")
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
