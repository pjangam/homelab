# Bhakti's Google Takeout into Immich
**Status:** Active
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** delete the Mac copies of `-2-001`/`-2-002` (both tested ok on xero 2026-11-14)
- [ ] **Together:** sort out storage first: her ~248 GiB of originals fit only at `copies=1` and with the zips off `datapool` (219G free with them, ~496G without), so after the backup HDD (Black Friday, 2026-11-27) is running, see "datapool storage headroom"
- [ ] **Pramod:** before importing, have Bhakti make an Immich API key (all permissions), add it to `.env` as `IMMICH_API_KEY_BHAKTI`, and fix her misspelt name `Bkahti` under Administration -> Users
- [ ] **Together:** import with `import_takeout.py`, following "Running a whole-library import" in `services/immich/README.md` (`--dry-run`, then `--limit 5`, then all)
- [ ] **Claude:** check it with `verify_takeout.py --owner`, re-measure `datapool` for "datapool storage headroom"
- [ ] **Pramod:** only then decide on Google One

**Why:** Bhakti's photos live in Google Photos on her account, on the Rs 150/month Google One plan. Moving them into Immich (and so into the Deep Archive copy) is the precondition for dropping that plan; see the cost note under "Offsite backup for Immich photo data".
**State:** export ready 2026-11-08: 279.36 GB in 32 parts. All 32 parts on xero 2026-11-14 (277G in `/datapool/google-takeout/bhakti/`), all pass `unzip -t`; importing once storage is sorted. Importer built and tested (below). Her Immich user exists, named `Bkahti`, holding 1 asset. The archive dedupes photos shared between the two libraries by SHA-1.

#### Log
- 2026-10-30: entry created, split out of "Immich re-enablement".
- 2026-11-08: export started with 10 GB parts. Wrote `import_takeout.py`, because `upload_from_takeout.sh` was built for small top-ups (skips repeated filenames, extracts everything first, reads no JSON) and immich-go is still broken on Immich 3.3. `verify_takeout.py` gained `--dir` and `--owner`: without an owner, a photo already in Pramod's library counted as imported. Tested against a fake Immich, and on the live 3.3.5 server with a photo already in Pramod's library (answered "duplicate", nothing stored). Album creation has only run against the fake.
- 2026-11-08: export is 279.36 GB in 32 parts. Worst case on disk at `copies=2` is ~558G of originals plus ~400G of transcodes against 555G free, and the zips need up to 279G more while importing. Decided: download now so the links do not lapse, import after storage is sorted. Bhakti keeps Google Photos and Google One until the import is verified.
- 2026-11-08: `takeout_download.sh` failed against real Google: exported cookies, even with `accounts.google.com`'s, end at the interactive sign-in page. Replaced by `takeout_browser.sh`, a Chromium container on xero viewed over an SSH tunnel; she signs in there and files save straight to `datapool`. Zips are on the single-copy root dataset, at the user's request.
- 2026-11-10: 30 parts downloaded through the xero browser, 5-8 at a time at ~4.8 MB/s total; `watch_takeout.sh` reported each finish, `test_takeout_zips.sh` tested all 30 ok (paced by SSD temperature, peaked ~61C). No part needed a second attempt except `-2-003`, whose first try stalled on 2026-11-08.
- 2026-11-14: `-2-001`/`-2-002` copied from the Intel Mac (landed in `~/Downloads`, moved to datapool), both ok. Ran `takeout_browser.sh stop` (her signed-in profile deleted) and removed `~/takeout-url.txt`.
- 2026-11-14: dry run (report kept next to the zips, not in git): 23,236 files to import, 266.1 GB; 57 in Google's bin left out; 194 favourites, 1,723 archived, 11 albums; every file matched its JSON. By extension: 22,380 photos = 24.4 GiB, 913 videos = 223.4 GiB, so transcodes depend on her video codecs. Thumbnails ~7G on the boot disk (34G free).
