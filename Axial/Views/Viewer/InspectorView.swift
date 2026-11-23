import SwiftUI

struct InspectorView: View {
    @Bindable var viewer: ViewerModel

    private var volume: Volume { viewer.volume }
    private var range: ClosedRange<Float> {
        let lo = volume.minValue, hi = max(volume.maxValue, volume.minValue + 1e-3)
        return lo...hi
    }

    var body: some View {
        Form {
            windowSection
            displaySection
            cursorSection
            infoSection
        }
        .formStyle(.grouped)
    }

    // MARK: Sections

    private var windowSection: some View {
        Section {
            HistogramView(histogram: volume.histogram, minValue: volume.minValue, maxValue: volume.maxValue,
                          window: viewer.window, colormap: viewer.colormap)
                .frame(height: 70)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 6, trailing: 8))

            FlowLayout(spacing: 6) {
                ForEach(viewer.windowPresets) { preset in
                    ChipButton(title: preset.name, isSelected: viewer.isCurrent(preset)) {
                        withAnimation(.easeOut(duration: 0.2)) { viewer.window = preset.window }
                    }
                }
            }
            .padding(.vertical, 2)

            DisclosureGroup("Fine-tune") {
                LabeledContent("Level") {
                    Text(NumberFormat.value(viewer.window.center)).monospacedDigit()
                }
                Slider(value: $viewer.window.center, in: range)
                    .labelsHidden()
                LabeledContent("Width") {
                    Text(NumberFormat.value(viewer.window.width)).monospacedDigit()
                }
                Slider(value: $viewer.window.width, in: Float(1e-3)...max((range.upperBound - range.lowerBound) * 2, 1e-2))
                    .labelsHidden()
            }
        } header: {
            Text("Window")
        } footer: {
            Text("Tip: option-drag or right-drag on any image. Sideways changes contrast, up and down changes brightness.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            HStack(spacing: 8) {
                ForEach(Colormap.allCases) { map in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { viewer.colormap = map }
                    } label: {
                        VStack(spacing: 4) {
                            ColormapBar(colormap: map)
                                .frame(height: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(viewer.colormap == map ? Theme.accent : Color.clear, lineWidth: 2)
                                )
                            Text(map.rawValue)
                                .font(.caption2)
                                .foregroundStyle(viewer.colormap == map ? Color.primary : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            Toggle("Crosshair", isOn: $viewer.showCrosshair)
            Toggle("Radiological convention", isOn: $viewer.radiological)
                .help("Show the patient's right on the left side of the screen")
            Toggle("Smooth interpolation", isOn: $viewer.smooth)
        }
    }

    private var cursorSection: some View {
        let v = viewer.hover ?? viewer.cursor
        let world = volume.world(v)
        return Section(viewer.hover == nil ? "Cursor" : "Pointer") {
            LabeledContent("Voxel") {
                Text(volume.isTwoDimensional ? "\(v.x), \(v.y)" : "\(v.x), \(v.y), \(v.z)").monospacedDigit()
            }
            if !volume.isTwoDimensional {
                LabeledContent("World (mm)") {
                    Text(world.map(NumberFormat.mm).joined(separator: ", ")).monospacedDigit()
                }
            }
            LabeledContent("Value") {
                Text(NumberFormat.value(volume.value(at: v))).monospacedDigit().fontWeight(.semibold)
            }
        }
    }

    private var infoSection: some View {
        Section("Info") {
            ForEach(volume.info) { item in
                LabeledContent(item.label) {
                    Text(item.isSensitive && !viewer.showSensitiveInfo ? "••••••" : item.value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
            if volume.info.contains(where: \.isSensitive) {
                Toggle("Show identifying fields", isOn: $viewer.showSensitiveInfo)
            }
            ForEach(volume.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ColormapBar: View {
    let colormap: Colormap

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: colormap.stops.map { Color(red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) },
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.15)))
    }
}

/// Log-scaled intensity histogram with the current window shaded.
struct HistogramView: View {
    let histogram: [Int]
    let minValue: Float
    let maxValue: Float
    let window: WindowLevel
    let colormap: Colormap

    var body: some View {
        Canvas { context, size in
            guard !histogram.isEmpty else { return }
            let span = CGFloat(max(maxValue - minValue, 1e-6))
            func x(_ v: Float) -> CGFloat { CGFloat(v - minValue) / span * size.width }

            // Window band
            let x0 = min(max(x(window.low), 0), size.width)
            let x1 = min(max(x(window.high), 0), size.width)
            let band = CGRect(x: x0, y: 0, width: max(x1 - x0, 1), height: size.height)
            context.fill(Path(roundedRect: band, cornerRadius: 2), with: .color(Theme.accent.opacity(0.16)))

            // Bars
            let peak = log1p(Double(histogram.max() ?? 1))
            let barWidth = size.width / CGFloat(histogram.count)
            var path = Path()
            for (i, count) in histogram.enumerated() where count > 0 {
                let h = CGFloat(log1p(Double(count)) / max(peak, 1)) * (size.height - 2)
                path.addRect(CGRect(x: CGFloat(i) * barWidth, y: size.height - h, width: max(barWidth - 0.5, 0.5), height: h))
            }
            context.fill(path, with: .color(.secondary.opacity(0.7)))

            // Window edges
            var edges = Path()
            edges.move(to: CGPoint(x: x0, y: 0)); edges.addLine(to: CGPoint(x: x0, y: size.height))
            edges.move(to: CGPoint(x: x1, y: 0)); edges.addLine(to: CGPoint(x: x1, y: size.height))
            context.stroke(edges, with: .color(Theme.accent), lineWidth: 1.5)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .accessibilityLabel("Intensity histogram")
    }
}
