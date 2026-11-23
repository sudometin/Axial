import Foundation

/// Reads little- or big-endian scalars from a `Data` buffer at absolute byte offsets.
struct BinaryReader {
    let data: Data
    var littleEndian: Bool

    init(data: Data, littleEndian: Bool = true) {
        // Normalise to a zero-based buffer so offsets are always absolute.
        self.data = data.startIndex == 0 ? data : Data(data)
        self.littleEndian = littleEndian
    }

    var count: Int { data.count }

    func u8(_ offset: Int) -> UInt8 {
        data[offset]
    }

    func u16(_ offset: Int) -> UInt16 {
        let raw: UInt16 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
        return littleEndian ? UInt16(littleEndian: raw) : UInt16(bigEndian: raw)
    }

    func u32(_ offset: Int) -> UInt32 {
        let raw: UInt32 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return littleEndian ? UInt32(littleEndian: raw) : UInt32(bigEndian: raw)
    }

    func u64(_ offset: Int) -> UInt64 {
        let raw: UInt64 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
        return littleEndian ? UInt64(littleEndian: raw) : UInt64(bigEndian: raw)
    }

    func i16(_ offset: Int) -> Int16 { Int16(bitPattern: u16(offset)) }
    func i32(_ offset: Int) -> Int32 { Int32(bitPattern: u32(offset)) }
    func f32(_ offset: Int) -> Float { Float(bitPattern: u32(offset)) }
    func f64(_ offset: Int) -> Double { Double(bitPattern: u64(offset)) }

    /// ASCII string of fixed length, cut at the first NUL.
    func string(_ offset: Int, _ length: Int) -> String {
        guard offset >= 0, offset + length <= data.count else { return "" }
        let bytes = data[offset..<(offset + length)].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Overwrites bytes at `offset` with the little-endian representation of `value`.
    mutating func setLE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        Swift.withUnsafeBytes(of: value.littleEndian) { bytes in
            replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
    }

    mutating func setLE(_ value: Float, at offset: Int) {
        setLE(value.bitPattern, at: offset)
    }

    mutating func setASCII(_ string: String, at offset: Int, maxLength: Int) {
        let bytes = Array(string.utf8.prefix(maxLength))
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
}

enum FileEnumerator {
    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// All regular, non-hidden files below `url` (recursively).
    static func regularFiles(in url: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let file as URL in enumerator {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(file)
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Expands folders into their files and keeps plain files as they are.
    static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { isDirectory($0) ? regularFiles(in: $0) : [$0] }
    }
}
