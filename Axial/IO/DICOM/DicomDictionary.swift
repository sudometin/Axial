import Foundation

extension DicomTag {
    // File meta
    static let metaGroupLength = DicomTag(0x0002, 0x0000)
    static let fileMetaInformationVersion = DicomTag(0x0002, 0x0001)
    static let mediaStorageSOPClassUID = DicomTag(0x0002, 0x0002)
    static let mediaStorageSOPInstanceUID = DicomTag(0x0002, 0x0003)
    static let transferSyntaxUID = DicomTag(0x0002, 0x0010)
    static let implementationClassUID = DicomTag(0x0002, 0x0012)
    static let implementationVersionName = DicomTag(0x0002, 0x0013)

    // Identification
    static let specificCharacterSet = DicomTag(0x0008, 0x0005)
    static let sopClassUID = DicomTag(0x0008, 0x0016)
    static let sopInstanceUID = DicomTag(0x0008, 0x0018)
    static let studyDate = DicomTag(0x0008, 0x0020)
    static let seriesDate = DicomTag(0x0008, 0x0021)
    static let acquisitionDate = DicomTag(0x0008, 0x0022)
    static let contentDate = DicomTag(0x0008, 0x0023)
    static let acquisitionDateTime = DicomTag(0x0008, 0x002A)
    static let accessionNumber = DicomTag(0x0008, 0x0050)
    static let modality = DicomTag(0x0008, 0x0060)
    static let manufacturer = DicomTag(0x0008, 0x0070)
    static let institutionName = DicomTag(0x0008, 0x0080)
    static let referringPhysicianName = DicomTag(0x0008, 0x0090)
    static let studyDescription = DicomTag(0x0008, 0x1030)
    static let seriesDescription = DicomTag(0x0008, 0x103E)
    static let performingPhysicianName = DicomTag(0x0008, 0x1050)
    static let manufacturerModelName = DicomTag(0x0008, 0x1090)
    static let referencedImageSequence = DicomTag(0x0008, 0x1140)
    static let referencedSOPInstanceUID = DicomTag(0x0008, 0x1155)

    // Patient
    static let patientName = DicomTag(0x0010, 0x0010)
    static let patientID = DicomTag(0x0010, 0x0020)
    static let patientBirthDate = DicomTag(0x0010, 0x0030)
    static let patientSex = DicomTag(0x0010, 0x0040)
    static let patientAge = DicomTag(0x0010, 0x1010)
    static let patientSize = DicomTag(0x0010, 0x1020)
    static let patientWeight = DicomTag(0x0010, 0x1030)
    static let patientIdentityRemoved = DicomTag(0x0012, 0x0062)
    static let deidentificationMethod = DicomTag(0x0012, 0x0063)

    // Acquisition
    static let sliceThickness = DicomTag(0x0018, 0x0050)
    static let repetitionTime = DicomTag(0x0018, 0x0080)
    static let echoTime = DicomTag(0x0018, 0x0081)
    static let magneticFieldStrength = DicomTag(0x0018, 0x0087)
    static let spacingBetweenSlices = DicomTag(0x0018, 0x0088)
    static let protocolName = DicomTag(0x0018, 0x1030)

    // Relationship / geometry
    static let studyInstanceUID = DicomTag(0x0020, 0x000D)
    static let seriesInstanceUID = DicomTag(0x0020, 0x000E)
    static let studyID = DicomTag(0x0020, 0x0010)
    static let seriesNumber = DicomTag(0x0020, 0x0011)
    static let instanceNumber = DicomTag(0x0020, 0x0013)
    static let imagePositionPatient = DicomTag(0x0020, 0x0032)
    static let imageOrientationPatient = DicomTag(0x0020, 0x0037)
    static let frameOfReferenceUID = DicomTag(0x0020, 0x0052)

    // Image pixel
    static let samplesPerPixel = DicomTag(0x0028, 0x0002)
    static let photometricInterpretation = DicomTag(0x0028, 0x0004)
    static let planarConfiguration = DicomTag(0x0028, 0x0006)
    static let numberOfFrames = DicomTag(0x0028, 0x0008)
    static let rows = DicomTag(0x0028, 0x0010)
    static let columns = DicomTag(0x0028, 0x0011)
    static let pixelSpacing = DicomTag(0x0028, 0x0030)
    static let bitsAllocated = DicomTag(0x0028, 0x0100)
    static let bitsStored = DicomTag(0x0028, 0x0101)
    static let highBit = DicomTag(0x0028, 0x0102)
    static let pixelRepresentation = DicomTag(0x0028, 0x0103)
    static let burnedInAnnotation = DicomTag(0x0028, 0x0301)
    static let windowCenter = DicomTag(0x0028, 0x1050)
    static let windowWidth = DicomTag(0x0028, 0x1051)
    static let rescaleIntercept = DicomTag(0x0028, 0x1052)
    static let rescaleSlope = DicomTag(0x0028, 0x1053)

    static let pixelData = DicomTag(0x7FE0, 0x0010)
}

/// A small data dictionary: names for display and VRs for implicit-VR decoding.
enum DicomDictionary {
    private static let entries: [DicomTag: (vr: String, name: String)] = {
        let table: [(UInt16, UInt16, String, String)] = [
            (0x0002, 0x0000, "UL", "File Meta Information Group Length"),
            (0x0002, 0x0001, "OB", "File Meta Information Version"),
            (0x0002, 0x0002, "UI", "Media Storage SOP Class UID"),
            (0x0002, 0x0003, "UI", "Media Storage SOP Instance UID"),
            (0x0002, 0x0010, "UI", "Transfer Syntax UID"),
            (0x0002, 0x0012, "UI", "Implementation Class UID"),
            (0x0002, 0x0013, "SH", "Implementation Version Name"),
            (0x0008, 0x0005, "CS", "Specific Character Set"),
            (0x0008, 0x0008, "CS", "Image Type"),
            (0x0008, 0x0012, "DA", "Instance Creation Date"),
            (0x0008, 0x0013, "TM", "Instance Creation Time"),
            (0x0008, 0x0014, "UI", "Instance Creator UID"),
            (0x0008, 0x0016, "UI", "SOP Class UID"),
            (0x0008, 0x0018, "UI", "SOP Instance UID"),
            (0x0008, 0x0020, "DA", "Study Date"),
            (0x0008, 0x0021, "DA", "Series Date"),
            (0x0008, 0x0022, "DA", "Acquisition Date"),
            (0x0008, 0x0023, "DA", "Content Date"),
            (0x0008, 0x002A, "DT", "Acquisition DateTime"),
            (0x0008, 0x0030, "TM", "Study Time"),
            (0x0008, 0x0031, "TM", "Series Time"),
            (0x0008, 0x0032, "TM", "Acquisition Time"),
            (0x0008, 0x0033, "TM", "Content Time"),
            (0x0008, 0x0050, "SH", "Accession Number"),
            (0x0008, 0x0060, "CS", "Modality"),
            (0x0008, 0x0070, "LO", "Manufacturer"),
            (0x0008, 0x0080, "LO", "Institution Name"),
            (0x0008, 0x0081, "ST", "Institution Address"),
            (0x0008, 0x0082, "SQ", "Institution Code Sequence"),
            (0x0008, 0x0090, "PN", "Referring Physician's Name"),
            (0x0008, 0x0092, "ST", "Referring Physician's Address"),
            (0x0008, 0x0094, "SH", "Referring Physician's Telephone Numbers"),
            (0x0008, 0x0096, "SQ", "Referring Physician Identification Sequence"),
            (0x0008, 0x1010, "SH", "Station Name"),
            (0x0008, 0x1030, "LO", "Study Description"),
            (0x0008, 0x1032, "SQ", "Procedure Code Sequence"),
            (0x0008, 0x103E, "LO", "Series Description"),
            (0x0008, 0x1040, "LO", "Institutional Department Name"),
            (0x0008, 0x1048, "PN", "Physician(s) of Record"),
            (0x0008, 0x1050, "PN", "Performing Physician's Name"),
            (0x0008, 0x1060, "PN", "Name of Physician(s) Reading Study"),
            (0x0008, 0x1070, "PN", "Operators' Name"),
            (0x0008, 0x1080, "LO", "Admitting Diagnoses Description"),
            (0x0008, 0x1090, "LO", "Manufacturer's Model Name"),
            (0x0008, 0x1110, "SQ", "Referenced Study Sequence"),
            (0x0008, 0x1111, "SQ", "Referenced Performed Procedure Step Sequence"),
            (0x0008, 0x1115, "SQ", "Referenced Series Sequence"),
            (0x0008, 0x1120, "SQ", "Referenced Patient Sequence"),
            (0x0008, 0x1140, "SQ", "Referenced Image Sequence"),
            (0x0008, 0x1150, "UI", "Referenced SOP Class UID"),
            (0x0008, 0x1155, "UI", "Referenced SOP Instance UID"),
            (0x0008, 0x2111, "ST", "Derivation Description"),
            (0x0008, 0x2112, "SQ", "Source Image Sequence"),
            (0x0008, 0x2218, "SQ", "Anatomic Region Sequence"),
            (0x0008, 0x9215, "SQ", "Derivation Code Sequence"),
            (0x0010, 0x0010, "PN", "Patient's Name"),
            (0x0010, 0x0020, "LO", "Patient ID"),
            (0x0010, 0x0021, "LO", "Issuer of Patient ID"),
            (0x0010, 0x0030, "DA", "Patient's Birth Date"),
            (0x0010, 0x0032, "TM", "Patient's Birth Time"),
            (0x0010, 0x0040, "CS", "Patient's Sex"),
            (0x0010, 0x0050, "SQ", "Patient's Insurance Plan Code Sequence"),
            (0x0010, 0x1000, "LO", "Other Patient IDs"),
            (0x0010, 0x1001, "PN", "Other Patient Names"),
            (0x0010, 0x1002, "SQ", "Other Patient IDs Sequence"),
            (0x0010, 0x1005, "PN", "Patient's Birth Name"),
            (0x0010, 0x1010, "AS", "Patient's Age"),
            (0x0010, 0x1020, "DS", "Patient's Size"),
            (0x0010, 0x1030, "DS", "Patient's Weight"),
            (0x0010, 0x1040, "LO", "Patient's Address"),
            (0x0010, 0x1060, "PN", "Patient's Mother's Birth Name"),
            (0x0010, 0x1090, "LO", "Medical Record Locator"),
            (0x0010, 0x2154, "SH", "Patient's Telephone Numbers"),
            (0x0010, 0x2160, "SH", "Ethnic Group"),
            (0x0010, 0x21B0, "LT", "Additional Patient History"),
            (0x0010, 0x4000, "LT", "Patient Comments"),
            (0x0012, 0x0062, "CS", "Patient Identity Removed"),
            (0x0012, 0x0063, "LO", "De-identification Method"),
            (0x0018, 0x0015, "CS", "Body Part Examined"),
            (0x0018, 0x0050, "DS", "Slice Thickness"),
            (0x0018, 0x0080, "DS", "Repetition Time"),
            (0x0018, 0x0081, "DS", "Echo Time"),
            (0x0018, 0x0087, "DS", "Magnetic Field Strength"),
            (0x0018, 0x0088, "DS", "Spacing Between Slices"),
            (0x0018, 0x1000, "LO", "Device Serial Number"),
            (0x0018, 0x1020, "LO", "Software Versions"),
            (0x0018, 0x1030, "LO", "Protocol Name"),
            (0x0018, 0x4000, "LT", "Acquisition Comments"),
            (0x0020, 0x000D, "UI", "Study Instance UID"),
            (0x0020, 0x000E, "UI", "Series Instance UID"),
            (0x0020, 0x0010, "SH", "Study ID"),
            (0x0020, 0x0011, "IS", "Series Number"),
            (0x0020, 0x0012, "IS", "Acquisition Number"),
            (0x0020, 0x0013, "IS", "Instance Number"),
            (0x0020, 0x0032, "DS", "Image Position (Patient)"),
            (0x0020, 0x0037, "DS", "Image Orientation (Patient)"),
            (0x0020, 0x0052, "UI", "Frame of Reference UID"),
            (0x0020, 0x0200, "UI", "Synchronization Frame of Reference UID"),
            (0x0020, 0x1041, "DS", "Slice Location"),
            (0x0020, 0x4000, "LT", "Image Comments"),
            (0x0028, 0x0002, "US", "Samples per Pixel"),
            (0x0028, 0x0004, "CS", "Photometric Interpretation"),
            (0x0028, 0x0006, "US", "Planar Configuration"),
            (0x0028, 0x0008, "IS", "Number of Frames"),
            (0x0028, 0x0010, "US", "Rows"),
            (0x0028, 0x0011, "US", "Columns"),
            (0x0028, 0x0030, "DS", "Pixel Spacing"),
            (0x0028, 0x0100, "US", "Bits Allocated"),
            (0x0028, 0x0101, "US", "Bits Stored"),
            (0x0028, 0x0102, "US", "High Bit"),
            (0x0028, 0x0103, "US", "Pixel Representation"),
            (0x0028, 0x0301, "CS", "Burned In Annotation"),
            (0x0028, 0x1050, "DS", "Window Center"),
            (0x0028, 0x1051, "DS", "Window Width"),
            (0x0028, 0x1052, "DS", "Rescale Intercept"),
            (0x0028, 0x1053, "DS", "Rescale Slope"),
            (0x0032, 0x1032, "PN", "Requesting Physician"),
            (0x0032, 0x1060, "LO", "Requested Procedure Description"),
            (0x0032, 0x1064, "SQ", "Requested Procedure Code Sequence"),
            (0x0038, 0x0010, "LO", "Admission ID"),
            (0x0038, 0x0300, "LO", "Current Patient Location"),
            (0x0038, 0x0400, "LO", "Patient's Institution Residence"),
            (0x0040, 0x0006, "PN", "Scheduled Performing Physician's Name"),
            (0x0040, 0x0244, "DA", "Performed Procedure Step Start Date"),
            (0x0040, 0x0245, "TM", "Performed Procedure Step Start Time"),
            (0x0040, 0x0253, "SH", "Performed Procedure Step ID"),
            (0x0040, 0x0254, "LO", "Performed Procedure Step Description"),
            (0x0040, 0x0260, "SQ", "Performed Protocol Code Sequence"),
            (0x0040, 0x0275, "SQ", "Request Attributes Sequence"),
            (0x0040, 0xA124, "UI", "UID"),
            (0x4008, 0x0114, "PN", "Physician Approving Interpretation"),
            (0x5200, 0x9229, "SQ", "Shared Functional Groups Sequence"),
            (0x5200, 0x9230, "SQ", "Per-frame Functional Groups Sequence"),
            (0x7FE0, 0x0010, "OW", "Pixel Data"),
        ]
        var dict: [DicomTag: (vr: String, name: String)] = [:]
        for (g, e, vr, name) in table { dict[DicomTag(g, e)] = (vr, name) }
        return dict
    }()

    static func vr(for tag: DicomTag) -> String? {
        if tag.isGroupLength { return "UL" }
        return entries[tag]?.vr
    }

    static func name(for tag: DicomTag) -> String {
        if let entry = entries[tag] { return entry.name }
        if tag.isPrivate { return tag.element <= 0x00FF ? "Private Creator" : "Private Tag" }
        if tag.isGroupLength { return "Group Length" }
        return "Unknown Attribute"
    }
}
