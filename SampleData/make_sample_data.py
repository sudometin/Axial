"""Generate synthetic sample data for Axial (no real patient data).

Creates:
  phantom_t1.nii.gz        – 128³ synthetic head phantom, 1.5 mm, RAS+
  dicom_phantom/IM*.dcm    – the same phantom as an axial MR DICOM series with
                             FAKE identifying data, a private tag and burned-in text,
                             for trying out the de-identifier.

The phantom has a bright "lesion" in the LEFT hemisphere, so you can check that
orientation is handled correctly: in neurological view it appears on the screen's left.

Requires: numpy, nibabel, pydicom, pillow
"""
import os
import numpy as np
import nibabel as nib
from PIL import Image, ImageDraw, ImageFont
import pydicom
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, generate_uid, MRImageStorage

HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(42)


def phantom(R, A, S):
    """Synthetic T1-like head. R, A, S are RAS+ coordinates in mm (arrays)."""
    def ell(cx, cy, cz, a, b, c):
        return ((R - cx) / a) ** 2 + ((A - cy) / b) ** 2 + ((S - cz) / c) ** 2 <= 1

    img = np.zeros(R.shape, np.float32)
    img[ell(0, 0, 0, 76, 96, 86)] = 900          # scalp (fat, bright on T1)
    img[ell(0, 0, 0, 70, 90, 80)] = 120          # skull (dark)
    img[ell(0, 0, 0, 65, 85, 75)] = 300          # CSF
    img[ell(0, 0, 0, 62, 82, 72)] = 520          # grey matter
    img[ell(0, 0, 5, 50, 70, 58)] = 720          # white matter
    # lateral ventricles
    img[ell(-10, 5, 12, 6, 28, 14)] = 260
    img[ell(10, 5, 12, 6, 28, 14)] = 260
    # deep grey nuclei
    img[ell(-22, 0, 0, 9, 14, 10)] = 560
    img[ell(22, 0, 0, 9, 14, 10)] = 560
    # midline fissure
    img[(np.abs(R) < 1.2) & ell(0, 0, 10, 62, 82, 62)] = 300
    # lesion in the LEFT hemisphere (R < 0), anterior, superior
    img[ell(-32, 30, 28, 8, 8, 8)] = 1000
    # eyes, so "anterior" is obvious
    img[ell(-32, 78, -40, 12, 12, 12)] = 250
    img[ell(32, 78, -40, 12, 12, 12)] = 250
    img += rng.normal(0, 12, img.shape).astype(np.float32) * (img > 0)
    return np.clip(img, 0, None)


def make_nifti():
    n, dx = 128, 1.5
    coords = (np.arange(n) - (n - 1) / 2) * dx
    R, A, S = np.meshgrid(coords, coords, coords, indexing="ij")
    vol = phantom(R, A, S).astype(np.int16)
    affine = np.diag([dx, dx, dx, 1.0])
    affine[:3, 3] = -(n - 1) / 2 * dx
    img = nib.Nifti1Image(vol, affine)
    img.set_qform(affine, code=1)
    img.set_sform(affine, code=1)
    nib.save(img, os.path.join(HERE, "phantom_t1.nii.gz"))


def make_dicom():
    out = os.path.join(HERE, "dicom_phantom")
    os.makedirs(out, exist_ok=True)
    rows = cols = 192
    dx = 1.0
    slices = 36
    thickness = 4.0
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)

    study_uid, series_uid, frame_uid = generate_uid(), generate_uid(), generate_uid()
    # DICOM patient coordinates are LPS+. Column i → patient left (+x), row j → posterior (+y).
    x_lps = (np.arange(cols) - (cols - 1) / 2) * dx
    y_lps = (np.arange(rows) - (rows - 1) / 2) * dx
    for k in range(slices):
        z = -70 + k * thickness
        J, I = np.meshgrid(y_lps, x_lps, indexing="ij")  # [row, col]
        R, A = -I, -J
        S = np.full_like(R, z)
        pixels = phantom(R, A, S).astype(np.uint16)

        # Burned-in annotation, like an old scanner console screenshot
        canvas = Image.fromarray(pixels.astype(np.int32), mode="I")
        draw = ImageDraw.Draw(canvas)
        draw.text((4, 3), "DOE^JANE  MRN-0042", fill=1023, font=font)
        draw.text((4, rows - 13), "DOB 12-MAR-1984  ST EXAMPLE HOSP", fill=1023, font=font)
        pixels = np.array(canvas).astype(np.uint16)

        meta = FileMetaDataset()
        meta.MediaStorageSOPClassUID = MRImageStorage
        meta.MediaStorageSOPInstanceUID = generate_uid()
        meta.TransferSyntaxUID = ExplicitVRLittleEndian
        meta.ImplementationClassUID = generate_uid()

        ds = FileDataset(None, {}, file_meta=meta, preamble=b"\0" * 128)
        ds.SOPClassUID = MRImageStorage
        ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
        ds.StudyInstanceUID, ds.SeriesInstanceUID, ds.FrameOfReferenceUID = study_uid, series_uid, frame_uid
        ds.Modality = "MR"
        ds.Manufacturer = "Synthetic"
        ds.ManufacturerModelName = "Phantom 3000"
        ds.MagneticFieldStrength = "3"
        ds.RepetitionTime = "2300"
        ds.EchoTime = "2.98"
        ds.SeriesDescription = "T1 MPRAGE AX (synthetic)"
        ds.ProtocolName = "T1_AX"
        ds.SeriesNumber = 3
        ds.InstanceNumber = k + 1
        # --- FAKE identifying data (for testing the de-identifier) ---
        ds.PatientName = "DOE^JANE"
        ds.PatientID = "MRN-0042"
        ds.PatientBirthDate = "19840312"
        ds.PatientSex = "F"
        ds.PatientAge = "040Y"
        ds.PatientAddress = "221B Example Street"
        ds.InstitutionName = "St. Example Hospital"
        ds.ReferringPhysicianName = "HOUSE^GREGORY"
        ds.OperatorsName = "TECH^ALEX"
        ds.AccessionNumber = "ACC778899"
        ds.StudyID = "4711"
        ds.StudyDate = ds.SeriesDate = ds.AcquisitionDate = ds.ContentDate = "20240105"
        ds.StudyTime = "101530"
        ds.StationName = "MR-ROOM-2"
        ds.add_new(0x00091010, "LO", "VENDOR PRIVATE DATA")
        ds.add_new(0x00090010, "LO", "SYNTHETIC CREATOR")
        ref = pydicom.Dataset()
        ref.ReferencedSOPClassUID = MRImageStorage
        ref.ReferencedSOPInstanceUID = generate_uid()
        ds.ReferencedImageSequence = [ref]
        # --- geometry & pixels ---
        ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
        ds.ImagePositionPatient = [float(x_lps[0]), float(y_lps[0]), float(z)]
        ds.PixelSpacing = [dx, dx]
        ds.SliceThickness = thickness
        ds.SpacingBetweenSlices = thickness
        ds.SamplesPerPixel = 1
        ds.PhotometricInterpretation = "MONOCHROME2"
        ds.Rows, ds.Columns = rows, cols
        ds.BitsAllocated, ds.BitsStored, ds.HighBit = 16, 12, 11
        ds.PixelRepresentation = 0
        ds.WindowCenter, ds.WindowWidth = 500, 1000
        ds.BurnedInAnnotation = "YES"
        ds.PixelData = pixels.tobytes()
        ds.save_as(os.path.join(out, f"IM{k + 1:04d}.dcm"), enforce_file_format=True)


if __name__ == "__main__":
    make_nifti()
    make_dicom()
    print("Sample data written to", HERE)
