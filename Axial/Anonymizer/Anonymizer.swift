import Foundation
import CryptoKit
import CoreGraphics

enum ChangeKind {
    case removed, emptied, replaced, dateShifted, uidReplaced, pixels
}

struct TagChange: Identifiable {
    let id = UUID()
    var kind: ChangeKind = .replaced
    let tag: DicomTag
    let name: String
    let before: String
    /// nil when the attribute was removed.
    let after: String?
}

enum FrameScan: Equatable {
    case none
    case all
    case frame(Int)
}

struct AnonymizationResult {
    var file: DicomFile
    var changes: [TagChange]
    /// Masked regions per frame, in pixel coordinates (origin top-left).
    var textRegions: [Int: [CGRect]]
    var warnings: [String]
    var pseudonym: String
    var dateShiftDays: Int
}

/// Re-identification key entry (only written to disk when the user asks for it).
struct KeyEntry {
    let originalID: String
    let originalName: String
    let pseudonym: String
    let dateShiftDays: Int
}

/// De-identifies DICOM files. Deterministic for a given project key: the same patient always
/// gets the same pseudonym and date shift, and the same UID always maps to the same new UID,
/// so studies anonymized in separate sessions still link together.
final class Anonymizer {
    let options: AnonymizationOptions
    private let actions: [DicomTag: TagAction]
    private(set) var keyEntries: [String: KeyEntry] = [:]

    init(options: AnonymizationOptions) {
        self.options = options
        self.actions = AnonymizationProfile.actions(for: options)
    }

    // MARK: Deterministic replacements

    private func digest(_ purpose: String, _ value: String) -> [UInt8] {
        Array(SHA256.hash(data: Data("\(options.projectKey)|\(purpose)|\(value)".utf8)))
    }

    func pseudonym(for patientKey: String) -> String {
        let hex = digest("patient", patientKey).prefix(4).map { String(format: "%02X", $0) }.joined()
        let prefix = options.pseudonymPrefix.trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? hex : "\(prefix)-\(hex)"
    }

    /// Between 30 and 729 days into the past.
    func dateShift(for patientKey: String) -> Int {
        let b = digest("date", patientKey)
        let n = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        return -(30 + Int(n % 700))
    }

    /// A UUID-derived UID under the 2.25 root (ISO/IEC 9834-8), always ≤ 44 characters.
    func remapUID(_ uid: String) -> String {
        "2.25." + Anonymizer.decimalString(Array(digest("uid", uid).prefix(16)))
    }

    static func decimalString(_ bigEndianBytes: [UInt8]) -> String {
        var number = bigEndianBytes
        var digits: [Character] = []
        while number.contains(where: { $0 != 0 }) {
            var remainder = 0
            for i in number.indices {
                let current = remainder * 256 + Int(number[i])
                number[i] = UInt8(current / 10)
                remainder = current % 10
            }
            digits.append(Character(String(remainder)))
        }
        return digits.isEmpty ? "0" : String(digits.reversed())
    }

    static func shiftDate(_ value: String, days: Int) -> String? {
        let digits = value.prefix(8)
        guard digits.count == 8, digits.allSatisfy(\.isNumber),
              let year = Int(digits.prefix(4)), let month = Int(digits.dropFirst(4).prefix(2)), let day = Int(digits.suffix(2))
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let shifted = calendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1) + value.dropFirst(8)
    }

    // MARK: Anonymization

    private struct Context {
        let pseudonym: String
        let shiftDays: Int
    }

    func anonymize(_ input: DicomFile, scan: FrameScan) -> AnonymizationResult {
        var file = input
        var changes: [TagChange] = []
        var warnings: [String] = []

        let ds = input.dataset
        let originalID = ds.string(.patientID) ?? ""
        let originalName = ds.string(.patientName) ?? ""
        let patientKey = originalID.isEmpty ? "\(originalName)|\(ds.string(.patientBirthDate) ?? "")" : originalID
        let alias = self.pseudonym(for: patientKey)
        let shift = options.dateMode == .shift ? dateShift(for: patientKey) : 0
        if keyEntries[patientKey] == nil {
            keyEntries[patientKey] = KeyEntry(originalID: originalID, originalName: originalName, pseudonym: alias, dateShiftDays: shift)
        }

        let context = Context(pseudonym: alias, shiftDays: shift)
        process(&file.dataset, context: context, path: "", changes: &changes)

        if options.remapUIDs, let uid = file.meta.string(.mediaStorageSOPInstanceUID), !uid.hasPrefix("1.2.840.10008.") {
            file.meta.setString(remapUID(uid), for: .mediaStorageSOPInstanceUID, vr: "UI")
        }
        file.meta[DicomTag(0x0002, 0x0016)] = nil // Source Application Entity Title

        // Always present after de-identification.
        if file.dataset[.patientName] == nil { file.dataset.setString(alias, for: .patientName, vr: "PN") }
        if file.dataset[.patientID] == nil { file.dataset.setString(alias, for: .patientID, vr: "LO") }
        file.dataset.setString("YES", for: .patientIdentityRemoved, vr: "CS")
        file.dataset.setString(methodDescription, for: .deidentificationMethod, vr: "LO")

        var regions: [Int: [CGRect]] = [:]
        if options.scanBurnedInText && scan != .none && file.dataset[.pixelData] != nil {
            if input.isCompressed {
                warnings.append("Compressed pixel data (\(TransferSyntax.name(input.transferSyntax))) was not scanned for burned-in text.")
            } else {
                do {
                    regions = try BurnedInText.scrub(&file.dataset, frames: scan)
                    let count = regions.values.reduce(0) { $0 + $1.count }
                    if count > 0 {
                        changes.append(TagChange(kind: .pixels, tag: .pixelData, name: "Pixel Data", before: "Burned-in text",
                                                 after: "\(count) region\(count == 1 ? "" : "s") masked"))
                    }
                } catch {
                    warnings.append("Burned-in text scan failed: \(error.localizedDescription)")
                }
            }
        }

        return AnonymizationResult(file: file, changes: changes, textRegions: regions, warnings: warnings, pseudonym: alias, dateShiftDays: shift)
    }

    private var methodDescription: String {
        var parts = ["Axial basic profile"]
        switch options.dateMode {
        case .shift: parts.append("dates shifted")
        case .remove: parts.append("dates removed")
        case .keep: parts.append("dates retained")
        }
        if options.remapUIDs { parts.append("UIDs replaced") }
        if options.removePrivateTags { parts.append("private tags removed") }
        if options.scanBurnedInText { parts.append("pixel text masked") }
        return parts.joined(separator: "; ")
    }

    private static let uidTags: Set<DicomTag> = [
        .sopInstanceUID, .studyInstanceUID, .seriesInstanceUID, .frameOfReferenceUID, .referencedSOPInstanceUID,
        DicomTag(0x0008, 0x0014), DicomTag(0x0020, 0x0200), DicomTag(0x0040, 0xA124),
    ]

    private func process(_ dataset: inout DicomDataset, context: Context, path: String, changes: inout [TagChange]) {
        for tag in dataset.sortedTags {
            guard var element = dataset[tag] else { continue }
            let name = DicomDictionary.name(for: tag)
            let label = path.isEmpty ? name : "\(path) › \(name)"
            func record(_ after: String?, _ kind: ChangeKind) {
                changes.append(TagChange(kind: kind, tag: tag, name: label, before: element.displayValue, after: after))
            }

            if tag == .pixelData { continue }

            if tag.isPrivate && options.removePrivateTags {
                record(nil, .removed)
                dataset[tag] = nil
                continue
            }

            if let action = actions[tag] {
                switch action {
                case .remove:
                    record(nil, .removed)
                    dataset[tag] = nil
                    continue
                case .empty:
                    if !(element.string ?? "").isEmpty || element.items != nil {
                        record("", .emptied)
                        dataset[tag] = element.items != nil
                            ? DicomElement(tag: tag, vr: "SQ", items: [])
                            : DicomElement(tag: tag, vr: element.vr)
                    }
                    continue
                case .pseudonym:
                    record(context.pseudonym, .replaced)
                    dataset.setString(context.pseudonym, for: tag, vr: tag == .patientName ? "PN" : "LO")
                    continue
                case .shiftDate:
                    if let value = element.string, !value.isEmpty {
                        let shifted = value.split(separator: "\\").map { Anonymizer.shiftDate(String($0), days: context.shiftDays) ?? "" }.joined(separator: "\\")
                        record(shifted, .dateShifted)
                        dataset.setString(shifted, for: tag, vr: element.vr)
                    }
                    continue
                }
            }

            if options.remapUIDs, element.vr == "UI" || Anonymizer.uidTags.contains(tag), let value = element.string, !value.isEmpty {
                let mapped = value.split(separator: "\\").map { part -> String in
                    let uid = String(part)
                    return uid.hasPrefix("1.2.840.10008.") ? uid : remapUID(uid)
                }.joined(separator: "\\")
                if mapped != value {
                    record(mapped, .uidReplaced)
                    dataset.setString(mapped, for: tag, vr: "UI")
                }
                continue
            }

            if var items = element.items {
                for i in items.indices {
                    process(&items[i], context: context, path: label, changes: &changes)
                }
                element.items = items
                dataset[tag] = element
            }
        }
    }
}
