# Home Wi-Fi: router and extender settings

What the home Wi-Fi is, how it is set, and why. Addresses and MACs are in the
gitignored `docs/hardware.md`, not here.

## Layout

| Piece | SSID | Band | Links back via | What uses it |
|---|---|---|---|---|
| Airtel router (also the internet gateway) | `dlink_pramod` | 2.4GHz (5GHz not checked) | - | Diwali WLED door lights, living-room voice satellite, phones/Macs near it |
| TP-Link extender (bedroom) | `dlink_pramod_bed_room` | 2.4GHz | **the router's 2.4GHz Wi-Fi** | wol Pi, akash kandil switch (smart-switch-bench), bedroom side |
| xero | - | wired | Ethernet straight into the router | - |

- **The router's 2.4GHz radio is a single point of failure for both SSIDs.**
  The extender repeats it over Wi-Fi, so when that radio stalls, the bedroom
  side goes down too.
- **Every ESP32 device is 2.4GHz-only** (satellites, WLED, switches, Tinxy), so
  they feel every 2.4GHz problem; phones on 5GHz often don't.
- **Retiring the extender:** `PROJECTS.md` "Move the Airtel router to a central spot".

## What channel and band mode mean

**Channel** - which slice of the 2.4GHz airwaves the router uses.

```
channel:  1  2  3  4  5  6  7  8  9  10 11 12 13
ch 1:    [=========]
ch 6:                   [=========]
ch 11:                                 [=========]
ch 10:                              [=========]   <- overlaps BOTH 6 and 11
```

- Channels are 5MHz apart but a network is ~20MHz wide, so it covers 4-5 numbers.
- **Only 1, 6 and 11 don't overlap.** Neighbours' routers sit on one of them.
- **Same channel as a neighbour:** the radios take turns. Slower, but clean.
- **In-between channel (10):** neighbours on 6 and 11 are just noise to it,
  not networks it can take turns with - errors and retries, worst in the
  evening when everyone's Wi-Fi is busy.
- **Fixed, not Auto:** Auto picked 10, and can hop channels mid-session, which
  briefly knocks ESP devices off.
- **Picking between 1/6/11:** a Wi-Fi analyser app shows the least crowded.
- **Neighbours can still move next to us.** Fixing ours only stops the
  interference we were causing.

  | Neighbour on | Effect | Why |
  |---|---|---|
  | 11 (same) | mild, shared airtime | radios hear each other and take turns |
  | 9, 10, 12, 13 | worst: retries, drops | heard only as noise |
  | 1 or 6 | none | no overlap |

  Most Auto routers land on 1/6/11, so sharing is likelier than overlapping.
  If evening drops return in `wifi_drops.py`, check an analyser app and move
  to 1 or 6.
- **Channel width should be 20MHz,** not 40 or 20/40 Auto: a 40MHz network
  covers two-thirds of the 2.4GHz band and overlaps almost everyone.

**Band mode** - which Wi-Fi generations the router accepts.

| Letter | Standard | Year | Top speed |
|---|---|---|---|
| b | 802.11b | 1999 | 11 Mbps |
| g | 802.11g | 2003 | 54 Mbps |
| n | 802.11n (Wi-Fi 4) | 2009 | 150+ Mbps |

- With **b** allowed the router keeps slow legacy timing in case a b device
  appears, and every client pays for it.
- **G+N** drops that. Everything in the house (ESP32, Pi, phones, Tinxy) does N.

## Router 2.4GHz settings (since 2026-11-06)

| Setting | Was | Now | Why |
|---|---|---|---|
| Channel | 10 (Auto) | **11, fixed** | 10 overlaps both 6 and 11, so it takes interference from neighbours on either. Auto may also hop channels under evening load. Only 1, 6, 11 don't overlap. |
| Band mode | B+G+N | **G+N** | Allowing 802.11b makes the router fall back to legacy timing and rates for everyone. Nothing in the house needs b. |
| Encryption | WPA2 Mixed | **WPA2** | "Mixed" keeps WPA1/TKIP enabled. |
| WPA2 cipher suite | TKIP + AES | **AES only** | With TKIP allowed, many routers cap N clients at legacy speeds; TKIP is also a classic radio-hang trigger on cheap firmware. |
| Authentication | Personal (PSK) | unchanged | |
| IEEE 802.11w (PMF) | None | **None, on purpose** | "Capable" is more secure but old ESP8266 IoT (Tinxy) can fail to join. |
| SSID, passphrase | - | unchanged | Every device rejoined by itself. |

- **Where:** router admin page, WLAN → Basic (band, channel) and WLAN →
  Security (encryption, cipher). WLAN Status shows the result.
- **Reset trap:** an Airtel firmware push or factory reset can put these back
  to Auto / B+G+N / Mixed. If evening drops come back, check WLAN Status first.
- **Changing them** drops every Wi-Fi client for about a minute, extender included.

## Extender settings

- **Security:** the Tether app shows "WPA/WPA2-Personal", not editable. The Pi
  still negotiates `PTK=CCMP GTK=TKIP` with it: per-device traffic is AES,
  only the broadcast key is TKIP. Acceptable; its backhaul to the router is
  now AES-only regardless.
- **To try if wanted:** `http://tplinkrepeater.net` from a phone on the
  extender, Settings → Wireless → Extended Network, set WPA2-PSK / AES if the
  model offers it.

## Diagnosing "everything went offline"

1. **Did xero reboot?** `uptime`, `last -x | head`.
2. **Did the router reboot?** xero is cabled into it, so a reboot drops the
   carrier: `journalctl --since -2h | grep -i enp1s0`. Also compare the public
   IP in `journalctl -u tailscaled | grep "endpoints changed"`.
3. **Was it only Wi-Fi?** `python3 tools/ha-diag/wifi_drops.py <start> <end> --times`
   (IST). Devices on the router *and* the extender dropping together = the
   router's 2.4GHz radio. Only extender devices = the extender.
4. **Who kept talking:** Pi-hole queries per client per minute
   (`docker exec pihole grep ... /var/log/pihole/pihole.log`); wired and 5GHz
   clients that kept querying prove the router itself was up.
5. **The Pi's own view:** `ssh 192.168.1.124 journalctl | grep -E "wpa_supplicant|CTRL-EVENT"`.
6. **Router log:** admin page → System Log. A `br0 up` pair 20s apart is the
   router re-adding its Wi-Fi radios to the LAN bridge.

## Incidents

- [2026-11-06: router 2.4GHz radio stalled for 7 minutes](incidents/2026-11-06-router-2.4ghz-wifi-stall.md)
