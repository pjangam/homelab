# Missing files from Google Takeout part 019

Part 019 of 23 hit the 5-download limit and could not be retrieved.
Download these by hand from Google Photos (signed in as the admin account,
pjangam2015) and upload them to Immich; the links open each file directly.

`services/immich/takeout_orphans.py` regenerates the first table: it lists
every file the remaining zips have a sidecar JSON for but not the file
itself, and checks Immich for it. Checked 2026-10-22: 15 not in Immich. The 11 photos were re-downloaded and uploaded the same day
(`services/immich/upload_files.sh` from phone-uploads); two had no EXIF
date and got the sidecar's `photoTakenTime` through the API. The 4 GoPro
videos followed (each read through with ffmpeg first); they date
themselves 2018-02-27 from their own metadata, as GOPR0274/0300 do, not the
2018-03-02 Google shows. The two below,
found in Google Photos by name, went up last. **All 17 are in Immich.** The
GoPro `.THM` thumbnails and the Anoushka Shankar concert video, listed here
before, are not needed (THM) or already in Immich (the video).

| Taken (UTC) | File | Google Photos |
|---|---|---|
| 2018-01-27 04:50 | `IMG_20180127_102022.jpg` | <https://photos.google.com/photo/AF1QipMUXVbPCAy6QZQe3wdbmh128eXOahHdI1baf-OC> |
| 2018-01-27 09:17 | `IMG_20180127_144740.jpg` | <https://photos.google.com/photo/AF1QipO88UqO29N8n5LnmEmoZYy_CGYwA039ygT7dIOh> |
| 2018-01-27 09:17 | `IMG_20180127_144748.jpg` | <https://photos.google.com/photo/AF1QipPyd9yVC7NZFRJvsnfApn_LlWj_Wn2AWRoYPosR> |
| 2018-01-27 09:36 | `IMG_20180127_150609.jpg` | <https://photos.google.com/photo/AF1QipORAvdS1iU72vuj_FXJAiDj2tYl-qMBByxe--zM> |
| 2018-01-27 09:37 | `IMG_20180127_150753.jpg` | <https://photos.google.com/photo/AF1QipOzXqn4_OoblrcxsX9WdRnXROaWwNewxaarbmYn> |
| 2018-01-28 18:57 | `IMG_20180129_002749.jpg` | <https://photos.google.com/photo/AF1QipO_17KQILJr-7YE8fGI1kZnp6-fM1eSHJxUT-Ko> |
| 2018-02-17 14:52 | `IMG_20180217_202220.jpg` | <https://photos.google.com/photo/AF1QipNuZZaLT-PUkvfuSYc0Ebg0RhCv6CWTBmGaJKz2> |
| 2018-02-25 16:06 | `25-02-2018 04.04.17.jpg` | <https://photos.google.com/photo/AF1QipNDs7k3_h7fqjslE81lmxKrrHAsymBqk7sPYb-n> |
| 2018-03-02 03:43 | `IMG_20180302_091256.jpg` | <https://photos.google.com/photo/AF1QipM8bsnDgKBO09CF4f0bHiN3ALoppt5k_MwmL7eH> |
| 2018-03-02 05:19 | `IMG_20180302_104938.jpg` | <https://photos.google.com/photo/AF1QipMo7Ix7QVO_dRIvNsb3tTRxIHkpQrKGgKkU3Mc9> |
| 2018-03-02 05:19 | `IMG_20180302_104948.jpg` | <https://photos.google.com/photo/AF1QipMNOXZL-QyWd87aByinfLEN2l-rI1fPeQsn3o7t> |
| 2018-03-02 08:46 | `GP010274.MP4` | <https://photos.google.com/photo/AF1QipOF1USAtmRMUdFheF64mFjNd5PRtg3ELnihj2Pe> |
| 2018-03-02 09:36 | `GOPR0286.MP4` | <https://photos.google.com/photo/AF1QipMVCZ0NTUyA2-0pJI1FEdZr2irmWraM2BN-TTRS> |
| 2018-03-02 10:32 | `GOPR0296.MP4` | <https://photos.google.com/photo/AF1QipO-22qEq5Cyxx68OIoyL_B-mPQYBv97181xcrfL> |
| 2018-03-02 10:40 | `GOPR0297.MP4` | <https://photos.google.com/photo/AF1QipNIzsDCvWPHL_t4-ktljOuKmini1Un7JUwYg78I> |

Two more were on the original list but have no sidecar in the remaining
zips, so there was no link; they were found by searching Google Photos for
the file name.

| Taken (local) | File |
|---|---|
| 2018-01-27 10:40 | `IMG_20180127_104007.jpg` |
| 2018-02-06 06:42 | `IMG_20180206_064207.jpg` |
