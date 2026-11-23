import Foundation
import CoreGraphics

enum Plane: String, CaseIterable, Identifiable {
    case axial = "Axial"
    case coronal = "Coronal"
    case sagittal = "Sagittal"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .axial: "square.split.2x2"
        case .coronal: "rectangle.split.2x1"
        case .sagittal: "rectangle.split.1x2"
        }
    }
}

struct OrientationLabels: Equatable {
    var left = ""
    var right = ""
    var top = ""
    var bottom = ""
    static let none = OrientationLabels()
}

/// Maps between a 2-D display plane and voxel space of a canonical (RAS+) volume.
///
/// * Axial: patient anterior at the top. Coronal and sagittal: superior at the top.
/// * Neurological convention by default (patient left on screen left); radiological flips it.
/// * Sagittal: anterior on screen left.
struct PlaneGeometry {
    let plane: Plane
    let nx: Int, ny: Int, nz: Int
    let spacing: [Double]
    let radiological: Bool

    init(volume: Volume, plane: Plane, radiological: Bool) {
        self.plane = plane
        nx = volume.nx; ny = volume.ny; nz = volume.nz
        spacing = volume.spacing
        self.radiological = radiological
    }

    var width: Int { plane == .sagittal ? ny : nx }
    var height: Int { plane == .axial ? ny : nz }
    var horizontalAxis: Int { plane == .sagittal ? 1 : 0 }
    var verticalAxis: Int { plane == .axial ? 1 : 2 }

    var physicalSize: CGSize {
        CGSize(width: Double(width) * spacing[horizontalAxis], height: Double(height) * spacing[verticalAxis])
    }

    var sliceCount: Int {
        switch plane {
        case .axial: nz
        case .coronal: ny
        case .sagittal: nx
        }
    }

    func sliceIndex(of v: Voxel) -> Int {
        switch plane {
        case .axial: v.z
        case .coronal: v.y
        case .sagittal: v.x
        }
    }

    func moving(_ v: Voxel, toSlice s: Int) -> Voxel {
        var out = v
        switch plane {
        case .axial: out.z = s
        case .coronal: out.y = s
        case .sagittal: out.x = s
        }
        return out
    }

    private func flipX(_ value: Int) -> Int { radiological ? nx - 1 - value : value }

    /// The voxel under display pixel (col, row); the through-plane coordinate comes from `base`.
    func voxel(col: Int, row: Int, base: Voxel) -> Voxel {
        var v = base
        switch plane {
        case .axial: v.x = flipX(col); v.y = ny - 1 - row
        case .coronal: v.x = flipX(col); v.z = nz - 1 - row
        case .sagittal: v.y = ny - 1 - col; v.z = nz - 1 - row
        }
        return v
    }

    func pixel(for v: Voxel) -> (col: Int, row: Int) {
        switch plane {
        case .axial: return (col: flipX(v.x), row: ny - 1 - v.y)
        case .coronal: return (col: flipX(v.x), row: nz - 1 - v.z)
        case .sagittal: return (col: ny - 1 - v.y, row: nz - 1 - v.z)
        }
    }

    /// Linear-index walk for a slice: index(col, row) = start + col·dc + row·dr.
    func walk(slice s: Int) -> (start: Int, dc: Int, dr: Int) {
        let sliceSize = nx * ny
        let xStart = radiological ? nx - 1 : 0
        let dx = radiological ? -1 : 1
        switch plane {
        case .axial:
            return (xStart + (ny - 1) * nx + s * sliceSize, dx, -nx)
        case .coronal:
            return (xStart + s * nx + (nz - 1) * sliceSize, dx, -sliceSize)
        case .sagittal:
            return (s + (ny - 1) * nx + (nz - 1) * sliceSize, -nx, -sliceSize)
        }
    }

    var labels: OrientationLabels {
        let left = radiological ? "R" : "L"
        let right = radiological ? "L" : "R"
        switch plane {
        case .axial: return OrientationLabels(left: left, right: right, top: "A", bottom: "P")
        case .coronal: return OrientationLabels(left: left, right: right, top: "S", bottom: "I")
        case .sagittal: return OrientationLabels(left: "A", right: "P", top: "S", bottom: "I")
        }
    }
}

enum SliceRenderer {
    /// Extracts one slice in display orientation.
    static func slice(_ volume: Volume, geometry g: PlaneGeometry, index: Int) -> [Float] {
        let w = g.width, h = g.height
        var out = [Float](repeating: 0, count: w * h)
        let s = min(max(index, 0), g.sliceCount - 1)
        let (start, dc, dr) = g.walk(slice: s)
        volume.voxels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for row in 0..<h {
                    var i = start + row * dr
                    let o = row * w
                    for col in 0..<w {
                        dst[o + col] = src[i]
                        i += dc
                    }
                }
            }
        }
        return out
    }

    /// Maximum-intensity projection through all slices of a plane, in display orientation.
    static func maximumProjection(_ volume: Volume, geometry g: PlaneGeometry) -> [Float] {
        let w = g.width, h = g.height
        var out = [Float](repeating: -Float.greatestFiniteMagnitude, count: w * h)
        volume.voxels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for s in 0..<g.sliceCount {
                    let (start, dc, dr) = g.walk(slice: s)
                    for row in 0..<h {
                        var i = start + row * dr
                        let o = row * w
                        for col in 0..<w {
                            let v = src[i]
                            if v > dst[o + col] { dst[o + col] = v }
                            i += dc
                        }
                    }
                }
            }
        }
        return out
    }

    /// Converts scalar values to an RGB image through a window and colormap.
    static func image(_ values: [Float], width: Int, height: Int, window: WindowLevel,
                      colormap: Colormap, invert: Bool = false) -> CGImage? {
        guard width > 0, height > 0, values.count == width * height else { return nil }
        let lut = colormap.lut
        let low = window.low
        let scale = 255 / max(window.width, 1e-6)
        var pixels = [UInt32](repeating: 0, count: width * height)
        values.withUnsafeBufferPointer { src in
            pixels.withUnsafeMutableBufferPointer { dst in
                for i in 0..<src.count {
                    let v = src[i]
                    var t = v.isFinite ? (v - low) * scale : 0
                    t = min(max(t, 0), 255)
                    var index = Int(t)
                    if invert { index = 255 - index }
                    dst[i] = lut[index]
                }
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// 8-bit grayscale image with min–max scaling, used for text recognition.
    static func grayscale(_ values: [Float], width: Int, height: Int) -> CGImage? {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in values where v.isFinite { lo = min(lo, v); hi = max(hi, v) }
        if hi <= lo { hi = lo + 1 }
        return image(values, width: width, height: height, window: WindowLevel(low: lo, high: hi), colormap: .gray)
    }

    /// Redraws an image into a bitmap of the given pixel size.
    static func resample(_ image: CGImage, width: Int, height: Int, smooth: Bool) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = smooth ? .high : .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
