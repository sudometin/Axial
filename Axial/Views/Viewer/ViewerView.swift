import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

struct ViewerView: View {
    @Bindable var viewer: ViewerModel
    @Environment(AppModel.self) private var app
    @State private var showInspector = true
    @State private var appeared = false

    var body: some View {
        content
            .padding(6)
            .background(Theme.canvas)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.985)
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
            .navigationTitle(viewer.volume.name)
            .navigationSubtitle("\(viewer.volume.kind.rawValue) · \(viewer.volume.dimensionsDescription)")
            .inspector(isPresented: $showInspector) {
                InspectorView(viewer: viewer)
                    .inspectorColumnWidth(min: 280, ideal: 310, max: 400)
            }
            .toolbar { toolbar }
    }

    @ViewBuilder
    private var content: some View {
        if viewer.volume.isTwoDimensional {
            PlaneTile(viewer: viewer, plane: .axial)
        } else if let plane = viewer.maximizedPlane {
            PlaneTile(viewer: viewer, plane: plane)
                .transition(.opacity)
        } else {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    PlaneTile(viewer: viewer, plane: .axial)
                    PlaneTile(viewer: viewer, plane: .coronal)
                }
                GridRow {
                    PlaneTile(viewer: viewer, plane: .sagittal)
                    ProjectionTile(viewer: viewer)
                }
            }
            .transition(.opacity)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if !viewer.volume.isTwoDimensional {
                Picker("Layout", selection: $viewer.maximizedPlane.animation(.snappy(duration: 0.25))) {
                    Image(systemName: "square.grid.2x2").tag(Plane?.none)
                    ForEach(Plane.allCases) { plane in
                        Text(String(plane.rawValue.prefix(1))).tag(Plane?.some(plane))
                    }
                }
                .pickerStyle(.segmented)
                .help("Layout: all planes, or Axial / Coronal / Sagittal only. Double-click a view to toggle.")
            }

            Menu {
                ForEach(viewer.volume.isTwoDimensional ? [Plane.axial] : Plane.allCases) { plane in
                    Button(viewer.volume.isTwoDimensional ? "Save Image…" : "\(plane.rawValue) Slice…") { saveSnapshot(plane) }
                }
            } label: {
                Label("Snapshot", systemImage: "camera")
            }
            .help("Save the current slice as PNG")

            if viewer.volume.kind == .dicom && !viewer.volume.sourceURLs.isEmpty {
                Button {
                    app.deidentify(viewer.volume)
                } label: {
                    Label("De-identify Series", systemImage: "checkmark.shield")
                }
                .help("Send this series to the de-identification tool")
            }

            Button {
                withAnimation { showInspector.toggle() }
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the inspector")
        }
    }

    private func saveSnapshot(_ plane: Plane) {
        guard let image = viewer.snapshot(plane) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let base = viewer.volume.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " · ", with: "-")
        panel.nameFieldStringValue = "\(base)-\(plane.rawValue.lowercased()).png"
        guard panel.runModal() == .OK, let url = panel.url,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

// MARK: - Tiles

/// One anatomical plane: the image, a floating label, a slice counter and a scrubber that appear on hover.
struct PlaneTile: View {
    let viewer: ViewerModel
    let plane: Plane
    @State private var isHovering = false

    var body: some View {
        let g = viewer.geometry(plane)
        let pixel = g.pixel(for: viewer.cursor)
        let is2D = viewer.volume.isTwoDimensional
        let slice = g.sliceIndex(of: viewer.cursor)
        let lines = viewer.crosshairPlanes(plane)
        let tint = Theme.color(plane)

        SliceView(
            image: viewer.image(plane),
            physicalSize: g.physicalSize,
            pixelSize: CGSize(width: g.width, height: g.height),
            crosshair: viewer.showCrosshair && !is2D ? CGPoint(x: pixel.col, y: pixel.row) : nil,
            labels: is2D ? .none : g.labels,
            smooth: viewer.smooth,
            horizontalLineColor: Theme.nsColor(lines.horizontal),
            verticalLineColor: Theme.nsColor(lines.vertical),
            onSelect: { col, row in viewer.select(plane, col: col, row: row) },
            onScroll: { viewer.scroll(plane, by: $0) },
            onWindowDrag: { viewer.adjustWindow(dx: $0, dy: $1) },
            onHover: { viewer.updateHover(plane, pixel: $0) },
            onDoubleClick: {
                guard !is2D else { return }
                withAnimation(.snappy(duration: 0.25)) { viewer.toggleMaximized(plane) }
            }
        )
        .overlay(alignment: .topLeading) {
            if !is2D {
                HUDPill {
                    HStack(spacing: 6) {
                        Circle().fill(tint).frame(width: 7, height: 7)
                        Text(plane.rawValue).foregroundStyle(.white)
                    }
                }
                .padding(10)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !is2D {
                HUDPill {
                    Text("\(slice + 1) / \(g.sliceCount)")
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(10)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isHovering {
                HoverReadout(viewer: viewer)
                    .padding(10)
                    .padding(.bottom, is2D ? 0 : 22)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if !is2D && g.sliceCount > 1 {
                SliceScrubber(index: slice, count: g.sliceCount, tint: tint) { viewer.setSlice(plane, to: $0) }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .opacity(isHovering ? 1 : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHovering ? tint.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
    }
}

/// Maximum-intensity projection with a direction menu.
struct ProjectionTile: View {
    @Bindable var viewer: ViewerModel
    @State private var isHovering = false

    var body: some View {
        let g = viewer.geometry(viewer.projectionPlane)
        SliceView(
            image: viewer.projectionImage(),
            physicalSize: g.physicalSize,
            pixelSize: CGSize(width: g.width, height: g.height),
            crosshair: nil,
            labels: g.labels,
            smooth: viewer.smooth,
            onWindowDrag: { viewer.adjustWindow(dx: $0, dy: $1) }
        )
        .overlay(alignment: .topLeading) {
            Menu {
                Picker("Direction", selection: $viewer.projectionPlane) {
                    ForEach(Plane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HUDPill {
                    HStack(spacing: 5) {
                        Image(systemName: "cube.transparent")
                        Text("MIP · \(viewer.projectionPlane.rawValue)")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.white)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(10)
            .help("Maximum-intensity projection: the brightest voxel along each ray")
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHovering ? Theme.accent.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
    }
}

/// Value under the pointer. A separate view so only it redraws while the mouse moves.
struct HoverReadout: View {
    let viewer: ViewerModel

    var body: some View {
        if let v = viewer.hover {
            HUDPill {
                HStack(spacing: 8) {
                    Text(NumberFormat.value(viewer.volume.value(at: v)))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(viewer.volume.isTwoDimensional ? "\(v.x), \(v.y)" : "\(v.x), \(v.y), \(v.z)")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .monospacedDigit()
            }
        }
    }
}

/// Thin draggable slice slider.
struct SliceScrubber: View {
    let index: Int
    let count: Int
    let tint: Color
    let onChange: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                Capsule().fill(tint.opacity(0.9)).frame(width: max(4, fraction * width), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: fraction * (width - 12))
            }
            .frame(width: width, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let f = min(max(value.location.x / width, 0), 1)
                    onChange(Int((f * CGFloat(count - 1)).rounded()))
                }
            )
        }
        .frame(height: 18)
    }
}
