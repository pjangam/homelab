# Baby-cry alert via ntfy (replace SMS Shortcut)
**Status:** Active
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Together:** run the two checks in "If the SE stays silent" (the iOS 26 observation is over: it never sent a real alert); check (2), Alfred closed, is the same as the mic test in "Replace Alfred Camera", so do them in one sitting
- [ ] **Pramod:** turn off (not delete) the SMS automation on the iPhone 14 once ntfy has carried a few real cries

**Why:** a baby-cry alert already exists, but it goes out as an SMS. An iPhone Shortcut fires on Sound Recognition's "Baby Crying" and texts a number. The plan is to move the listening to a **different, dedicated iPhone** that stays near the baby, and have it publish to the self-hosted ntfy on xero instead of SMS. That gives a real push to every subscribed phone, at a priority that can break through, with no carrier involved.
**State:** reopened 2026-10-05 after a Done close on 2026-10-03. Server side and the SE's Shortcut work end to end, but the SE has sent no cry alerts in real use. Its mic hears the cry (Alfred on the SE keeps sending its own baby-cry alerts), so the likely suspect is Alfred holding the mic, with iOS pausing Sound Recognition while another app records. The SE was updated to iOS 26 on 2026-10-05; by 2026-11-07 it had still **never** sent a real cry alert over ntfy (user). Removing Alfred ("Replace Alfred Camera with a free, local baby monitor on the iPhone SE") is now the likely fix.
#### If the SE stays silent
(1) Check whether the SE shows its own Sound Recognition banner when a crying clip plays. No banner means recognition is not running; a banner but no ntfy alert means the Shortcut or Tailscale is at fault. (2) Repeat with Alfred closed. **Play the clip at a real cry's volume from the cot, not next to the phone:** the SE is mounted high in a corner of the room (user, 2026-11-07), farther from the cot than the iPhone 14 whose SMS automation does fire, and Sound Recognition may need a louder or closer cry than Alfred's own detection. If it fires only with the clip held near the phone, distance is the cause: move or angle the SE, which the Alfred-replacement placement step already plans to revisit. If it then fires, Alfred and Sound Recognition cannot share the SE, so either Alfred moves to another phone or the iPhone 14 becomes the listener.

#### Feasibility
**Yes, and nothing has to be bought if a second iPhone is at hand.** Shortcuts has a **Sound Recognition** personal-automation trigger, and the automation can be set to run without asking ([Apple: run automations automatically](https://support.apple.com/guide/shortcuts/apd602971e63/ios)). "Baby Crying" is one of the built-in sounds ([iPhone Life](https://iphonelife.com/content/how-to-enable-use-sound-recognition-iphone-ios-14), [iMore](https://imore.com/how-set-and-use-sound-recognition-iphone-and-ipad)). The existing SMS automation already proves the trigger works; only the action changes. Recognition happens on the phone itself. The ntfy POST only needs the tailnet, so it survives an ISP outage while the LAN is up and xero is on the UPS.

#### Design notes
- **The action:** replace "Send Message" with "Get Contents of URL", method POST, to the ntfy **root** URL `https://ntfy.{tailnet}/`. The body is JSON `{"topic":"baby-cry","title":...,"message":...,"priority":5,"tags":["baby"]}`, with `priority` as a number, not a string. The header is `Authorization: Bearer tk_...`. Set the automation to **Run Immediately**.
- **New topic `baby-cry`, with its own write-only principal** (e.g. `babycry`) and token. Add it to `tools/notify/setup_ntfy_users.sh` the same way as `clawlight`, `healthcheck` and `watchtower`, give `pramod` read-write on it, and extend `tools/notify/verify_ntfy_topics.sh` to cover it in both directions. **Do not put the `pramod` password in the Shortcut:** it reads every topic, and a Shortcut can be shared or exported.
- **Receiving phones subscribe to `baby-cry` at high/urgent priority.** The listener publishes at priority 5 (urgent). In the ntfy app, check that the subscription is not muted and that the alert sound is set, so the push actually makes a noise. It is its own topic, so muting `clawlight` or `homelab-updates` never silences it.
- **Keep the SMS automation until ntfy is proven, then disable it, but do not delete it.** Run both side by side until several real cries have arrived over ntfy on every receiving phone. Disabling instead of deleting keeps SMS one tap away if ntfy, Tailscale or xero ever lets it down.
- **The listener iPhone must stay plugged in, on Wi-Fi, and on Tailscale with VPN On Demand.** ntfy is tailnet-only with `auth-default-access: deny-all` (`services/ntfy/server.yml`), so without Tailscale every POST fails, and SMS would no longer be there to cover it. Test once with Tailscale switched off, to see what failure looks like.
- **Locked-phone behaviour decides the whole thing.** Sound Recognition is reported to listen only while the phone is awake, and it is not clear whether the Shortcut runs from a locked screen. Check both with the phone locked and the screen off before it goes into service. If it fails, the fallbacks are Auto-Lock "Never" on the charger, with brightness turned all the way down, or Guided Access.
- **Mains-dependent.** In a long power cut the listener runs on its battery, then dies, and the Wi-Fi drops with it. Note this; at night it matters.
- **Supplementary only.** Apple says Sound Recognition must not be relied on where someone could be harmed. This is a convenience alert, not a safety monitor.
- **Unverified on the listener:** older iOS disables "Hey Siri" while Sound Recognition is on. Whether Sound Recognition still hears anything while another app (Alfred) holds the mic is also unknown.
- **Shortcut gotchas (found 2026-10-03):** ntfy accepts only `Authorization: Bearer tk_…` - the header typed as `Authorisation` with no `Bearer ` prefix gave 403s - and a trailing slash (`/baby-cry/`) returns 404.
- **Access:** `everyone` has read-only on `baby-cry`, so every account, including ones made later, and anonymous tailnet clients receive it. Only `babycry` and `pramod` can publish.
- **Network route:** the listener reaches ntfy over Tailscale (VPN On Demand). If Tailscale proves flaky on that phone, the fallback is to also publish ntfy on xero's LAN address (`192.168.1.123:8127`, plain HTTP, publish-only token).

#### Alfred Camera, the camera half (moved here from `Readme.md` 2026-11-04)
The root Readme is host-level only now, so the camera notes live with the
entry they belong to. Unchanged from what it said; the Shortcuts recipe below
is **not known to work** - see Overlaps for why its trigger looks absent.


Currently using **Alfred Camera** on iPhone. No native HA integration exists yet.

**Features in use:** low light mode, motion detection alerts, sound alerts.

**Approach under consideration — bridge Alfred alerts to HA via iOS Shortcuts:**
- Alfred detects motion/sound → sends push notification to iPhone
- iOS Shortcuts automation fires on Alfred notification → sends HTTP POST to HA webhook
- HA webhook triggers automations (lights, alerts on other devices, etc.)
- Low light mode stays Alfred's job — no HA integration needed for that

**HA side (webhook automation skeleton):**
```yaml
automation:
  - alias: "Alfred Motion Alert"
    trigger:
      - platform: webhook
        webhook_id: alfred_motion
    action:
      - ... # e.g. notify, turn on light
```
Webhook URL: `http://<ha-ip>:8123/api/webhook/alfred_motion`

**iOS Shortcuts side:**
1. Shortcuts → Automation → New Automation
2. Trigger: App → Alfred → "Notification received"
3. Action: Get Contents of URL → POST to HA webhook URL
4. Create separate automations for motion and sound (filter by notification text)

**Other options ruled out:**
- RTSP server apps on iPhone — iOS restricts background network servers, unreliable
  - *2026-11-07: never tested, and the reason only holds for a backgrounded app; a foreground RTSP/ONVIF app on the charger is now the first test in "Replace Alfred Camera with a free, local baby monitor on the iPhone SE".*
- New hardware — not preferred
- Alfred web viewer — laggy and buggy

#### Overlaps
- **Baby monitor, Alfred Camera** ("Alfred Camera, the camera half" above; `iphone_se` in `docs/hardware.md`). Alfred already sends cloud sound alerts from the SE. If the dedicated listener turns out to be the phone running Alfred, check that the two do not fight over the mic (it is: see the Log for 2026-10-03). This entry is also the local route for the "bridge Alfred alerts via Shortcuts" idea above. That plan's "App -> Alfred -> Notification received" trigger does not appear to exist in Shortcuts, whereas the Sound Recognition trigger does.
- **"Replace Alfred Camera with a free, local baby monitor on the iPhone SE"** (2026-11-07): the replacement test includes whether Sound Recognition fires while the new app streams with and without audio. If it does, removing Alfred fixes this entry; if not, that entry's Frigate audio `crying` detection on xero is the fallback cry alert.
- **"ESP32 UPS LED monitor"** considers listening for a UPS low-battery beep. A second automation on the same listener phone (iOS 16+ can be trained on a custom alarm sound) could cover that later, on its own topic.

#### Phase 2: the touch-button mister (optional, decide later)
A smart plug only restores power; this mister then waits for a touch press. Options, in order of preference:
- **Test first.** Some touch-button units remember their last state across a power cut. Press it on, unplug, replug: if it comes back misting, a plug is enough after all.
- **Simulate the touch.** Open it up and find the touch pad (usually a copper pad behind the plastic wired to a TTP223-style touch IC, or a plain tactile switch under the panel). Have the ESP32 short the IC's output/the button's two contacts through a **PC817 optocoupler** (~Rs 10), so the mister's circuit stays isolated from the ESP32. Pulse it ~200ms after power-up via the smart plug, or leave the mister permanently powered and toggle with the button. Feasible because most ultrasonic misters run off a **24V DC adapter**, so the board is low voltage - **check this first; if it is mains inside, do not open it.** Two catches: a press usually cycles modes (off -> low -> high -> off), so the automation must know the state, and water near the hacked board.
- **Swap the mister** for one with a mechanical rocker switch (~Rs 800-1,500, estimate) that starts on power - then only the plug is needed.
- **Skip it.** If phase 1 (AC dry mode) is all that matters in practice, drop phase 2. The bedroom problem is usually too humid, not too dry.

#### Readymade alternatives
Alfred, already in use, is cloud-dependent. A dedicated baby monitor with cry detection is a second device, cloud-tied or limited in range, and cannot be pointed at xero. The current SMS route works, but it is a single recipient, depends on the carrier and costs per message. On a phone already owned, the ntfy route wins.

#### Parts
```parts
qty | item | est | note
1 | iPhone as the dedicated listener | 0 | a spare one already owned - confirm which; nothing to buy if it exists
1 | charger + cable for it, by the cot | 0 | reuse a spare; a phone charger from a local shop if not
```

**Cost:** ₹0 on a spare iPhone and charger already owned.

#### Effort
~1 hour. (1) 15min: on the listener phone, turn on Sound Recognition "Baby Crying" with an automation that only shows a notification, then play a crying clip from a speaker with the **phone locked and on the charger**. This decides the project, and it is the step that will overrun (finding where the phone sits so it hears the cot, and an awake/locked workaround if needed). (2) 15min: `baby-cry` topic, `babycry` user and token in `setup_ntfy_users.sh`, plus `verify_ntfy_topics.sh`. (3) 15min: swap the test action for the ntfy POST, and subscribe the receiving phones at urgent priority. (4) 15min: update `projects/endpoints/endpoints.toml`'s ntfy entry (`desc` lists three topics, `who` the publishers) and re-render with `render_endpoints.py`. Add the listener iPhone to `docs/hardware.md` as a new device (never commit that file). Then run alongside SMS, and disable the SMS automation once proven.

#### Log
- 2026-10-02: idea noted. Original next step: pick the listener iPhone, then run Effort step 1 on it locked and charging; if it fires from a locked screen, the rest is mechanical, and the project is meant to be built.
- 2026-10-03: listener decided - the **iPhone SE that already runs Alfred Camera** by the cot (in `docs/hardware.md` as `iphone_se`). The SMS automation it replaces runs on the iPhone 14. So the Alfred mic-sharing question became live: confirm that Sound Recognition still fires while Alfred is running, and that Alfred still alerts. Also decided: the listener reaches ntfy over Tailscale (VPN On Demand), with the LAN fallback in Design notes.
- 2026-10-03: server side done. The `baby-cry` topic, the write-only `babycry` user and its token (`NTFY_BABYCRY_TOKEN` in `.env.ntfy`) exist via `tools/notify/setup_ntfy_users.sh`. `tools/notify/verify_ntfy_topics.sh` passes all 26 checks, including the babycry token being refused on every other topic and unable to read its own. A Shortcut-shaped JSON POST to `https://ntfy.{tailnet}/` returned 200. `everyone` given read-only on `baby-cry`. `endpoints.toml` lists the fourth topic and has been re-rendered. Still to do at that point: run the locked-screen test on the SE, with Alfred running, (Effort step 1), build the Shortcut with the token, subscribe the receiving phones to `baby-cry`, and retire the SMS automation once ntfy is proven.
- 2026-10-03: the SE's Shortcut published to `baby-cry` end to end, with the notification received on the phone (after fixing the 403s from the `Authorisation` header, see Design notes).
- 2026-10-03: closed as Done at the user's call before the soak. They still needed to check, informally, that it fires with the SE locked on its charger while Alfred holds the mic, and to turn off (not delete) the SMS automation on the iPhone 14 once ntfy has carried a few real cries. If either check failed, reopen.
- 2026-10-05: reopened - the SE has sent no cry alerts in real use. ntfy's cache, which holds 12h, had nothing on `baby-cry`. Over the same days Alfred on the SE kept sending its own baby-cry alerts, and the iPhone 14 still detects the cry. The SE was updated to iOS 26 the same day; observe for a few days (see Next step).
- 2026-11-07: user: the ntfy cry alert has never worked in real use, iOS 26 did not fix it. ntfy's container logs only go back to 2026-11-01 and do not log publishes at the default level, so they could not confirm it either way. Observation item replaced by the "If the SE stays silent" checks, merged with the Alfred-replacement mic test.
