# LAN time server on xero, so the wol Pi's clock survives an ISP outage
**Status:** Done

**Why:** on 2026-09-28 a power cut followed by an ISP outage left the wol Pi (and its screensaver clock) 15 minutes behind for about 10 hours. The Pi has no RTC: it boots on the time `systemd-timesyncd` last saved (04:31, but it actually booted at 04:46) and its only time sources were the internet pool, so nothing could correct it until the ISP came back at 14:54.
**Outcome:** shipped 2026-09-28. After a power cut the Pi now comes right as soon as xero is back up (it WoLs xero itself on boot), internet or not.

#### Design

chrony on xero (replaces timesyncd there) serves the LAN on UDP 123, with `local stratum 10` so it keeps answering from xero's RTC while the internet is down. The Pi's timesyncd lists xero first, then the Debian pool, in `NTP=` (not `FallbackNTP=`, which timesyncd ignores whenever `NTP=` is set). Files and `deploy.sh`: `services/chrony/`.

#### Log
- 2026-09-28: power cut then ISP outage; the Pi ran 15 minutes behind until the ISP came back at 14:54. chrony on xero shipped the same day.
