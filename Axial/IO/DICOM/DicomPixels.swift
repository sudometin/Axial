import Foundation
import CoreGraphics
import ImageIO

/// Layout of native (uncompressed) pixel data.
struct PixelFormat {
    let rows: Int
    let columns: Int
    let samplesPerPixel: Int
    let bitsAllocated: Int
    let bitsStored: Int
    let isSigned: Bool
    let isPlanar: Bool
    let frames: Int
    let photometric: String

    var bytesPerSample: Int { bitsAllocated / 8 }
    var pixelsPerFrame: Int { rows * columns }
    var frameBytes: Int { pixelsPerFrame * samplesPerPixel * bytesPerSample }
    var isMonochrome1: Bool { photometric == "MONOCHROME1" }

    init(_ ds: DicomDataset) throws {
        guard let rows = ds.uint16(.rows), let columns = ds.uint16(.columns), rows > 0, columns > 0 else {
            throw DicomError.missing("Rows / Columns")
        }
        self.rows = rows
        self.columns = columns
        samplesPerPixel = ds.uint16(.samplesPerPixel) ?? 1
        bitsAllocated = ds.uint16(.bitsAllocated) ?? 16
        bitsStored = min(max(ds.uint16(.bitsStored) ?? bitsAllocated, 1), bitsAllocated)
        isSigned = (ds.uint16(.pixelRepresentation) ?? 0) == 1
        isPlanar = (ds.uint16(.planarConfiguration) ?? 0) == 1
        frames = max(ds.int(.numberOfFrames) ?? 1, 1)
        photometric = ds.string(.photometricInterpretation) ?? "MONOCHROME2"

        guard samplesPerPixel == 1 || samplesPerPixel == 3 else {
            throw DicomError.unsupportedPixelFormat("\(samplesPerPixel) samples per pixel")
        }
        guard [8, 16].contains(bitsAllocated) || (bitsAllocated == 32 && samplesPerPixel == 1) else {
            throw DicomError.unsupportedPixelFormat("\(bitsAllocated)-bit")
        }
        if photometric.hasPrefix("YBR") && samplesPerPixel == 3 {
            throw DicomError.unsupportedPixelFormat(photometric)
        }
    }
}

enum DicomPixelDecoder {
    /// Decodes one frame of native pixel data to stored values (no rescale).
    /// Colour images are converted to luminance.
    static func frame(_ raw: Data, format f: PixelFormat, index: Int) throws -> [Float] {
        let start = index * f.frameBytes
        guard index >= 0, start + f.frameBytes <= raw.count else { throw DicomError.truncated }
        let n = f.pixelsPerFrame
        var out = [Float](repeating: 0, count: n)
        let shift = UInt16(16 - min(f.bitsStored, 16))
        let mask16: UInt16 = f.bitsStored >= 16 ? 0xFFFF : UInt16((1 << f.bitsStored) - 1)

        raw.withUnsafeBytes { buffer in
            let base = buffer.baseAddress!.advanced(by: start)
            func sample(_ i: Int) -> Float {
                switch f.bitsAllocated {
                case 8:
                    let v = base.load(fromByteOffset: i, as: UInt8.self)
                    return f.isSigned ? Float(Int8(bitPattern: v)) : Float(v)
                case 16:
                    let v = UInt16(littleEndian: base.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                    if f.isSigned { return Float(Int16(bitPattern: v << shift) >> Int16(shift)) }
                    return Float(v & mask16)
                default:
                    let v = UInt32(littleEndian: base.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
                    return f.isSigned ? Float(Int32(bitPattern: v)) : Float(v)
                }
            }
            if f.samplesPerPixel == 1 {
                for i in 0..<n { out[i] = sample(i) }
            } else {
                for i in 0..<n {
                    let r, g, b: Float
                    if f.isPlanar {
                        r = sample(i); g = sample(n + i); b = sample(2 * n + i)
                    } else {
                        r = sample(3 * i); g = sample(3 * i + 1); b = sample(3 * i + 2)
                    }
                    out[i] = 0.299 * r + 0.587 * g + 0.114 * b
                }
            }
        }
        return out
    }

    /// Best-effort preview of compressed (encapsulated) single-frame images via ImageIO.
    /// Works for JPEG Baseline and JPEG 2000; returns nil otherwise.
    static func previewCompressed(_ file: DicomFile) -> CGImage? {
        guard let fragments = file.dataset[.pixelData]?.fragments, fragments.count >= 2 else { return nil }
        var payload = Data()
        for fragment in fragments.dropFirst() { payload.append(fragment) } // first item is the offset table
        guard let source = CGImageSourceCreateWithData(payload as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
