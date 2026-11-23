import XCTest
import AppKit
@testable import Axial

final class GzipTests: XCTestCase {
    func testRoundTrip() throws {
        let original = Data((0..<10_000).map { UInt8($0 % 251) })
        let compressed = try Gzip.compress(original)
        XCTAssertTrue(Gzip.isGzipped(compressed))
        XCTAssertEqual(try Gzip.decompress(compressed), original)
    }

    func testCRC32KnownValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }
}

final class NIfTITests: XCTestCase {
    func testWriteReadRoundTrip() throws {
        let voxels = (0..<24).map(Float.init)
        let volume = Volume(name: "test", kind: .nifti, dims: [4, 3, 2], spacing: [2, 3, 4],
                            affine: .diagonal([2, 3, 4], origin: [1, 2, 3]), voxels: voxels)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("axial-test-\(UUID()).nii.gz")
        defer { try? FileManager.default.removeItem(at: url) }

        try NIfTI.write(volume, to: url)
        let loaded = try NIfTI.read(url)

        XCTAssertEqual([loaded.nx, loaded.ny, loaded.nz], [4, 3, 2])
        XCTAssertEqual(loaded.voxels, voxels)
        XCTAssertEqual(loaded.spacing, [2, 3, 4])
        XCTAssertEqual(loaded.world(Voxel(x: 1, y: 1, z: 1)), [3, 5, 7])
    }

    func testCanonicalizeFlipsNegativeAxis() {
        // x axis points left (negative) → reorientation must flip it.
        let voxels: [Float] = [0, 1, 2, 3, 4, 5, 6, 7]
        let affine = Affine(m: [[-1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]])
        let result = Volume.canonicalize(voxels: voxels, dims: [2, 2, 2], affine: affine)
        XCTAssertEqual(result.voxels, [1, 0, 3, 2, 5, 4, 7, 6])
        XCTAssertEqual(result.affine.m[0][0], 1)
        XCTAssertEqual(result.affine.m[0][3], -1)
    }

    func testCanonicalizePermutesAxes() {
        // voxel axis 0 → world y, voxel axis 1 → world x
        let voxels = (0..<6).map(Float.init) // dims [3, 2, 1] … use a 3-D volume
        let dims = [3, 2, 1]
        let affine = Affine(m: [[0, 1, 0, 0], [1, 0, 0, 0], [0, 0, 1, 0]])
        let result = Volume.canonicalize(voxels: voxels, dims: dims, affine: affine)
        XCTAssertEqual(result.dims, [2, 3, 1])
        // old (a, b) → new (b, a); new index = b + 2·a
        XCTAssertEqual(result.voxels, [0, 3, 1, 4, 2, 5])
    }
}

final class DicomTests: XCTestCase {
    static func makeFile(explicit: Bool = true) -> DicomFile {
        var meta = DicomDataset()
        meta.setString("1.2.840.10008.5.1.4.1.1.4", for: .mediaStorageSOPClassUID, vr: "UI")
        meta.setString("1.2.3.4.5.6.7", for: .mediaStorageSOPInstanceUID, vr: "UI")
        meta.setString(explicit ? TransferSyntax.explicitLE : TransferSyntax.implicitLE, for: .transferSyntaxUID, vr: "UI")

        var ds = DicomDataset()
        ds.setString("1.2.840.10008.5.1.4.1.1.4", for: .sopClassUID, vr: "UI")
        ds.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: "UI")
        ds.setString("1.2.3.4.5", for: .studyInstanceUID, vr: "UI")
        ds.setString("1.2.3.4.5.1", for: .seriesInstanceUID, vr: "UI")
        ds.setString("MR", for: .modality, vr: "CS")
        ds.setString("DOE^JANE", for: .patientName, vr: "PN")
        ds.setString("MRN12345", for: .patientID, vr: "LO")
        ds.setString("19840312", for: .patientBirthDate, vr: "DA")
        ds.setString("F", for: .patientSex, vr: "CS")
        ds.setString("General Hospital", for: .institutionName, vr: "LO")
        ds.setString("20240301", for: .studyDate, vr: "DA")
        ds.setString("ACC1", for: .accessionNumber, vr: "SH")
        let privateTag = DicomTag(0x0009, 0x1010)
        ds[privateTag] = DicomElement(tag: privateTag, vr: "LO", value: Data("SECRET VENDOR".utf8))

        var item = DicomDataset()
        item.setString("1.2.3.4.5.6.6", for: .referencedSOPInstanceUID, vr: "UI")
        item.setString("WHO^DR", for: .performingPhysicianName, vr: "PN")
        ds[.referencedImageSequence] = DicomElement(tag: .referencedImageSequence, vr: "SQ", items: [item])

        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: "CS")
        ds.setUInt16(4, for: .rows)
        ds.setUInt16(4, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        var pixels = Data()
        for v in 0..<16 { pixels.appendLE(UInt16(v * 10)) }
        ds[.pixelData] = DicomElement(tag: .pixelData, vr: "OW", value: pixels)
        return DicomFile(meta: meta, dataset: ds)
    }

    func testExplicitRoundTrip() throws { try roundTrip(explicit: true) }
    func testImplicitRoundTrip() throws { try roundTrip(explicit: false) }

    private func roundTrip(explicit: Bool) throws {
        let original = Self.makeFile(explicit: explicit)
        let parsed = try DicomParser.parse(data: DicomWriter.write(original))
        XCTAssertEqual(parsed.transferSyntax, original.transferSyntax)
        XCTAssertEqual(parsed.dataset.string(.patientName), "DOE^JANE")
        XCTAssertEqual(parsed.dataset.uint16(.rows), 4)
        XCTAssertEqual(parsed.dataset[.pixelData]?.value, original.dataset[.pixelData]?.value)
        XCTAssertEqual(parsed.dataset.string(DicomTag(0x0009, 0x1010)), "SECRET VENDOR")
        let items = try XCTUnwrap(parsed.dataset[.referencedImageSequence]?.items)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].string(.referencedSOPInstanceUID), "1.2.3.4.5.6.6")
    }

    func testPixelDecoding() throws {
        let file = Self.makeFile()
        let format = try PixelFormat(file.dataset)
        let values = try DicomPixelDecoder.frame(file.dataset[.pixelData]!.value, format: format, index: 0)
        XCTAssertEqual(values, (0..<16).map { Float($0 * 10) })
    }

    func testSignedPixelsAreSignExtended() throws {
        var file = Self.makeFile()
        file.dataset.setUInt16(1, for: .pixelRepresentation)
        var pixels = Data()
        for _ in 0..<16 { pixels.appendLE(UInt16(0x0FFF)) } // -1 in 12 bits
        file.dataset[.pixelData]?.value = pixels
        let values = try DicomPixelDecoder.frame(pixels, format: PixelFormat(file.dataset), index: 0)
        XCTAssertEqual(values.first, -1)
    }
}

final class AnonymizerTests: XCTestCase {
    private func options() -> AnonymizationOptions {
        var o = AnonymizationOptions()
        o.projectKey = "unit-test-key"
        o.scanBurnedInText = false
        return o
    }

    func testRemovesAndReplacesIdentifiers() throws {
        let anonymizer = Anonymizer(options: options())
        let result = anonymizer.anonymize(DicomTests.makeFile(), scan: .none)
        let ds = result.file.dataset

        XCTAssertTrue(ds.string(.patientName)!.hasPrefix("SUBJ-"))
        XCTAssertEqual(ds.string(.patientName), ds.string(.patientID))
        XCTAssertEqual(ds.string(.patientBirthDate), "")
        XCTAssertEqual(ds.string(.accessionNumber), "")
        XCTAssertNil(ds[.institutionName])
        XCTAssertNil(ds[DicomTag(0x0009, 0x1010)])
        XCTAssertEqual(ds.string(.patientSex), "F") // demographics kept by default
        XCTAssertEqual(ds.string(.patientIdentityRemoved), "YES")

        let study = try XCTUnwrap(ds.string(.studyDate))
        XCTAssertNotEqual(study, "20240301")
        XCTAssertEqual(study.count, 8)

        let sop = try XCTUnwrap(ds.string(.sopInstanceUID))
        XCTAssertTrue(sop.hasPrefix("2.25."))
        XCTAssertLessThanOrEqual(sop.count, 64)
        XCTAssertEqual(result.file.meta.string(.mediaStorageSOPInstanceUID), sop)
        XCTAssertEqual(ds.string(.sopClassUID), "1.2.840.10008.5.1.4.1.1.4") // standard UIDs untouched

        let item = try XCTUnwrap(ds[.referencedImageSequence]?.items?.first)
        XCTAssertEqual(item.string(.referencedSOPInstanceUID), anonymizer.remapUID("1.2.3.4.5.6.6"))
        XCTAssertNil(item[.performingPhysicianName])
    }

    func testDeterministicAcrossInstances() {
        let a = Anonymizer(options: options()).anonymize(DicomTests.makeFile(), scan: .none)
        let b = Anonymizer(options: options()).anonymize(DicomTests.makeFile(), scan: .none)
        XCTAssertEqual(a.pseudonym, b.pseudonym)
        XCTAssertEqual(a.file.dataset.string(.studyInstanceUID), b.file.dataset.string(.studyInstanceUID))
        XCTAssertEqual(a.file.dataset.string(.studyDate), b.file.dataset.string(.studyDate))
    }

    func testAnonymizedFileStillParses() throws {
        let result = Anonymizer(options: options()).anonymize(DicomTests.makeFile(explicit: false), scan: .none)
        let parsed = try DicomParser.parse(data: DicomWriter.write(result.file))
        XCTAssertEqual(parsed.dataset.string(.patientName), result.pseudonym)
    }

    func testDateShiftHandlesLeapYear() {
        XCTAssertEqual(Anonymizer.shiftDate("20240301", days: -1), "20240229")
        XCTAssertEqual(Anonymizer.shiftDate("20240301120000.000", days: -1), "20240229120000.000")
        XCTAssertNil(Anonymizer.shiftDate("garbage", days: 3))
    }

    func testDecimalConversion() {
        XCTAssertEqual(Anonymizer.decimalString([0x01, 0x00]), "256")
        XCTAssertEqual(Anonymizer.decimalString([0xFF, 0xFF, 0xFF, 0xFF]), "4294967295")
        XCTAssertEqual(Anonymizer.decimalString([0, 0]), "0")
    }

    /// Draws large text into an 8-bit image and checks that Vision finds and masks it.
    func testBurnedInTextIsMasked() throws {
        let width = 512, height = 256
        let space = CGColorSpaceCreateDeviceGray()
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: "DOE JANE 1984", attributes: [
            .font: NSFont.systemFont(ofSize: 44, weight: .bold),
            .foregroundColor: NSColor.white,
        ]).draw(at: CGPoint(x: 20, y: 170))
        NSGraphicsContext.restoreGraphicsState()
        let bytes = Data(bytes: try XCTUnwrap(ctx.data), count: width * height)

        var ds = DicomDataset()
        ds.setUInt16(UInt16(height), for: .rows)
        ds.setUInt16(UInt16(width), for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds[.pixelData] = DicomElement(tag: .pixelData, vr: "OB", value: bytes)

        let regions = try BurnedInText.scrub(&ds, frames: .all)
        let rects = try XCTUnwrap(regions[0])
        XCTAssertFalse(rects.isEmpty)
        let masked = try XCTUnwrap(ds[.pixelData]?.value)
        XCTAssertLessThan(masked.filter { $0 > 128 }.count, bytes.filter { $0 > 128 }.count / 10)
    }
}
