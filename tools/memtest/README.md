# memtest

RAM testing on xero, after a bit flipped during a hot memtest run on the
pegboard (2026-10-06, `PROJECTS.md` "Check if server RAM is expandable" and
"xero cooling on the Skadis pegboard").

`boot_memtest_once.sh` - boot memtest86+ **once**, straight from the EFI system
partition: no USB stick, no GRUB. Not GRUB because `grub-reboot memtest86+`
with Ubuntu's 7.00 package left a blank screen and needed a full power drain to
recover. This has the firmware load the upstream release directly as a one-shot
`BootNext`, so the next boot returns to Ubuntu by the normal `BootOrder`.
Needs Secure Boot off (memtest86+ is unsigned) - the script checks.

`watch_memtester.sh` - watch a `memtester` run from another machine: once a
minute, the CPU package temperature, the peak so far, how many processes are
left and the failure count. Stops when they finish, at the first failure, or at
`STOP_AT_C` (default 95°C). It does **not** kill memtester - that needs sudo on
xero.
