#!/usr/bin/env python3
"""Map a Devanagari transcript ("प्ले अग्गोबाई ढग्गोबाई") to one of our songs.

For the Marathi speech-to-text fallback (IndicConformer writes Devanagari;
our song list is Latin script, as Spotify spells it). Two steps, never a
stranger's song:
  1. local: transliterate to rough Latin, squash spelling differences on both
     sides (aa/a, dh/d, w/v, double letters ...), fuzzy-match every title in
     packages/spotify_songs.yaml; accept only a clear winner
  2. Spotify search with the Devanagari text; accept the best of the top 3
     results only if that track is in our library
       (spotify_devanagari_search.py, 2026-11-15: 21/27 right)
Library use: match(text, library(), keys, token) -> (spoken title, uri, how)
or None; stt_fallback.py uses it.
CLI: reads JSON lines {"said": ..., "text": ..., "secs": ...} on stdin
(bench_indicconformer.sh) and prints what each would play.
"""
import difflib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import spotify_library as lib  # noqa: E402

VOWELS = {"अ": "a", "आ": "aa", "इ": "i", "ई": "ee", "उ": "u", "ऊ": "oo", "ऋ": "ru",
          "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au", "ॲ": "a", "ऑ": "o"}
SIGNS = {"ा": "aa", "ि": "i", "ी": "ee", "ु": "u", "ू": "oo", "ृ": "ru", "े": "e",
         "ै": "ai", "ो": "o", "ौ": "au", "ॅ": "e", "ॉ": "o"}
CONS = {"क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "n", "च": "ch", "छ": "chh",
        "ज": "j", "झ": "jh", "ञ": "n", "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh",
        "ण": "n", "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n", "प": "p",
        "फ": "ph", "ब": "b", "भ": "bh", "म": "m", "य": "y", "र": "r", "ल": "l",
        "ळ": "l", "व": "v", "श": "sh", "ष": "sh", "स": "s", "ह": "h", "क्ष": "ksh",
        "ज्ञ": "dny", "ड़": "d", "ढ़": "dh", "फ़": "f", "ज़": "z"}
VIRAMA, ANUSVARA, CHANDRA, VISARGA, NUKTA = "्", "ं", "ँ", "ः", "़"
# "play" as an Indic ASR writes it, said before the title
PLAY = re.compile(r"^\s*(प्लेय|प्लेस|प्लेज|प्लीज|प्ले|प्ली|प्लै|आपली|्ले|ली)\s+")


def translit(text):
    out, i = [], 0
    text = text.replace(NUKTA, "")
    while i < len(text):
        c = text[i]
        if c in CONS:
            out.append(CONS[c])
            nxt = text[i + 1] if i + 1 < len(text) else ""
            if nxt in SIGNS:
                out.append(SIGNS[nxt]); i += 1
            elif nxt == VIRAMA:
                i += 1
            elif nxt and (nxt in CONS or nxt in (ANUSVARA, CHANDRA)):
                out.append("a")  # inherent vowel inside a word
            # end of word: Marathi drops the inherent "a" (कापूस -> kapoos)
        elif c in VOWELS:
            out.append(VOWELS[c])
        elif c in (ANUSVARA, CHANDRA):
            out.append("n")
        elif c == VISARGA:
            out.append("h")
        else:
            out.append(c)
        i += 1
    return "".join(out)


def squash(s):
    """Spelling-blind key: what differs between Spotify's Latin and ours."""
    s = s.lower()
    s = re.sub(r"[^a-z ]", " ", s)
    for a, b in (("chh", "ch"), ("sh", "s"), ("w", "v"), ("ee", "i"), ("oo", "u"),
                 ("aa", "a"), ("ou", "u"), ("ai", "ai"), ("z", "j"), ("q", "k"),
                 ("f", "ph"), ("y", "i")):
        s = s.replace(a, b)
    s = re.sub(r"([bcdgjklpt])h", r"\1", s)  # dh/d, th/t, kh/k ... aspiration
    s = re.sub(r"(.)\1+", r"\1", s)          # aggo -> ago
    s = re.sub(r"\s+", "", s)                 # word breaks differ too
    return s


def library():
    """spoken title -> (uri, 'Title - Artist') from the generated package."""
    text = lib.OUT_PKG.read_text()
    pairs = re.findall(r'"([^"]+)": \[\s*"(spotify:track:[^"]+)",\s*"([^"]+)"', text)
    return {k: (u, n) for k, u, n in pairs}


def match_local(text, lib_map, keys=None):
    q = squash(translit(PLAY.sub("", text)))
    if not q:
        return None
    keys = keys or {k: squash(k) for k in lib_map if " by " not in k}
    scored = sorted(((difflib.SequenceMatcher(None, q, v).ratio(), k) for k, v in keys.items()),
                    reverse=True)
    best, k = scored[0]
    # runner-up must be a different track to count as competition
    second = next((s for s, k2 in scored[1:] if lib_map[k2][0] != lib_map[k][0]), 0)
    if best >= 0.75 and best - second >= 0.08:
        return k, lib_map[k][0], f"local {best:.2f} (next {second:.2f})"
    return None


def match_spotify(text, lib_map, tok):
    import urllib.parse
    q = PLAY.sub("", text).strip()
    if not q:
        return None
    url = ("https://api.spotify.com/v1/search?type=track&market=from_token&limit=3&q="
           + urllib.parse.quote(q))
    # track id -> its spoken title, the key "play {song}" looks up
    # (sorted: the plain title before its "... by <artist>" form)
    key_of = {}
    for k, (u, _) in sorted(lib_map.items(), key=lambda kv: " by " in kv[0]):
        key_of.setdefault(u.split(":")[-1], k)
    for t in lib.get(url, tok)["tracks"]["items"]:
        if t["id"] in key_of:
            return key_of[t["id"]], "spotify:track:" + t["id"], "spotify top-3"
    return None


def match(text, lib_map, keys, tok=None):
    """Local first, then Spotify (when a token is given). None = no song."""
    return match_local(text, lib_map, keys) or (tok and match_spotify(text, lib_map, tok)) or None


def main():
    lib_map = library()
    keys = {k: squash(k) for k in lib_map if " by " not in k}
    tok = lib.token()
    for line in sys.stdin:
        r = json.loads(line)
        hit = match(r["text"], lib_map, keys, tok)
        got = f"{hit[0]}  [{hit[2]}]" if hit else "nothing"
        print(f"{r['secs']:5.2f}s  {r['said']:34} heard {r['text']!r:40} -> {got}")


if __name__ == "__main__":
    main()
