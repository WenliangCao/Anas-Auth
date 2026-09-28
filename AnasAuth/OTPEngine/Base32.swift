import Foundation

enum Base32Error: Error, Equatable {
    case invalidCharacter(Character)
    /// 没有内容，或长度不可能由整字节编码得到（多半是密钥被截断）
    case invalidLength
}

/// RFC 4648 Base32 编解码。容忍小写、空格、连字符和 `=` 填充。
/// 只用于 OTP 密钥，所以空内容也视为无效。
enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

    private static let lookup: [UInt8: UInt8] = {
        var table: [UInt8: UInt8] = [:]
        for (index, byte) in alphabet.enumerated() {
            table[byte] = UInt8(index)
        }
        return table
    }()

    static func decode(_ string: String) throws -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(string.count * 5 / 8)
        var buffer: UInt32 = 0
        var bitsInBuffer = 0
        var characterCount = 0
        for byte in string.uppercased().utf8 {
            switch byte {
            case UInt8(ascii: "="), UInt8(ascii: " "), UInt8(ascii: "-"):
                continue
            default:
                guard let value = lookup[byte] else {
                    throw Base32Error.invalidCharacter(Character(Unicode.Scalar(byte)))
                }
                characterCount += 1
                buffer = (buffer << 5) | UInt32(value)
                bitsInBuffer += 5
                if bitsInBuffer >= 8 {
                    bitsInBuffer -= 8
                    bytes.append(UInt8((buffer >> UInt32(bitsInBuffer)) & 0xff))
                }
            }
        }
        // 整字节编码后的字符数模 8 只可能是 0、2、4、5、7
        guard !bytes.isEmpty, ![1, 3, 6].contains(characterCount % 8) else {
            throw Base32Error.invalidLength
        }
        return Data(bytes)
    }

    static func encode(_ data: Data) -> String {
        var result = ""
        result.reserveCapacity((data.count * 8 + 4) / 5)
        var buffer: UInt32 = 0
        var bitsInBuffer = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bitsInBuffer += 8
            while bitsInBuffer >= 5 {
                bitsInBuffer -= 5
                result.append(Character(Unicode.Scalar(alphabet[Int((buffer >> UInt32(bitsInBuffer)) & 0x1f)])))
            }
        }
        if bitsInBuffer > 0 {
            result.append(Character(Unicode.Scalar(alphabet[Int((buffer << UInt32(5 - bitsInBuffer)) & 0x1f)])))
        }
        return result
    }
}
