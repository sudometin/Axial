import Foundation

enum GzipError: LocalizedError {
    case notGzip
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notGzip: "The file is not gzip-compressed."
        case .corrupt: "The gzip stream is damaged or truncated."
        }
    }
}

/// Minimal gzip (RFC 1952) support on top of Foundation's raw-DEFLATE codec.
enum Gzip {
    static func isGzipped(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B else { throw GzipError.notGzip }
        guard bytes[2] == 8 else { throw GzipError.corrupt } // DEFLATE only

        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw GzipError.corrupt }
            let extraLength = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            offset += 2 + extraLength
        }
        if flags & 0x08 != 0 { offset = try skipZeroTerminated(bytes, from: offset) } // FNAME
        if flags & 0x10 != 0 { offset = try skipZeroTerminated(bytes, from: offset) } // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset < bytes.count - 8 else { throw GzipError.corrupt }

        let payload = Data(bytes[offset..<(bytes.count - 8)])
        do {
            // NSData's `.zlib` algorithm is raw DEFLATE, which is exactly the gzip payload.
            return try (payload as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw GzipError.corrupt
        }
    }

    static func compress(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        out.append(deflated)
        out.appendLE(CRC32.checksum(data))
        out.appendLE(UInt32(truncatingIfNeeded: data.count))
        return out
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var offset = start
        while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
        guard offset < bytes.count else { throw GzipError.corrupt }
        return offset + 1
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
