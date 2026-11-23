import Foundation

struct AnonymizationOptions: Equatable {
    enum DateMode: String, CaseIterable, Identifiable {
        case shift = "Shift"
        case remove = "Remove"
        case keep = "Keep"
        var id: String { rawValue }

        var explanation: String {
            switch self {
            case .shift: "Dates move back by a fixed, per-patient number of days, so intervals between scans are preserved."
            case .remove: "Dates are emptied."
            case .keep: "Dates are left as they are. Only do this if your study protocol allows it."
            }
        }
    }

    var pseudonymPrefix = "SUBJ"
    var keepDemographics = true
    var dateMode: DateMode = .shift
    var removePrivateTags = true
    var remapUIDs = true
    var removeDescriptions = false
    var scanBurnedInText = true
    var exportNIfTI = false
    var writeKeyFile = false
    /// Secret mixed into every hash. The same key always yields the same pseudonyms and UIDs.
    var projectKey: String = AnonymizationOptions.storedProjectKey

    static let projectKeyDefaultsKey = "AxialProjectKey"

    static var storedProjectKey: String {
        if let key = UserDefaults.standard.string(forKey: projectKeyDefaultsKey), !key.isEmpty { return key }
        let key = UUID().uuidString
        UserDefaults.standard.set(key, forKey: projectKeyDefaultsKey)
        return key
    }
}

/// What happens to a given attribute.
enum TagAction {
    case remove
    case empty
    case pseudonym
    case shiftDate
}

/// A subset of the DICOM PS3.15 Annex E Basic Application Level Confidentiality Profile,
/// plus UID replacement and optional retention of demographics.
enum AnonymizationProfile {
    static let removed: [DicomTag] = [
        DicomTag(0x0008, 0x0080), // Institution Name
        DicomTag(0x0008, 0x0081), // Institution Address
        DicomTag(0x0008, 0x0082), // Institution Code Sequence
        DicomTag(0x0008, 0x0092), // Referring Physician's Address
        DicomTag(0x0008, 0x0094), // Referring Physician's Telephone Numbers
        DicomTag(0x0008, 0x0096), // Referring Physician Identification Sequence
        DicomTag(0x0008, 0x1010), // Station Name
        DicomTag(0x0008, 0x1040), // Institutional Department Name
        DicomTag(0x0008, 0x1048), // Physician(s) of Record
        DicomTag(0x0008, 0x1050), // Performing Physician's Name
        DicomTag(0x0008, 0x1060), // Name of Physician(s) Reading Study
        DicomTag(0x0008, 0x1070), // Operators' Name
        DicomTag(0x0008, 0x1080), // Admitting Diagnoses Description
        DicomTag(0x0008, 0x1120), // Referenced Patient Sequence
        DicomTag(0x0010, 0x0021), // Issuer of Patient ID
        DicomTag(0x0010, 0x0032), // Patient's Birth Time
        DicomTag(0x0010, 0x0050), // Patient's Insurance Plan Code Sequence
        DicomTag(0x0010, 0x1000), // Other Patient IDs
        DicomTag(0x0010, 0x1001), // Other Patient Names
        DicomTag(0x0010, 0x1002), // Other Patient IDs Sequence
        DicomTag(0x0010, 0x1005), // Patient's Birth Name
        DicomTag(0x0010, 0x1040), // Patient's Address
        DicomTag(0x0010, 0x1060), // Patient's Mother's Birth Name
        DicomTag(0x0010, 0x1090), // Medical Record Locator
        DicomTag(0x0010, 0x2154), // Patient's Telephone Numbers
        DicomTag(0x0010, 0x2160), // Ethnic Group
        DicomTag(0x0010, 0x21B0), // Additional Patient History
        DicomTag(0x0010, 0x4000), // Patient Comments
        DicomTag(0x0018, 0x1000), // Device Serial Number
        DicomTag(0x0018, 0x4000), // Acquisition Comments
        DicomTag(0x0020, 0x4000), // Image Comments
        DicomTag(0x0032, 0x1032), // Requesting Physician
        DicomTag(0x0038, 0x0010), // Admission ID
        DicomTag(0x0038, 0x0300), // Current Patient Location
        DicomTag(0x0038, 0x0400), // Patient's Institution Residence
        DicomTag(0x0040, 0x0006), // Scheduled Performing Physician's Name
        DicomTag(0x0040, 0x0253), // Performed Procedure Step ID
        DicomTag(0x0040, 0x0275), // Request Attributes Sequence
        DicomTag(0x4008, 0x0114), // Physician Approving Interpretation
    ]

    /// Required (type 2) attributes that must stay present but empty.
    static let emptied: [DicomTag] = [
        .accessionNumber, .referringPhysicianName, .studyID, .patientBirthDate,
    ]

    static let dates: [DicomTag] = [
        DicomTag(0x0008, 0x0012), // Instance Creation Date
        .studyDate, .seriesDate, .acquisitionDate, .contentDate, .acquisitionDateTime,
        DicomTag(0x0040, 0x0244), // Performed Procedure Step Start Date
    ]

    static let demographics: [DicomTag] = [.patientAge, .patientSize, .patientWeight]

    static let descriptions: [DicomTag] = [
        .studyDescription, .seriesDescription,
        DicomTag(0x0008, 0x2111), // Derivation Description
        DicomTag(0x0032, 0x1060), // Requested Procedure Description
        DicomTag(0x0040, 0x0254), // Performed Procedure Step Description
    ]

    static func actions(for options: AnonymizationOptions) -> [DicomTag: TagAction] {
        var actions: [DicomTag: TagAction] = [:]
        for tag in removed { actions[tag] = .remove }
        for tag in emptied { actions[tag] = .empty }
        actions[.patientName] = .pseudonym
        actions[.patientID] = .pseudonym
        if !options.keepDemographics {
            actions[.patientSex] = .empty
            for tag in demographics { actions[tag] = .remove }
        }
        switch options.dateMode {
        case .keep: break
        case .remove: for tag in dates { actions[tag] = .empty }
        case .shift: for tag in dates { actions[tag] = .shiftDate }
        }
        if options.removeDescriptions {
            for tag in descriptions { actions[tag] = .remove }
        }
        return actions
    }
}
