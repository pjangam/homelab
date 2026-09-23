# 2026-09-23: xero kernel oops during a Rust build - suspect RAM

**What happened:** at 18:49:37 IST xero crashed with a kernel oops and rebooted.
kdump saved a vmcore (`/var/crash/202609231850/`), then the machine came back at
18:51 on its own. After the reboot: `zpool status -x` healthy, all containers
up, no failed units.

**What it was doing:** cross-compiling spotifyd for the wol Pi in Docker
(`projects/spotifyd/build_spotifyd_arm64.sh`, started 18:45:56). This was a
full-core `cargo build --release`, the heaviest sustained CPU and memory load
this box has been given.

**The crash log** (`dmesg.202609231850`, root-only; a readable copy was made
with `sudo install -o pramod ...`):

```
18:49:33  opt cgu.02: segfault ... error 4 in rustc
18:49:37  opt cgu.06: segfault ... error 4 in libgcc_s.so.1
18:49:37  BUG: unable to handle page fault for address: ffffffff8352b2a8
          #PF: supervisor write access in kernel mode
          Comm: runc   RIP: __anon_vma_interval_tree_augment_rotate+0xa
          Call Trace: anon_vma_interval_tree_insert <- __anon_vma_prepare
                      <- wp_page_copy <- do_wp_page <- handle_mm_fault
```

**Reading it:** this is not an out-of-memory kill: there is no OOM message
anywhere. Two unrelated userspace processes segfaulted inside ordinary code
(the compiler and libgcc) within four seconds of each other. The kernel then
followed a pointer in its own memory-management tree (the anon_vma
interval tree) that pointed into kernel text, and died writing to it. So data
was corrupted in three places at once, under the heaviest load the machine has
seen, and no single piece of software explains all three. **Bad or marginal
RAM is the leading suspect.** Other hardware instability (CPU, power, heat) is
possible but less likely.

**Why RAM, and what supports it:**
- **The stick:** the one SO-DIMM is branded "Kingsotin" (`docs/hardware.md`),
  not Kingston - a knock-off brand.
- **Past trouble:**
  - 2026-06-29 kernel soft lockup, blamed then on a ZFS I/O deadlock with an
    orphaned postgres
  - 2026-07-12 ZFS corruption found in `datapool`, attributed to the hard
    power cycle that followed the lockup

  Both are consistent with memory errors too, though neither proves it.
- **The kernel command line already has `intel_idle.max_cstate=1`,** the usual
  workaround for Jasper Lake (N5105) C-state freezes. So instability on this
  box has been worked around before.
- **Temperature:** the package sat at 70°C after the reboot at light load (high
  and crit are 105°C). Warm but not alarming, so heat is not the lead.

**Next step:** run memtest86+ (it is in the Ubuntu GRUB menu) for at least one
full pass, ideally overnight. Any error at all settles it: replace the stick,
and scrub `datapool` afterwards. A clean pass does not fully clear the RAM, but
it moves suspicion to CPU or power.

**Until then:** do not run heavy full-core builds on xero. The spotifyd build
for the Pi moves elsewhere, or runs capped at 2 CPUs and a memory limit.
