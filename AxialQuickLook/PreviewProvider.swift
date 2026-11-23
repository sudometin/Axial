import Cocoa
import Quartz

/// Quick Look preview for NIfTI (.nii) and DICOM (.dcm) files: press Space in Finder.
/// 3-D images show the three central planes; 2-D images show the image itself.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let volume: Volume
        if NIfTI.isNIfTIFile(url) {
            volume = try NIfTI.read(url)
        } else {
            let file = try DicomParser.parse(url: url)
            volume = try DicomVolumeBuilder.build([file], sourceURLs: [url])
        }
        let renderer = QuickLookRenderer(volume: volume, fileName: url.lastPathComponent)
        return QLPreviewReply(contextSize: renderer.canvasSize, isBitmap: false) { context, _ in
            renderer.draw(in: context)
        }
    }
}

struct QuickLookRenderer {
    let volume: Volume
    let fileName: String

    private let margin: CGFloat = 24
    private let header: CGFloat = 64
    private let footer: CGFloat = 36
    private let panel: CGFloat = 420

    private var planes: [Plane] { volume.isTwoDimensional ? [.axial] : Plane.allCases }

    var canvasSize: CGSize {
        if volume.isTwoDimensional {
            let g = PlaneGeometry(volume: volume, plane: .axial, radiological: false)
            let aspect = g.physicalSize.width / max(g.physicalSize.height, 1)
            let height: CGFloat = 640
            return CGSize(width: max(height * aspect, 360) + margin * 2, height: height + header + footer)
        }
        let count = CGFloat(planes.count)
        return CGSize(width: count * panel + (count + 1) * margin, height: panel + header + footer)
    }

    func draw(in context: CGContext) {
        let size = canvasSize
        context.setFillColor(CGColor(red: 0.035, green: 0.04, blue: 0.05, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let window = volume.presetWindow ?? volume.autoWindow
        let center = volume.center

        for (i, plane) in planes.enumerated() {
            let g = PlaneGeometry(volume: volume, plane: plane, radiological: false)
            let values = SliceRenderer.slice(volume, geometry: g, index: g.sliceIndex(of: center))
            guard let image = SliceRenderer.image(values, width: g.width, height: g.height, window: window,
                                                  colormap: .gray, invert: volume.invert) else { continue }
            let box: CGRect
            if volume.isTwoDimensional {
                box = CGRect(x: margin, y: footer, width: size.width - margin * 2, height: size.height - header - footer)
            } else {
                box = CGRect(x: margin + CGFloat(i) * (panel + margin), y: footer, width: panel, height: panel)
            }
            let phys = g.physicalSize
            let scale = min(box.width / phys.width, box.height / phys.height)
            let w = phys.width * scale, h = phys.height * scale
            let rect = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
            context.interpolationQuality = .high
            context.draw(image, in: rect)

            if !volume.isTwoDimensional {
                drawText(plane.rawValue.uppercased(), at: CGPoint(x: box.minX + 4, y: box.maxY - 18), in: context,
                         size: 11, weight: .bold, color: color(plane))
            }
        }

        drawText(fileName, at: CGPoint(x: margin, y: size.height - 34), in: context, size: 17, weight: .semibold, color: .white)
        drawText("\(volume.kind.rawValue) · \(volume.dimensionsDescription) · "
                 + volume.spacing.map { String(format: "%.2f", $0) }.joined(separator: " × ") + " mm",
                 at: CGPoint(x: margin, y: size.height - 54), in: context, size: 12, weight: .regular,
                 color: NSColor(white: 1, alpha: 0.55))
        drawText("Previewed by Axial", at: CGPoint(x: margin, y: 12), in: context, size: 11, weight: .medium,
                 color: NSColor(white: 1, alpha: 0.35))
    }

    private func color(_ plane: Plane) -> NSColor {
        switch plane {
        case .axial: NSColor(red: 0.25, green: 0.84, blue: 0.84, alpha: 1)
        case .coronal: NSColor(red: 0.69, green: 0.52, blue: 1.0, alpha: 1)
        case .sagittal: NSColor(red: 1.0, green: 0.66, blue: 0.30, alpha: 1)
        }
    }

    private func drawText(_ text: String, at point: CGPoint, in context: CGContext,
                          size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]).draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }
}
