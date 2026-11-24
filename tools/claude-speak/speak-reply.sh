#!/bin/bash
# Speak Claude's last reply aloud (macOS). Runs from the Stop hook in ~/.claude/settings.json;
# installed to ~/.claude/hooks/ by install.sh in this folder - edit the repo copy, not that one.
# Off by default: on with `touch ~/.claude/speak`, off with `rm ~/.claude/speak`.
# Optional voice/rate: put e.g. `-v Samantha -r 210` in ~/.claude/speak.
toggle="$HOME/.claude/speak"
[ -f "$toggle" ] || exit 0

input=$(cat)
# Newer Claude Code passes the reply directly; fall back to the transcript.
text=$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')
if [ -z "$text" ]; then
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
  [ -f "$transcript" ] || exit 0
  text=$(jq -rs '
    [.[] | select(.type == "assistant")
         | .message.content[]? | select(.type == "text") | .text]
    | last // empty' "$transcript")
fi
[ -z "$text" ] && exit 0

opts=$(head -n1 "$toggle")
[ -z "$opts" ] && opts="-v Samantha -r 210"  # the MacBook's system default voice rendered silence (2026-11-20)

# Stop any reply still being read, so replies don't talk over each other
killall say 2>/dev/null

# Drop code blocks, tables and markdown symbols. No length cap: a cap cut long
# replies off mid-sentence (2026-11-20); `killall say` stops one early.
# Acronyms to spell out: any case (XmlParser splits to "Xml"), then uppercase-only
# for the short ones that are also words or syllables (ha, os, pr, ...).
any='ID|XML|HTML|HTTPS?|URL|URI|API|CSS|SQL|AWS|RDS|SSH|DNS|CLI|SDK|JWT|LAN|VPN|MQTT|TCP|UDP|PDF|CPU|GPU|SSD|USB|LLM|EC2|S3|JS|TS|DB'
upper='HA|OS|IP|PR|UI|CI|CD|IO|AI|ESP'
spell='sub sp { my ($w, $s) = @_; join(" ", split(//, uc $w)) . $s }
  s/\b('"$any"')(s?)(?![a-zA-Z])/sp($1, $2)/gie; s/\b('"$upper"')(s?)(?![a-zA-Z])/sp($1, $2)/ge'
speech=$(mktemp -t claude-speak)
printf '%s' "$text" \
  | sed -E '/^```/,/^```/d; /^\|/d; s/[*#`]//g' \
  | perl -pe 's/_/ /g; s/([a-z0-9])(?=[A-Z])/$1 /g; s/([A-Z]+)(?=[A-Z][a-z])(?![A-Z]s\b)/$1 /g' \
  | perl -pe "$spell" > "$speech"
# The first perl splits identifiers into words (keeping a plural s: APIs, not AP Is), or say reads them as one:
# ItineraryItemDetailResponse, snake_case, HTTPServerError -> HTTP Server Error.
# Then acronyms are spelled letter by letter, or say reads XML as a word and the
# split getUserById as "user id" (the word).

# Claude Code kills the hook's process group when it exits, which took a plain
# `say &` with it. Fork into a new session (macOS has no setsid binary) so say survives.
perl -MPOSIX -e 'fork and exit; POSIX::setsid(); exec @ARGV' \
  sh -c 'say "$@" -f "$0"; rm -f "$0"' "$speech" $opts </dev/null >/dev/null 2>&1
exit 0
