#!/usr/bin/env python3
"""One-off (2026-11-04): convert Active PROJECTS.md entries from the old
**Next step:** paragraph to the #### Open items checklist. Kept in the repo per
CLAUDE.md; delete once the migration is long done."""
import re, sys

P = 'PROJECTS.md'
s = open(P).read()

def convert(title, items, detail=None, state_append=None):
    global s
    start = s.index('### ' + title + '\n')
    end = s.find('\n### ', start + 4)
    e = s[start:end]
    j = e.index('**Next step:**')
    stops = [x for x in (e.find('\n\n', j), e.find('\n####', j)) if x != -1]
    k = min(stops)
    replacement = ''
    if detail:
        heading, text = detail
        replacement = f'#### {heading}\n{text}'
    e = e[:j] + replacement + e[k:] if replacement else e[:j].rstrip('\n') + e[k:]
    if state_append:
        m = re.search(r'^\*\*State:\*\*.*$', e, re.M)
        e = e[:m.end()] + ' ' + state_append + e[m.end():]
    m = re.search(r'^\*\*Priority:\*\*.*\n', e, re.M)
    block = '\n#### Open items\n' + ''.join(f'- [ ] {i}\n' for i in items)
    e = e[:m.end()] + block + e[m.end():]
    s = s[:start] + e + s[end:]

convert('Home power audit - smart/network devices + major appliances', [
    '**Pramod:** decide whether real numbers matter; if so, buy a cheap plug-in energy meter',
    '**Claude:** check whether the Tinxy integration exposes energy data for the loads behind the two Tinxy units',
    '**Together:** measure the fridge first (likely the biggest load), then replace the router/extender/xero/Pi estimates',
])
convert('Clawlight jump-to-console from the iPhone (Termius -> ssh -> tmux attach)', [
    '**Pramod:** in Termius, save the xero host with `~/code/homelab/clawlight/phone-attach.sh` as its startup command',
    '**Pramod:** tap a xero session on the clawlight page, connect by hand, then try the open links; report what fails',
])
convert('Peer-to-peer sensitive document sync (Syncthing) - Dropbox replacement', [
    '**Together:** list the devices and what each gets: xero (always-on peer, `datapool/documents`), the 2019 MacBook, the iPhone, the work laptop (see Open question)',
    '**Claude:** Syncthing container on xero, reachable over the tailnet only',
])
convert('In-house smart switch to replace Tinxy', [
    '**Pramod:** after Diwali lights: read the ratings on the relays already owned (see Relay check)',
    '**Pramod:** open one Tinxy switch and note what is inside (chip ID, flashable module?) before picking a path',
], detail=('Relay check', 'Starts after "Diwali lights 2026" (user, 2026-10-30). Check the relays against this job: the coil voltage (5V suits an ESP32 board\'s 5V; 12V needs its own supply), the **contact rating on the AC side** (printed like `10A 250VAC`), comfortably above the load - fans and lights, and mind the inrush of LED drivers and fan motors - and whether they come on a module with a transistor/optocoupler driver, since an ESP32 GPIO cannot drive a bare relay coil.'))
convert("xero's UPS (CRU12V3A) dead - xero off until it is replaced", [
    '**Pramod:** chase Resonate for the CRU12V3A warranty repair (in progress since 2026-10-22)',
    '**Claude:** before the router goes back on a UPS, land the watchdog\'s ping signal ("Pi audio move follow-ups" step 3), or the watchdog goes blind',
    '**Claude:** when the UPS is back, restore a measured `DOWN_THRESHOLD_MIN` (10 min for now)',
    '**Together:** decide on a "UPS stopped charging" alert (the ESP32 UPS LED monitor idea would cover it)',
], state_append='Do not re-run full-load tests on the pegboard (94°C and climbing).')
convert('Baby-cry alert via ntfy (replace SMS Shortcut)', [
    '**Pramod:** observe the SE on iOS 26 for a few days: does it send cry alerts?',
    '**Together:** if it still sends nothing, run the two checks in "If the SE stays silent"',
    '**Pramod:** check it fires with the SE locked on its charger while Alfred holds the mic (outstanding from the 2026-10-03 close)',
    '**Pramod:** turn off (not delete) the SMS automation on the iPhone 14 once ntfy has carried a few real cries',
], detail=('If the SE stays silent', '(1) Check whether the SE shows its own Sound Recognition banner when a crying clip plays. No banner means recognition is not running; a banner but no ntfy alert means the Shortcut or Tailscale is at fault. (2) Repeat with Alfred closed. If it then fires, Alfred and Sound Recognition cannot share the SE, so either Alfred moves to another phone or the iPhone 14 becomes the listener.'))
convert("Use xero's spare RAM", [
    '**Claude:** after a few days of normal Immich use, run `tools/zfs/arc_max.sh stats` and compare with the Log baseline at a similar uptime; if ghost hits stop climbing and the metadata hit rate rises, set Done',
])
convert('Hands-free Claude in the car (Siri -> HA Assist -> Claude)', [
    '**Pramod:** buy API credit (console -> Plans & Billing; auto-reload off makes it a hard cap)',
    '**Claude:** then re-run `setup_claude_pipeline.py` (`set -a; . ./.env.healthcheck; . ./.env.anthropic; set +a; projects/voice-assistant/setup_claude_pipeline.py`): home location for web search, the two test questions',
    '**Pramod:** build the Shortcut (README step 3)',
])
convert('Spotify by voice (HA Assist)', [
    '**Pramod:** try it by voice on both satellites for a few days and report titles that fail',
    '**Claude:** add `ALIASES` in `spotify_library.py` for the titles that fail',
], state_append='Phase 2 ("play anything") is parked on the no-paid rule: Moonshine is fast enough locally (0.3s) but needs a Wyoming wrapper and its own pipeline or wake phrase.')
open(P, 'w').write(s)
