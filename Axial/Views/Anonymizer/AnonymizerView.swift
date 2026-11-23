import SwiftUI

struct AnonymizerView: View {
    @Bindable var model: AnonymizerModel
    @State private var showOptions = true

    var body: some View {
        Group {
            if model.items.isEmpty {
                AnonymizerDropZone(isScanning: model.isScanning, message: model.exportSummary) {
                    model.presentAddPanel()
                }
            } else {
                HStack(spacing: 0) {
                    fileList
                        .frame(width: 230)
                    Divider()
                    // idealWidth 0: never let the preview's content widen the window
                    previewPane
                        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
                }
            }
        }
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("De-identify")
        .navigationSubtitle(model.items.isEmpty ? "DICOM" : "\(model.items.count) DICOM file\(model.items.count == 1 ? "" : "s")")
        .inspector(isPresented: $showOptions) {
            AnonymizerOptionsView(model: model)
                .inspectorColumnWidth(min: 250, ideal: 290, max: 360)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.presentAddPanel() } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .help("Add DICOM files or folders")
                Button { model.clear() } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.items.isEmpty || model.isExporting)
                .help("Remove all files from the list (originals are not touched)")
                Button { model.presentExportPanel() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.items.isEmpty || model.isExporting)
                .help("Write de-identified copies to a folder")
                Button { showOptions.toggle() } label: {
                    Label("Options", systemImage: "sidebar.trailing")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isExporting || (model.exportSummary != nil && !model.items.isEmpty) {
                ExportStatusBar(model: model)
            }
        }
        .onChange(of: model.options) { model.refreshPreview() }
        .onChange(of: model.selection) { model.refreshPreview() }
        .onAppear { model.refreshPreview() }
    }

    // MARK: File list

    private var fileList: some View {
        List(selection: $model.selection) {
            ForEach(model.items) { item in
                HStack(spacing: 8) {
                    StatusIcon(status: item.status)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).lineLimit(1)
                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .tag(item.id)
                .help(item.statusMessage ?? "")
            }
        }
        .listStyle(.inset)
    }

    // MARK: Preview

    private var previewPane: some View {
        VSplitView {
            imagePreview
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, minHeight: 240, idealHeight: 380)
            changesTable
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, minHeight: 180)
        }
    }

    private var imagePreview: some View {
        ZStack {
            Theme.canvas
            if let preview = model.preview {
                if let original = preview.originalImage, let cleaned = preview.anonymizedImage {
                    CompareView(before: original, after: cleaned, regions: preview.regions)
                        .padding(14)
                } else {
                    ContentUnavailableView("No Preview", systemImage: "photo",
                                           description: Text("This file's pixel data can't be previewed."))
                }
            } else if let error = model.previewError {
                ContentUnavailableView("Couldn't Read File", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            }
            if model.isPreviewing {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(14)
            }
        }
        .overlay(alignment: .topLeading) {
            if let preview = model.preview {
                HStack(spacing: 6) {
                    HUDPill {
                        Label(preview.pseudonym, systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.white)
                    }
                    if !preview.frameDescription.isEmpty {
                        HUDPill { Text(preview.frameDescription).foregroundStyle(.white.opacity(0.8)) }
                    }
                }
                .padding(12)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var changesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let preview = model.preview {
                ReportCard(preview: preview, options: model.options)
                    .padding(12)
                ForEach(preview.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                }
                Table(preview.changes) {
                    TableColumn("") { change in
                        Image(systemName: change.kind.symbol)
                            .foregroundStyle(change.kind.color)
                            .help(change.kind.label)
                    }
                    .width(18)
                    TableColumn("Tag") { change in
                        Text(change.tag.description)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 86, ideal: 90, max: 100)
                    TableColumn("Attribute") { change in
                        Text(change.name).lineLimit(1).truncationMode(.middle).help(change.name)
                    }
                    .width(min: 90, ideal: 170)
                    TableColumn("Original") { change in
                        Text(change.before).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).help(change.before)
                    }
                    .width(min: 80, ideal: 160)
                    TableColumn("De-identified") { change in
                        if let after = change.after {
                            Text(after.isEmpty ? "(empty)" : after)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(after)
                                .foregroundStyle(after.isEmpty ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                        } else {
                            Text("Removed").foregroundStyle(.red)
                        }
                    }
                }
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
            } else {
                Spacer()
            }
        }
    }
}

extension ChangeKind {
    var label: String {
        switch self {
        case .removed: "Removed"
        case .emptied: "Emptied"
        case .replaced: "Pseudonymised"
        case .dateShifted: "Date shifted"
        case .uidReplaced: "UID replaced"
        case .pixels: "Pixels masked"
        }
    }

    var symbol: String {
        switch self {
        case .removed: "minus.circle.fill"
        case .emptied: "circle.dashed"
        case .replaced: "person.fill.questionmark"
        case .dateShifted: "calendar.badge.clock"
        case .uidReplaced: "number.circle.fill"
        case .pixels: "rectangle.dashed.badge.record"
        }
    }

    var color: Color {
        switch self {
        case .removed: .red
        case .emptied: .secondary
        case .replaced: Theme.accent
        case .dateShifted: .orange
        case .uidReplaced: .purple
        case .pixels: .pink
        }
    }
}

/// At-a-glance summary of what de-identification does to the selected file.
struct ReportCard: View {
    let preview: AnonymizationPreview
    let options: AnonymizationOptions

    var body: some View {
        let removed = preview.count(.removed) + preview.count(.emptied)
        let regions = preview.regions.count
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            StatTile(value: "\(removed)", label: "fields removed", symbol: "minus.circle.fill", color: .red)
            StatTile(value: "\(preview.count(.replaced))", label: "pseudonymised", symbol: "person.fill.questionmark", color: Theme.accent)
            StatTile(value: dateValue, label: dateLabel, symbol: "calendar.badge.clock", color: .orange)
            StatTile(value: "\(preview.count(.uidReplaced))", label: "UIDs replaced", symbol: "number.circle.fill", color: .purple)
            StatTile(value: options.scanBurnedInText ? "\(regions)" : "off", label: "text regions", symbol: "text.viewfinder", color: .pink)
        }
    }

    private var dateValue: String {
        switch options.dateMode {
        case .shift: "\(preview.dateShiftDays)d"
        case .remove: "–"
        case .keep: "kept"
        }
    }

    private var dateLabel: String {
        switch options.dateMode {
        case .shift: "date shift"
        case .remove: "dates removed"
        case .keep: "dates"
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.18)))
    }
}

/// Before/after comparison with a draggable divider. Detected text is outlined on the "before" side.
struct CompareView: View {
    let before: CGImage
    let after: CGImage
    let regions: [CGRect]
    @State private var split: CGFloat = 0.5

    var body: some View {
        let aspect = CGFloat(before.width) / CGFloat(max(before.height, 1))
        GeometryReader { geo in
            let size = fittedSize(in: geo.size, aspect: aspect)
            let x = size.width * split
            ZStack(alignment: .topLeading) {
                Image(decorative: after, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)

                ZStack(alignment: .topLeading) {
                    Image(decorative: before, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                    ForEach(Array(regions.enumerated()), id: \.offset) { _, r in
                        Rectangle()
                            .strokeBorder(Color.red, lineWidth: 2)
                            .background(Color.red.opacity(0.18))
                            .frame(width: r.width * size.width, height: r.height * size.height)
                            .offset(x: r.minX * size.width, y: r.minY * size.height)
                    }
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: x)
                }

                // Divider + handle
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: size.height)
                    .offset(x: x - 1)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 11, weight: .bold)))
                    .frame(width: 30, height: 30)
                    .offset(x: x - 15, y: size.height / 2 - 15)

                HUDPill { Text("Original").foregroundStyle(.white) }
                    .padding(8)
                    .opacity(split > 0.15 ? 1 : 0)
                HUDPill { Text("De-identified").foregroundStyle(.white) }
                    .padding(8)
                    .frame(width: size.width, alignment: .trailing)
                    .opacity(split < 0.85 ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    split = min(max(value.location.x / max(size.width, 1), 0), 1)
                }
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .help("Drag to compare the original with the de-identified image")
    }

    private func fittedSize(in container: CGSize, aspect: CGFloat) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        if container.width / container.height > aspect {
            return CGSize(width: container.height * aspect, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / aspect)
    }
}

private extension AnonymizerItem {
    var statusMessage: String? {
        switch status {
        case .ready, .done: nil
        case .warning(let m), .failed(let m): m
        }
    }
}

struct StatusIcon: View {
    let status: AnonymizerItem.Status

    var body: some View {
        Group {
            switch status {
            case .ready: Image(systemName: "doc").foregroundStyle(.secondary)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
        .frame(width: 16)
    }
}

struct ExportStatusBar: View {
    @Bindable var model: AnonymizerModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isExporting {
                ProgressView(value: model.exportProgress)
                    .frame(maxWidth: 260)
                Text("Exporting… \(Int(model.exportProgress * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if let summary = model.exportSummary {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(summary).lineLimit(2)
                Spacer()
                if model.lastExportFolder != nil {
                    Button("Show in Finder") { model.revealExport() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

struct AnonymizerDropZone: View {
    let isScanning: Bool
    let message: String?
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("De-identify DICOM")
                .font(.title.bold())
            Text("Drop DICOM files or folders here. Axial replaces names and IDs with pseudonyms, shifts dates, replaces UIDs, removes private tags and finds text burned into the pixels.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            if isScanning {
                ProgressView("Reading headers…").controlSize(.small)
            } else {
                Button("Choose Files…", action: onChoose)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            Label("Originals are never modified. Processing happens entirely on this Mac.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(24)
        )
    }
}
