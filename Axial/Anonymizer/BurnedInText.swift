import Foundation
import CoreGraphics
import Vision

/// Finds text burned into pixel data with on-device OCR (Vision) and blacks it out.
enum BurnedInText {
    /// Minimum width of the image handed to Vision; small MR slices are upscaled so overlay text is legible.
    private static let ocrMinimumWidth = 1024
    private static let padding = 3

    /// Detects and masks text in native pixel data. Returns masked regions per frame (pixel coordinates).
    static func scrub(_ dataset: inout DicomDataset, frames: FrameScan) throws -> [Int: [CGRect]] {
        let format = try PixelFormat(dataset)
        guard var pixelElement = dataset[.pixelData], !pixelElement.value.isEmpty else { return [:] }

        let indices: [Int]
        switch frames {
        case .none: indices = []
        case .all: indices = Array(0..<format.frames)
        case .frame(let i): indices = [min(max(i, 0), format.frames - 1)]
        }

        var result: [Int: [CGRect]] = [:]
        for frame in indices {
            let values = try DicomPixelDecoder.frame(pixelElement.value, format: format, index: frame)
            guard let image = SliceRenderer.grayscale(values, width: format.columns, height: format.rows) else { continue }
            let normalized = try detect(in: image)
            guard !normalized.isEmpty else { continue }
            let rects = normalized.map { pixelRect($0, format: format) }.filter { !$0.isEmpty }
            guard !rects.isEmpty else { continue }
            let fill = format.isMonochrome1 ? (values.max() ?? 0) : (values.min() ?? 0)
            mask(&pixelElement.value, format: format, frame: frame, rects: rects, fill: fill)
            result[frame] = rects
        }
        dataset[.pixelData] = pixelElement
        return result
    }

    /// Text bounding boxes, normalised to 0…1 with the origin at the top-left.
    static func detect(in image: CGImage) throws -> [CGRect] {
        var input = image
        if image.width < ocrMinimumWidth {
            let factor = Double(ocrMinimumWidth) / Double(image.width)
            if let scaled = SliceRenderer.resample(image, width: ocrMinimumWidth, height: Int(Double(image.height) * factor), smooth: true) {
                input = scaled
            }
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: input, options: [:]).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= 0.3,
                  !candidate.string.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            let box = observation.boundingBox // origin bottom-left
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }

    private static func pixelRect(_ r: CGRect, format: PixelFormat) -> CGRect {
        let w = Double(format.columns), h = Double(format.rows)
        let x0 = max(Int((r.minX * w).rounded(.down)) - padding, 0)
        let y0 = max(Int((r.minY * h).rounded(.down)) - padding, 0)
        let x1 = min(Int((r.maxX * w).rounded(.up)) + padding, format.columns)
        let y1 = min(Int((r.maxY * h).rounded(.up)) + padding, format.rows)
        guard x1 > x0, y1 > y0 else { return .null }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private static func mask(_ data: inout Data, format f: PixelFormat, frame: Int, rects: [CGRect], fill: Float) {
        let frameStart = frame * f.frameBytes
        let n = f.pixelsPerFrame
        let bps = f.bytesPerSample
        let fillRaw = Int64(fill.rounded())

        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress?.advanced(by: frameStart) else { return }
            func write(_ sampleIndex: Int, _ value: Int64) {
                let offset = sampleIndex * bps
                switch bps {
                case 1: base.storeBytes(of: UInt8(truncatingIfNeeded: value), toByteOffset: offset, as: UInt8.self)
                case 2: base.storeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian, toByteOffset: offset, as: UInt16.self)
                default: base.storeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian, toByteOffset: offset, as: UInt32.self)
                }
            }
            for rect in rects {
                for y in Int(rect.minY)..<Int(rect.maxY) {
                    for x in Int(rect.minX)..<Int(rect.maxX) {
                        let p = y * f.columns + x
                        if f.samplesPerPixel == 1 {
                            write(p, fillRaw)
                        } else {
                            for c in 0..<3 { write(f.isPlanar ? c * n + p : p * 3 + c, 0) }
                        }
                    }
                }
            }
        }
    }
}
