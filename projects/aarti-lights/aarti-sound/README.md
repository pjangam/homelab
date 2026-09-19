# Labelled sound samples for the aarti lights Tier 3 classifier

Captured 2026-09-14 with `aarti-sound-lab.py record`, from WLED's
AudioReactive UDP broadcast - i.e. through the INMP441 mounted behind the
makhar, in that room, with that bell. The thresholds in
`aarti_audio.py` are derived from these files, so if the mic
moves, the bell changes, or the room does, re-record rather than re-guess.

Recorded with WLED squelch at **0**: any higher and the board zeroes quiet
frames, which throws away the decay tail - the single most useful feature for
telling a ringing bell from a clap.

| file | contents |
|---|---|
| `ghanta.jsonl` | ~13s of continuous ringing plus handling noise either side |
| `clap.jsonl` | 12 discrete claps at roughly 1s intervals |
| `voice.jsonl` | continuous speech at normal volume |
| `kid.jsonl` | 2026-09-19: the toddler (1) babbling, ~30s |
| `kid2.jsonl` | 2026-09-19: the toddler babbling with an older adult talking to her, 45s - held out from tuning and used to check the kid rule |

Each line is one frame: `t`, `raw`, `smth`, `peak`, 16 `fft` bins, `mag`,
`major`. About 40 frames/sec.

## What the data showed

| class | centroid p10/med/p90 | flatness med | energy med |
|---|---|---|---|
| voice | 1.94 / 2.32 / 2.64 | 0.959 | 712 |
| clap | 6.55 / 8.72 / 9.27 | 0.897 | 2340 |
| ghanta | 3.39 / 8.75 / 11.17 | 0.820 | 560 |

**Voice separates on centroid alone** - its p90 is 2.64 while both bright
sounds sit at 8.7.

**Clap and ghanta do not separate on centroid at all** (8.72 vs 8.75). They
separate on persistence: the ghanta rang continuously for 13 seconds, claps
were discrete bursts under half a second. That is why the classifier is a
state machine and not a per-frame rule, and why a strike cannot be named at
its onset - a bell and a clap look identical for the first moments.

Flatness is the more promising fast discriminator: in live validation the
ghanta read **0.694** against **0.839-0.887** for every clap, a wider gap
than the aggregates above suggest. Worth using to call a bell in ~0.3s
instead of waiting 1.2s for it to sustain.

## The toddler (2026-09-19)

| class | centroid p10/med/p90 | flatness med | energy med |
|---|---|---|---|
| kid | 2.93 / 4.57 / 7.74 | 0.941 | 1456 |

Her centroid overlaps all three classes, so the old rules read her squeals
as claps (12) and bells (4). She separates on **shape**: median share of
energy per bin shows voice empty from bin 6 up, clap spread out to bin 15,
ghanta piled into 14-15, and her with a bump at bins 6-8 and nothing above
bin 9. The `KID_*` rule in `aarti_audio.py` keys on exactly that.
