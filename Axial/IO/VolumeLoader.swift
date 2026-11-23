import Foundation

/// Opens a mix of NIfTI files, DICOM files and folders.
enum VolumeLoader {
    struct Outcome {
        var volumes: [Volume] = []
        var errors: [String] = []
    }

    static func load(_ urls: [URL]) -> Outcome {
        var outcome = Outcome()
        var dicomCandidates: [URL] = []

        for url in FileEnumerator.expand(urls) {
            if NIfTI.isNIfTIFile(url) {
                do {
                    outcome.volumes.append(try NIfTI.read(url))
                } catch {
                    outcome.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            } else {
                dicomCandidates.append(url)
            }
        }

        if !dicomCandidates.isEmpty {
            let result = DicomSeriesLoader.loadVolumes(from: dicomCandidates)
            outcome.volumes += result.volumes
            // Only surface the "nothing found" message when nothing at all was opened.
            if !(outcome.volumes.count > result.volumes.count && result.volumes.isEmpty) {
                outcome.errors += result.errors
            }
        }
        return outcome
    }
}
