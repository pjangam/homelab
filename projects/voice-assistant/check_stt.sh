#!/usr/bin/env bash
# Is speech-to-phrase able to hear a *custom* voice command? Sends the saved
# clip stt_probe.wav ("turn off the AC", Piper's voice, 16kHz mono) to HA's
# STT API and checks the transcript. Transcription only - nothing is executed.
#
# Two failures this catches, both silent ("No text recognized" for the user):
#   - speech-to-phrase learns the sentences in packages/voice_commands.yaml
#     from HA only when it starts. After a xero boot it can start before HA
#     has loaded them, and then every custom command (AC, fan speed) is
#     unknown until it is restarted (2026-10-09/10).
#   - its Kaldi decoder getting stuck, failing every request with "decoded
#     no frames" (2026-10-06/07, possibly the old bad RAM).
# A built-in phrase would pass in the first case, hence a custom one.
#
# Exit 0 = heard it, 1 = did not (restart speech-to-phrase), 2 = cannot tell
# (HA or its token not answering). Used by projects/healthcheck/healthcheck.sh.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[ -n "${HA_TOKEN:-}" ] || source "$here/../../.env.healthcheck"
out=$(curl -s --max-time 30 -H "Authorization: Bearer $HA_TOKEN" \
  --data-binary @"$here/stt_probe.wav" \
  -H 'X-Speech-Content: format=wav; codec=pcm; sample_rate=16000; bit_rate=16; channel=1; language=en' \
  http://localhost:8123/api/stt/stt.speech_to_phrase) || { echo "HA STT API not answering"; exit 2; }
text=$(jq -r '.text // empty' <<< "$out" 2>/dev/null) || { echo "unexpected reply: $out"; exit 2; }
if [[ "${text,,}" == *"turn off the a c"* ]]; then
  echo "ok: heard '$text'"
  exit 0
fi
echo "probe 'turn off the AC' came back as '${text}'"
exit 1
