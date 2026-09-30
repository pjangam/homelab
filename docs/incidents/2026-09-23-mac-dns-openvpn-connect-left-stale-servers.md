# MacBook DNS kept breaking: OpenVPN Connect left its servers in `Setup:`

**Date found:** 2026-09-23 (5th occurrence; the first four were 2026-08-28,
2026-09-10, 2026-09-16, 2026-09-22). A 6th followed on 2026-09-28 and settled
what this round left open - see the 2026-09-30 section at the end, which also
corrects two things below: the `Setup:` key is written only into configd's
in-memory store and never to disk, and OpenVPN Connect does usually restore it.
**Machine:** `sonalis-macbook-pro`, the employer-owned M2 - the host clawlight
calls `mac`
**Symptom, every time:** `en0` resolves against `192.168.0.2` + `192.169.0.2`.
Neither is on this LAN (192.168.1.0/24), and the second is a 168->169 typo
landing in publicly routable space, so queries *hang* instead of failing fast -
which is why it reads as "the internet is slow" rather than "DNS is down".

## What found it

`tools/network/mac-dns-recorder.sh`, installed on this Mac 2026-09-22 13:55 IST
for exactly this purpose. It polls every 20s and snapshots only on change, so
for the first time the evidence survived instead of being destroyed by the
repair. The break it caught began **2026-09-22 19:56:16 IST**, about six hours
after the recorder went in.

## Root cause

**OpenVPN Connect writes the DNS servers into the persistent `Setup:` layer and
does not restore them on disconnect.**

The Wi-Fi service's `Setup:` DNS dictionary
(`Setup:/Network/Service/A02B9918-F5FF-4C22-ADC2-D8052BE73543/DNS`, whose
`UserDefinedName` is `Wi-Fi`) holds:

```
<dictionary> {
  OpenVPNConnectOrigSearchDomains : OpenVPNConnectDeleteValue
  OpenVPNConnectOrigSearchOrder : OpenVPNConnectDeleteValue
  OpenVPNConnectOrigServerAddresses : OpenVPNConnectDeleteValue
  SearchOrder : 5000
  ServerAddresses : <array> {
    0 : 192.168.0.2
    1 : 192.169.0.2
  }
}
```

The three `OpenVPNConnectOrig*` keys are OpenVPN Connect's own backup of what
was in this dictionary before it took it over, and the sentinel
`OpenVPNConnectDeleteValue` means "there was nothing here - delete the key when
you put it back". So OpenVPN Connect correctly recorded that Wi-Fi had no
manual DNS, wrote its own pair in, and then never performed the restore. Its
agent is running on this machine
(`/Library/Frameworks/OpenVPNConnect.framework/.../ovpnagent`, plus a
`/opt/homebrew/opt/openvpn/sbin/openvpn --config`, with the corporate tunnel on
`utun18`).

## Why a month of investigation missed it

- **The project was looking in the wrong layer.** Every earlier round concluded
  the bad pair "lives at the runtime (`State:`) layer, not the persistent
  (`Setup:`) one, because `networksetup -getdnsservers` shows no manual
  override". That conclusion was drawn from `networksetup` alone, and
  `networksetup -getdnsservers Wi-Fi` **still** answers *"There aren't any DNS
  Servers set on Wi-Fi"* while `scutil` shows the `Setup:` dictionary above
  populated. The two tools disagree, and the one that was trusted is the one
  that is wrong.
- **The repair hid it.** `fix_macbook_dns.sh` step 3, the
  `tailscale set --accept-dns` toggle, makes tailscaled rewrite the resolver
  config so the bad pair stops being *used*. It never clears the `Setup:` key,
  so the entry survives every repair and comes back the next time OpenVPN runs.
  Step 1, "clear the Wi-Fi override", was recorded as a no-op for four
  occurrences - because it asks `networksetup`, which cannot see it.
- The suspects on the list - a second DHCP server on the TP-Link extender, a
  stale lease, MDM configuration profiles - were all plausible and all wrong.
  MDM was close: this *is* corporate software on a managed Mac, but it is the
  VPN client, not a profile.

## The 192.169 typo

It is not a macOS or DHCP artefact: it is whatever the corporate OpenVPN
profile pushes, so the fat-finger is in that profile (or in the server config
behind it). Worth reporting to whoever maintains it - every client on that VPN
is resolving against a publicly routable address that is not theirs.

## Fix

Clear the key that OpenVPN Connect should have cleared:

```bash
sudo networksetup -setdnsservers Wi-Fi empty
```

Verify with `scutil` rather than `networksetup`, since `networksetup` reported
the broken state as clean throughout:

```bash
scutil <<< "show Setup:/Network/Service/A02B9918-F5FF-4C22-ADC2-D8052BE73543/DNS"
```

This is a repair, not a cure - the next OpenVPN session can write it again.
Leave `tools/network/mac-dns-recorder.sh` running to confirm whether it does,
and whether it is a connect or a disconnect that leaves it behind.

## Later the same day

**The typo'd server is dead even while the VPN is connected.** OpenVPN pushes
explicit `/32` routes for both DNS servers into the tunnel
(`192.168.0.2/32` and `192.169.0.2/32` via `172.27.240.1` on `utun18`), so
packets to `192.169.0.2` do go somewhere - nothing answers. `dig @192.168.0.2`
returns in ~300 ms; `dig @192.169.0.2` times out. The pair is therefore
half-broken *whenever the VPN runs*, not only after a disconnect, and every
lookup that falls to the second server eats a full timeout. Measured effect:
fresh system lookups took ~600 ms with the tunnel up versus ~80 ms without it.

**Not every disconnect strands the servers.** A router restart dropped the
tunnel mid-session; `utun18` lost its address and the `Setup:` dictionary was
left genuinely empty (`<dictionary> { }`), the bad pair gone, the resolver back
to `192.168.1.123` on `en0`. So the failure is conditional on something about
*how* the session ends, which is the thing the recorder should now be aimed at.

**The tunnel is split, not full.** The default route stays on `en0` via the
home gateway; only `10.0.0.0/16`, `10.80.0.0/15`, `172.27.224.0/20`,
`172.27.240.0/20`, `192.168.0.0/15` and the two DNS `/32`s go into `utun18`.
So the corporate resolver sees every name looked up while connected, but the
traffic itself does not traverse the tunnel. Worth noting that the pushed
`192.168.0.0/15` covers the whole home range in principle and only misses
because the on-link `192.168.1.0/24` route is more specific - anything moved to
`192.168.0.x` would silently disappear into the corporate tunnel.

## Side effect worth knowing

While DNS is broken and Tailscale is stopped, this Mac cannot resolve
`xero.<tailnet>`, so **every clawlight hook on it silently reports nowhere** -
`set-status.sh` swallows network errors by design. The light then shows only
xero's sessions plus whatever the Mac last managed to report, until the
server's 30-minute staleness prune drops them. A clawlight colour that does not
match what the Mac is actually doing is a symptom of this, and was how the 5th
occurrence was noticed.

---

# 2026-09-30: 6th occurrence, and the two things the 09-23 round still had wrong

**Found:** 2026-09-30 morning. The user ran `fix_macbook_dns.sh` before this
investigation started, so DNS was already working; the recorder's log is the
whole of the evidence below, which is precisely what it was installed for.

**When it broke:** `2026-09-28 18:37:41 IST`. It had been clean since
2026-09-26 16:12 (the previous manual repair) and stayed broken for
**39 hours**, through the whole of 09-29, until the repair at
`2026-09-30 09:49:11`.

Read it with the two summarisers added the same day, rather than by scrolling
90 snapshots of 170 lines:

```
tools/network/summarize_dns_snapshots.sh    # when it flipped, against the tunnel
tools/network/summarize_ovpnagent_dns.sh    # ovpnagent's own write/restore log
```

## It is written at CONNECT, and that was the open question

The 09-23 write-up ended asking whether a connect or a disconnect strands the
servers. It is the connect, every time. `summarize_dns_snapshots.sh` collapses
the recorder's log to its transitions, and all eight appearances of the pair
since the recorder went in line up with `utun18` coming up or re-establishing:

```
2026-09-28 17:25:37  tun=                       Setup=-
2026-09-28 18:37:41  tun=utun18/172.27.246.167  Setup=BAD  <== written  [tunnel: down -> up]
```

Not one appears at a disconnect. What a *disconnect* does is restore it -
usually. The 09-23 note that "one disconnect restored cleanly" was not the
exception; it was the rule, seen once.

## ovpnagent logs every write it makes, in its own words

`/var/log/ovpnagent.log` - the `StandardOutPath` of the
`org.openvpn.client` LaunchDaemon - prints each dynamic-store dictionary it
touches. This is the confession, and it had been sitting on disk unread since
April:

```
*** DSDict Setup:/Network/Service/A02B9918-F5FF-4C22-ADC2-D8052BE73543/DNS
ORIG {
    OpenVPNConnectOrigSearchDomains = OpenVPNConnectDeleteValue;
    OpenVPNConnectOrigSearchOrder = OpenVPNConnectDeleteValue;
    OpenVPNConnectOrigServerAddresses = OpenVPNConnectDeleteValue;
    SearchOrder = 5000;
    ServerAddresses = ( "192.168.0.2", "192.169.0.2" );
}
MODIFIED {
}
```

Counted over the log's whole span (2026-04-23 to 2026-09-25):

| | |
|---|---|
| writes of the bad pair | 447 |
| restores | 442 |
| **net strandings** | **5** |
| `Process N has exited, destroy tun` | 48, of which **32 had no restore near them** |

Five net strandings against six occurrences on record is as close a match as
this kind of count gets.

## The restore is skipped when the tunnel process *dies* instead of disconnecting

That is the discriminator the 09-23 round was looking for. A clean disconnect
logs four things in order: the `DSDict` restore, `dscacheutil -flushcache`,
`killall -HUP mDNSResponder`, then `INSTANCE STOP : E_SUCCESS`. A session whose
last line is `Process N has exited, destroy tun` logs **none of them** - the tun
device is torn down and the DNS dictionary is left exactly as the connect wrote
it. The log's final entry is such an exit:

```
Fri Sep 25 23:07:12.439 2026 Process 18271 has exited, destroy tun
```

and the recorder shows the pair sitting there from then until the manual repair.
(`INSTANCE STOP : E_SUCCESS` on its own is not a session end - it is the agent's
per-HTTP-request completion marker, logged 126,000 times. Don't key on it.)

## The layer was wrong too: it is Setup:, but only in memory

The 09-23 write-up called it "the persistent `Setup:` layer". Half right, and
the wrong half is the interesting one. The pair never reaches disk:

```
$ plutil -extract NetworkServices xml1 -o - \
    /Library/Preferences/SystemConfiguration/preferences.plist
  ... Wi-Fi  ->  DNS: {}
```

That is true of the current file **and** of `preferences.plist.old`, the copy
macOS left behind at the moment of this morning's repair - so the on-disk store
was empty while the override was live. ovpnagent writes straight into configd's
dynamic store with `SCDynamicStoreSetValue` on a `Setup:`-prefixed key, skipping
SCPreferences entirely.

Everything that was confusing follows from that one fact:

- **`networksetup -getdnsservers Wi-Fi` is not lying.** It reads SCPreferences,
  which really is empty. It was the right answer to the wrong question, six
  times.
- **`networksetup -setdnsservers Wi-Fi empty` really is the cure,** and for a
  reason nobody had articulated: committing SCPreferences makes configd
  recompute the `Setup:` keys from disk, which drops the agent's in-memory
  override as a side effect. Step 1 of `fix_macbook_dns.sh` was doing the work
  all along while being written off as a no-op, because "before" and "after"
  both printed "There aren't any DNS Servers set".
- **It should not survive a reboot.** Untested, and worth testing: an in-memory
  dynamic-store key cannot outlive configd. If a reboot does clear it, that is a
  simpler repair than the one documented here.

## One thing still unattributed

The ovpnagent log stops at that 2026-09-25 23:07:12 abnormal exit and has not
been written to since, though it is the same process (pid 556, up since 22 Jul).
So the 09-28 18:37 write is **not** in it, and cannot be pinned on ovpnagent
from the log alone - the snapshot for that moment shows a
`/opt/homebrew/opt/openvpn/sbin/openvpn --config` process, a separate CLI
OpenVPN that is also installed here, and the recorder was only capturing `$11
$12` of the command line so it cannot say which config. Two gaps, both now
closed in `mac-dns-recorder.sh`: it captures the full command line, and the
`Setup:` dictionary verbatim - so the `OpenVPNConnectOrig*` sentinels will name
the writer on the next occurrence without a follow-up.

## Also worth knowing

- **Not every `Setup=-` in the summariser is a repair.** When `en0` loses its
  address, the service's `Setup:` key can drop out of the live store and come
  back on reassociation. Those show as `en0=(none)` in
  `summarize_dns_snapshots.sh` and are not clears.
- **The tunnel reconnects a lot.** utun18's address changed on nearly every
  snapshot while connected (`172.27.245.x` -> `.246.x` over a few days), so
  "connect" here means dozens of writes per day, not one per session.

## Tooling fixed the same day

- `mac-dns-recorder.sh`: dumps every `Setup:` DNS dictionary verbatim, compares
  it against the on-disk store, records full VPN command lines, and tails
  ovpnagent's own DNS bookkeeping.
- `diagnose_macbook_dns.sh`: its "WHO owns the DNS setting" comment asserted
  that "OpenVPN/Tunnelblick push DNS into State:, never into Setup:". That
  sentence is the false premise the whole month rested on, and it is gone.
- `fix_macbook_dns.sh`: resolves the Wi-Fi service UUID, verifies step 1 with
  `scutil` instead of `networksetup`, says why step 1 looks like a no-op and is
  not, and says that step 3's tailscale toggle is what hid the bug.
- New: `summarize_dns_snapshots.sh`, `summarize_ovpnagent_dns.sh`.
- `setup-mac-dns-recorder.sh` ships the two new readers alongside the rest.

## The mechanism, end to end (2026-09-30, second pass)

### What the write actually is

ovpnagent replaces the Wi-Fi service's DNS dictionary wholesale and records what
it displaced in the same dictionary. The write direction, from the log's first
occurrence:

```
*** DSDict Setup:/Network/Service/A02B9918-.../DNS
ORIG {
}
MODIFIED {
    OpenVPNConnectOrigSearchDomains = OpenVPNConnectDeleteValue;
    OpenVPNConnectOrigSearchOrder = OpenVPNConnectDeleteValue;
    OpenVPNConnectOrigServerAddresses = OpenVPNConnectDeleteValue;
    SearchOrder = 5000;
    ServerAddresses = ( "192.168.0.2", "8.8.8.8", "192.169.0.2" );
}
```

So the three `OpenVPNConnectOrig*` keys are not evidence of a restore that went
wrong - they are written *by the write*, as its own undo record, and
`OpenVPNConnectDeleteValue` is the sentinel for "this key did not exist, delete
it when putting things back". The design is sound. Only the teardown is missing.

### Why the write wins over Pi-hole

`SearchOrder = 5000`. macOS orders resolvers ascending, and the DHCP-derived
en0 resolver sits at `order : 200000`. Worse, the resulting resolver is
**unscoped** - it has no `if_index`, so it is not "the DNS for Wi-Fi", it is the
DNS for everything:

```
resolver #2
  nameserver[0] : 192.168.0.2
  nameserver[1] : 192.169.0.2
  flags    : Request A records
  reach    : 0x00000002 (Reachable)
  order    : 5000
```

`192.168.1.123` is not merely outranked, it is **absent** - from the scoped list
too, where en0's entry is also the bad pair. Writing at `Setup:` with a low
SearchOrder is exactly how you make a VPN's DNS authoritative over DHCP's, which
is a reasonable thing for a VPN client to want. It is also why the failure is
total rather than a fallback.

Note `reach : 0x00000002 (Reachable)`. macOS believes these are reachable,
because OpenVPN pushes `/32` routes for both into the tunnel. Nothing in the
system flags them, which is why this never surfaces as an error - only as
latency.

### The teardown that is missing

A clean disconnect, verbatim:

```
DSDict: updated Setup:/Network/Service/A02B9918-.../DNS
DSDict: removed State:/Network/Service/OpenVPNConnect/Info
MacDNS: RESETDNS 25.5.0
*** DSDict Setup:/Network/Service/A02B9918-.../DNS
ORIG {  ... OpenVPNConnectOrig* sentinels, SearchOrder, the bad pair ... }
MODIFIED {
}
/usr/bin/dscacheutil -flushcache
/usr/bin/killall -HUP mDNSResponder
DSDict: SCDynamicStoreNotifyValue Setup:/Network/Global/IPv4
INSTANCE STOP : E_SUCCESS : Succeeded
```

Eight steps. A session that ends with `Process N has exited, destroy tun` does
**none** of them: no `RESETDNS`, no dictionary restore, no cache flush, no
mDNSResponder HUP. The tun device is reclaimed and the resolver configuration is
left exactly as the connect wrote it. That is the whole bug - `destroy tun` and
`RESETDNS` are separate paths, and only one of them is on the process-death path.

### Why it only started hurting in August, though it has run since April

The bug is five months old. What changed is *what the corporate profile pushes*,
which the log also records:

```
Apr 23 -> Jul  7   x297   192.168.0.2, 8.8.8.8, 192.169.0.2
Jul  9 -> Jul  9   x2     192.168.0.2, 192.169.0.2
Jul  9 -> Jul  9   x7     8.8.8.8, 1.1.1.1, 192.168.0.2, 192.169.0.2
Jul  9 -> Jul 10   x12    192.168.0.2, 192.169.0.2
Jul 13 -> Jul 16   x18    192.168.0.2, 192.169.0.2, 8.8.8.8
Jul 17 -> Jul 17   x3     192.168.0.2, 192.169.0.2
Jul 22 -> Sep  2   x95    8.8.8.8, 1.1.1.1, 192.168.0.2, 192.169.0.2
Sep 23 -> Sep 24   x13    192.168.0.2, 192.169.0.2
```

The same stranding bug therefore produces **two different symptoms**, and which
one you get depends on whether that day's profile included a reachable public
resolver:

- **With `8.8.8.8` / `1.1.1.1` in the list** (Apr-Jul 7, Jul 22 - Sep 2): DNS
  keeps working. It resolves against Google and Cloudflare, off-LAN, with
  Pi-hole bypassed entirely. Nothing feels wrong. **This is the silently
  unfiltered state**, and 2026-08-28 - the first recorded occurrence, unnoticed
  for 10 days - falls squarely inside the Jul 22 - Sep 2 window.
- **With only `192.168.0.2` + `192.169.0.2`** (the Jul and late-Sep windows):
  both servers are off-LAN and unanswerable with the tunnel down, so every
  lookup eats a timeout. **This is the "internet is slow" state**, and it is
  what 2026-09-22 onwards, including 2026-09-28, looked like.

### A correction this forces

`fix_macbook_dns.sh` has said since August that on 2026-08-28 *"Wi-Fi had a
manual `8.8.8.8 1.1.1.1`, which bypassed Pi-hole entirely"*. It was never
manual. ovpnagent wrote `8.8.8.8, 1.1.1.1, 192.168.0.2, 192.169.0.2` on every
connect throughout that window, and a stranded one of those writes is what was
found. The "two unrelated DNS problems" this project has been carrying - a stale
manual public-resolver override in August, and unreachable off-LAN servers in
September - are one bug with one cause, seen at two different settings of the
corporate profile.

### What is still upstream, and worse than it looked

The `192.169.0.2` typo has been in the profile for at least five months and
survived at least seven profile revisions. Every client on that VPN resolves
against a publicly routable address in a block that is not theirs. Worth
reporting.
