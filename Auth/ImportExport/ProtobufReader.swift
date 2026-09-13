import Foundation

enum ProtobufError: Error {
    case truncated
    case malformedVarint
    case unsupportedWireType(UInt64)
}

/// 极简 Protocol Buffers wire format 读取器，只够解析
/// Google Authenticator 的迁移负载，不引入第三方依赖。
struct ProtobufReader {
    struct Field {
        let number: Int
        let wireType: UInt64
        /// wireType == 0 时的 varint 值
        let varintValue: UInt64?
        /// wireType == 2 时的长度限定数据
        let data: Data?
    }

    static func readFields(from data: Data) throws -> [Field] {
        var fields: [Field] = []
        var offset = data.startIndex
        while offset < data.endIndex {
            let key = try readVarint(from: data, at: &offset)
            let fieldNumber = Int(key >> 3)
            let wireType = key & 0x7
            switch wireType {
            case 0: // varint
                let value = try readVarint(from: data, at: &offset)
                fields.append(Field(number: fieldNumber, wireType: wireType, varintValue: value, data: nil))
            case 2: // length-delimited
                let length = Int(try readVarint(from: data, at: &offset))
                guard offset + length <= data.endIndex else { throw ProtobufError.truncated }
                fields.append(Field(number: fieldNumber, wireType: wireType, varintValue: nil,
                                    data: data[offset..<(offset + length)]))
                offset += length
            case 5: // fixed32
                guard offset + 4 <= data.endIndex else { throw ProtobufError.truncated }
                offset += 4
            case 1: // fixed64
                guard offset + 8 <= data.endIndex else { throw ProtobufError.truncated }
                offset += 8
            default:
                throw ProtobufError.unsupportedWireType(wireType)
            }
        }
        return fields
    }

    static func readVarint(from data: Data, at offset: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.endIndex {
            let byte = data[offset]
            offset = data.index(after: offset)
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else { throw ProtobufError.malformedVarint }
        }
        throw ProtobufError.truncated
    }
}
