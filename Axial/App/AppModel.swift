import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case volume(UUID)
    case anonymizer
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class AppModel {
    var volumes: [Volume] = []
    var viewers: [UUID: ViewerModel] = [:]
    var selection: SidebarItem?
    let anonymizer = AnonymizerModel()
    let recents = RecentStore()
    var isLoading = false
    var loadingMessage = ""
    var alert: AppAlert?

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Open"
        panel.message = "Choose NIfTI files (.nii, .nii.gz), DICOM files, or a folder with a DICOM series."
        if panel.runModal() == .OK { open(panel.urls) }
    }

    /// Files dropped anywhere go to whichever tool is showing.
    func handleDrop(_ urls: [URL]) {
        if selection == .anonymizer {
            anonymizer.add(urls)
        } else {
            open(urls)
        }
    }

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isLoading = true
        loadingMessage = urls.count == 1 ? "Opening \(urls[0].lastPathComponent)…" : "Opening \(urls.count) items…"
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                VolumeLoader.load(urls)
            }.value
            isLoading = false
            if !outcome.volumes.isEmpty { recents.add(urls) }
            for volume in outcome.volumes { add(volume) }
            if let last = outcome.volumes.last { selection = .volume(last.id) }
            if !outcome.errors.isEmpty {
                alert = AppAlert(
                    title: outcome.volumes.isEmpty ? "Couldn't open the selection" : "Some items couldn't be opened",
                    message: outcome.errors.prefix(8).joined(separator: "\n")
                        + (outcome.errors.count > 8 ? "\n…and \(outcome.errors.count - 8) more." : "")
                )
            }
        }
    }

    func openRecent(_ item: RecentItem) {
        if let url = recents.resolve(item) {
            open([url])
        } else {
            alert = AppAlert(title: "Couldn't find \(item.name)", message: "It may have been moved or deleted.")
        }
    }

    func add(_ volume: Volume) {
        volumes.append(volume)
        viewers[volume.id] = ViewerModel(volume: volume)
    }

    func close(_ id: UUID) {
        volumes.removeAll { $0.id == id }
        viewers[id] = nil
        if selection == .volume(id) {
            selection = volumes.last.map { SidebarItem.volume($0.id) }
        }
    }

    /// Sends the files of a DICOM series to the de-identification tool.
    func deidentify(_ volume: Volume) {
        anonymizer.add(volume.sourceURLs)
        selection = .anonymizer
    }
}
