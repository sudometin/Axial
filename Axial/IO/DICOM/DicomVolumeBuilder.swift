import Foundation

/// Groups DICOM files into series and assembles each series into a `Volume`.
enum DicomSeriesLoader {
    static func loadVolumes(from urls: [URL]) -> (volumes: [Volume], errors: [String]) {
        var groups: [String: [(url: URL, file: DicomFile)]] = [:]
        var order: [String] = []
        var errors: [String] = []

        for url in urls where url.lastPathComponent.uppercased() != "DICOMDIR" {
            do {
                let file = try DicomParser.parse(url: url)
                guard file.dataset[.pixelData] != nil else { continue } // reports, presentation states…
                let key = file.dataset.string(.seriesInstanceUID) ?? url.path
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append((url: url, file: file))
            } catch DicomError.notDicom {
                continue
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        var volumes: [Volume] = []
        for key in order {
            guard let members = groups[key] else { continue }
            do {
                volumes.append(try DicomVolumeBuilder.build(members.map(\.file), sourceURLs: members.map(\.url)))
            } catch {
                let label = members.first?.file.dataset.string(.seriesDescription) ?? "Series"
                errors.append("\(label): \(error.localizedDescription)")
            }
        }
        if volumes.isEmpty && errors.isEmpty {
            errors.append("No images were found in the selected files.")
        }
        return (volumes, errors)
    }
}

enum DicomVolumeBuilder {
    private struct Slice {
        let file: DicomFile
        let position: [Double]?
        let instance: Int
    }

    static func build(_ files: [DicomFile], sourceURLs: [URL] = []) throws -> Volume {
        guard let first = files.first else { throw DicomError.emptySeries }
        if first.isCompressed { throw DicomError.unsupportedTransferSyntax(first.transferSyntax) }

        let ds = first.dataset
        let format = try PixelFormat(ds)
        let rows = format.rows, cols = format.columns

        // Geometry (DICOM patient coordinates are LPS+).
        let orientation = ds.doubles(.imageOrientationPatient)
        let rowDir = orientation.count == 6 ? normalize(Array(orientation[0..<3])) : [1.0, 0, 0]
        let colDir = orientation.count == 6 ? normalize(Array(orientation[3..<6])) : [0.0, 1, 0]
        let normal = cross(rowDir, colDir)
        let pixelSpacing = ds.doubles(.pixelSpacing)
        let dy = pixelSpacing.count >= 1 && pixelSpacing[0] > 0 ? pixelSpacing[0] : 1 // between rows
        let dx = pixelSpacing.count >= 2 && pixelSpacing[1] > 0 ? pixelSpacing[1] : dy // between columns
        let nominalSliceSpacing = ds.double(.spacingBetweenSlices) ?? ds.double(.sliceThickness) ?? 1

        var frames: [[Float]] = []
        var origin = ds.doubles(.imagePositionPatient)
        var sliceVector = normal.map { $0 * nominalSliceSpacing }

        if files.count == 1 {
            // Single file, possibly multi-frame.
            guard let pixels = ds[.pixelData]?.value else { throw DicomError.missing("Pixel Data") }
            let (slope, intercept) = rescale(ds)
            for i in 0..<format.frames {
                frames.append(try DicomPixelDecoder.frame(pixels, format: format, index: i).map { $0 * slope + intercept })
            }
        } else {
            var slices = files.compactMap { file -> Slice? in
                guard let f = try? PixelFormat(file.dataset), f.rows == rows, f.columns == cols else { return nil }
                let ipp = file.dataset.doubles(.imagePositionPatient)
                return Slice(file: file, position: ipp.count == 3 ? ipp : nil, instance: file.dataset.int(.instanceNumber) ?? 0)
            }
            guard !slices.isEmpty else { throw DicomError.emptySeries }
            let allHavePositions = slices.allSatisfy { $0.position != nil }
            if allHavePositions {
                slices.sort { dot($0.position!, normal) < dot($1.position!, normal) }
                origin = slices[0].position!
                if slices.count > 1, let last = slices.last?.position {
                    let n = Double(slices.count - 1)
                    sliceVector = (0..<3).map { (last[$0] - origin[$0]) / n }
                    if sliceVector.allSatisfy({ abs($0) < 1e-6 }) { sliceVector = normal.map { $0 * nominalSliceSpacing } }
                }
            } else {
                slices.sort { $0.instance < $1.instance }
            }
            for slice in slices {
                guard let pixels = slice.file.dataset[.pixelData]?.value else { continue }
                let f = try PixelFormat(slice.file.dataset)
                let (slope, intercept) = rescale(slice.file.dataset)
                frames.append(try DicomPixelDecoder.frame(pixels, format: f, index: 0).map { $0 * slope + intercept })
            }
        }
        guard !frames.isEmpty else { throw DicomError.emptySeries }

        let nz = frames.count
        var voxels = [Float](repeating: 0, count: rows * cols * nz)
        let flipRowsFor2D = nz == 1 // so a single image displays with row 0 at the top
        for (k, frame) in frames.enumerated() {
            let sliceOffset = k * rows * cols
            for row in 0..<rows {
                let targetRow = flipRowsFor2D ? rows - 1 - row : row
                let src = row * cols
                let dst = sliceOffset + targetRow * cols
                for col in 0..<cols { voxels[dst + col] = frame[src + col] }
            }
        }

        if origin.count != 3 { origin = [0, 0, 0] }
        // Voxel → LPS, then LPS → RAS by negating x and y.
        let lps: [[Double]] = (0..<3).map { r in
            [rowDir[r] * dx, colDir[r] * dy, sliceVector[r], origin[r]]
        }
        let ras = Affine(m: [lps[0].map { -$0 }, lps[1].map { -$0 }, lps[2]])
        let affine = nz == 1 ? Affine.diagonal([dx, dy, 1]) : ras

        var preset: WindowLevel?
        if let center = ds.doubles(.windowCenter).first, let width = ds.doubles(.windowWidth).first, width > 0 {
            preset = WindowLevel(center: Float(center), width: Float(width))
        }

        let modality = ds.string(.modality) ?? "OT"
        let description = ds.string(.seriesDescription).flatMap { $0.isEmpty ? nil : $0 }
            ?? ds.string(.protocolName).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Series \(ds.string(.seriesNumber) ?? "?")"

        var info: [InfoItem] = [
            InfoItem(label: "Format", value: "DICOM · \(TransferSyntax.name(first.transferSyntax))"),
            InfoItem(label: "Modality", value: modality),
            InfoItem(label: "Series", value: description),
        ]
        func add(_ label: String, _ tag: DicomTag, sensitive: Bool = false, suffix: String = "") {
            if let v = ds.string(tag), !v.isEmpty { info.append(InfoItem(label: label, value: v + suffix, isSensitive: sensitive)) }
        }
        add("Protocol", .protocolName)
        let scanner = [ds.string(.manufacturer), ds.string(.manufacturerModelName)].compactMap { $0 }.filter { !$0.isEmpty }
        if !scanner.isEmpty { info.append(InfoItem(label: "Scanner", value: scanner.joined(separator: " "))) }
        add("Field strength", .magneticFieldStrength, suffix: " T")
        add("TR", .repetitionTime, suffix: " ms")
        add("TE", .echoTime, suffix: " ms")
        info.append(InfoItem(label: "Dimensions", value: nz == 1 ? "\(cols) × \(rows)" : "\(cols) × \(rows) × \(nz)"))
        info.append(InfoItem(label: "Voxel size", value: String(format: "%.2f × %.2f × %.2f mm", dx, dy, nz == 1 ? nominalSliceSpacing : norm(sliceVector))))
        add("Patient", .patientName, sensitive: true)
        add("Patient ID", .patientID, sensitive: true)
        add("Birth date", .patientBirthDate, sensitive: true)
        add("Study date", .studyDate, sensitive: true)
        add("Institution", .institutionName, sensitive: true)

        var notes: [String] = []
        if files.count > 1 && files.count != nz { notes.append("\(files.count - nz) file(s) with a different size were skipped.") }
        if orientation.count != 6 { notes.append("No orientation in header; displayed in acquisition order.") }

        return Volume.reoriented(
            name: "\(modality) · \(description)", kind: .dicom,
            dims: [cols, rows, nz], affine: affine, voxels: voxels,
            presetWindow: preset, invert: format.isMonochrome1,
            info: info, notes: notes, sourceURLs: sourceURLs, modality: modality
        )
    }

    private static func rescale(_ ds: DicomDataset) -> (Float, Float) {
        let slope = Float(ds.double(.rescaleSlope) ?? 1)
        let intercept = Float(ds.double(.rescaleIntercept) ?? 0)
        return (slope == 0 ? 1 : slope, intercept)
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
    private static func norm(_ a: [Double]) -> Double { dot(a, a).squareRoot() }
    private static func normalize(_ a: [Double]) -> [Double] {
        let n = norm(a)
        return n > 0 ? a.map { $0 / n } : a
    }
    private static func cross(_ a: [Double], _ b: [Double]) -> [Double] {
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    }
}
