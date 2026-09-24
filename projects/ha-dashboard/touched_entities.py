#!/usr/bin/env python3
"""List the entities a person actually changed, from HA's recorder.

The input for curating dashboards/home.yaml: an entity belongs on Home if
somebody acts on it. A state change carries context_user_id when it came from
a user (app, dashboard, voice); automations, integrations and devices changing
themselves leave it NULL. So counting user-initiated changes per entity is a
direct measure of "touched in a normal week", as far back as the recorder goes
(10 days by default).

Physical buttons and remotes act through automations, so they show up in the
second column (changed by an automation), not the first.

    projects/ha-dashboard/touched_entities.py [path/to/home-assistant_v2.db]

Opens the database read-only, so it is safe with HA running.
"""
import datetime
import pathlib
import sqlite3
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
db = sys.argv[1] if len(sys.argv) > 1 else REPO / "HOMEASSISTANT_CONFIG/home-assistant_v2.db"
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)

lo, hi = con.execute("SELECT min(last_updated_ts), max(last_updated_ts) FROM states").fetchone()
fmt = lambda ts: datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
print(f"recorder window: {fmt(lo)} .. {fmt(hi)} ({(hi - lo) / 86400:.1f} days)\n")

# By user: the state's own context has a user. By automation: the context's
# parent is an automation/script run (context_parent_id set, no user).
rows = con.execute("""
    SELECT m.entity_id,
           sum(s.context_user_id_bin IS NOT NULL)                                AS by_user,
           sum(s.context_user_id_bin IS NULL AND s.context_parent_id_bin IS NOT NULL) AS by_automation,
           max(CASE WHEN s.context_user_id_bin IS NOT NULL THEN s.last_updated_ts END) AS last_user
    FROM states s JOIN states_meta m USING (metadata_id)
    -- real state changes, not attribute churn: HA stores last_changed_ts as
    -- NULL when it equals last_updated_ts, and a different value otherwise
    WHERE s.last_changed_ts IS NULL
    GROUP BY m.entity_id
    HAVING by_user > 0 OR by_automation > 0
    ORDER BY by_user DESC, by_automation DESC
""").fetchall()

print(f"{'by user':>8} {'by auto':>8}  {'last by user':16}  entity")
for entity, user, auto, last in rows:
    print(f"{user:>8} {auto:>8}  {fmt(last) if last else '-':16}  {entity}")
