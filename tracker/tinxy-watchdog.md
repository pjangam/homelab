# Tinxy watchdog: two-tier recovery + entity-based down-detection
**Status:** Done

**Why:** the 2026-07-27 ISP outage exposed two gaps in `watchdog_tinxy.sh`.
**Outcome:** both gaps fixed - entity-availability detection added alongside the log grep, and recovery now reloads the config entry before escalating to a full restart. All three tiers (start watch, reload, escalate to restart) tested live against the real script and real data, including one real end-to-end restart.

#### The two gaps and fixes
- **(1) Detection only grepped MQTT connect/disconnect log lines** - blind to a stalled integration setup that logged nothing distinctive after one of the watchdog's own restarts. Fixed by adding a second signal: querying actual Tinxy entity availability via the HA API, tripping at >=90% unavailable (had to be that high since ~60% of registered entities are *always* unavailable already, from old/decommissioned devices - see the backlog item for those).
- **(2) Recovery jumped straight to a full `docker restart homeassistant`** - now tries a lighter config-entry reload first (what actually fixed the outage) at 20min, only escalating to a full restart at 35min if that doesn't clear it.
