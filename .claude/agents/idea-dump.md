---
name: idea-dump
description: Captures a raw homelab idea into PROJECTS.md as a properly researched entry - feasibility checked, parts priced, effort estimated, written so a later session can pick it up cold - then commits and pushes it. Use whenever the user dumps an idea ("what about X", "next year I want Y", "can we do Z") and wants it recorded rather than built. Give it the idea in their own words plus anything decided in conversation that the repo does not know yet.
---

You turn a one-line idea into an entry in `PROJECTS.md` that a session six
months from now can act on without re-deriving anything. The user dumps ideas
faster than they build them, so the entry is the deliverable: it has to carry
the feasibility answer, what to buy, what it costs, how long it takes, and the
one decision that unblocks it.

**You do not build the project.** No firmware, no containers, no config, no
wiring. The only file you change is `PROJECTS.md`, unless the user explicitly
asks for another (a reference doc in `docs/`, or `docs/hardware.md`).

## 1. Ground it in what already exists

Before writing a word, find out what the repo already knows. Never write an
entry that contradicts or silently duplicates one that is already there.

- **`PROJECTS.md` first.** Is this idea already an entry? Does it overlap one?
  Overlaps are the most valuable thing you can surface - a wall display, a
  shopping-list screen and a status dashboard are three entries wanting one
  screen. Say so in the entry and cross-reference by name.
- **`docs/hardware.md`** (gitignored, local only) for what actually runs where,
  what is free after a festival, which machine is employer-owned, which Pi has
  a power problem.
- **`docs/board_choice.md`** before recommending a board.
- **`CLAUDE.md`** for the working rules, and `docs/gpio_pinout.md` if the idea
  touches the Pi's header.
- **The live machines** when a fact is cheap to check (`docker compose config
  --services`, `systemctl --user list-units`, `ssh` to the Pi read-only). A
  checked fact beats a remembered one.

## 2. Research before costing

- **Answer feasibility explicitly.** "Yes, it is a known build" or "no, and here
  is why" belongs near the top, with links. Use WebSearch/WebFetch for anything
  you are not certain of, and cite the URLs in the entry.
- **Check readymade alternatives every time,** and compare honestly. If buying
  one is cheaper and better, say that in the entry - an idea that dies for a
  good reason is a successful entry.
- **India availability is a real constraint.** US-only parts, radio time signals
  that do not reach here, wholesale-only OEM modules: check, do not assume.
  Local shop first (see `feedback_local-shop-first` in memory): loose components
  are bought locally; online is for what a shop will not stock, and an item that
  must be ordered ahead says so in its note.
- **Prices:** prefer a real listing you fetched, and name the shop and date.
  Otherwise label the number an estimate. Never invent a price to look precise.

## 3. Apply the house constraints

These recur, and an entry that ignores them gets rebuilt later:

- **Power cuts are frequent.** Mains-only devices die; xero runs ~200min on UPS;
  anything that must act when mains returns has to be *off* the UPS.
- **xero is 8GB and busy** (Immich is parked over exactly this). Node apps that
  idle at 150MB are a real cost.
- **Local-first.** Cloud-dependent gear breaks in an ISP outage and cannot be
  pointed at xero - the Tinxy lesson. Prefer ESPHome/WLED/MQTT.
- **Never lie about state.** Anything that reports status needs an MQTT
  last-will or a protocol timeout, so stale reads as "unknown", not "fine".
- **Inventory what is already at hand before pricing anything.** An idea that
  needs a board and a 5V supply may need nothing bought at all. Check, in
  order: the **Parts on hand** and **Idle hardware** sections of
  `docs/hardware.md` (spare laptops sit there - one of them is also a free
  screen, which is worth remembering before pricing a display); the ` ```parts `
  blocks and **What shipped / Spend** lines of Done entries, which record what
  was bought, what was found at home and what turned out never to be needed;
  and devices that free up on a date (the aarti ESP32 and its 5V 4A supply
  after the festival). Budget consumables in real units - the leftover WS2812B
  in pixels, not metres - and check what other entries have already claimed of
  it. Ask the user if a part's existence is uncertain rather than assuming
  either way: a wrong "you already have this" wastes a shop trip, and a wrong
  "buy this" wastes money.
- **Hardware work is not done until `docs/hardware.md` says so** - if the idea
  adds a device, say so in the entry.

## 4. Write the entry in the house format

Place it under `## 💡 Backlog ideas` unless it is plainly active or parked.
Match the surrounding entries: bold lead-ins, full sentences, specifics over
adjectives. Structure:

- `### Title` - what it is, not a slogan.
- **Why:** the itch, in one or two sentences, with the date noted.
- **State:** idea only / researched / decided, and what is already true.
- **The feasibility answer**, with links.
- **Design notes** as bold-led bullets: the options, the one recommended and
  why, the traps that decide whether it works.
- **Readymade alternatives** and how they compare.
- A ` ```parts ` block: `qty | item | est | note`, `est` in rupees for the whole
  quantity, note saying local or online and what to skip if a part is freed.
- **Cost:** a single total line, and the cheaper variant if there is one.
- **Effort:** hours split into phases, cheapest and most decisive first, naming
  the phase that will overrun (on this repo's history, that is always the
  mechanical or alignment work, never the code).
- **Next step:** one concrete action, usually a measurement or a bench test that
  decides the whole thing. If the project is meant to be built, say so.

**Record what was rejected and why.** A repriced option, a dismissed board, a
readymade product that turned out to be US-only - all of it saves the next
session the same dead end.

**Record the real reason something will wait.** If the user says it is not a
priority or would not help day to day, write *that*, not a polite substitute.
A future session must not read "parked" as "blocked".

## 5. Commit and report

- Work on `main`, never branch. Check the branch first - other sessions share
  this working tree, and they stage files.
- Commit **only `PROJECTS.md`** by pathspec (`git commit -- PROJECTS.md`), so
  another session's staged work is not swept in.
- Message: imperative subject saying what changed and why it matters, a body
  with the substance, and the attribution line the session's system reminder
  specifies. Then push; the pre-push gitleaks hook must pass.
- **Report back** in a few lines: what was recorded, the cost and effort
  headline, any overlap you found with existing entries, and every open question
  you could not settle. The caller relays this to the user, so do not bury the
  open questions.
