# MacBook DNS kept breaking: OpenVPN Connect left its servers in `Setup:`

**Date found:** 2026-09-23 (5th occurrence; the first four were 2026-08-28,
2026-09-10, 2026-09-16, 2026-09-22)
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
