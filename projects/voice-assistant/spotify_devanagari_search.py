#!/usr/bin/env python3
"""Does Spotify search find our Marathi songs from a Devanagari query?

Question (user, 2026-11-15): a Marathi speech-to-text fallback (AI4Bharat
IndicConformer) would write what it hears in Devanagari. Could we hand that
text straight to Spotify search instead of matching it against our own
Latin-script song list?

For each song in the "Sasa To Sasa" playlist, search Spotify with the title
written in Devanagari - the correct spelling and a sloppier one, the way an ASR
might write it - and report where our exact track (the playlist's URI) lands,
and where the first track with the same Latin title lands (another version).
Read-only: search only, nothing is played.
    projects/voice-assistant/spotify_devanagari_search.py
"""
import json
import re
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import spotify_library as lib  # noqa: E402

# Latin title in the playlist -> (track id, [Devanagari queries]).
# First query: the usual spelling. Others: what an ASR might write instead
# (short/long vowels, ड/ढ, missing anusvara).
TESTS = {
    "Aggobai Dhaggobai": ("6YH1K7b7dgyvHDKRkt0TQ8", ["अग्गोबाई ढग्गोबाई", "अगोबाई ढगोबाई", "अग्गो बाई डग्गो बाई"]),
    "Sasa To Sasa Ki Kapoos Jasa": ("6fNygOaI3qZMlEM1aDAbpo", ["ससा तो ससा की कापूस जसा", "ससा तो ससा कि कापुस जसा"]),
    "Chiv Chiv Chimni": ("3UKMk5qDLsbzOTsUntYmWb", ["चिव चिव चिमणी", "चीव चीव चिमनी"]),
    "Chanda Rani": ("2PUvBo2jUOMB8YgOxe6vTj", ["चांदा राणी", "चंदा रानी"]),
    "Konas Thauk Kasa": ("29f68GCEcnZX4P4lbTgcpb", ["कोणास ठाऊक कसा", "कोनास ठाउक कसा"]),
    "Mungibai": ("7exzwqyQsCiGmDavDOhTTF", ["मुंगीबाई", "मुंगी बाई"]),
    "Illu Illu Pillu": ("7fzwmZNuxwzE0vmk4ZTpKX", ["इल्लु इल्लु पिल्लु", "इलु इलु पिलु"]),
    "Boom Boom Ba": ("4wtV6JnIOWEpBNO9MsoPWu", ["बूम बूम बा"]),
    "Eka Makdane Kadhla Dukan": ("72meSAxKkxn09QKqbc9xio", ["एका माकडाने काढलं दुकान", "एका माकडाने काढला दुकान"]),
    "Beduk Shalemadhe Gela": ("2kMUizEd0MojrTJJK0hAbz", ["बेडूक शाळेमध्ये गेला", "बेडुक शालेमधे गेला"]),
    "Jhuk Jhuk Gadi": ("2s3aeem6eX8wfHEjBTr7rF", ["झुक झुक गाडी"]),
    "Sang Na Aai": ("0RBeJh7lzypeRboVQwUmor", ["सांग ना आई", "सांगना आई"]),
    "Manu Tai Aali": ("3jffqto01DxU2QV20OJQl4", ["मनू ताई आली", "मनु ताई आलि"]),
    "Pakhra Pakhra Yeun Ja": ("6qvwVnSJujUf0R31fdMDns", ["पाखरा पाखरा येऊन जा"]),
    "Swapnat Pahili Ranichi Baug": ("0axKwznYEjUSj8duS5Ukqi", ["स्वप्नात पाहिली राणीची बाग"]),
}


def search(q, tok, limit=10):
    url = ("https://api.spotify.com/v1/search?type=track&market=from_token&limit=%d&q=%s"
           % (limit, urllib.parse.quote(q)))
    return lib.get(url, tok)["tracks"]["items"]


def library_uris():
    # every track the voice command can play: liked songs + PLAYLISTS
    return set(re.findall(r'"spotify:track:([A-Za-z0-9]+)"', lib.OUT_PKG.read_text()))


def main():
    tok = lib.token()
    mine = library_uris()
    exact = same = guard = wrong = total = 0
    for title, (tid, queries) in TESTS.items():
        print(f"\n{title}")
        for q in queries:
            total += 1
            items = search(q, tok)
            ranks = [i for i, t in enumerate(items, 1) if t["id"] == tid]
            alt = [i for i, t in enumerate(items, 1) if lib.spoken(t["name"]) == lib.spoken(title)]
            # the rule a fallback would use: the best-ranked of the top 3 that is in
            # our library, else nothing (never play a stranger's song)
            lib_hit = next((t for t in items[:3] if t["id"] in mine), None)
            guard += bool(lib_hit and lib_hit["id"] == tid)
            wrong += bool(lib_hit and lib_hit["id"] != tid)
            top = f"{items[0]['name']} - {items[0]['artists'][0]['name']}" if items else "(nothing)"
            exact += bool(ranks and ranks[0] == 1)
            same += bool(alt and alt[0] == 1)
            print(f"  {q:32} ours: {('#%d' % ranks[0]) if ranks else '-':4} "
                  f"same title: {('#%d' % alt[0]) if alt else '-':4} "
                  f"library rule: {'OK' if lib_hit and lib_hit['id'] == tid else (lib_hit['name'] if lib_hit else 'nothing')}"
                  f" | top: {top}")
    print(f"\n{total} queries: our track first {exact}, a same-title track first {same}")
    print(f"library rule (first top-3 result that is in our library): right {guard}, "
          f"wrong song {wrong}, nothing {total - guard - wrong}")


if __name__ == "__main__":
    main()
