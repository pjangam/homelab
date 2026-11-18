#!/bin/sh
# ExecStopPost of every generated job unit: saves the run's peak memory while
# its cgroup still exists. systemd 255 drops MemoryPeak once a oneshot unit
# stops (kept from 256 on), so jobs_collector.py reads it from here.
#   record_run.sh <unit name>
# Writes ~/.local/state/jobs-dashboard/<unit>.run: "<unix time> <peak bytes> <exit status>".
# Never fails: the unit runs it with a "-" prefix, and a recorder problem must
# not mark the job failed.
st=${XDG_STATE_HOME:-$HOME/.local/state}/jobs-dashboard
mkdir -p "$st" || exit 0
cg=$(systemctl --user show -p ControlGroup --value "$1" 2>/dev/null)
peak=$(cat "/sys/fs/cgroup$cg/memory.peak" 2>/dev/null)
printf '%s %s %s\n' "$(date +%s)" "${peak:-NaN}" "${EXIT_STATUS:-}" > "$st/$1.run.tmp" &&
  mv "$st/$1.run.tmp" "$st/$1.run"
exit 0
