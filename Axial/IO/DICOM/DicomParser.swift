import Foundation

/// Parses DICOM Part 10 files encoded as Implicit or Explicit VR Little Endian.
/// Encapsulated (compressed) pixel data is kept as raw fragments so the file can still be
/// de-identified and written back unchanged.
enum DicomParser {
    static let undefinedLength: UInt32 = 0xFFFF_FFFF

    static let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "SV", "UC", "UN", "UR", "UT", "UV"]

    static let validVRs: Set<String> = [
        "AE", "AS", "AT", "CS", "DA", "DS", "DT", "FL", "FD", "IS", "LO", "LT", "OB", "OD", "OF", "OL", "OV", "OW",
        "PN", "SH", "SL", "SQ", "SS", "ST", "SV", "TM", "UC", "UI", "UL", "UN", "UR", "US", "UT", "UV",
    ]

    private struct Context {
        let reader: BinaryReader
        var explicit: Bool
        var stopBeforePixelData: Bool
    }

    /// Quick check for the 128-byte preamble followed by "DICM".
    static func hasPreamble(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 132), head.count == 132 else { return false }
        return head.suffix(4) == Data("DICM".utf8)
    }

    static func parse(url: URL, stopBeforePixelData: Bool = false) throws -> DicomFile {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parse(data: data, stopBeforePixelData: stopBeforePixelData)
    }

    static func parse(data: Data, stopBeforePixelData: Bool = false) throws -> DicomFile {
        let reader = BinaryReader(data: data)
        var offset: Int
        if reader.count >= 132, reader.string(128, 4) == "DICM" {
            offset = 132
        } else if reader.count >= 8, [0x0002, 0x0008].contains(reader.u16(0)) {
            offset = 0 // no preamble (older files)
        } else {
            throw DicomError.notDicom
        }

        var ctx = Context(reader: reader, explicit: true, stopBeforePixelData: false)
        var meta = DicomDataset()
        while offset + 8 <= reader.count, reader.u16(offset) == 0x0002 {
            let element = try readElement(&offset, ctx: ctx, end: reader.count)
            meta[element.tag] = element
        }

        let syntax: String
        if let ts = meta.string(.transferSyntaxUID), !ts.isEmpty {
            syntax = ts
        } else {
            // No file meta: guess from the first element.
            syntax = looksExplicit(reader, at: offset) ? TransferSyntax.explicitLE : TransferSyntax.implicitLE
            meta.setString(syntax, for: .transferSyntaxUID, vr: "UI")
        }
        if syntax == TransferSyntax.explicitBE || syntax == TransferSyntax.deflatedLE {
            throw DicomError.unsupportedTransferSyntax(syntax)
        }

        ctx.explicit = syntax != TransferSyntax.implicitLE
        ctx.stopBeforePixelData = stopBeforePixelData
        let dataset = try parseDataset(&offset, end: reader.count, ctx: ctx, inItem: false)
        return DicomFile(meta: meta, dataset: dataset)
    }

    private static func looksExplicit(_ r: BinaryReader, at offset: Int) -> Bool {
        guard offset + 6 <= r.count else { return false }
        return validVRs.contains(r.string(offset + 4, 2))
    }

    private static func parseDataset(_ offset: inout Int, end: Int, ctx: Context, inItem: Bool) throws -> DicomDataset {
        let r = ctx.reader
        var dataset = DicomDataset()
        while offset + 8 <= end {
            let group = r.u16(offset)
            let element = r.u16(offset + 2)
            if group == 0xFFFE {
                offset += 8
                if element == 0xE00D || element == 0xE0DD { return dataset } // item / sequence delimiter
                continue
            }
            let tag = DicomTag(group, element)
            if ctx.stopBeforePixelData && !inItem && tag == .pixelData { break }
            let parsed = try readElement(&offset, ctx: ctx, end: end)
            dataset[parsed.tag] = parsed
        }
        return dataset
    }

    private static func readElement(_ offset: inout Int, ctx: Context, end: Int) throws -> DicomElement {
        let r = ctx.reader
        guard offset + 8 <= end else { throw DicomError.truncated }
        let tag = DicomTag(r.u16(offset), r.u16(offset + 2))
        var vr: String
        let length: UInt32

        if ctx.explicit, validVRs.contains(r.string(offset + 4, 2)) {
            vr = r.string(offset + 4, 2)
            if longVRs.contains(vr) {
                guard offset + 12 <= end else { throw DicomError.truncated }
                length = r.u32(offset + 8)
                offset += 12
            } else {
                length = UInt32(r.u16(offset + 6))
                offset += 8
            }
        } else {
            vr = DicomDictionary.vr(for: tag) ?? "UN"
            length = r.u32(offset + 4)
            offset += 8
        }

        // Encapsulated pixel data: a sequence of raw fragments.
        if tag == .pixelData && length == undefinedLength {
            var fragments: [Data] = []
            while offset + 8 <= r.count {
                let g = r.u16(offset), e = r.u16(offset + 2)
                let itemLength = Int(r.u32(offset + 4))
                offset += 8
                if g == 0xFFFE && e == 0xE0DD { break }
                guard g == 0xFFFE, e == 0xE000, offset + itemLength <= r.count else { throw DicomError.truncated }
                fragments.append(r.data.subdata(in: offset..<(offset + itemLength)))
                offset += itemLength
            }
            return DicomElement(tag: tag, vr: vr == "UN" ? "OB" : vr, fragments: fragments)
        }

        // Sequences. An undefined-length UN element is a sequence encoded as implicit VR.
        if vr == "SQ" || length == undefinedLength {
            var itemCtx = ctx
            itemCtx.explicit = ctx.explicit && vr != "UN"
            itemCtx.stopBeforePixelData = false
            let items = try parseItems(&offset, length: length, ctx: itemCtx, end: end)
            return DicomElement(tag: tag, vr: "SQ", items: items)
        }

        let count = Int(length)
        guard offset + count <= end else { throw DicomError.truncated }
        let value = r.data.subdata(in: offset..<(offset + count))
        offset += count
        if vr == "UN", let known = DicomDictionary.vr(for: tag), known != "SQ" { vr = known }
        return DicomElement(tag: tag, vr: vr, value: value)
    }

    private static func parseItems(_ offset: inout Int, length: UInt32, ctx: Context, end: Int) throws -> [DicomDataset] {
        let r = ctx.reader
        let sequenceEnd = length == undefinedLength ? end : offset + Int(length)
        guard sequenceEnd <= end else { throw DicomError.truncated }
        var items: [DicomDataset] = []
        while offset + 8 <= sequenceEnd {
            let g = r.u16(offset), e = r.u16(offset + 2)
            let itemLength = r.u32(offset + 4)
            offset += 8
            if g == 0xFFFE && e == 0xE0DD { break }
            guard g == 0xFFFE, e == 0xE000 else { throw DicomError.truncated }
            if itemLength == undefinedLength {
                items.append(try parseDataset(&offset, end: sequenceEnd, ctx: ctx, inItem: true))
            } else {
                let itemEnd = offset + Int(itemLength)
                guard itemEnd <= sequenceEnd else { throw DicomError.truncated }
                var itemOffset = offset
                items.append(try parseDataset(&itemOffset, end: itemEnd, ctx: ctx, inItem: true))
                offset = itemEnd
            }
        }
        if length != undefinedLength { offset = sequenceEnd }
        return items
    }
}

/// Serialises a `DicomFile` back to Part 10 format, keeping its transfer syntax.
/// Sequences and items are always written with undefined length, which is valid in every syntax
/// and avoids recomputing nested lengths after edits.
enum DicomWriter {
    static func write(_ file: DicomFile) -> Data {
        var out = Data(count: 128)
        out.append(contentsOf: Array("DICM".utf8))

        var meta = file.meta
        meta[.metaGroupLength] = nil
        if meta[.fileMetaInformationVersion] == nil {
            meta[.fileMetaInformationVersion] = DicomElement(tag: .fileMetaInformationVersion, vr: "OB", value: Data([0x00, 0x01]))
        }
        if let sopClass = file.dataset.string(.sopClassUID), meta[.mediaStorageSOPClassUID] == nil {
            meta.setString(sopClass, for: .mediaStorageSOPClassUID, vr: "UI")
        }
        if let sopInstance = file.dataset.string(.sopInstanceUID) {
            meta.setString(sopInstance, for: .mediaStorageSOPInstanceUID, vr: "UI")
        }
        meta.setString("AXIAL_0_1", for: .implementationVersionName, vr: "SH")

        var metaBody = Data()
        for tag in meta.sortedTags {
            writeElement(meta[tag]!, explicit: true, into: &metaBody)
        }
        var groupLength = Data()
        groupLength.appendLE(UInt32(metaBody.count))
        writeElement(DicomElement(tag: .metaGroupLength, vr: "UL", value: groupLength), explicit: true, into: &out)
        out.append(metaBody)

        writeDataset(file.dataset, explicit: file.isExplicitVR, into: &out)
        return out
    }

    private static func writeDataset(_ dataset: DicomDataset, explicit: Bool, into out: inout Data) {
        for tag in dataset.sortedTags where !tag.isGroupLength {
            writeElement(dataset[tag]!, explicit: explicit, into: &out)
        }
    }

    private static func writeElement(_ element: DicomElement, explicit: Bool, into out: inout Data) {
        let undefined = DicomParser.undefinedLength

        if let items = element.items {
            writeHeader(element.tag, vr: "SQ", length: undefined, explicit: explicit, into: &out)
            for item in items {
                out.appendLE(UInt16(0xFFFE)); out.appendLE(UInt16(0xE000)); out.appendLE(undefined)
                writeDataset(item, explicit: explicit, into: &out)
                out.appendLE(UInt16(0xFFFE)); out.appendLE(UInt16(0xE00D)); out.appendLE(UInt32(0))
            }
            out.appendLE(UInt16(0xFFFE)); out.appendLE(UInt16(0xE0DD)); out.appendLE(UInt32(0))
            return
        }

        if let fragments = element.fragments {
            writeHeader(element.tag, vr: "OB", length: undefined, explicit: explicit, into: &out)
            for fragment in fragments {
                out.appendLE(UInt16(0xFFFE)); out.appendLE(UInt16(0xE000))
                var bytes = fragment
                if bytes.count % 2 == 1 { bytes.append(0) }
                out.appendLE(UInt32(bytes.count))
                out.append(bytes)
            }
            out.appendLE(UInt16(0xFFFE)); out.appendLE(UInt16(0xE0DD)); out.appendLE(UInt32(0))
            return
        }

        var value = element.value
        if value.count % 2 == 1 {
            let zeroPadded = element.vr == "UI" || DicomElement.binaryVRs.contains(element.vr)
            value.append(zeroPadded ? 0x00 : 0x20)
        }
        var vr = DicomParser.validVRs.contains(element.vr) ? element.vr : "UN"
        if explicit && !DicomParser.longVRs.contains(vr) && value.count > 0xFFFF { vr = "UN" }
        writeHeader(element.tag, vr: vr, length: UInt32(value.count), explicit: explicit, into: &out)
        out.append(value)
    }

    private static func writeHeader(_ tag: DicomTag, vr: String, length: UInt32, explicit: Bool, into out: inout Data) {
        out.appendLE(tag.group)
        out.appendLE(tag.element)
        if explicit {
            out.append(contentsOf: Array(vr.utf8.prefix(2)))
            if DicomParser.longVRs.contains(vr) {
                out.appendLE(UInt16(0))
                out.appendLE(length)
            } else {
                out.appendLE(UInt16(length))
            }
        } else {
            out.appendLE(length)
        }
    }
}
