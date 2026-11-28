#!/usr/bin/env bash
# Install (or update) the spoken-reply units on one host. Run ON XERO:
#   projects/voice-assistant/install_voice_reply.sh xero
#   projects/voice-assistant/install_voice_reply.sh pi     # copies to the wol Pi over ssh
# User units, no sudo (linger is on on both). Re-run after changing
# voice_reply_mqtt.py or the units. plan-room-replies.md step 2.
set -euo pipefail
HOSTNAME_ARG="${1:?usage: $0 xero|pi}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PI="pramod@192.168.1.124"

case "$HOSTNAME_ARG" in
  xero)
    ENV='VOICE_REPLY_HOST=xero
VLC_OUTPUT=--aout=pulse
VOICE_REPLY_AMIXER=-D pipewire
VOICE_REPLY_CONTROL=Master
BT_SPEAKER_MAC=0D:67:1F:80:92:22'
    mkdir -p ~/.config/systemd/user
    printf '%s\n' "$ENV" > ~/.config/voice-reply.env
    cp "$HERE/voice-reply-vlc.service" ~/.config/systemd/user/
    sed "s#REPO_DIR#$REPO#g" "$HERE/voice-reply.service" > ~/.config/systemd/user/voice-reply.service
    systemctl --user daemon-reload
    systemctl --user enable voice-reply-vlc voice-reply
    systemctl --user restart voice-reply-vlc voice-reply
    systemctl --user --no-pager status voice-reply-vlc voice-reply | grep -E '●|Active'
    ;;
  pi)
    PI_ROOT=/home/pramod/homelab
    ENV='VOICE_REPLY_HOST=pi
VLC_OUTPUT=--aout=alsa --alsa-audio-device=default:CARD=Headphones
VOICE_REPLY_AMIXER=-c Headphones
VOICE_REPLY_CONTROL=PCM'
    ssh "$PI" "mkdir -p $PI_ROOT/projects/voice-assistant ~/.config/systemd/user"
    scp -q "$HERE/voice_reply_mqtt.py" "$HERE/done.mp3" "$HERE/yes.mp3" "$PI:$PI_ROOT/projects/voice-assistant/"
    scp -q "$HERE/voice-reply-vlc.service" "$PI:.config/systemd/user/"
    sed "s#REPO_DIR#$PI_ROOT#g" "$HERE/voice-reply.service" | ssh "$PI" "cat > .config/systemd/user/voice-reply.service"
    printf '%s\n' "$ENV" | ssh "$PI" "cat > .config/voice-reply.env"
    ssh "$PI" 'systemctl --user daemon-reload && systemctl --user enable voice-reply-vlc voice-reply &&
      systemctl --user restart voice-reply-vlc voice-reply && sleep 3 &&
      systemctl --user --no-pager status voice-reply-vlc voice-reply | grep -E "●|Active"'
    ;;
  *) echo "usage: $0 xero|pi" >&2; exit 2 ;;
esac
