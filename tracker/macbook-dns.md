# MacBook DNS keeps breaking - root cause closed out (OpenVPN Connect, at connect); no client-side cure
**Status:** Closed

**Why:** the Mac's resolver broke six times with an identical signature, and each repair destroyed the evidence before anyone could say what caused it. Between breaks the Mac is silently unfiltered - the 2026-08-28 occurrence went unnoticed for 10 days.
**Outcome:** closed 2026-10-26: nothing more can be done from this side. Root cause known since 2026-09-30: OpenVPN Connect writes the off-LAN server pair (see "The signature, every time") into configd's in-memory `Setup:` store when it connects, and skips the restore when the tunnel process dies instead of disconnecting. The bug is in corporate software on a managed Mac (the employer M2), so there is no client-side cure.
- **When it happens again** (lookups hang, "the internet is slow"): run `fix_macbook_dns.sh` on the Mac and verify with `scutil --dns`, never `networksetup`. About 30 seconds. Clawlight keeps working at home either way, since its hooks report over the LAN (see "Knock-on: clawlight").
- **Not pursued:** reporting the 192.169 typo upstream to whoever runs the corporate VPN profile, and attributing the one 2026-09-28 write left unexplained. A reboot instead of the repair (should clear an in-memory key) was never tried; worth one go at the next occurrence, since it costs nothing.
- **Still running:** the DNS recorder on the M2 (`tools/network/mac-dns-recorder.sh`, log `~/Library/Logs/homelab/dns-recorder/snapshots.log`). Harmless to leave; it would attribute the next write if anyone looks.

#### The signature, every time
`en0` resolves against `192.168.0.2` + `192.169.0.2`. Neither is on this LAN (192.168.1.0/24) and the second is a typo landing in publicly routable space, so queries *hang* rather than fail fast - which is why it reads as "the internet is slow", not "DNS is down".

#### Occurrences
2026-08-28 (last clean query 20:47, found and fixed 09-07) - 2026-09-10 - 2026-09-16 - 2026-09-22 - 2026-09-22 19:56 (the one the recorder caught, noticed 2026-09-23) - **2026-09-28 18:37, broken for 39 hours until the repair on 2026-09-30 09:49.**

#### Root cause
Full write-up in `docs/incidents/2026-09-23-mac-dns-openvpn-connect-left-stale-servers.md` (the 2026-09-30 detail is appended to the same doc).

- **It is written at CONNECT, not left at disconnect.** All eight appearances of the pair since the recorder went in line up with `utun18` coming up or re-establishing; not one appears at a disconnect. A disconnect normally *restores* it - the "one disconnect restored cleanly" note from 09-23 was the rule, not the exception.
- **The restore is skipped when the tunnel process dies instead of disconnecting.** A clean disconnect logs the restore, a `dscacheutil -flushcache`, a `killall -HUP mDNSResponder` and `INSTANCE STOP : E_SUCCESS`. A session whose last line is `Process N has exited, destroy tun` logs none of them. Over five months of `/var/log/ovpnagent.log`: **447 writes, 442 restores, 5 net strandings**, and 32 of 48 such abnormal exits had no restore near them. Five strandings against six recorded occurrences.
- **ovpnagent was logging the whole thing all along.** `/var/log/ovpnagent.log` (the `StandardOutPath` of the `org.openvpn.client` LaunchDaemon) prints every dynamic-store dictionary it touches, `OpenVPNConnectOrig*` sentinels and all. Unread since April. `tools/network/summarize_ovpnagent_dns.sh` reads it.
- **The layer is `Setup:`, but only in configd's in-memory store.** The Wi-Fi service's `Setup:.../DNS` dictionary holds `ServerAddresses = 192.168.0.2, 192.169.0.2` alongside three `OpenVPNConnectOrig*` keys set to the sentinel `OpenVPNConnectDeleteValue` - OpenVPN Connect's own note that the dictionary was empty before it took it over and that the keys should be deleted on restore. But `/Library/Preferences/SystemConfiguration/preferences.plist` has `DNS: {}` for Wi-Fi, and so does the `.old` copy macOS left at the moment of the repair. So `networksetup` was never lying, it was answering the wrong question; and `networksetup -setdnsservers Wi-Fi empty` cures it only as a side effect - committing SCPreferences makes configd recompute the `Setup:` keys from disk. Step 1 of `fix_macbook_dns.sh` was doing the work for four occurrences while being written off as a no-op.

#### Two things this overturned, both of which cost a month
- **The layer was wrong.** Every earlier round concluded the pair lives in `State:`, not `Setup:`, on the strength of `networksetup -getdnsservers` reporting no override. `networksetup -getdnsservers Wi-Fi` *still* answers "There aren't any DNS Servers set on Wi-Fi" while `scutil` shows that dictionary populated. The two disagree; the one that was trusted is the wrong one. **Check DNS ownership with `scutil`, never `networksetup`.** (Refined 2026-09-30: `Setup:` but in-memory only, see Root cause.)
- **The repair hid it.** `fix_macbook_dns.sh` step 3's `tailscale set --accept-dns` toggle makes tailscaled rewrite the resolver config so the pair stops being *used*, but never clears the `Setup:` key - so it survives every repair. Step 1, "clear the Wi-Fi override", was logged as a no-op four times because it asks `networksetup`, which cannot see it.

Ruled out along the way and now moot: a stale global nameserver in the Tailscale admin console (2026-09-16), a second DHCP server on the TP-Link extender, a stale lease. MDM was close - this is corporate software on a managed Mac - but it is the VPN client, not a configuration profile.

#### Why it only started hurting in August
The bug is five months old; what changed is what the corporate profile pushes. ovpnagent's log records the server list of every write:

```
Apr 23 -> Jul  7   x297   192.168.0.2, 8.8.8.8, 192.169.0.2
Jul  9 -> Jul 17   x42    (four revisions, some with 8.8.8.8/1.1.1.1, some without)
Jul 22 -> Sep  2   x95    8.8.8.8, 1.1.1.1, 192.168.0.2, 192.169.0.2
Sep 23 -> Sep 24   x13    192.168.0.2, 192.169.0.2
```

So one bug produces **two symptoms**, depending on whether that day's profile included a reachable public resolver. With `8.8.8.8`/`1.1.1.1` in the list DNS keeps working, off-LAN, Pi-hole bypassed and nothing feeling wrong - the silently-unfiltered state, and 2026-08-28 falls inside the Jul 22 - Sep 2 window. With only the two off-LAN servers every lookup times out - the "internet is slow" state, which is 2026-09-22 onwards.

**This collapses two things the project was carrying as separate.** `fix_macbook_dns.sh` has said since August that on 2026-08-28 "Wi-Fi had a **manual** `8.8.8.8 1.1.1.1`". It was never manual - ovpnagent wrote exactly that list on every connect through that whole window. The August "stale manual public-resolver override" and the September "unreachable off-LAN servers" are one bug with one cause. Corrected in the script.

#### Why the write beats Pi-hole so completely
`SearchOrder = 5000` against the DHCP resolver's `200000` (macOS orders ascending), and the resulting resolver is **unscoped** - no `if_index`, so it is the DNS for everything, not just Wi-Fi. `192.168.1.123` is not outranked, it is *absent*, from the scoped list too. And it reads `reach : 0x00000002 (Reachable)`, because OpenVPN pushes `/32` routes for both servers into the tunnel - so nothing in macOS ever flags it. That is why this surfaces only as latency.

#### The missing teardown, precisely
A clean disconnect logs eight steps - `DSDict: updated`, `removed State:.../Info`, `MacDNS: RESETDNS`, the dictionary restore, `dscacheutil -flushcache`, `killall -HUP mDNSResponder`, `SCDynamicStoreNotifyValue`, `INSTANCE STOP : E_SUCCESS`. A session ending in `Process N has exited, destroy tun` does none of them. `destroy tun` and `RESETDNS` are separate code paths and only one is on the process-death path. The `OpenVPNConnectOrig*` sentinels are written *by the connect* as its own undo record, so the design is sound - only the teardown is unreachable on that path.

#### The 192.169 typo is upstream
It is whatever the corporate OpenVPN profile pushes, so the fat-finger is in that profile or the server config behind it. Every client on that VPN is resolving against a publicly routable address that is not theirs - worth reporting to whoever maintains it. And it is worse than it looked: the typo has been in the profile for at least five months and survived at least seven profile revisions (the table above). Every client on that VPN resolves against a publicly routable address in a block that is not theirs.

#### One write still unattributed
ovpnagent's log stops at the 2026-09-25 abnormal exit and has not been written since, though it is the same process (pid 556, up since 22 Jul), so the 09-28 18:37 write is not in it. The snapshot for that moment shows a separate `/opt/homebrew/opt/openvpn/sbin/openvpn --config` CLI running, and the recorder was truncating the command line so it cannot say which config. Both gaps are closed in the recorder now (full command lines, plus the `Setup:` dictionary verbatim so the `OpenVPNConnectOrig*` sentinels name the writer), so the next occurrence settles it with no follow-up.

#### Tooling
All of it re-deployed with `setup-mac-dns-recorder.sh`, which scp's from xero - a `git pull` on the Mac does nothing for it.
- `summarize_dns_snapshots.sh` - collapses the recorder's log to its transitions: when the pair appeared or went, against the tunnel coming up or down. This is the view that answered the connect-vs-disconnect question on its first run.
- `summarize_ovpnagent_dns.sh` - ovpnagent's own write/restore history, with the net-stranding count and the verdict on whether the pair is sitting there now.
- `diagnose_macbook_dns.sh` - its "WHO owns the DNS setting" comment used to assert that "OpenVPN/Tunnelblick push DNS into State:, never into Setup:". That single sentence is the false premise the whole month rested on; it is gone, and the script now prints the `Setup:` dictionary verbatim next to the on-disk store.
- `fix_macbook_dns.sh` - resolves the Wi-Fi service UUID, verifies step 1 with `scutil` rather than `networksetup`, explains why step 1 looks like a no-op and is not, and says plainly that step 3's tailscale toggle is what hid the bug for a month.

**The recorder is what cracked it.** `tools/network/mac-dns-recorder.sh` polls every 20s and snapshots only on change, capturing `Setup:` vs `State:` ownership, the network and location, the DHCP offer, per-resolver reachability and any VPN client or tunnel. It runs from `~/code/personal/scripts/`, which `setup-mac-dns-recorder.sh` fills by scp from xero - re-run it to update the recorder, a `git pull` alone does not. Its log lives at `~/Library/Logs/homelab/dns-recorder/snapshots.log` on the M2.

#### Knock-on: clawlight
While DNS is broken (and Tailscale stopped), the M2 cannot resolve `xero.<tailnet>`, so every clawlight hook on it silently reports nowhere - `set-status.sh` swallows network errors by design. A clawlight colour that does not match what the Mac is doing is a symptom of this; that is how the 5th occurrence was noticed.

Mitigated for clawlight specifically on 2026-09-28 (see Log): reporting never needed Tailscale. `server.py` binds `0.0.0.0:8126` and the tailnet URL is only Caddy in front of it, so the Mac's hooks can use `http://192.168.1.123:8126` while at home and fall back to the tailnet URL when away. "At home" is decided by the default gateway's MAC rather than the IP or a hostname - a bare LAN IP would post session ids and project paths to whatever holds `.123` on a cafe network, and a hostname would depend on the DNS that keeps breaking. See `clawlight/server-url.sh` and the README's "Reporting over the LAN". This narrows the blast radius of this bug; it does not fix the bug, and a Mac that is away from home still needs the tailnet up.

#### Log
- 2026-08-28: 1st occurrence (last clean query 20:47), unnoticed for 10 days; found and fixed 09-07.
- 2026-09-10, 2026-09-16, 2026-09-22: further occurrences. 2026-09-16: a stale global nameserver in the Tailscale admin console ruled out.
- 2026-09-22: recorder installed on the M2 at 13:55 IST from the clone via `setup-mac-dns-recorder.sh`; the break it caught began six hours later (19:56, noticed 2026-09-23).
- 2026-09-23: **root cause: OpenVPN Connect writes the pair into the `Setup:` layer and never restores it.** Written up in `docs/incidents/2026-09-23-mac-dns-openvpn-connect-left-stale-servers.md`. One disconnect was noted as having restored cleanly.
- 2026-09-28: **mitigated for clawlight** - a *different* 2026-09-28 failure from the DNS one, and the 6th time clawlight reported nowhere: Tailscale simply stopped, DNS itself was healthy, and *no* Mac session was on the light - noticed as a missing `travolutionary` session. Hooks now report over the LAN at home (see "Knock-on: clawlight").
- 2026-09-28 18:37: 6th occurrence, broken for 39 hours until the repair on 2026-09-30 09:49. The recorder caught it (pid 41238, still alive 2026-09-30).
- 2026-09-30: the 6th occurrence closed the remaining questions. Refined the 09-23 conclusion: "persistent" was wrong - the key is written only into configd's in-memory store - and "never restores" is wrong too, it restores 442 times out of 447 and the interesting case is the 5 it does not. Written at connect, restore skipped on process death, ovpnagent's log found (see "Root cause").
- 2026-09-30, second pass: the mechanism, the profile history, why it only started hurting in August, and the August/September symptoms merged into one bug; `fix_macbook_dns.sh` corrected; tooling and recorder updated (full command lines, `Setup:` dictionary verbatim).
- 2026-10-26: closed by the user: the cause is in OpenVPN Connect on a managed Mac and nothing on our side can stop it. The repair and its verification are the standing answer; reporting upstream and attributing the last write are not pursued.
