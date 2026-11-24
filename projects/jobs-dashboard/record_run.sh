#!/bin/sh
# Two hooks on every generated job unit (install_jobs.py):
#
#   record_run.sh start <unit>   ExecStartPre (the last one): starts a sampler
#                                in the unit's own cgroup that reads cpu.stat
#                                every second and keeps the highest 1s CPU %.
#                                systemd kills it with the cgroup when the job
#                                ends.
#   record_run.sh <unit>         ExecStopPost: saves the run's peak memory and
#                                peak CPU % while the cgroup still exists.
#                                systemd 255 drops MemoryPeak once a oneshot
#                                unit stops (kept from 256 on), so
#                                jobs_collector.py reads it from here.
#
# Writes ~/.local/state/jobs-dashboard/<unit>.run:
#   "<unix time> <peak bytes> <peak cpu %> <exit status>"
# CPU % is of one core (100 = one full core; xero has 4), the max over 1s
# samples. A run shorter than a second gets its whole-run rate. The sampler
# itself costs ~0.5-1% of a core, so an idle job reads about that.
# Never fails: the unit runs both with a "-" prefix, and a recorder problem
# must not mark the job failed.
st=${XDG_STATE_HOME:-$HOME/.local/state}/jobs-dashboard
mkdir -p "$st" || exit 0

# usage_usec of a cgroup's cpu.stat and the uptime in centiseconds, without forking
usage() { u=; while read -r k v; do [ "$k" = usage_usec ] && u=$v; done < "$1/cpu.stat"; }
now_cs() { read -r up _ < /proc/uptime; c=$(( ${up%.*} * 100 + 1${up#*.} - 100 )); }

if [ "$1" = start ]; then
  unit=$2
  cg=/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)
  [ -r "$cg/cpu.stat" ] || exit 0
  f=$st/$unit.cpu
  (
    usage "$cg"; now_cs; c0=$c u0=$u lu=$u lc=$c max=-1
    echo "$c0 $u0 $lc $lu $max" > "$f"
    while sleep 1; do
      usage "$cg"; now_cs
      dc=$(( c - lc ))
      if [ "$dc" -gt 0 ]; then
        p=$(( (u - lu) / (dc * 10) ))   # tenths of a percent of one core
        [ "$p" -gt "$max" ] && max=$p
      fi
      lu=$u lc=$c
      echo "$c0 $u0 $lc $lu $max" > "$f"   # no tmp+mv: one fork less a second
    done
  ) </dev/null >/dev/null 2>&1 &
  exit 0
fi

unit=$1
# The final counter first: this hook runs in the job's cgroup, so everything
# it does from here on (systemctl alone is ~20ms) is charged to the job.
cg=/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)
u=; c=; [ -r "$cg/cpu.stat" ] && { usage "$cg"; now_cs; }
cpu=NaN
if [ -n "$u" ] && [ -r "$st/$unit.cpu" ] && read -r c0 u0 lc lu max < "$st/$unit.cpu"; then
  if [ "$max" -lt 0 ]; then
    # no full second sampled: the whole run's rate (it includes the hooks'
    # own few ms, so very short jobs read high)
    dc=$(( c - c0 )); [ "$dc" -gt 0 ] && max=$(( (u - u0) / (dc * 10) ))
  elif [ $(( c - lc )) -ge 50 ]; then
    # the last partial second, if it is long enough not to be mostly this hook
    p=$(( (u - lu) / ((c - lc) * 10) )); [ "$p" -gt "$max" ] && max=$p
  fi
  [ "$max" -ge 0 ] && cpu=$(( max / 10 )).$(( max % 10 ))
fi
peak=$(cat "$cg/memory.peak" 2>/dev/null)
rm -f "$st/$unit.cpu"
printf '%s %s %s %s\n' "$(date +%s)" "${peak:-NaN}" "$cpu" "${EXIT_STATUS:-}" > "$st/$unit.run.tmp" &&
  mv "$st/$unit.run.tmp" "$st/$unit.run"
exit 0
