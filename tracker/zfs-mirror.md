# ZFS mirror (real redundancy for datapool)
**Status:** Parked
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** if the downtime or the one-month backup gap starts to matter, buy a 2TB USB HDD (~Rs 6-7k) as the cheaper first step
- [ ] **Claude:** then set up nightly incremental `zfs send` of `immich-upload` and `immich-db` to it

**Why:** `datapool` is a single disk (`sda`, Kingston SA400 - budget SSD, no power-loss protection, and it reaches 84-87°C on bulk reads against a 70°C rating, so it is more likely than most to fail). Since 2026-10-26 the Immich originals and DB are archived monthly to S3 Deep Archive ("Offsite backup for Immich photo data", Done) and `documents` goes to Dropbox, so a dead disk no longer means lost photos. What a mirror would still add (reassessed 2026-10-30):
- **No downtime:** today a dead Kingston means a 12-48h Glacier restore of ~80GB, then thumbnails, transcodes and ML redone (days on the N5105); a mirror means swap the disk at leisure.
- **The gap since the last monthly archive** (runs on the 1st): photos added since then are only on `datapool` and, usually, still on the phones.
It does not cover fire/theft or deletions - S3 does. `copies=2` heals isolated corruption only.
**State:** not started, Parked: S3 took away the data-loss reason. Both of xero's SATA slots are taken (SA400 + Biwin boot), so a mirror now means a USB enclosure, which is a poor fit for ZFS. More natural when xero is replaced (the "no soldered hardware" rule already asks for 2 drive slots). Nothing planned now. The USB HDD is the local half of the backup plan dropped on 2026-10-26: covers the gap, restores in hours, needs no free bay. The full mirror waits for a box with two drive bays.

#### Parts
```parts
qty | item | est | note
1 | 2.5" SATA SSD, 1TB (960GB or larger) | 5000-8000 | the mirror half for `sda`; must be at least 894.3GB (`zpool attach` refuses a smaller disk). Prefer a DRAM-cached one (Crucial MX500 / Samsung 870 EVO class) over another SA400; price is a guess under the chip-price spike
1 | USB 3 SATA enclosure (UASP) | 500-900 | only if xero has no free internal bay - both its SATA slots look taken (SA400 + Biwin boot); check when the case is open
```

#### Log
- 2026-10-30: reassessed after the S3 archive went live: no longer needed for safety, only for uptime and the one-month gap; stays Parked with the USB-HDD `zfs send` as the cheaper step.
