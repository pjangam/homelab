# xero boot SSD health check
**Status:** Done

**Why:** xero's boot drive is a budget Biwin NP202 128GB (DRAM-less class, no power-loss protection), and it has taken several uncontrolled power losses: the 2026-07 crash, a UPS that died under load on 2026-10-08, and frequent short power cuts since, with xero running off its own UPS for now. Cheap SSDs can corrupt or wear early under repeated sudden cuts, and nothing watches it.
**Outcome (2026-10-09):** checked - healthy. SMART overall PASSED, no errors, wear about 1% (details below).
- To watch: Power-Off_Retract_Count 439 against 469 power cycles - likely unclean power-offs, possibly inflated by normal shutdowns the drive counts too; re-read in a few months and compare the two.
- Left open: a self-test (`smartctl -t short /dev/sdb`), the same check on `sda`, and a SMART check in `healthcheck.sh` (optional).

#### SMART readings (2026-10-09)
The boot disk is `/dev/sdb` (SATA, M.2; model BIWIN CNF82NS1F00-128, fw T0910A0R); `datapool` is `/dev/sda`. `smartmontools` installed with `--no-install-recommends` (skips postfix). Overall PASSED, error log empty; reallocated / pending / uncorrectable sectors, program and erase fails, CRC errors all 0; reserve space 100. Wear about 1%: vendor attributes read as avg erase count 16 (167) of a rated 2000 (168), life left 100 (169) - consistent with Total_LBAs_Written 70754 being ~2TB in 32MiB units. 9665 power-on hours, 38°C.

#### Original plan (the old Next step, now done)
On xero, `sudo smartctl -a /dev/nvme0` (or `/dev/sda`, whichever `findmnt /` says is the boot disk; `apt install smartmontools` if missing). Read "Unsafe Shutdowns", "Media and Data Integrity Errors", "Percentage Used" and "Available Spare". If they look fine, consider adding a SMART check to `healthcheck.sh` (needs a sudoers rule for smartctl, like the power watchdog's for shutdown). If not, plan a replacement - and check that `new_machine_setup.sh` plus the backups really rebuild xero.
