import SwiftUI
import AppKit

@MainActor
@Observable
final class AnonymizerModel {
    var items: [AnonymizerItem] = []
    var selection: AnonymizerItem.ID?
    var options = AnonymizationOptions()

    var preview: AnonymizationPreview?
    var previewError: String?
    var isPreviewing = false
    var isScanning = false

    var isExporting = false
    var exportProgress: Double = 0
    var exportSummary: String?
    var lastExportFolder: URL?

    @ObservationIgnored private var previewTask: Task<Void, Never>?

    var selectedItem: AnonymizerItem? { items.first { $0.id == selection } }

    // MARK: Adding files

    func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.message = "Choose DICOM files or folders to de-identify."
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isScanning = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { DicomScanner.scan(urls) }.value
            isScanning = false
            let known = Set(items.map(\.url))
            let fresh = found.filter { !known.contains($0.url) }
            items.append(contentsOf: fresh)
            exportSummary = fresh.isEmpty && found.isEmpty ? "No DICOM files found in the selection." : nil
            if selection == nil { selection = items.first?.id }
        }
    }

    func clear() {
        previewTask?.cancel()
        items = []
        selection = nil
        preview = nil
        previewError = nil
        exportSummary = nil
    }

    func newProjectKey() {
        let key = UUID().uuidString
        UserDefaults.standard.set(key, forKey: AnonymizationOptions.projectKeyDefaultsKey)
        options.projectKey = key
    }

    // MARK: Preview

    func refreshPreview() {
        previewTask?.cancel()
        guard let item = selectedItem else {
            preview = nil
            previewError = nil
            return
        }
        isPreviewing = true
        let url = item.url
        let options = options
        previewTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<AnonymizationPreview, Error> in
                Result { try AnonymizationPreviewBuilder.make(url: url, options: options) }
            }.value
            guard !Task.isCancelled else { return }
            isPreviewing = false
            switch result {
            case .success(let p):
                preview = p
                previewError = nil
            case .failure(let error):
                preview = nil
                previewError = error.localizedDescription
            }
        }
    }

    // MARK: Export

    func presentExportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose an empty folder for the de-identified files."
        if panel.runModal() == .OK, let folder = panel.url { export(to: folder) }
    }

    func export(to folder: URL) {
        guard !items.isEmpty, !isExporting else { return }
        let items = items
        let options = options
        isExporting = true
        exportProgress = 0
        exportSummary = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            let report = Self.runExport(items: items, options: options, folder: folder) { id, status, progress in
                Task { @MainActor in
                    guard let self else { return }
                    if let index = self.items.firstIndex(where: { $0.id == id }) { self.items[index].status = status }
                    self.exportProgress = progress
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.isExporting = false
                self.exportProgress = 1
                self.exportSummary = report
                self.lastExportFolder = folder
            }
        }
    }

    func revealExport() {
        if let folder = lastExportFolder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
    }

    /// Runs off the main thread. Writes <folder>/<pseudonym>/<series>/IM00001.dcm …
    nonisolated private static func runExport(
        items: [AnonymizerItem], options: AnonymizationOptions, folder: URL,
        progress: @escaping (AnonymizerItem.ID, AnonymizerItem.Status, Double) -> Void
    ) -> String {
        let anonymizer = Anonymizer(options: options)
        let fm = FileManager.default
        var counters: [String: Int] = [:]
        var seriesFiles: [String: [DicomFile]] = [:]
        var written = 0, failed = 0, maskedRegions = 0
        var notes: [String] = []
        var kindCounts: [ChangeKind: Int] = [:]
        var warningsCount = 0

        for (i, item) in items.enumerated() {
            var status: AnonymizerItem.Status
            do {
                let file = try DicomParser.parse(url: item.url)
                let result = anonymizer.anonymize(file, scan: .all)
                let ds = result.file.dataset
                let seriesUID = ds.string(.seriesInstanceUID) ?? "0"
                let seriesFolder = "S\(ds.string(.seriesNumber) ?? "0")_\(ds.string(.modality) ?? "OT")_\(seriesUID.suffix(6))"
                let directory = folder
                    .appendingPathComponent(result.pseudonym, isDirectory: true)
                    .appendingPathComponent(seriesFolder, isDirectory: true)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let n = (counters[directory.path] ?? 0) + 1
                counters[directory.path] = n
                let target = directory.appendingPathComponent(String(format: "IM%05d.dcm", n))
                try DicomWriter.write(result.file).write(to: target, options: .atomic)

                if options.exportNIfTI { seriesFiles[directory.path, default: []].append(result.file) }
                maskedRegions += result.textRegions.values.reduce(0) { $0 + $1.count }
                for change in result.changes { kindCounts[change.kind, default: 0] += 1 }
                if !result.warnings.isEmpty { warningsCount += 1 }
                written += 1
                status = result.warnings.isEmpty ? .done : .warning(result.warnings.joined(separator: " "))
            } catch {
                failed += 1
                status = .failed(error.localizedDescription)
            }
            progress(item.id, status, Double(i + 1) / Double(items.count))
        }

        if options.exportNIfTI {
            for (path, files) in seriesFiles.sorted(by: { $0.key < $1.key }) {
                do {
                    let volume = try DicomVolumeBuilder.build(files)
                    try NIfTI.write(volume, to: URL(fileURLWithPath: path + ".nii.gz"))
                } catch {
                    notes.append("NIfTI for \(URL(fileURLWithPath: path).lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        if options.writeKeyFile {
            var csv = "original_patient_id,original_patient_name,pseudonym,date_shift_days\n"
            func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            for entry in anonymizer.keyEntries.values.sorted(by: { $0.pseudonym < $1.pseudonym }) {
                csv += [quote(entry.originalID), quote(entry.originalName), quote(entry.pseudonym), String(entry.dateShiftDays)]
                    .joined(separator: ",") + "\n"
            }
            do {
                try csv.write(to: folder.appendingPathComponent("axial-reidentification-key.csv"), atomically: true, encoding: .utf8)
            } catch {
                notes.append("Key file: \(error.localizedDescription)")
            }
        }

        // Human-readable audit report next to the data
        let formatter = ISO8601DateFormatter()
        var report = """
        Axial de-identification report
        ==============================
        Date:            \(formatter.string(from: Date()))
        Axial version:   \(AppInfo.version)
        Files written:   \(written)
        Files failed:    \(failed)
        Files w/ notes:  \(warningsCount)
        Patients:        \(anonymizer.keyEntries.count)

        Changes
        -------
        Attributes removed or emptied: \((kindCounts[.removed] ?? 0) + (kindCounts[.emptied] ?? 0))
        Identifiers pseudonymised:     \(kindCounts[.replaced] ?? 0)
        Dates shifted:                 \(kindCounts[.dateShifted] ?? 0)
        UIDs replaced:                 \(kindCounts[.uidReplaced] ?? 0)
        Burned-in text regions masked: \(maskedRegions)

        Settings
        --------
        Date handling:          \(options.dateMode.rawValue)
        Keep demographics:      \(options.keepDemographics ? "yes" : "no")
        Remove private tags:    \(options.removePrivateTags ? "yes" : "no")
        Replace UIDs:           \(options.remapUIDs ? "yes" : "no")
        Remove descriptions:    \(options.removeDescriptions ? "yes" : "no")
        Scan burned-in text:    \(options.scanBurnedInText ? "yes" : "no")
        Pseudonym prefix:       \(options.pseudonymPrefix)

        Profile: subset of DICOM PS3.15 Annex E Basic Application Level Confidentiality Profile.
        Automated de-identification can miss information. Review the output before sharing.

        """
        if !notes.isEmpty { report += "\nNotes\n-----\n" + notes.joined(separator: "\n") + "\n" }
        try? report.write(to: folder.appendingPathComponent("deidentification-report.txt"), atomically: true, encoding: .utf8)

        var summary = "De-identified \(written) file\(written == 1 ? "" : "s")"
        if maskedRegions > 0 { summary += ", masked \(maskedRegions) text region\(maskedRegions == 1 ? "" : "s")" }
        if failed > 0 { summary += ", \(failed) failed" }
        summary += "."
        if !notes.isEmpty { summary += " " + notes.joined(separator: " ") }
        return summary
    }
}
