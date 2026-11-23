# Sample data

Everything here is **synthetic**. No real person's data is included.

| File | What it is |
|---|---|
| `phantom_t1.nii.gz` | 128³ head phantom at 1.5 mm, RAS+ orientation |
| `dicom_phantom/` | The same phantom as a 36-slice axial MR series, with **fake** identifiers (`DOE^JANE`, `MRN-0042`, a hospital, physicians, a private tag) and text burned into every image |

The phantom has a bright spot in the **left** hemisphere. In Axial's default (neurological) view it
appears on the left of the screen in both files, which is a quick check that orientation handling works.

To regenerate: `pip install numpy nibabel pydicom pillow && python3 make_sample_data.py`
