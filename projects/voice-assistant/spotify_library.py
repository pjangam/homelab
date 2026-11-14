#!/usr/bin/env python3
"""Build "play <song>" from the Spotify library (liked songs and PLAYLISTS). Writes two
generated, gitignored files:
  custom_sentences/en/songs.yaml - the {song} list Speech-to-Phrase trains on
  packages/spotify_songs.yaml    - the HA automation: spoken title -> that
                                   exact track's URI, played on xero
A recognised title plays exactly that track; no Spotify search, which picked
wrong songs for correct titles (PROJECTS.md, 2026-11-04).

Borrows the access token HA's Spotify integration keeps in
HOMEASSISTANT_CONFIG/.storage/core.config_entries. Read-only: it never
refreshes the token (HA does, and a refresh here could rotate it under HA),
so if HA has not refreshed it lately this exits and says so - re-run later.
No new Spotify app or account, nothing paid.

Titles are cleaned to what a person says: "Numb - Remastered 2009" and
"Song (feat. X)" become "Numb" and "Song". Titles with no Latin letters left
(Devanagari etc.) are dropped. Marathi/Hindi titles written in Latin script
stay as Spotify spells them: recognised if Speech-to-Phrase guesses the
pronunciation, failing otherwise (user's call, 2026-11-04) - a title that
matters gets a hand-written phonetic alias in ALIASES instead.

    projects/voice-assistant/spotify_library.py [--limit N]
    docker restart speech-to-phrase    # retrain
"""
import argparse
import json
import re
import sys
import time
import unicodedata
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ENTRIES = REPO / "HOMEASSISTANT_CONFIG/.storage/core.config_entries"
HERE = Path(__file__).resolve().parent
OUT_LIST = HERE / "custom_sentences/en/songs.yaml"
OUT_PKG = HERE / "packages/spotify_songs.yaml"
# Which spotifyd plays a "play <song>": by the HA area of the satellite that
# heard it (user, 2026-11-07); anything else (living room, the phone app,
# typed) plays on xero.
SPEAKERS = {
    "bedroom": "media_player.raspberrypi_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast",  # wol Pi's jack
    "default": "media_player.xero_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast",
}

# how it is said -> the title as spoken() writes it. For titles that matter
# and that Speech-to-Phrase cannot pronounce from their spelling.
# Speech-to-Phrase guesses unknown words from English spelling: "aggobai" came
# out as "AG-uh-bye" (2026-11-07), not the Marathi "uh-GO-bye". Spell aliases
# with English words that sound right ("ago" is uh-GO).
ALIASES = {
    "ago bye the go bye": "aggobai dhaggobai",
    "ago bye dago bye": "aggobai dhaggobai",
    "ago by dhago by": "aggobai dhaggobai",
}

# Playlists whose tracks are speakable too, besides the liked songs. Liked
# songs win when a title is in both. Add a playlist by its id (the part of the
# share link after /playlist/, before ?).
PLAYLISTS = {
    "63uNCHuVgqNqXOUPoujY5Q": "Sasa To Sasa Ki Kapoos Jasa",  # user, 2026-11-07
}


def token():
    for e in json.loads(ENTRIES.read_text())["data"]["entries"]:
        if e["domain"] == "spotify":
            t = e["data"]["token"]
            left = t["expires_at"] - time.time()
            if left < 60:
                sys.exit(f"HA's Spotify token expired {-left:.0f}s ago; HA refreshes it "
                         "when it next polls - re-run in a minute")
            return t["access_token"]
    sys.exit("no spotify config entry in HA")


def get(url, tok):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def paged(url, tok, limit):
    while url and limit > 0:
        page = get(url, tok)
        for item in page["items"][:limit]:
            yield item
        limit -= len(page["items"])
        url = page.get("next")


def spoken(title):
    # drop "(feat. X)" and " - Remastered 2009"-style suffixes, but keep the
    # hyphens inside a title ("Jaan - E - Jigar Jaaneman")
    t = re.sub(r"\s*[(\[][^)\]]*[)\]]\s*", " ", title).strip() or title  # "[Chali]" keeps "Chali"
    t = re.split(r"\s+-\s+(?=(?:\d{4}\s+)?(?:remaster\w*|from|live|version|remix\w*|original|"
                 r"complete|male|female|edit|mono|stereo|radio|acoustic|unplugged|lofi)\b)",
                 t, flags=re.I)[0]
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode()
    t = t.replace("&", " and ")
    t = re.sub(r"[^A-Za-z0-9' ]+", " ", t)
    t = re.sub(r"\s+", " ", t).strip().lower()
    return t if re.search(r"[a-z]", t) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=10000, help="max tracks per source")
    a = ap.parse_args()
    tok = token()
    songs, dropped = {}, []  # spoken title -> [uri, "Title - Artist"]
    sources = [f"https://api.spotify.com/v1/me/tracks?limit=50"] + [
        f"https://api.spotify.com/v1/playlists/{pid}/tracks?limit=100" for pid in PLAYLISTS]
    items = (it for url in sources for it in paged(url, tok, a.limit))
    for it in items:
        tr = it.get("track")
        if not tr or tr.get("type") != "track" or not tr.get("uri", "").startswith("spotify:track:"):
            continue  # removed, local file or podcast episode
        name = spoken(tr["name"])
        if name:
            entry = [tr["uri"], f"{tr['name']} - {tr['artists'][0]['name']}"]
            songs.setdefault(name, entry)
            # "in the end by linkin park": more words for the recogniser to go
            # on - a bare short title was heard as another (2026-11-07)
            artist = spoken(tr["artists"][0]["name"])
            if artist:
                songs.setdefault(f"{name} by {artist}", entry)
        else:
            dropped.append(tr["name"])
    for said, title in ALIASES.items():
        songs[said] = songs[title]
    head = "# GENERATED by spotify_library.py - do not edit; gitignored.\n"
    OUT_LIST.write_text(head + json.dumps(
        {"language": "en", "lists": {"song": {"values": sorted(songs)}}}, indent=1) + "\n")
    # JSON is valid YAML; HA loads this as a package.
    OUT_PKG.write_text(head + json.dumps({"automation": [{
        "id": "voice_play_song",
        "alias": "Voice: play a song from the library",
        "triggers": [{"trigger": "conversation",
                      "command": ["play {song}", "play [the] song {song}"]}],
        "variables": {
            "songs": songs,
            "speakers": SPEAKERS,
            "area": "{{ area_id(trigger.device_id) if trigger.device_id else '' }}",
            "speaker": "{{ speakers.get(area, speakers['default']) }}",
            "key": "{{ trigger.slots.song | lower | regex_replace('[^a-z0-9\\' ]', '') | trim }}",
        },
        "actions": [{
            "if": "{{ key in songs }}",
            "then": [
                # xero's speaker is Bluetooth since 2026-11-14: ask xero
                # (projects/spotifyd/bt_speaker_mqtt.py) to reconnect it and
                # wait for the answer, so a speaker switched on a moment ago
                # plays instead of xero falling back to its USB jack.
                {"if": "{{ speaker == speakers['default'] }}",
                 "then": [
                     {"action": "mqtt.publish",
                      "data": {"topic": "bt_speaker_xero/connect", "payload": "play"}},
                     {"wait_for_trigger": [{"trigger": "mqtt", "topic": "bt_speaker_xero/state"}],
                      "timeout": 25, "continue_on_timeout": True},
                 ]},
                {"action": "spotcast.play_media",
                 "data": {"spotify_uri": "{{ songs[key][0] }}",
                          "media_player": {"entity_id": "{{ speaker }}"}}},
                {"set_conversation_response": "Playing {{ songs[key][1] }}"},
            ],
            "else": [{"set_conversation_response": "{{ key }} is not in your liked songs"}],
        }],
    }]}, indent=1, ensure_ascii=False) + "\n")
    print(f"{len(songs)} songs -> {OUT_LIST.relative_to(REPO)}, {OUT_PKG.relative_to(REPO)}; "
          f"dropped {len(dropped)} non-Latin titles: {dropped[:10]}")


if __name__ == "__main__":
    main()
