import Foundation

enum NIfTIError: LocalizedError {
    case notNIfTI
    case nifti2Unsupported
    case separateHeaderUnsupported
    case unsupportedDatatype(Int16)
    case truncated

    var errorDescription: String? {
        switch self {
        case .notNIfTI: "This doesn't look like a NIfTI-1 file."
        case .nifti2Unsupported: "NIfTI-2 files aren't supported yet."
        case .separateHeaderUnsupported: "Separate .hdr/.img pairs aren't supported. Use a single .nii or .nii.gz file."
        case .unsupportedDatatype(let t): "Unsupported NIfTI datatype code \(t)."
        case .truncated: "The file ends before all voxel data was read."
        }
    }
}

/// Reader and writer for single-file NIfTI-1 images (.nii, .nii.gz).
enum NIfTI {
    static func isNIfTIFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".nii") || name.hasSuffix(".nii.gz")
    }

    static func displayName(for url: URL) -> String {
        var name = url.lastPathComponent
        for suffix in [".nii.gz", ".nii"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name
    }

    // MARK: Reading

    static func read(_ url: URL) throws -> Volume {
        var data = try Data(contentsOf: url, options: .mappedIfSafe)
        if Gzip.isGzipped(data) { data = try Gzip.decompress(data) }
        return try parse(data, name: displayName(for: url), sourceURL: url)
    }

    static func parse(_ data: Data, name: String, sourceURL: URL? = nil) throws -> Volume {
        guard data.count >= 348 else { throw NIfTIError.notNIfTI }
        var r = BinaryReader(data: data, littleEndian: true)
        if r.i32(0) != 348 {
            if r.i32(0) == 540 { throw NIfTIError.nifti2Unsupported }
            r.littleEndian = false
            if r.i32(0) == 540 { throw NIfTIError.nifti2Unsupported }
            guard r.i32(0) == 348 else { throw NIfTIError.notNIfTI }
        }

        let magic = r.string(344, 4)
        if magic == "ni1" { throw NIfTIError.separateHeaderUnsupported }
        guard magic == "n+1" else { throw NIfTIError.notNIfTI }

        let ndim = Int(r.i16(40))
        guard (1...7).contains(ndim) else { throw NIfTIError.notNIfTI }
        let dim = (1...7).map { Int(r.i16(40 + $0 * 2)) }
        let nx = max(dim[0], 1)
        let ny = ndim >= 2 ? max(dim[1], 1) : 1
        let nz = ndim >= 3 ? max(dim[2], 1) : 1
        let nt = ndim >= 4 ? max(dim[3], 1) : 1

        let datatype = r.i16(70)
        let pixdim = (0..<8).map { Double(r.f32(76 + $0 * 4)) }
        let voxOffset = max(Int(r.f32(108)), 352)
        var slope = r.f32(112)
        var intercept = r.f32(116)
        if slope == 0 || !slope.isFinite { slope = 1; intercept = 0 }
        if !intercept.isFinite { intercept = 0 }
        let qformCode = r.i16(252)
        let sformCode = r.i16(254)
        let descrip = r.string(148, 80).trimmingCharacters(in: .whitespaces)

        let affine = makeAffine(r: r, pixdim: pixdim, qformCode: qformCode, sformCode: sformCode)

        let count = nx * ny * nz
        guard let bytesPerVoxel = bytesPerVoxel(datatype) else { throw NIfTIError.unsupportedDatatype(datatype) }
        guard data.count >= voxOffset + count * bytesPerVoxel else { throw NIfTIError.truncated }

        var values = try readSamples(r.data, offset: voxOffset, count: count, datatype: datatype, littleEndian: r.littleEndian)
        if slope != 1 || intercept != 0 {
            for i in values.indices { values[i] = values[i] * slope + intercept }
        }

        var info: [InfoItem] = [
            InfoItem(label: "Format", value: "NIfTI-1"),
            InfoItem(label: "Dimensions", value: ndim >= 4 && nt > 1 ? "\(nx) × \(ny) × \(nz) × \(nt)" : "\(nx) × \(ny) × \(nz)"),
            InfoItem(label: "Voxel size", value: (1...3).map { String(format: "%.2f", abs(pixdim[$0])) }.joined(separator: " × ") + " mm"),
            InfoItem(label: "Data type", value: datatypeName(datatype)),
            InfoItem(label: "Orientation", value: sformCode > 0 ? "sform (code \(sformCode))" : qformCode > 0 ? "qform (code \(qformCode))" : "none (voxel grid)"),
        ]
        if !descrip.isEmpty { info.append(InfoItem(label: "Description", value: descrip)) }

        var notes: [String] = []
        if nt > 1 { notes.append("4-D image: showing volume 1 of \(nt).") }
        if sformCode <= 0 && qformCode <= 0 { notes.append("No orientation in header; displayed in voxel order.") }

        return Volume.reoriented(
            name: name, kind: .nifti,
            dims: [nx, ny, nz], affine: affine, voxels: values,
            info: info, notes: notes, sourceURLs: sourceURL.map { [$0] } ?? []
        )
    }

    private static func makeAffine(r: BinaryReader, pixdim: [Double], qformCode: Int16, sformCode: Int16) -> Affine {
        if sformCode > 0 {
            let rows = (0..<3).map { row in (0..<4).map { Double(r.f32(280 + row * 16 + $0 * 4)) } }
            let affine = Affine(m: rows)
            if !affine.isDegenerate { return affine }
        }
        let dx = pixdim[1] > 0 ? pixdim[1] : 1
        let dy = pixdim[2] > 0 ? pixdim[2] : 1
        var dz = pixdim[3] > 0 ? pixdim[3] : 1
        if qformCode > 0 {
            var b = Double(r.f32(256)), c = Double(r.f32(260)), d = Double(r.f32(264))
            let qx = Double(r.f32(268)), qy = Double(r.f32(272)), qz = Double(r.f32(276))
            var a = 1 - (b * b + c * c + d * d)
            if a < 1e-7 {
                // 180° rotation: renormalise (b, c, d) and set a = 0
                let n = (b * b + c * c + d * d).squareRoot()
                if n > 0 { b /= n; c /= n; d /= n }
                a = 0
            } else {
                a = a.squareRoot()
            }
            if pixdim[0] < 0 { dz = -dz } // qfac
            let rot = [
                [a * a + b * b - c * c - d * d, 2 * (b * c - a * d), 2 * (b * d + a * c)],
                [2 * (b * c + a * d), a * a + c * c - b * b - d * d, 2 * (c * d - a * b)],
                [2 * (b * d - a * c), 2 * (c * d + a * b), a * a + d * d - c * c - b * b],
            ]
            let origin = [qx, qy, qz]
            return Affine(m: (0..<3).map { i in
                [rot[i][0] * dx, rot[i][1] * dy, rot[i][2] * dz, origin[i]]
            })
        }
        return Affine.diagonal([dx, dy, dz])
    }

    private static func bytesPerVoxel(_ datatype: Int16) -> Int? {
        switch datatype {
        case 2, 256: 1
        case 4, 512: 2
        case 8, 16, 768: 4
        case 64, 1024, 1280: 8
        default: nil
        }
    }

    private static func datatypeName(_ datatype: Int16) -> String {
        switch datatype {
        case 2: "uint8"
        case 4: "int16"
        case 8: "int32"
        case 16: "float32"
        case 64: "float64"
        case 256: "int8"
        case 512: "uint16"
        case 768: "uint32"
        case 1024: "int64"
        case 1280: "uint64"
        default: "code \(datatype)"
        }
    }

    private static func readSamples(_ data: Data, offset: Int, count: Int, datatype: Int16, littleEndian le: Bool) throws -> [Float] {
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: offset)
            @inline(__always) func u16(_ i: Int) -> UInt16 {
                let v = base.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)
                return le ? UInt16(littleEndian: v) : UInt16(bigEndian: v)
            }
            @inline(__always) func u32(_ i: Int) -> UInt32 {
                let v = base.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                return le ? UInt32(littleEndian: v) : UInt32(bigEndian: v)
            }
            @inline(__always) func u64(_ i: Int) -> UInt64 {
                let v = base.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)
                return le ? UInt64(littleEndian: v) : UInt64(bigEndian: v)
            }
            out.withUnsafeMutableBufferPointer { dst in
                switch datatype {
                case 2: for i in 0..<count { dst[i] = Float(base.load(fromByteOffset: i, as: UInt8.self)) }
                case 256: for i in 0..<count { dst[i] = Float(base.load(fromByteOffset: i, as: Int8.self)) }
                case 4: for i in 0..<count { dst[i] = Float(Int16(bitPattern: u16(i))) }
                case 512: for i in 0..<count { dst[i] = Float(u16(i)) }
                case 8: for i in 0..<count { dst[i] = Float(Int32(bitPattern: u32(i))) }
                case 768: for i in 0..<count { dst[i] = Float(u32(i)) }
                case 16: for i in 0..<count { dst[i] = Float(bitPattern: u32(i)) }
                case 64: for i in 0..<count { dst[i] = Float(Double(bitPattern: u64(i))) }
                case 1024: for i in 0..<count { dst[i] = Float(Int64(bitPattern: u64(i))) }
                case 1280: for i in 0..<count { dst[i] = Float(u64(i)) }
                default: break
                }
            }
        }
        return out
    }

    // MARK: Writing

    /// Writes a float32 NIfTI-1 file. Gzip-compresses when the name ends in `.gz`.
    static func write(_ volume: Volume, to url: URL) throws {
        var header = Data(count: 352)
        header.setLE(Int32(348), at: 0)
        header.setLE(Int16(3), at: 40)
        header.setLE(Int16(volume.nx), at: 42)
        header.setLE(Int16(volume.ny), at: 44)
        header.setLE(Int16(volume.nz), at: 46)
        for i in 4...7 { header.setLE(Int16(1), at: 40 + i * 2) }
        header.setLE(Int16(16), at: 70)  // datatype: float32
        header.setLE(Int16(32), at: 72)  // bitpix
        header.setLE(Float(1), at: 76)   // pixdim[0] = qfac
        for i in 0..<3 { header.setLE(Float(volume.spacing[i]), at: 80 + i * 4) }
        header.setLE(Float(352), at: 108) // vox_offset
        header.setLE(Float(1), at: 112)   // scl_slope
        header.setLE(Float(0), at: 116)   // scl_inter
        header[123] = 2                   // xyzt_units: mm
        header.setASCII("Exported by Axial", at: 148, maxLength: 79)

        let a = volume.affine
        let isAxisAligned = abs(a.m[0][1]) + abs(a.m[0][2]) + abs(a.m[1][0]) + abs(a.m[1][2]) + abs(a.m[2][0]) + abs(a.m[2][1]) < 1e-6
            && a.m[0][0] > 0 && a.m[1][1] > 0 && a.m[2][2] > 0
        if isAxisAligned {
            header.setLE(Int16(1), at: 252) // qform_code: scanner
            // identity quaternion (b = c = d = 0) with the origin as offset
            for i in 0..<3 { header.setLE(Float(a.m[i][3]), at: 268 + i * 4) }
        }
        header.setLE(Int16(1), at: 254) // sform_code
        for row in 0..<3 {
            for col in 0..<4 { header.setLE(Float(a.m[row][col]), at: 280 + row * 16 + col * 4) }
        }
        header.setASCII("n+1", at: 344, maxLength: 3)

        var out = header
        volume.voxels.withUnsafeBufferPointer { buffer in
            out.append(Data(buffer: buffer)) // float32, little-endian on Apple silicon and Intel
        }
        if url.pathExtension.lowercased() == "gz" { out = try Gzip.compress(out) }
        try out.write(to: url, options: .atomic)
    }
}
