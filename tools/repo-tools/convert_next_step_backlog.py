#!/usr/bin/env python3
"""One-off (2026-11-04): the second half of the Next step -> #### Open items
migration - the 34 Parked/Backlog entries left after convert_next_step.py did
the Active ones. Kept in the repo per CLAUDE.md; delete once the migration is
long done."""
import re

P = 'PROJECTS.md'
s = open(P).read()

def convert(title, items, state_append=None):
    global s
    start = s.index('### ' + title + '\n')
    end = s.find('\n### ', start + 4)
    end = len(s) if end == -1 else end
    e = s[start:end]
    j = e.index('**Next step:**')
    stops = [x for x in (e.find('\n\n', j), e.find('\n####', j)) if x != -1]
    k = min(stops) if stops else len(e)
    e = e[:j].rstrip('\n') + e[k:]
    if state_append:
        m = re.search(r'^\*\*State:\*\*', e, re.M)
        para_end = e.find('\n\n', m.start())
        para_end = len(e.rstrip('\n')) if para_end == -1 else para_end
        e = e[:para_end] + ' ' + state_append + e[para_end:]
    m = list(re.finditer(r'^\*\*(Status|Priority):\*\*.*\n', e, re.M))[-1]
    block = '\n#### Open items\n' + ''.join(f'- [ ] {i}\n' for i in items)
    e = e[:m.end()] + block + e[m.end():]
    e = re.sub(r'\n{3,}', '\n\n', e)
    s = s[:start] + e + s[end:]

convert('Pi audio move follow-ups: monitoring, xero cleanup, then xero to the router', [
    '**Claude:** rest of monitoring step 1 - the advertising check and the bridge alarms (the Pi watchdog is in)',
    '**Pramod:** pin the extender (`TL-WA850RE`) to `192.168.1.7` on the router',
    '**Claude:** watchdog ping signal (step 3) - must land before the router gets a UPS back',
])
convert('ESP32 UPS LED monitor', [
    '**Pramod:** open the UPS case if possible; note the fastening (screws/glue), LED wiring (flying leads vs PCB-mounted) and pad spacing',
    '**Together:** from that inspection, decide whether option (D) is viable before buying anything',
])
convert('Local Qwen (Ollama) delegation experiment', [
    '**Pramod:** on the Mac, install Ollama and `ollama pull qwen2.5:1.5b`, set `ANTHROPIC_API_KEY`',
    '**Pramod:** run `uv run tools/dev-shell/qwen_delegate_repl.py` (or `pip install anthropic requests` and drop the `uv run --script` shebang) and report what breaks',
], state_append='It runs on the Mac, so the user runs and debugs it there.')
convert('ZFS mirror (real redundancy for datapool)', [
    '**Pramod:** if the downtime or the one-month backup gap starts to matter, buy a 2TB USB HDD (~Rs 6-7k) as the cheaper first step',
    '**Claude:** then set up nightly incremental `zfs send` of `immich-upload` and `immich-db` to it',
], state_append='Nothing planned now. The USB HDD is the local half of the backup plan dropped on 2026-10-26: covers the gap, restores in hours, needs no free bay. The full mirror waits for a box with two drive bays.')
convert("Bhakti's Google Takeout into Immich", [
    '**Pramod:** Bhakti requests a Google Photos Takeout; note its size from the export page',
    '**Together:** import it as her user with `upload_from_takeout.sh` and her API key ("Importing a Google Takeout export" in `services/immich/README.md`), paced for the Kingston\'s temperature',
    '**Claude:** check it with `verify_takeout.py`, re-measure `datapool` for "datapool storage headroom"',
    '**Pramod:** only then decide on Google One',
], state_append='immich-go 0.32 breaks on Immich 3.3, hence the curl-based script. The archive dedupes photos shared between the two libraries by SHA-1.')
convert('datapool storage headroom', [
    '**Pramod:** before Bhakti\'s import, note the Takeout\'s size from Google\'s export page',
    '**Claude:** after the import, re-measure (`zpool list datapool`, `zfs list -o name,used,logicalused -r datapool`)',
    '**Together:** then decide between the options below',
])
convert('Move the Airtel router to a central spot (retire the Wi-Fi extender)', [
    '**Pramod:** answer the open questions below (`docs/home-network-uplink-options.md` has all the options, costs and trade-offs)',
])
convert('Miraie AC self-healing', [
    '**Claude:** on the next real HA restart, confirm `journalctl --user -u miraie-ha-birth` shows the fix within ~2min and the healthcheck logs no auto-fix for that outage',
])
convert('Tinxy: remove stale/decommissioned devices from account', [
    '**Pramod:** remove the stale/unused devices from the Tinxy account so only in-use ones show in HACS',
])
convert('Backup restore drill', [
    '**Together:** pull a recent backup down and restore it to a scratch location (needs the backup passphrase) to confirm it works',
], state_append='Never restore over production.')
convert('Shopping list display (touchscreen e-ink)', [
    '**Claude:** research touchscreen e-ink modules (all-in-one like Inkplate vs bare panel + touch overlay + MCU) and how list state syncs back to HA/a shared list',
])
convert('Automatic plant watering (balcony)', [
    '**Pramod:** revisit if the wall/pipe work happens for another reason, or if a balcony-sited reservoir becomes acceptable',
], state_append='Parked on the wall/pipe work; nothing planned until then.')
convert('Pigeon deterrent - motion-triggered sprinkler (balcony railing/parapet)', [
    '**Pramod:** revisit once the balcony water supply (see plant watering) and the runoff question are settled',
], state_append='Nothing planned: gated on the same balcony water supply as the watering project, and on the runoff question.')
convert('Remote controlled curtains', [
    '**Pramod:** measure the rod diameter and shape, count the windows (one motor each), weigh or estimate each curtain',
    '**Claude:** check whether SwitchBot or an authorised Indian seller lists the Rod 2.0 cheaper than this reseller (or wait for a sale)',
    '**Claude:** check whether xero has working Bluetooth; if not, budget the ESP32 proxy',
], state_append='All of these come before buying.')
convert('Door open/close and lock status (main, safety, balcony)', [
    '**Pramod:** take the strike plates off both entrance doors - measure the main door\'s strike box depth against the deadbolt\'s full throw, see what is behind the grill door\'s slot',
    '**Pramod:** check for a socket near the entrance and measure the grill door\'s closed gap',
    '**Together:** bench-test magnet + reed and magnet + hall sensor against the actual bolts, before chiselling or drilling anything',
])
convert('Network device + access map', [
    '**Pramod:** export the router DHCP table (router admin page)',
    '**Claude:** diff it and the Pi-hole client list against `docs/hardware.md`, extend the file with the access columns below',
])
convert('Clawlight: a bootstrap script for a machine that has no hooks yet', [
    '**Claude:** write `clawlight/setup-clawlight-hooks.sh`, driven by the same ten-event list the README documents',
    '**Pramod:** run it on the personal MacBook as its first real test',
])
convert('Big wall display (HUB75 LED matrix) - clock, and whatever else is worth a glance', [
    '**Pramod:** decide the shape - clock-first (buy one) or dashboard-first (build the matrix)',
    '**Together:** if dashboard, list what actually deserves wall space (a 64x32 grid holds very little text)',
])
convert('Ganapati 2027: solar system / general relativity decoration', [
    '**Together, mid-2027:** fix the makhar size, decide the grid resolution, price the pixel count',
    '**Pramod, by July 2027:** order anything long-lead (this year\'s shortlist lesson)',
])
convert('WiFi-synced analog clock (ESP32 retrofit of a quartz movement)', [
    '**Pramod:** open a spare movement and confirm the coil can be freed from its quartz chip and pulsed by hand - that one bench test decides the project',
])
convert('Move WoL to an ESP32, put the Pi on the UPS (post-Ganapati)', [
    '**Together:** in the next real outage (or by switching off the extender and xero\'s UPS input), check whether the Pi\'s spot can still reach xero',
], state_append="If it can't, this idea mostly buys buttons and Node-RED that have nothing to talk to.")
convert('Pegboard backlight as the clawlight (leftover WS2812B on Pi GPIO13)', [
    '**Pramod:** measure the leftover strip and the pegboard (size, material, gap from the wall)',
    '**Together:** pixel test from the Pi on GPIO13 with audio off, before any mounting',
])
convert('Homelab health LED (Pi GPIO) - the whole healthcheck as one light', [
    '**Pramod:** decide - LED reads `homelab/healthcheck/overall` directly (nothing new server-side) or an HA-consolidated topic (more coverage, one more moving part)',
    '**Claude:** then build it from `scripts/clawlight/clawlight-led.py` + `deploy_clawlight_led_pi.sh` as templates',
], state_append='The templates already have the MQTT-retained-state, stale-means-amber, systemd-unit shape worked out.')
convert('Remote control for scenes/scripts (Spotify, white noise, etc.)', [
    '**Pramod:** decide the buttons needed (e.g. white noise on/off, Spotify play/pause/skip)',
    '**Together:** pick ESPHome\'s native HA integration (least custom code, matches the MQTT-bridge pattern) or fully custom firmware',
])
convert('xero cooling on the Skadis pegboard', [
    '**Pramod, by December:** buy the SATA extension, standoffs and a USB fan locally',
    '**Together:** open the cover to see whether the stock SSD ribbon reaches outside with slack, then move the SSD out (plan below)',
    '**Together:** CPU - standoffs + USB fan, or stand xero on its edge',
    '**Claude:** use the cool months for heavy jobs (Bhakti\'s Takeout import, transcodes to `copies=1`)',
], state_append='**Deadline: before February 2027** (noted 2026-11-02): winter room temperatures hide the problem now, and it comes back with the Feb-March warm-up. The parts are cheap commodity items untouched by the chip-price spike, no reason to wait for prices.')
convert('Voice satellites: speakers and wake word', [
    '**Claude:** try `andromeda` / `dumbledore` against `hey_jarvis` (`WAKE_WORD_ID` in `projects/voice-assistant/setup_assist.py`, restart speech-to-phrase, temporary `--debug` on openwakeword); train on Colab only if neither works',
    '**Pramod:** check which end (DIN, follow the arrows) of the bedroom strip is wired before connecting it',
    '**Pramod:** buy the speaker parts below (local shop first)',
    '**Together:** wire per the plan, add the firmware pieces, OTA both boards',
    '**Claude:** update both boards\' `docs/hardware.md` entries (GPIOs, firmware)',
])
convert('Automatic pour-over coffee (dose by weight, timed spiral pour, bell at the end)', [
    '**Pramod:** if picked up, start with the water half - a pump into a cup on a load cell, checking the pump\'s hot-water rating and pour accuracy',
], state_append='Nothing planned.')
convert('Humidity-triggered AC dry mode and mister (temperature/humidity sensor on an ESP32)', [
    '**Pramod:** buy one SHT41 or SHT31 breakout and a ~30cm 4-core lead locally',
    '**Together:** bench the sensor beside a known hygrometer for a day, before writing any automation',
], state_append='Phase 1 only for now.')
convert('Machine upgrades (whole-house UPS/inverter, second SSD, better machine)', [
    '**Pramod:** when purchases are possible, pick the order',
    '**Together:** for the UPS/inverter, get the load figure first ("Home power audit" plus a new machine\'s idle draw)',
])
convert('Old duplicity backup in Google Drive - keep or delete', [
    '**Pramod:** look for the passphrase in Vaultwarden or old passwords; if found, list the contents, else delete the folder and empty Drive\'s Trash',
])
convert('Wired Ethernet dongle for the MacBooks', [
    '**Pramod:** buy the UGREEN CM648 below (local shop first)',
    '**Pramod:** plug in Cat6, check System Settings -> Network shows the USB LAN linked at 1Gbps',
], state_append='It runs at 1Gbps until the router or a switch does 2.5GbE ("Machine upgrades", part 3, Network port).')
convert('Workbench stock: jumper wires and project boxes', [
    '**Pramod:** buy on the next shop trip (all loose local stock)',
])
convert('xero OS: stay on Ubuntu 24.04 LTS, no 26.04 upgrade yet', [
    '**Pramod:** revisit only on a trigger: a new machine (install Ubuntu Server 26.04 fresh), keeping xero long-term (release upgrade early 2027), or the ZFS mismatch causing a real problem',
], state_append='For (b), the release upgrade goes on a quiet weekend after backups and a `zpool scrub`, with keyboard and screen attached.')
convert('Minecraft server on xero (family world, local and over Tailscale)', [
    '**Pramod:** list who will play and on which devices (PC Java, PC Bedrock, phone/tablet, Xbox/Switch/PlayStation) - that picks the server software',
    '**Claude:** then the build, about an evening\'s work',
])
open(P, 'w').write(s)
