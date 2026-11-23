import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            detail
                .animation(.easeOut(duration: 0.25), value: model.selection)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                DropOverlay(deidentify: model.selection == .anonymizer)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .overlay {
            if model.isLoading {
                LoadingOverlay(message: model.loadingMessage)
            }
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .volume(let id):
            if let viewer = model.viewers[id] {
                ViewerView(viewer: viewer).id(id)
                    .transition(.opacity)
            } else {
                WelcomeView()
            }
        case .anonymizer:
            AnonymizerView(model: model.anonymizer)
                .transition(.opacity)
        case nil:
            WelcomeView()
                .transition(.opacity)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Images") {
                if model.volumes.isEmpty {
                    Text("Nothing open yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.volumes) { volume in
                    VolumeRow(volume: volume)
                        .tag(SidebarItem.volume(volume.id))
                        .contextMenu {
                            if volume.kind == .dicom && !volume.sourceURLs.isEmpty {
                                Button("De-identify Series") { model.deidentify(volume) }
                            }
                            Button("Close") { model.close(volume.id) }
                        }
                }
            }
            Section("Tools") {
                Label {
                    HStack {
                        Text("De-identify")
                        Spacer()
                        if !model.anonymizer.items.isEmpty {
                            Text("\(model.anonymizer.items.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "checkmark.shield")
                }
                .tag(SidebarItem.anonymizer)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Link(destination: AppInfo.profileURL) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("github.com/\(AppInfo.githubUser)")
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Axial on GitHub")
        }
        .toolbar {
            ToolbarItem {
                Button { model.presentOpenPanel() } label: {
                    Label("Open", systemImage: "plus")
                }
                .help("Open NIfTI or DICOM (⌘O)")
            }
        }
    }
}

struct VolumeRow: View {
    let volume: Volume

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name).lineLimit(1)
                Text("\(volume.kind.rawValue) · \(volume.dimensionsDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: volume.isTwoDimensional ? "photo" : (volume.kind == .dicom ? "square.stack.3d.up" : "cube"))
        }
    }
}

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}

struct DropOverlay: View {
    let deidentify: Bool
    @State private var bounce = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [12, 8]))
                .padding(18)
            VStack(spacing: 14) {
                Image(systemName: deidentify ? "checkmark.shield" : "arrow.down.doc")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: bounce)
                Text(deidentify ? "Drop to add for de-identification" : "Drop to open")
                    .font(.title2.weight(.semibold))
                Text("NIfTI files, DICOM files or folders")
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
        .onAppear { bounce += 1 }
    }
}
