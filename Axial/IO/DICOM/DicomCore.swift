import Foundation

enum DicomError: LocalizedError {
    case notDicom
    case truncated
    case unsupportedTransferSyntax(String)
    case unsupportedPixelFormat(String)
    case missing(String)
    case emptySeries

    var errorDescription: String? {
        switch self {
        case .notDicom: "Not a DICOM file."
        case .truncated: "The DICOM file is truncated or malformed."
        case .unsupportedTransferSyntax(let ts): "Unsupported transfer syntax: \(TransferSyntax.name(ts))."
        case .unsupportedPixelFormat(let s): "Unsupported pixel format: \(s)."
        case .missing(let what): "Missing required attribute: \(what)."
        case .emptySeries: "The series contains no usable images."
        }
    }
}

struct DicomTag: Hashable, Comparable, CustomStringConvertible {
    let group: UInt16
    let element: UInt16

    init(_ group: UInt16, _ element: UInt16) {
        self.group = group
        self.element = element
    }

    static func < (a: DicomTag, b: DicomTag) -> Bool {
        (a.group, a.element) < (b.group, b.element)
    }

    var isPrivate: Bool { group % 2 == 1 }
    var isGroupLength: Bool { element == 0x0000 }
    var description: String { String(format: "(%04X,%04X)", group, element) }
}

/// A single data element. Exactly one of `value`, `items` (SQ) or `fragments`
/// (encapsulated pixel data) carries the payload.
struct DicomElement {
    var tag: DicomTag
    var vr: String
    var value: Data = Data()
    var items: [DicomDataset]? = nil
    var fragments: [Data]? = nil

    static let binaryVRs: Set<String> = ["OB", "OD", "OF", "OL", "OV", "OW", "UN", "SQ", "US", "SS", "UL", "SL", "FL", "FD", "AT", "SV", "UV"]

    /// The value decoded as text (trailing padding removed).
    var string: String? {
        guard items == nil, fragments == nil else { return nil }
        let text = String(data: value, encoding: .utf8) ?? String(data: value, encoding: .isoLatin1) ?? ""
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }

    var displayValue: String {
        if let items { return items.count == 1 ? "1 item" : "\(items.count) items" }
        if let fragments { return "Encapsulated (\(fragments.count) fragments)" }
        switch vr {
        case "US" where value.count >= 2:
            return String(BinaryReader(data: value).u16(0))
        case "UL" where value.count >= 4:
            return String(BinaryReader(data: value).u32(0))
        case "SS" where value.count >= 2:
            return String(BinaryReader(data: value).i16(0))
        case "SL" where value.count >= 4:
            return String(BinaryReader(data: value).i32(0))
        case "FL" where value.count >= 4:
            return String(BinaryReader(data: value).f32(0))
        case "FD" where value.count >= 8:
            return String(BinaryReader(data: value).f64(0))
        default:
            break
        }
        let looksTextual = value.allSatisfy { ($0 >= 0x20 && $0 < 0x7F) || $0 == 0 || $0 == 0x0A || $0 == 0x0D || $0 >= 0xA0 }
        if DicomElement.binaryVRs.contains(vr) && !(vr == "UN" && looksTextual) {
            return "<\(value.count) bytes>"
        }
        let s = string ?? ""
        return s.count > 80 ? String(s.prefix(77)) + "…" : s
    }
}

struct DicomDataset {
    var elements: [DicomTag: DicomElement] = [:]

    subscript(tag: DicomTag) -> DicomElement? {
        get { elements[tag] }
        set { elements[tag] = newValue }
    }

    var sortedTags: [DicomTag] { elements.keys.sorted() }

    func string(_ tag: DicomTag) -> String? { elements[tag]?.string }

    func strings(_ tag: DicomTag) -> [String] {
        guard let s = string(tag), !s.isEmpty else { return [] }
        return s.split(separator: "\\", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func doubles(_ tag: DicomTag) -> [Double] { strings(tag).compactMap { Double($0) } }
    func double(_ tag: DicomTag) -> Double? { doubles(tag).first }
    func int(_ tag: DicomTag) -> Int? { strings(tag).first.flatMap { Int($0) } }

    /// Reads a binary US value (2 bytes, little-endian).
    func uint16(_ tag: DicomTag) -> Int? {
        guard let v = elements[tag]?.value, v.count >= 2 else { return nil }
        return Int(BinaryReader(data: v).u16(0))
    }

    mutating func setString(_ string: String, for tag: DicomTag, vr: String) {
        var bytes = Data(string.utf8)
        let elementVR = elements[tag]?.vr ?? vr
        if bytes.count % 2 == 1 { bytes.append(elementVR == "UI" ? 0x00 : 0x20) }
        if var existing = elements[tag], existing.items == nil {
            existing.value = bytes
            elements[tag] = existing
        } else {
            elements[tag] = DicomElement(tag: tag, vr: vr, value: bytes)
        }
    }

    mutating func setUInt16(_ value: UInt16, for tag: DicomTag) {
        var bytes = Data()
        bytes.appendLE(value)
        elements[tag] = DicomElement(tag: tag, vr: "US", value: bytes)
    }
}

struct DicomFile {
    var meta: DicomDataset
    var dataset: DicomDataset

    var transferSyntax: String { meta.string(.transferSyntaxUID) ?? TransferSyntax.implicitLE }
    var isExplicitVR: Bool { transferSyntax != TransferSyntax.implicitLE }
    var isCompressed: Bool { dataset[.pixelData]?.fragments != nil || TransferSyntax.isEncapsulated(transferSyntax) }
}

enum TransferSyntax {
    static let implicitLE = "1.2.840.10008.1.2"
    static let explicitLE = "1.2.840.10008.1.2.1"
    static let deflatedLE = "1.2.840.10008.1.2.1.99"
    static let explicitBE = "1.2.840.10008.1.2.2"

    static func isEncapsulated(_ uid: String) -> Bool {
        ![implicitLE, explicitLE, deflatedLE, explicitBE].contains(uid)
    }

    static func name(_ uid: String) -> String {
        switch uid {
        case implicitLE: "Implicit VR Little Endian"
        case explicitLE: "Explicit VR Little Endian"
        case deflatedLE: "Deflated Explicit VR Little Endian"
        case explicitBE: "Explicit VR Big Endian"
        case "1.2.840.10008.1.2.4.50": "JPEG Baseline"
        case "1.2.840.10008.1.2.4.51": "JPEG Extended"
        case "1.2.840.10008.1.2.4.57", "1.2.840.10008.1.2.4.70": "JPEG Lossless"
        case "1.2.840.10008.1.2.4.80", "1.2.840.10008.1.2.4.81": "JPEG-LS"
        case "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91": "JPEG 2000"
        case "1.2.840.10008.1.2.5": "RLE Lossless"
        default: uid
        }
    }
}
