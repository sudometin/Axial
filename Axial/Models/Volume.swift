import Foundation

/// Voxel-to-world transform. `m` is 3 rows × 4 columns, row-major:
/// world = M · [i, j, k, 1]ᵀ, world coordinates in RAS+ millimetres.
struct Affine: Equatable {
    var m: [[Double]]

    static let identity = Affine(m: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]])

    static func diagonal(_ spacing: [Double], origin: [Double] = [0, 0, 0]) -> Affine {
        Affine(m: [
            [spacing[0], 0, 0, origin[0]],
            [0, spacing[1], 0, origin[1]],
            [0, 0, spacing[2], origin[2]],
        ])
    }

    func column(_ j: Int) -> [Double] { [m[0][j], m[1][j], m[2][j]] }

    func apply(_ v: [Double]) -> [Double] {
        (0..<3).map { r in m[r][0] * v[0] + m[r][1] * v[1] + m[r][2] * v[2] + m[r][3] }
    }

    /// Length of each voxel axis in millimetres.
    var columnNorms: [Double] {
        (0..<3).map { j in
            let c = column(j)
            return (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).squareRoot()
        }
    }

    var isDegenerate: Bool { columnNorms.contains { $0 < 1e-9 || !$0.isFinite } }
}

struct WindowLevel: Equatable {
    var center: Float
    var width: Float

    init(center: Float, width: Float) {
        self.center = center
        self.width = max(width, 1e-6)
    }

    init(low: Float, high: Float) {
        self.init(center: (low + high) / 2, width: high - low)
    }

    var low: Float { center - width / 2 }
    var high: Float { center + width / 2 }
}

struct Voxel: Equatable, Hashable {
    var x: Int
    var y: Int
    var z: Int
}

struct InfoItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var isSensitive = false
}

/// Intensity statistics used for automatic windowing and the histogram.
struct IntensityStats {
    let min: Float
    let max: Float
    let window: WindowLevel
    let histogram: [Int]

    init(_ values: [Float], histogramBins: Int = 128) {
        var lo = Float.greatestFiniteMagnitude
        var hi = -Float.greatestFiniteMagnitude
        var zeros = 0
        for v in values where v.isFinite {
            if v < lo { lo = v }
            if v > hi { hi = v }
            if v == 0 { zeros += 1 }
        }
        if lo > hi { lo = 0; hi = 1 }
        if hi <= lo { hi = lo + 1 }

        // Background (exact zero) dominates most MRI volumes; leave it out of the percentiles.
        let ignoreZeros = zeros > values.count / 5
        let fineBins = 2048
        var fine = [Int](repeating: 0, count: fineBins)
        let scale = Float(fineBins - 1) / (hi - lo)
        var counted = 0
        for v in values where v.isFinite {
            if ignoreZeros && v == 0 { continue }
            fine[Int((v - lo) * scale)] += 1
            counted += 1
        }

        func percentile(_ p: Double) -> Float {
            guard counted > 0 else { return p < 0.5 ? lo : hi }
            let target = Int(Double(counted) * p)
            var cumulative = 0
            for (i, n) in fine.enumerated() {
                cumulative += n
                if cumulative > target { return lo + Float(i) / scale }
            }
            return hi
        }

        let pLow = percentile(0.005)
        var pHigh = percentile(0.995)
        if pHigh <= pLow { pHigh = pLow + (hi - lo) * 0.01 }

        var histogram = [Int](repeating: 0, count: histogramBins)
        let binFactor = Double(histogramBins) / Double(fineBins)
        for (i, n) in fine.enumerated() {
            histogram[Swift.min(Int(Double(i) * binFactor), histogramBins - 1)] += n
        }

        self.min = lo
        self.max = hi
        self.window = WindowLevel(low: pLow, high: pHigh)
        self.histogram = histogram
    }
}

/// A scalar 3-D image stored in canonical RAS+ voxel order
/// (x → patient Right, y → Anterior, z → Superior) whenever it has more than one slice.
final class Volume: Identifiable {
    enum Kind: String {
        case nifti = "NIfTI"
        case dicom = "DICOM"
    }

    let id = UUID()
    let name: String
    let kind: Kind
    let nx: Int
    let ny: Int
    let nz: Int
    let spacing: [Double]
    let affine: Affine
    let voxels: [Float]
    let stats: IntensityStats
    let presetWindow: WindowLevel?
    let invert: Bool
    let info: [InfoItem]
    let notes: [String]
    let sourceURLs: [URL]
    let modality: String?

    var minValue: Float { stats.min }
    var maxValue: Float { stats.max }
    var autoWindow: WindowLevel { stats.window }
    var histogram: [Int] { stats.histogram }
    var isTwoDimensional: Bool { nz == 1 }
    var dimensionsDescription: String { nz == 1 ? "\(nx) × \(ny)" : "\(nx) × \(ny) × \(nz)" }

    init(
        name: String, kind: Kind,
        dims: [Int], spacing: [Double], affine: Affine, voxels: [Float],
        presetWindow: WindowLevel? = nil, invert: Bool = false,
        info: [InfoItem] = [], notes: [String] = [], sourceURLs: [URL] = [], modality: String? = nil
    ) {
        precondition(dims.count == 3 && dims[0] * dims[1] * dims[2] == voxels.count, "Voxel count mismatch")
        self.name = name
        self.kind = kind
        self.nx = dims[0]
        self.ny = dims[1]
        self.nz = dims[2]
        self.spacing = spacing.map { $0 > 0 && $0.isFinite ? $0 : 1 }
        self.affine = affine
        self.voxels = voxels
        self.stats = IntensityStats(voxels)
        self.presetWindow = presetWindow
        self.invert = invert
        self.info = info
        self.notes = notes
        self.sourceURLs = sourceURLs
        self.modality = modality
    }

    /// Builds a volume, reorienting 3-D data to the closest canonical RAS+ orientation.
    static func reoriented(
        name: String, kind: Kind,
        dims: [Int], affine: Affine, voxels: [Float],
        presetWindow: WindowLevel? = nil, invert: Bool = false,
        info: [InfoItem] = [], notes: [String] = [], sourceURLs: [URL] = [], modality: String? = nil
    ) -> Volume {
        let safeAffine = affine.isDegenerate ? Affine.identity : affine
        let result: (voxels: [Float], dims: [Int], affine: Affine)
        if dims[2] > 1 {
            result = canonicalize(voxels: voxels, dims: dims, affine: safeAffine)
        } else {
            result = (voxels, dims, safeAffine)
        }
        return Volume(
            name: name, kind: kind,
            dims: result.dims, spacing: result.affine.columnNorms, affine: result.affine, voxels: result.voxels,
            presetWindow: presetWindow, invert: invert, info: info, notes: notes, sourceURLs: sourceURLs,
            modality: modality
        )
    }

    @inline(__always) func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + nx * (y + ny * z) }

    func value(at v: Voxel) -> Float { voxels[index(v.x, v.y, v.z)] }

    func world(_ v: Voxel) -> [Double] { affine.apply([Double(v.x), Double(v.y), Double(v.z)]) }

    func clamp(_ v: Voxel) -> Voxel {
        Voxel(x: min(max(v.x, 0), nx - 1), y: min(max(v.y, 0), ny - 1), z: min(max(v.z, 0), nz - 1))
    }

    var center: Voxel { Voxel(x: nx / 2, y: ny / 2, z: nz / 2) }

    /// Permutes / flips voxel axes so they line up with RAS+ as closely as possible
    /// (same idea as nibabel's `as_closest_canonical`).
    static func canonicalize(voxels: [Float], dims: [Int], affine: Affine) -> (voxels: [Float], dims: [Int], affine: Affine) {
        // Greedy assignment of voxel axes (columns) to world axes (rows) by largest |component|.
        var perm = [0, 1, 2]     // voxel axis j → world axis perm[j]
        var flip = [false, false, false]
        var usedRows = Set<Int>(), usedCols = Set<Int>()
        for _ in 0..<3 {
            var best = (row: -1, col: -1, value: -1.0)
            for r in 0..<3 where !usedRows.contains(r) {
                for c in 0..<3 where !usedCols.contains(c) {
                    let v = abs(affine.m[r][c])
                    if v > best.value { best = (r, c, v) }
                }
            }
            perm[best.col] = best.row
            flip[best.col] = affine.m[best.row][best.col] < 0
            usedRows.insert(best.row)
            usedCols.insert(best.col)
        }

        if perm == [0, 1, 2] && flip == [false, false, false] {
            return (voxels, dims, affine)
        }

        var newDims = [0, 0, 0]
        for j in 0..<3 { newDims[perm[j]] = dims[j] }

        var newAffine = Affine(m: [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var origin = [affine.m[0][3], affine.m[1][3], affine.m[2][3]]
        for j in 0..<3 {
            let col = affine.column(j)
            let sign: Double = flip[j] ? -1 : 1
            for r in 0..<3 { newAffine.m[r][perm[j]] = col[r] * sign }
            if flip[j] {
                for r in 0..<3 { origin[r] += Double(dims[j] - 1) * col[r] }
            }
        }
        for r in 0..<3 { newAffine.m[r][3] = origin[r] }

        let newStrides = [1, newDims[0], newDims[0] * newDims[1]]
        // contribution[j][v] = new linear-index contribution of old coordinate v along voxel axis j
        let contribution: [[Int]] = (0..<3).map { j in
            (0..<dims[j]).map { v in
                let n = flip[j] ? dims[j] - 1 - v : v
                return n * newStrides[perm[j]]
            }
        }

        var out = [Float](repeating: 0, count: voxels.count)
        out.withUnsafeMutableBufferPointer { dst in
            voxels.withUnsafeBufferPointer { src in
                var i = 0
                for c in 0..<dims[2] {
                    let cz = contribution[2][c]
                    for b in 0..<dims[1] {
                        let cyz = cz + contribution[1][b]
                        for a in 0..<dims[0] {
                            dst[cyz + contribution[0][a]] = src[i]
                            i += 1
                        }
                    }
                }
            }
        }
        return (out, newDims, newAffine)
    }
}

enum NumberFormat {
    static func value(_ v: Float) -> String {
        guard v.isFinite else { return "–" }
        if v == v.rounded() && abs(v) < 1e7 { return String(format: "%.0f", v) }
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 1 { return String(format: "%.2f", v) }
        return String(format: "%.4g", v)
    }

    static func mm(_ v: Double) -> String { String(format: "%.1f", v) }
}
