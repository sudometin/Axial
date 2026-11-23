import SwiftUI
import CoreGraphics

@MainActor
@Observable
final class ViewerModel {
    let volume: Volume
    var cursor: Voxel
    var hover: Voxel?
    var window: WindowLevel
    var colormap: Colormap = .gray
    var radiological = false
    var showCrosshair = true
    var smooth = true
    var showSensitiveInfo = false
    var maximizedPlane: Plane?
    var projectionPlane: Plane = .coronal

    @ObservationIgnored private var projectionCache: [String: [Float]] = [:]

    init(volume: Volume) {
        self.volume = volume
        self.cursor = volume.center
        self.window = volume.presetWindow ?? volume.autoWindow
    }

    func geometry(_ plane: Plane) -> PlaneGeometry {
        PlaneGeometry(volume: volume, plane: plane, radiological: radiological)
    }

    func image(_ plane: Plane) -> CGImage? {
        let g = geometry(plane)
        let values = SliceRenderer.slice(volume, geometry: g, index: g.sliceIndex(of: cursor))
        return SliceRenderer.image(values, width: g.width, height: g.height, window: window,
                                   colormap: colormap, invert: volume.invert)
    }

    func projectionImage() -> CGImage? {
        let g = geometry(projectionPlane)
        let key = "\(projectionPlane.rawValue)-\(radiological)"
        let values: [Float]
        if let cached = projectionCache[key] {
            values = cached
        } else {
            values = SliceRenderer.maximumProjection(volume, geometry: g)
            projectionCache[key] = values
        }
        return SliceRenderer.image(values, width: g.width, height: g.height, window: window,
                                   colormap: colormap, invert: volume.invert)
    }

    // MARK: Interaction

    func select(_ plane: Plane, col: Int, row: Int) {
        cursor = volume.clamp(geometry(plane).voxel(col: col, row: row, base: cursor))
    }

    func setSlice(_ plane: Plane, to index: Int) {
        let g = geometry(plane)
        cursor = g.moving(cursor, toSlice: min(max(index, 0), g.sliceCount - 1))
    }

    /// Which planes the horizontal and vertical crosshair lines in `plane` represent.
    func crosshairPlanes(_ plane: Plane) -> (horizontal: Plane, vertical: Plane) {
        switch plane {
        case .axial: return (horizontal: .coronal, vertical: .sagittal)
        case .coronal: return (horizontal: .axial, vertical: .sagittal)
        case .sagittal: return (horizontal: .axial, vertical: .coronal)
        }
    }

    // MARK: Window presets

    struct WindowPreset: Identifiable {
        var id: String { name }
        let name: String
        let window: WindowLevel
    }

    var windowPresets: [WindowPreset] {
        var presets = [
            WindowPreset(name: "Auto", window: volume.autoWindow),
            WindowPreset(name: "High Contrast", window: WindowLevel(center: volume.autoWindow.center,
                                                                     width: volume.autoWindow.width * 0.55)),
            WindowPreset(name: "Full Range", window: WindowLevel(low: volume.minValue, high: volume.maxValue)),
        ]
        if let scanner = volume.presetWindow {
            presets.append(WindowPreset(name: "Scanner", window: scanner))
        }
        if volume.modality == "CT" {
            presets += [
                WindowPreset(name: "Brain", window: WindowLevel(center: 40, width: 80)),
                WindowPreset(name: "Subdural", window: WindowLevel(center: 75, width: 215)),
                WindowPreset(name: "Soft Tissue", window: WindowLevel(center: 50, width: 400)),
                WindowPreset(name: "Bone", window: WindowLevel(center: 600, width: 2800)),
            ]
        }
        return presets
    }

    func isCurrent(_ preset: WindowPreset) -> Bool {
        abs(preset.window.center - window.center) < 1e-3 * max(abs(window.width), 1)
            && abs(preset.window.width - window.width) < 1e-3 * max(abs(window.width), 1)
    }

    func scroll(_ plane: Plane, by delta: Int) {
        let g = geometry(plane)
        let s = min(max(g.sliceIndex(of: cursor) + delta, 0), g.sliceCount - 1)
        cursor = g.moving(cursor, toSlice: s)
    }

    func updateHover(_ plane: Plane, pixel: (Int, Int)?) {
        guard let pixel else { hover = nil; return }
        hover = volume.clamp(geometry(plane).voxel(col: pixel.0, row: pixel.1, base: cursor))
    }

    func adjustWindow(dx: CGFloat, dy: CGFloat) {
        let sensitivity = max(volume.maxValue - volume.minValue, 1e-3) / 500
        window = WindowLevel(
            center: window.center - Float(dy) * sensitivity,
            width: max(window.width + Float(dx) * sensitivity, sensitivity)
        )
    }

    func resetWindow() { window = volume.presetWindow ?? volume.autoWindow }
    func autoWindow() { window = volume.autoWindow }
    func fullRangeWindow() { window = WindowLevel(low: volume.minValue, high: volume.maxValue) }

    func toggleMaximized(_ plane: Plane) {
        maximizedPlane = maximizedPlane == nil ? plane : nil
    }

    // MARK: Snapshot

    /// The current slice at its true physical aspect ratio, about 1024 px on the long side.
    func snapshot(_ plane: Plane) -> CGImage? {
        guard let image = image(plane) else { return nil }
        let size = geometry(plane).physicalSize
        let scale = 1024 / max(size.width, size.height)
        return SliceRenderer.resample(image, width: max(Int(size.width * scale), 1),
                                      height: max(Int(size.height * scale), 1), smooth: smooth)
    }
}
