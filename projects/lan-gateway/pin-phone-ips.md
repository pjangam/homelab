# Pin the phones' addresses (so the usage dashboard names them)

Written 2026-10-23, to do with the phones in hand. Why: the "Network usage
(per device)" Grafana dashboard names a device by its MAC on the router's WiFi
and by its IP on the extender's WiFi. Phones change both unless told not to,
and the TP-Link extender hides every device's MAC, so the router cannot
reserve IPs for devices behind it (`README.md`, "Known limits").

## 0. Router, once (http://192.168.1.1 -> LAN -> DHCP)

- [ ] **IP range:** change `192.168.1.2 - 192.168.1.254` to
      `192.168.1.2 - 192.168.1.199`. Leave the gateway (`192.168.1.123`) and
      DNS (`192.168.1.123,192.168.1.124`) as they are. Save.

`.200` and up are then never handed out by the router, so they are free for
the manual addresses below.

## 1. Router WiFi (`dlink_pramod`) - stop the MAC changing

| Phone | Where | Set to |
|---|---|---|
| iPhone 14 | Settings -> Wi-Fi -> (i) on `dlink_pramod` -> Private Wi-Fi Address | **Fixed** - done 2026-10-22 |
| iPhone SE (Alfred) | same | **Fixed** |
| OnePlus 7 | Settings -> Wi-Fi -> tap `dlink_pramod` -> Privacy | **Use device MAC** |
| realme X | same (may be under "MAC address type") | **Use device MAC** |
| Mom's phone | same | **Use device MAC** |

- [ ] For each Android phone, note the MAC shown on that screen (or under
      Settings -> About phone -> Status -> Wi-Fi MAC address) and send it to
      Claude, or add a line to `device-names`: `<mac>  <name>`.

## 2. Bedroom WiFi (`dlink_pramod_bed_room`) - set the IP by hand

Connect the phone to `dlink_pramod_bed_room` first, then:

- **iPhone:** Settings -> Wi-Fi -> (i) -> **Configure IP -> Manual**, and
  **Configure DNS -> Manual**.
- **Android:** Settings -> Wi-Fi -> tap the network (or long-press -> Modify)
  -> Advanced -> **IP settings -> Static**.

Same values on every phone except the IP address:

| Field | Value |
|---|---|
| Subnet mask (iPhone) / Network prefix length (Android) | `255.255.255.0` / `24` |
| Router (iPhone) / Gateway (Android) | `192.168.1.123` |
| DNS 1 | `192.168.1.123` |
| DNS 2 | `192.168.1.124` |

| Phone | IP address | Done |
|---|---|---|
| iPhone 14 | `192.168.1.201` | [ ] |
| iPhone SE (Alfred camera) | `192.168.1.202` | [ ] |
| OnePlus 7 | `192.168.1.203` | [ ] |
| realme X | `192.168.1.204` | [ ] |
| Mom's phone | `192.168.1.205` | [ ] |

The names for `.201`-`.205` are already in `device-names`, so each phone shows
up named on the dashboard within a minute of joining.

## 3. Check

- [ ] On each phone, open a web page on both networks.
- [ ] Grafana -> "Network usage (per device)": no new bare `192.168.1.x`
      rows for these phones. Anything still shown as an IP is a device not on
      this list.

## If xero is off

On the bedroom WiFi these phones then have no internet: they point at xero
by hand. Same as every DHCP device today (the router hands out xero as the
gateway), but the fix differs: switch the phone's IP settings back to
**Automatic / DHCP** for that network.
