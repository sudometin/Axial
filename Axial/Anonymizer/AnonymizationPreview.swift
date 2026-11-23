import Foundation
import CoreGraphics

/// One file of the de-identification batch.
struct AnonymizerItem: Identifiable, Hashable {
    enum Status: Hashable {
        case ready
        case done
        case warning(String)
        case failed(String)
    }

    let id = UUID()
    let url: URL
    let modality: String
    let seriesDescription: String
    let seriesNumber: Int
    let instanceNumber: Int
    let isCompressed: Bool
    var status: Status = .ready

    var title: String {
        seriesDescription.isEmpty ? "\(modality) · Series \(seriesNumber)" : "\(modality) · \(seriesDescription)"
    }

    var subtitle: String { "Series \(seriesNumber) · Image \(instanceNumber)" + (isCompressed ? " · compressed" : "") }
}

enum DicomScanner {
    /// Finds DICOM files (reading headers only). File names are not shown, since they often contain names.
    static func scan(_ urls: [URL]) -> [AnonymizerItem] {
        var items: [AnonymizerItem] = []
        for url in FileEnumerator.expand(urls) where url.lastPathComponent.uppercased() != "DICOMDIR" {
            guard let file = try? DicomParser.parse(url: url, stopBeforePixelData: true) else { continue }
            let ds = file.dataset
            items.append(AnonymizerItem(
                url: url,
                modality: ds.string(.modality) ?? "OT",
                seriesDescription: ds.string(.seriesDescription) ?? "",
                seriesNumber: ds.int(.seriesNumber) ?? 0,
                instanceNumber: ds.int(.instanceNumber) ?? 0,
                isCompressed: file.isCompressed
            ))
        }
        return items.sorted { ($0.seriesNumber, $0.instanceNumber) < ($1.seriesNumber, $1.instanceNumber) }
    }
}

struct AnonymizationPreview {
    let changes: [TagChange]
    let warnings: [String]
    let originalImage: CGImage?
    let anonymizedImage: CGImage?
    /// Masked text regions, normalised to 0…1 (origin top-left).
    let regions: [CGRect]
    let pseudonym: String
    let frameDescription: String
    let dateShiftDays: Int

    func count(_ kind: ChangeKind) -> Int { changes.filter { $0.kind == kind }.count }
}

enum AnonymizationPreviewBuilder {
    static func make(url: URL, options: AnonymizationOptions) throws -> AnonymizationPreview {
        let file = try DicomParser.parse(url: url)
        let format = try? PixelFormat(file.dataset)
        let frame = (format?.frames ?? 1) / 2
        let result = Anonymizer(options: options).anonymize(file, scan: .frame(frame))

        var regions: [CGRect] = []
        if let format, let rects = result.textRegions[frame] {
            let w = CGFloat(format.columns), h = CGFloat(format.rows)
            regions = rects.map { CGRect(x: $0.minX / w, y: $0.minY / h, width: $0.width / w, height: $0.height / h) }
        }
        let frames = format?.frames ?? 1
        return AnonymizationPreview(
            changes: result.changes,
            warnings: result.warnings,
            originalImage: image(of: file, frame: frame),
            anonymizedImage: image(of: result.file, frame: frame),
            regions: regions,
            pseudonym: result.pseudonym,
            frameDescription: frames > 1 ? "Frame \(frame + 1) of \(frames)" : "",
            dateShiftDays: result.dateShiftDays
        )
    }

    static func image(of file: DicomFile, frame: Int) -> CGImage? {
        if file.isCompressed { return DicomPixelDecoder.previewCompressed(file) }
        let ds = file.dataset
        guard let format = try? PixelFormat(ds),
              let pixels = ds[.pixelData]?.value,
              var values = try? DicomPixelDecoder.frame(pixels, format: format, index: frame)
        else { return nil }

        let slope = Float(ds.double(.rescaleSlope) ?? 1), intercept = Float(ds.double(.rescaleIntercept) ?? 0)
        if slope != 1 || intercept != 0 { values = values.map { $0 * (slope == 0 ? 1 : slope) + intercept } }

        var window = IntensityStats(values, histogramBins: 8).window
        if format.samplesPerPixel == 1, let c = ds.doubles(.windowCenter).first, let w = ds.doubles(.windowWidth).first, w > 0 {
            window = WindowLevel(center: Float(c), width: Float(w))
        }
        return SliceRenderer.image(values, width: format.columns, height: format.rows,
                                   window: window, colormap: .gray, invert: format.isMonochrome1)
    }
}
