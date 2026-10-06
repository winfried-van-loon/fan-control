import CSMC
import Foundation

public enum SMCError: Error, CustomStringConvertible {
    case openFailed(Int32)
    case readFailed(String, Int32)
    case writeFailed(String, Int32)
    case unsupportedType(String, String)

    public var description: String {
        switch self {
        case .openFailed(let rc): return "Could not open AppleSMC (\(rc))"
        case .readFailed(let key, let rc): return "Could not read SMC key \(key) (\(rc))"
        case .writeFailed(let key, let rc): return "Could not write SMC key \(key) (\(rc)) — root required"
        case .unsupportedType(let key, let type): return "Unsupported SMC type '\(type)' for key \(key)"
        }
    }
}

public func fourCC(_ s: String) -> UInt32 {
    s.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
}

public func fourCCString(_ v: UInt32) -> String {
    let bytes = [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
    return String(decoding: bytes, as: UTF8.self)
}

public struct SMCValue {
    public let key: String
    public let type: String
    public let bytes: [UInt8]

    /// Numeric interpretation of the value, if the type is known.
    public var double: Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "ui8 ", "flag":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "si8 ":
            return bytes.first.map { Double(Int8(bitPattern: $0)) }
        case "si16":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1])))
        default:
            return nil
        }
    }
}

public enum SMC {
    private static let lock = NSLock()

    public static func open() throws {
        let rc = smc_open()
        if rc != 0 { throw SMCError.openFailed(rc) }
    }

    public static func read(_ key: String) throws -> SMCValue {
        lock.lock(); defer { lock.unlock() }
        var v = smc_value_t()
        let rc = smc_read(fourCC(key), &v)
        if rc != 0 { throw SMCError.readFailed(key, rc) }
        let bytes = withUnsafeBytes(of: v.bytes) { Array($0.prefix(Int(v.dataSize))) }
        return SMCValue(key: key, type: fourCCString(v.dataType), bytes: bytes)
    }

    public static func double(_ key: String) -> Double? {
        try? read(key).double
    }

    /// Encodes `value` in the key's native type and writes it.
    public static func write(_ key: String, _ value: Double) throws {
        let current = try read(key)
        let bytes: [UInt8]
        switch current.type {
        case "flt ":
            let bits = Float(value).bitPattern
            bytes = [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
        case "fpe2":
            let raw = UInt16(max(0, min(16383, value)) * 4)
            bytes = [UInt8(raw >> 8), UInt8(raw & 0xff)]
        case "ui8 ", "flag":
            bytes = [UInt8(max(0, min(255, value)))]
        case "ui16":
            let raw = UInt16(max(0, min(65535, value)))
            bytes = [UInt8(raw >> 8), UInt8(raw & 0xff)]
        default:
            throw SMCError.unsupportedType(key, current.type)
        }
        try writeRaw(key, bytes)
    }

    public static func writeRaw(_ key: String, _ bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        let rc = bytes.withUnsafeBufferPointer { smc_write(fourCC(key), $0.baseAddress, UInt32($0.count)) }
        if rc != 0 { throw SMCError.writeFailed(key, rc) }
    }

    public static func allKeys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let count = smc_key_count()
        return (0..<count).compactMap { i in
            let k = smc_key_at_index(i)
            return k == 0 ? nil : fourCCString(k)
        }
    }
}
