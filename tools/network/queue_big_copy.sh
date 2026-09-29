#!/usr/bin/env bash
# Copy large files to a homelab host over a link that is slow and stalls,
# optionally waiting for a transfer already in flight to finish first.
#
# Written 2026-09-29, moving 3.3 GB of birthday photos to xero across a
# 2.4 GHz Wi-Fi hop doing ~1.2 MB/s (see lancheck.sh for why it was that
# slow). Two things that copy needed and `scp` does not give you:
#
#   - resume. scp restarts from byte zero when the link drops, and on this
#     path it dropped. rsync --append continues from the bytes already at the
#     far end, so a retry costs seconds rather than the whole file, and a
#     partial file left by an earlier scp is a head start rather than garbage
#     to delete.
#
#     macOS ships *openrsync* as /usr/bin/rsync (protocol 29, "2.6.9
#     compatible"), which has --append but NOT --append-verify: it trusts the
#     existing prefix instead of checksumming it. That is why the sha256
#     check at the end of this script is not optional - it is the only thing
#     standing between a bad resume and a silently corrupt archive. On a
#     mismatch the script deletes the remote file and recopies it clean.
#   - patience. The wireless hop went 25+ seconds without moving a byte while
#     still being perfectly alive, so a short --timeout would abort a healthy
#     transfer. --timeout=300 plus an outer retry loop rides that out.
#
# Compression is deliberately off: these are .zip files and -z would burn CPU
# on both ends to make them fractionally larger.
#
# Usage:
#   tools/network/queue_big_copy.sh [--wait-pid PID] [--host H] [--dest DIR] FILE...
# Defaults: host 192.168.1.123 (xero), dest ~/Downloads, no wait.
#
# Every file is verified by sha256 on both ends before the script calls it
# done - rsync verifies its own transfer, but a file another tool started
# (the scp above) has never been checked end to end.

set -u

HOST="192.168.1.123"
DEST="~/Downloads"
WAIT_PID=""
RETRIES=20

while [ $# -gt 0 ]; do
  case "$1" in
    --wait-pid) WAIT_PID="$2"; shift 2 ;;
    --host)     HOST="$2";     shift 2 ;;
    --dest)     DEST="$2";     shift 2 ;;
    --retries)  RETRIES="$2";  shift 2 ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

[ $# -gt 0 ] || { echo "usage: $0 [--wait-pid PID] [--host H] [--dest DIR] FILE..." >&2; exit 2; }

log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*"; }

if [ -n "$WAIT_PID" ]; then
  log "waiting for pid $WAIT_PID to finish before starting"
  while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 15; done
  log "pid $WAIT_PID has exited"
fi

overall=0
for f in "$@"; do
  base=$(basename "$f")
  local_size=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f")
  log "=== $base ($(awk -v b="$local_size" 'BEGIN{printf "%.2f", b/1e9}') GB) ==="

  # A partial from a previous attempt is a head start, not a problem.
  already=$(ssh -o BatchMode=yes "$HOST" "stat -c %s \"$DEST/$base\" 2>/dev/null || echo 0" 2>/dev/null)
  [ "${already:-0}" -gt 0 ] && \
    log "  $((already * 100 / local_size))% already there ($already bytes) - resuming"

  # --progress only on a terminal; in a log file its \r updates are unreadable.
  PROGRESS=""; [ -t 1 ] && PROGRESS="--progress"

  attempt=1
  while [ "$attempt" -le "$RETRIES" ]; do
    start=$(date +%s)
    if rsync -a --partial --append --inplace --timeout=300 \
         $PROGRESS "$f" "$HOST:$DEST/"; then
      log "  rsync finished in $(( $(date +%s) - start ))s (attempt $attempt)"
      break
    fi
    log "  rsync exited $? after $(( $(date +%s) - start ))s - retrying (attempt $attempt/$RETRIES)"
    attempt=$((attempt + 1))
    sleep 10
  done

  if [ "$attempt" -gt "$RETRIES" ]; then
    log "  GAVE UP on $base after $RETRIES attempts"
    overall=1
    continue
  fi

  log "  verifying sha256 on both ends"
  want=$(shasum -a 256 "$f" | awk '{print $1}')
  got=$(ssh -o BatchMode=yes "$HOST" "sha256sum \"$DEST/$base\"" 2>/dev/null | awk '{print $1}')
  if [ -n "$got" ] && [ "$want" = "$got" ]; then
    log "  OK  $base verified ($want)"
    continue
  fi

  # A bad resume is the likely cause, so a second --append would rebuild the
  # same wrong file. Start the copy over from an empty destination.
  log "  MISMATCH $base: local $want / remote ${got:-<none>} - recopying clean"
  ssh -o BatchMode=yes "$HOST" "rm -f \"$DEST/$base\"" 2>/dev/null
  if rsync -a --partial --inplace --timeout=300 $PROGRESS "$f" "$HOST:$DEST/"; then
    got=$(ssh -o BatchMode=yes "$HOST" "sha256sum \"$DEST/$base\"" 2>/dev/null | awk '{print $1}')
  fi
  if [ "$want" = "${got:-}" ]; then
    log "  OK  $base verified after clean recopy ($want)"
  else
    log "  FAILED $base: still does not match after a clean recopy"
    overall=1
  fi
done

log "done (exit $overall)"
exit "$overall"
