# Machine upgrades (whole-house UPS/inverter, second SSD, better machine)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** when purchases are possible, pick the order
- [ ] **Together:** for the UPS/inverter, get the load figure first ("Home power audit" plus a new machine's idle draw)

**Why:** three hardware purchases the user has in mind, collected in one place because they affect each other (a bigger machine changes the UPS load and the drive plan). Nothing can be bought for a few months (user, 2026-10-23), so this records the options and reasoning so far, ready for when it can.
**State:** options researched 2026-10-23 (below), nothing decided or bought. Standing rule for any machine: **no soldered RAM or storage** - the user wants to upgrade parts when needed. That rules out the Mac mini, Ryzen AI Max boxes and most N100/N150 mini PCs. **The network port is now a buying criterion too** (2026-10-28): see "Network port" under part 3. **Thunderbolt is mandatory, and the number of Thunderbolt ports is an important consideration** (user, 2026-11-15): see "Thunderbolt (added 2026-11-15)" under part 3.

#### 1. UPS + inverter for the whole house
Instead of today's DC mini UPSes on just the router and xero (one is dead, see "xero's UPS (CRU12V3A) dead").
- Sizing depends on what it carries: the network stack alone is tiny; fridge, fans and lights are what set the battery size. Use "Home power audit" for the numbers.
- Changeover time matters: xero, the router and the Pi must not reboot during the switch. Pick an inverter with a computer/"UPS mode" (narrow input window, faster switching), and consider keeping the DC mini UPS on xero/router behind it anyway as a gap-free last stage.
- What it changes elsewhere: the wol Pi would stay up in an outage, so its boot-time WoL packet never fires and the reasoning in "Move WoL to an ESP32, put the Pi on the UPS" flips. And with the router on battery, the power watchdog's carrier signal goes blind - it needs the ping signal from "Pi audio move follow-ups" first.
- Prices not researched yet.

#### 2. Second SSD - deferred
Deferred 2026-10-23: the monthly S3 Deep Archive run ("Offsite backup for Immich photo data") now gives an off-box copy, which was the urgent half. A second disk is still the only thing that survives the Kingston dying *without downtime* - see "ZFS mirror" for the parts. A new machine with two M.2 slots and a 2.5" bay changes this: buy the mirror disk with it rather than squeezing a USB enclosure onto xero.

#### 3. Better machine
xero today: Celeron N5105 (4c/4t), one DDR4 SO-DIMM slot (32GB fitted), 1 M.2 + 1 2.5", 1GbE. Load over the week of 2026-10-16 to 10-23: CPU p95 30% (mostly Immich ML on the import backlog, which will end), memory p95 42%, temperature max 90°C. **Capacity is not the problem; heat, one SSD and one RAM slot are.** So a better CPU is mainly for headroom and a possible local LLM, not today's load.

Options (prices 2026-10-23; only the NUC has an Indian listing - the rest are US/EU prices converted plus ~20-30% import/GST, so check a local shop first):

| Machine | CPU | RAM | Drives | Network | Approx. | Notes |
|---|---|---|---|---|---|---|
| Beelink EQ14 | N150 (4/4) | 1x DDR4 | 2 M.2 (2nd x1) | 2x 1GbE | ~₹20-25k est. | barely faster than xero; one RAM slot |
| Lenovo ThinkCentre M75q/M70q Tiny (refurb) | Ryzen 5 PRO / i5-10400T (6/12) | 2x DDR4 | M.2 + 2.5" (by generation) | 1GbE | ~₹15-30k est. | best value: reuses the 32GB DDR4 stick and the Kingston; business-grade cooling |
| ASUS NUC 14 Pro (tall) | Core Ultra 5 125H (14/18) | 2x DDR5, 96GB | M.2 + 2.5" bay | 2.5GbE Intel | ₹46k barebone + ~₹10k RAM | new, warranty, low idle |
| GMKtec K8 Plus | Ryzen 7 8845HS (8/16) | 2x DDR5 | 2 M.2 (unconfirmed) | 2x 2.5GbE | ~₹45-55k est. | overkill; smaller brand |
| Beelink SER8 | Ryzen 7 8745HS (8/16) | 2x DDR5 | 2 M.2 PCIe4 | 2.5GbE | ~₹50-60k est. | overkill; no 2.5" bay |
| Minisforum UM890 Pro | Ryzen 9 8945HS (8/16) | 2x DDR5, 96GB | 2 M.2 PCIe4 | 2x 2.5GbE | ~₹60-70k est. | **OCuLink** for an external GPU later |
| DIY micro-ATX build | e.g. i5-12400/14400 | 4x DDR5 DIMM | 2 M.2 + 4 SATA | 2.5GbE | ~₹50-70k, no GPU | most upgradeable; real PCIe x16 slot |

Sources: [NUC 14 Pro India](https://varietyinfotech.com/product-tag/barebones-mini-pc/), [UM890 Pro](https://liliputing.com/minisforum-um890-pro-mini-pc-with-ryzen-9-8945hs-launches-globally-for-479-and-up/), [SER8](https://www.notebookcheck.net/Excellent-Beelink-SER8-mini-PC-with-AMD-Ryzen-7-8745HS-APU-and-32-GB-RAM-now-discounted-to-lowest-ever-price.1086220.0.html), [EQ14](https://liliputing.com/beelink-eq14-mini-pc-is-powered-by-an-unannounced-intel-n150-processor/), [M75q refurb](https://boingboing.net/2026/10/08/your-monitors-may-take-up-more-space-than-this-tiny-lenovo-pc.html).

**Pick, by goal:** homelab only -> refurb ThinkCentre Tiny (cheapest) or NUC 14 Pro (new). Local LLM as a real goal -> UM890 Pro (OCuLink) or the DIY build. The Ryzen 8000 boxes are several times the CPU the homelab uses.

**Local LLM.** Speed is set by memory bandwidth, not CPU. Rough 4-bit estimates (not measured): DDR4 CPU-only ~5-8 tok/s on a 7-8B model; DDR5 iGPU ~10-15 tok/s on 7-8B, ~3 on 32B; an RTX 3060 12GB ~40-60 tok/s on 7-8B, ~25 on 14B. The fast unified-memory machines (Ryzen AI Max+ 395, Mac mini) have soldered memory, so they are out under the rule above - the upgradeable path to speed is a GPU (in a PCIe slot, or over OCuLink). Best use here: a local conversation agent for HA Assist (speech-to-phrase and piper are already local), summaries, tagging. Not a substitute for Claude on coding. Related: "Local Qwen (Ollama) delegation experiment".

**DIY build.** User has never built one; friends have. Pick parts with them, then build together or let the local shop assemble. Common first-build misses: front-panel header wiring, XMP left off, RAM or cooler not seated. Rough parts (estimates, not checked against Indian prices; RAM prices volatile): CPU i5-12400/14400 ₹12-18k (Quick Sync for Immich), B760 micro-ATX board with 2x M.2/4x SATA/2.5GbE ₹12-16k, 2x16GB DDR5 ₹8-12k, 550-650W 80+ Gold PSU ₹6-8k, case + tower cooler ₹6-9k, 1TB NVMe for the mirror ₹6-8k; later a used RTX 3060 12GB ₹18-25k. xero's DDR4 SO-DIMM does not fit a desktop; the SSDs do. Bigger than a mini PC: a wall shelf, not flat on the wall.

**Why a desktop idles higher** (~20-35W vs xero's ~10W; +10-15W with a GPU): a large PSU is inefficient at 20W load; desktop boards carry power delivery and extra chips sized for 150W+ CPUs; C-states/ASPM often ship disabled; more fans and drives; a GPU idles at 10-15W; and Ryzen 7000/9000 desktop chips idle ~25-30W from their I/O die (AMD "G" APUs and Intel avoid that). Tuned - Intel, no RGB, a quality ~550W PSU, C-states and ASPM on, `powertop --auto-tune`, GPU only once needed - it can land around 15-20W, about ₹60-80/month more than xero. The bigger cost is UPS runtime, which ties back to part 1.

**Network port (added 2026-10-28).** The new patch cable fixed xero's 100Mb/s downshift, and the link is now 1Gbps/Full. That is the ceiling at both ends: xero's onboard Realtek RTL8111/8168 and the Airtel router's port each advertise at most 1000BASE-T. Cat6 would carry 10Gbps, so the cable is not the limit.
- **xero's port is soldered** to the board, so it cannot be swapped. The one upgrade path is **USB**: xero has a USB 3.2 Gen 2 (10Gbps) root hub, so a 2.5GbE USB adapter (Realtek RTL8156B, roughly ₹2-3k; check locally) would work. The Intel 7265 Wi-Fi card on PCIe `02:00.0` is probably a socketed M.2 card, and an M.2 A+E 2.5GbE adapter could replace it in theory, but that is fiddly; prefer USB.
- **Nothing on the LAN needs more than 1Gbps today.** The router is 1GbE, and phones upload to Immich over Wi-Fi, which is slower than 1Gbps. Going faster than 1GbE needs a 2.5GbE switch (or a new router) **and** a 2.5GbE port on the server. Only worth it alongside a new machine, or once something wired (a NAS, a desktop) moves bulk data to xero.
- **For the new machine:** prefer **2.5GbE onboard, Intel i226-V** (Realtek RTL8125 is fine on Linux too), or a free PCIe/M.2 slot for a NIC later. Two ports is a plus (VLANs, or a direct link to a second box). In the table above that favours the NUC 14 Pro, the GMKtec K8 Plus, the SER8, the UM890 Pro and the DIY build (a PCIe slot takes a 10GbE card later). It counts against the ThinkCentre Tiny and the Beelink EQ14 (1GbE only; the Tiny's add-in slot depends on the model).

**Thunderbolt (added 2026-11-15).** Mandatory, and more ports rank higher (user). Raised by the external-GPU question: xero has no Thunderbolt/USB4, so its only eGPU route is an adapter in the Wi-Fi card's M.2 slot (PCIe 3.0 x1, and it takes xero's Bluetooth with it).
- **What it is for:** an external GPU (local LLM, Immich ML), fast external storage, docks; each port is a separate 40Gbps link, so two lets a GPU and a disk run without sharing.
- **USB4 (40Gbps) is Thunderbolt-compatible** on most of these boxes and should count, but check the exact SKU says "Thunderbolt" or "USB4 40Gbps" (USB4 20Gbps does not run eGPUs well). OCuLink is a plus for a GPU, not a substitute for the rule.
- **Effect on the tables below:** NUC 14 Pro (2x TB4) ranks highest among mini PCs; UM890 Pro (2x USB4 + OCuLink) and K8 Plus (USB4, 1 or 2 by listing, + OCuLink) qualify; SER8 qualifies with one. **Out:** ThinkCentre Tiny, Beelink EQ14/S13, Gigabyte BRIX, NUC 14 Essential, AOOSTAR N1 Pro. DIY: only with a board that has Thunderbolt onboard or a TB header for an add-in card (mostly Z790/Z890 or B860 boards with TB4/TB5), check before buying.

**Ports by machine (looked up 2026-10-28).** From reviews and retailer listings, which disagree in places; check the exact SKU's spec sheet before buying. Includes the cheaper N150/N250 boxes from the 2026-10-23 conversation that were not in the table above.

| Machine | LAN | Fast expansion ports | Other ports | RAM rule |
|---|---|---|---|---|
| **xero today** | 1x 1GbE Realtek RTL8111, soldered | none (USB 3.2 Gen 2, 10Gbps) | HDMI | 1x DDR4 SO-DIMM, ok |
| **ASUS NUC 14 Pro** | 1x 2.5GbE (Intel); a LAN/USB expansion lid adds a 2nd | **2x Thunderbolt 4 / USB4 (40Gbps)**, rear | front: USB-C 20Gbps + 2x USB-A 10Gbps; rear: USB-A 10Gbps, USB 2.0, 2x HDMI 2.1 | 2x DDR5 SO-DIMM, ok |
| **ASUS NUC 14 Essential (N250)** | 2.5GbE on some SKUs, 1GbE on others | none confirmed | not confirmed | 1x DDR5 SO-DIMM (16 or 32GB max, sources differ), ok; discontinued at CDW 2025-04 |
| **Gigabyte BRIX GB-BTIP-N250** | 1x 1GbE Realtek RTL8111H | USB-C | DP, HDMI | 1x DDR5 SO-DIMM, ok |
| **Beelink EQ14 (N150)** | 2x 1GbE, or 2x 2.5GbE as a separate variant | USB-C 10Gbps, data only (no DP, no charging) | 2x HDMI, USB-A (counts vary) | 1x DDR4 SO-DIMM, ok |
| **Beelink S13 / S13 Pro (N150)** | 1x 1GbE on the S13; 2.5GbE only on some variants | none | 4x USB 3.2 10Gbps, 2x HDMI | 1x DDR4 SO-DIMM, ok; 2x M.2 2280 (2nd is PCIe 3.0 x1), no 2.5" bay |
| **AOOSTAR N1 Pro (N150)** | **2x 2.5GbE Intel i226-V** | USB-C | USB 3.2, HDMI, DP | **12GB LPDDR5 soldered - out**; storage is one M.2 2242 |
| **Lenovo ThinkCentre M75q Gen 2 Tiny** | 1x 1GbE Realtek RTL8111FP | front USB-C 5Gbps | rear 2x USB 3.2 Gen 1, 2x USB 2.0, HDMI, DP; one optional port (DP/HDMI/serial/USB-C/VGA). No 2nd LAN option listed | 2x DDR4 SO-DIMM, ok |
| **GMKtec K8 Plus** | **2x 2.5GbE Intel i226-V** | **OCuLink (PCIe 4.0 x4)** + 2x USB4 (1 on some listings) | 2x USB-A 10Gbps, HDMI 2.1, DP 2.1 | 2x DDR5 SO-DIMM, ok |
| **Beelink SER8** | 1x 2.5GbE Realtek | 1x USB4 (40Gbps), rear | front USB-C + USB-A 10Gbps; rear USB-A 10Gbps, 2x USB 2.0, HDMI 2.1, DP 1.4 | 2x DDR5 SO-DIMM, ok |
| **Minisforum UM890 Pro** | **2x 2.5GbE Realtek RTL8125** (not Intel) | 2x USB4 (40Gbps); **OCuLink via an M.2 adapter board that uses one of the two M.2 slots** | 4x USB-A, HDMI 2.1, DP 1.4 | 2x DDR5 SO-DIMM, ok |
| **DIY micro-ATX (B760)** | 2.5GbE onboard (board-dependent) | **PCIe x16 slot** (+ x1/x4 slots by board) | as the board | 4x DDR5 DIMM, ok |

What the ports would be used for here:
- **2.5GbE / dual LAN:** faster LAN once the router or a switch does 2.5GbE. A second port allows a separate VLAN for IoT or a direct cable to a second box (a backup target or ZFS replication).
- **Thunderbolt 4 / USB4 (40Gbps):** a 10GbE adapter (~₹10-15k), a fast external drive for the `datapool` mirror, or a slower eGPU. The cleanest way to get past 2.5GbE on a mini PC.
- **OCuLink:** a full-speed eGPU for a local LLM (see Local LLM above); not useful for networking.
- **USB 10Gbps only (N150/N250 boxes, xero):** room for a 2.5GbE USB adapter and nothing faster.
- **PCIe slot (DIY):** takes any NIC (10GbE ~₹5-8k used Intel X520/X540), a GPU, or a SATA/HBA card.

Sources: [NUC 14 Pro (ServeTheHome)](https://www.servethehome.com/asus-nuc-14-pro-review-intel-core), [NUC 14 Pro (Tom's Guide)](https://www.tomsguide.com/computing/desktop-computers/asus-NUC-14-pro-review), [NUC 14 Essential N250 (Scan)](https://www.scan.co.uk/products/asus-rnuc14mnk250-nuc-14-essential-intel-n250-intel-graphics-ddr5-m2-pcie-gen3x4-usb32-gen2-hdmi-dp), [BRIX N250 (Gigabyte)](https://www.gigabyte.com/be/Mini-PcBarebone/GB-BTIP-N250/sp), [EQ14 (Notebookcheck)](https://www.notebookcheck.net/Beelink-EQ14-mini-PC-review-Ready-to-go-HTPC-for-under-200.939127.0.html), [Beelink S13 (iFixit)](https://www.ifixit.com/Device/Beelink_Mini_S13), [AOOSTAR N1 Pro (YPC)](https://www.ypc.co.uk/product/aoostar-n1pro-mini-pc-intel-n150-twin-lakebeat-n95-n100up-to-3-6ghz-with-12g-lpddr5-ram-256g-m-2-2242-ssdmicro-desktop-computer-support-4k-3-displaydual-2-5g-lanwifi5-bt5-for-office-business/), [M75q Gen 2 PSREF](https://psref.lenovo.com/syspool/Sys/PDF/ThinkCentre/ThinkCentre_M75q_Gen_2/ThinkCentre_M75q_Gen_2_Spec.PDF), [K8 Plus (Notebookcheck)](https://www.notebookcheck.net/AMD-powered-mini-PC-with-OCuLink-and-dual-2-5G-Ethernet-now-available-with-30-discount.1105367.0.html), [SER8 (ServeTheHome)](https://www.servethehome.com/beelink-ser8-review-amd-ryzen-7-8845hs-powered-mini-pc/), [UM890 Pro (Liliputing)](https://liliputing.com/minisforum-um890-pro-review-a-versatile-high-performance-and-nearly-silent-mini-pc/).

Moving to any new machine means moving Docker, ZFS (`zfs send` to the new pool), the systemd units, Tailscale identities, the crontab and the static IP `.123`; plan it as its own step when the box is chosen.

#### Log
- 2026-10-28: added "Ports by machine" to part 3: LAN, USB4/Thunderbolt/OCuLink and RAM rule for each candidate, plus the N150/N250 boxes (NUC 14 Essential, BRIX N250, Beelink S13, AOOSTAR N1 Pro - soldered RAM, out) from the 2026-10-23 conversation.
- 2026-10-28: added "Network port" to part 3: xero's link is 1Gbps since the new patch cable, capped by the soldered RTL8111 and the 1GbE router; USB 2.5GbE is xero's only upgrade path; 2.5GbE (Intel i226) is now a buying criterion.
- 2026-10-23: entry created from a conversation: load review (xero has headroom; the Pi is the tight box, see "Move some load to the Raspberry Pi"), machine options, local LLM, DIY build and idle power. Second SSD deferred because the S3 Deep Archive backup is now running.
