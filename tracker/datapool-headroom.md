# datapool storage headroom
**Status:** Active
**Priority:** P3
**Cost:** ₹16,000-17,000 (the backup HDD)
**Effort:** ~2 weekends (HDD pool + syncoid, then the `copies=1` rewrite)

#### Open items
- [ ] **Pramod, with the next batch of cleanup commands:** destroy `datapool/recovered-media` (851M; both videos are in Immich, SHA-1 checked 2026-10-26, and in Deep Archive): `sudo zfs destroy -nv datapool/recovered-media`, then without `-nv`
- [ ] **Together, when the HDD arrives:** serial on Seagate's warranty page, SMART long test, `f3probe`, make it its own ZFS pool (ZFS native encryption, key file on the boot disk + copy in Vaultwarden), stays plugged in but exported between runs (each run imports, sends, exports, then spins the disk down itself with `sdparm --command=stop` so a power cut finds the heads parked; watch SMART `Power-Off_Retract_Count`; ~0.5W idle; unplugging saves only ~Rs 30/year, S3 is the offline copy; decided 2026-11-17), check the UPS margin against the watchdog's 10 min; set up sanoid/syncoid: originals, albums, documents and phone uploads hourly but skipped when `written` is 0, `immich-db` every 6 hours, transcodes and thumbs not copied. Not a mirror: it would slow every write and copy deletions instantly
- [ ] **Claude:** monthly scrub of the backup pool and an alert when a backup run fails
- [ ] **Together, with the backup:** rewrite the originals at `copies=1` (decided 2026-11-10, reverses 2026-11-02; frees ~80G) in this order: rsync into a new `copies=1` dataset (old one kept), first full send of the new one to the HDD + clean scrub, then destroy the old dataset and its snapshots. xero's zfs userland is 2.2.2, so no `zfs rewrite`
- [ ] **Pramod, around Black Friday (2026-11-27):** buy the Seagate Portable 4TB (STGX4000400) on Amazon, home delivery, ~Rs 16,949 from Clicktech with the Amazon Pay ICICI card; check the page says India/APAC warranty first (STGX is Seagate's global model). See Log 2026-11-17 for the comparison
- [ ] **Together, before Bhakti's import:** decide where the zips sit while importing: on the backup HDD, or deleted one by one as their photos are verified (see "Space math" below)
- [ ] **Claude:** after the import, re-measure (`zpool list datapool`, `zfs list -o name,used,logicalused -r datapool`)
- [ ] **Together:** then decide between the options below

**Why:** raised 2026-11-02: the user expected to run out of storage soon and was pricing bigger SSDs (4TB 870 EVO - expensive under the chip-price spike).
**State:** measured 2026-11-02, no space problem yet. `datapool` (Kingston SA400, 888G): **302G used (33%), 586G free.** Every dataset has `copies=2` (self-healing on one disk), so data takes twice its size: `immich-upload` is 281G on disk for 143G of data. Of that 143G, about **56G is Immich's transcoded videos** (`encoded-video/`) and ~6G thumbnails (`thumbs/`), both regenerable from the originals but stored twice too. New photos look like tens of GB of data a year, so roughly 50-100G/year on disk including transcodes - **several years of runway** (rough estimate, not a measured trend). Bhakti's Takeout, measured 2026-11-08, is 279.36 GB in zips (unique size not yet known, albums repeat files): at `copies=2` it does not fit, so this entry now blocks her import.

#### Space math for Bhakti's import (2026-11-19)
Measured with `zfs list -r -o name,used,logicalused,copies datapool`; her size from the 2026-11-14 dry run (`/datapool/google-takeout/bhakti/dry-run-2026-11-14.txt`).

| What | Data | On disk | Why |
|---|---|---|---|
| Pramod's originals | ~82G | ~162G | `copies=2` |
| Pramod's transcodes (`encoded-video`) | 58G | 58G | `copies=1` |
| **Pramod's Immich total** | 140G | **219G** | |
| Everything else (albums, phone uploads, docs, db, recovered) | ~11G | ~20G | `copies=2` |
| Bhakti's zips (root dataset) | 279G | 279G | deleted after her import is verified |
| Bhakti's originals | 248 GiB (266 GB; 223 GiB of it 913 videos) | 248G or 496G | `copies=1` or `2` |
| Bhakti's transcodes | ? | ~50-100G (guess) | depends on her video codecs |

**After the import, zips deleted:**

| Scenario | Pramod | Bhakti | Others | Total | Of 888G |
|---|---|---|---|---|---|
| Originals at `copies=2` (today) | 219 | 496 + 50-100 | 20 | 785-835G | 88-94%: too full |
| Originals at `copies=1` (decided 2026-11-10) | 140 | 248 + 50-100 | ~15 | 450-500G | 51-56%: fine |

- **`copies=2` is the lever, not the other folders:** albums, phone uploads, docs etc. are only ~20G on disk; moving them off changes nothing.
- **ZFS slows past ~80% full**, so the `copies=2` case does not work even though it technically fits.
- **Tightest point is during the import**, zips and imported files both on disk: ~342G free now + ~80G from the `copies=1` rewrite = ~420G, minus 248G + 50-100G = ~70-120G left (87-92% full). Works, barely.
- **To ease it:** copy the zips to the backup HDD and import from there, or delete each zip once its photos are verified in Immich.
- **Order stays:** backup HDD -> `copies=1` rewrite of the originals -> Bhakti's import.
- **Unknowns:** her transcode size, and photos shared between the two libraries (stored once, so her real size may be a little lower). Re-measure after the import (open item above).

#### Options (cheapest first)
1. **Transcodes and thumbnails to `copies=1`** - free, frees ~60-70G. **Script ready (2026-11-02): `services/immich/split_regenerable.sh`** (`check` / `run` / `finish` / `rollback`; dry-tested, not yet run). Best right after the `@pre-v3.3.5` snapshots are destroyed (mid-November), in winter. Put `encoded-video/` and `thumbs/` on their own dataset with `copies=1` (originals stay at `copies=2`); needs a short Immich stop and sudo for the `zfs create` and the move. If a block of a transcode rots, Immich regenerates it.
2. **Check the Takeout size before importing** - decides whether 1. is enough.
3. **Bigger storage with the next machine** - see "Purchases" (better machine) and "ZFS mirror". **xero cannot take NVMe** (checked 2026-11-02): its M.2 drive slot is SATA (the Biwin boot disk is on the SATA controller), and the N5105's two PCIe root ports are used by the Realtek NIC and the Intel 7265 WiFi card. On xero, more space means a 2.5"/M.2 SATA SSD or USB.
- **Keep `copies=2` on the originals even with S3 (decided 2026-11-02).** They cover different failures: S3 (monthly, Deep Archive) covers the whole disk dying, fire/theft and deletions; `copies=2` repairs bad blocks on the one SSD by itself at scrub or read time, and covers the up-to-a-month of new photos not yet in S3. Without it ZFS still detects a bad block (checksums), but repair becomes a manual Deep Archive restore (12-48h retrieval). So: originals (`library/`), `immich-db`, `documents`, `albums`, `phone-uploads` stay at `copies=2` (~80-90G of data); only the regenerable transcodes/thumbs go to `copies=1` (option 1). Dropping `copies=2` on the originals too is the last resort if space gets tight (~80G more). Changing `copies` affects new writes only - existing data must be rewritten (moved into a new dataset) to free space.

- **Price timing (checked 2026-11-02):** forecasts agree SSD/RAM prices stay high or flat through early 2027 (NAND still rising in Q4 2026); relief mainly in **H2 2027** as new supply lands, still ~3x the 2023 low. Nothing here is needed before then, so do not buy storage or a new machine at peak prices; aim for H2 2027 or later. Sources: [storageswiss](https://storageswiss.com/2026/05/06/memory-and-flash-prices-not-coming-down/), [Club386 / TrendForce](https://www.club386.com/ssd-pricing-chaos-could-end-2027/), [storagediskprices](https://storagediskprices.com/ssd-price-history/).

4. **If buying an SSD anyway:** Samsung 870 EVO and Crucial MX500 go to 4TB (870 QVO to 8TB, but QLC: slow on long writes, half the endurance); Kingston KC600 is a cheaper DRAM-cached TLC option. Avoid DRAM-less ones (BX500, SA510, NS100, another SA400). A mirror is only as large as its smaller disk, so 4TB usable with redundancy means two 4TB drives (attach one, swap out the Kingston for the second, `autoexpand`). Prices not checked locally.

#### Log
- 2026-11-02: entry created; measured, options recorded, parked until after Bhakti's Takeout.
- 2026-11-08: `split_regenerable.sh run` done: `encoded-video` and `thumbs` are now `copies=1` datasets. `finish` and the snapshot destroy still to come, so the space is not back yet.
- 2026-11-08: measured the database at 507 MB and thumbnails at 5.8G for 18,991 items. Wrote `move_thumbs_to_boot.sh` at the user's request (dry-tested, not run). Weighed a USB HDD: a 2.5" 4-5TB drive is generally SMR, a 3.5" needs its own 12V.
- 2026-11-08: storage research, prices as seen that day (many listings stale):
  - **Plan:** Kingston stays live, HDD on USB takes a nightly `zfs send` of originals, database, albums, documents and phone uploads, S3 stays off-site. Not a mirror: that would cap at 888G and tie Immich to USB. SMR is acceptable for this role only.
  - **4TB HDD:** Seagate Expansion Desktop Rs 15,199-18,249, WD My Passport Rs 16,999, CMR internal (WD Purple) Rs 18-19k plus a powered enclosure. 8TB One Touch Desktop Rs 27,499.
  - **Abroad:** not cheaper. US about $188+, Sweden 2,122 kr (Rs 20,200). Would need under about $129 or 1,280 kr or EUR 116 to save Rs 3,000. Seagate India reportedly refuses foreign-bought drives.
  - **4TB SATA SSD:** no trustworthy Indian price found. 870 EVO listings at Rs 15-21k are not believable (launched at Rs 43,999 in 2021), others Rs 53k+. Fanxiang S101 (Rs 36,600 in Sweden) rejected: flash type, DRAM and endurance unknown. Used enterprise SATA is the option if the Kingston fills, after the backup exists.
  - **M.2 SATA:** Rs 19,000/TB or worse, not a storage path. xero's boot slot takes only M.2 SATA, not NVMe.
  - **Trend:** NAND shortage, sources disagree on relief in H2 2027.
- 2026-11-10: **decided (user):** Kingston at 1 copy + the 1TB Samsung SD card (scheduled `zfs send`) + S3 Deep Archive, because the wishlist total is too high. HDD or SSD only for a crazy Black Friday deal or a big price drop in early 2027. Revives the SD-card copy that "Offsite backup for Immich photo data" set aside on 2026-10-26.
- 2026-11-10: `split_regenerable.sh finish` done, `.old` copies deleted. Thumbnails moved to the boot disk with `move_thumbs_to_boot.sh` (34,478 files, 5.7G, ~2 minutes of downtime), `finish` run after the user's spot-check. Immich's storage check passes; boot disk 36G free. The `@pre-v3.3.5` snapshot still holds the old blocks.
- 2026-11-14: the 1TB Samsung SD card cannot be found, so the backup copy waits for an HDD bought at Black Friday (2026-11-27). Bhakti's thumbnails checked against her dry run: ~7G for 23k files, 34G free on the boot disk. Transcodes to the boot disk ruled out: 57G today vs 34G free.
- 2026-11-17: decided (user): buy the backup HDD now instead of waiting for Black Friday. Prefer a USB-powered Portable (on xero's mini UPS through USB); pool stays plugged in, exported and spun down between hourly runs, ZFS-encrypted.
- 2026-11-17: compared listings (prices that day): Seagate One Touch Portable 5TB (metal, Rescue 3y) Rs 18,999 on Flipkart was best per TB, but Flipkart does not deliver to home and office delivery is awkward. Decided (user): Seagate Portable 4TB STGX4000400 on Amazon, Rs 16,949, sold by Clicktech, home delivery, Amazon Pay ICICI cashback (~Rs 16,100 effective), around Black Friday. Skipped: Seagate Expansion Desktop 4TB (own adapter, no UPS), WD My Passport 4TB Rs 19,000, WD Elements 4TB Rs 17,258-20,549, One Touch on Amazon Rs 21,499 (4TB) / 25,299 (5TB), IronWolf ST4000VN006 Rs 24,879 (internal 3.5", imported).
- 2026-11-19: destroyed `@pre-v3.3.5` and `@pre-v3.4.1` on `immich-upload` and `immich-db` (127G + 880M back). Only `@pre-v3.4.2` left. `datapool` now 519G used (58%), 342G free: `google-takeout/bhakti` 279G (root dataset), `immich-upload` 219G (58G of it `encoded-video`), `phone-uploads` 12G, `albums` 6G, `immich-db` 950M, `recovered-media` 851M, `documents` 449M. Frag 37% is free-space fragmentation, harmless on an SSD; ZFS has no defrag, so the number to watch is staying under ~80% full.
- 2026-11-19: the first destroy failed with `dataset is busy`: `immich_server` had auto-mounted `.zfs/snapshot/pre-v3.3.5` inside its container (seen in `/proc/<pid>/mountinfo`, not in the host's `mount`). `docker restart immich_server` released it. Cause not yet found.
