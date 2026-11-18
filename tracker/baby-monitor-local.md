# Replace Alfred Camera with a free, local baby monitor on the iPhone SE
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Together:** RTSP bench test first - Vantage on the SE (Alfred closed), foreground, screen on, on the charger, added to HA's ONVIF integration; then soak overnight (checks in "Effort" phase 1)
- [ ] **Together, during the test:** night-time view in the real dark room at the cot - **must pass** (user, 2026-11-07: low light is a must-have); compare side by side with Alfred's low light mode the same night
- [ ] **Together, during the test:** play a crying clip with Vantage streaming audio, then video-only - does iOS Sound Recognition still fire? (decides the fix for "Baby-cry alert via ntfy")
- [ ] **Pramod:** say which HA room the camera tile goes in (Bedroom is a guess, not decided)
- [ ] **Claude, after a passing test:** HA camera tile, motion -> ntfy automation, and a "stream dropped" ntfy alert; add the SE's RTSP/ONVIF ports to `endpoints.toml` and `docs/hardware.md`
- [ ] **Pramod:** cancel Alfred in App Store subscriptions as soon as the replacement is proven (a couple of weeks), and before 2027-05-19

**Why:** the iPhone SE by the cot runs Alfred Camera, a cloud app on a ₹799/year subscription (renews 2027-05-19). The user wants a free replacement on the same old iPhone (2026-11-07). Being local also means it can be viewed on the HA dashboard, survives an ISP outage, and may stop Alfred blocking the baby-cry Sound Recognition alert.
**State:** researched 2026-11-07; nothing installed. The "old iPhone" is `iphone_se` in `docs/hardware.md`, the one already running Alfred. Its generation is unrecorded, but it took iOS 26 on 2026-10-05, so it is an SE 2nd or 3rd gen: iOS 26 supports SE 2nd gen and later ([MacRumors](https://www.macrumors.com/2025/06/10/ios-26-compatible-iphones-list)). Every app below runs on it.

#### Current Alfred subscription
| | |
|---|---|
| Accepted | 2026-05-15 |
| Trial | free, 3 days from 2026-05-15 |
| Renewal | ₹799/year, started 2026-05-18 |
| Next renewal | **2027-05-19**, as the App Store shows it (Settings -> Subscriptions, checked by the user 2026-11-07); the receipt's 2026-05-18 start would suggest the 18th |
| Paid through | 2027-05-19. Cancelling early only stops the next renewal: Premium keeps working until then, so cancel as soon as the replacement is proven |

#### Feasibility
**Yes, as long as the app stays in the foreground.** Several iOS apps run an RTSP and/or ONVIF server on the phone, and Home Assistant 2026.10.4 on xero already has what it needs to show one: the ONVIF integration built in, and the bundled go2rtc for low-latency WebRTC. go2rtc was checked running inside the `homeassistant` container (`/bin/go2rtc`) on 2026-11-07 ([HA go2rtc docs](https://www.home-assistant.io/integrations/go2rtc/)).
- **The old "RTSP server apps ruled out" note was never tested.** The reason given ("iOS restricts background network servers") is real, but only for an app in the **background**. iOS stops camera capture when the app goes to the background or the phone locks ([Apple forum](https://developer.apple.com/forums/thread/61406)). An app kept in the foreground, with the screen on and the phone on the charger, keeps running. That is exactly how Alfred runs today.
- **The real risks, to check in the test:**
  - **Screen on all night:** set Auto-Lock to Never. The phone runs warm, encoding video 24/7 on the charger.
  - **The app gets killed:** an iOS update, a crash or an incoming call can stop it. HA must send a ntfy alert when the stream drops, so a dead monitor never looks like a quiet baby.
  - **The mic:** if the app records audio, it may block iOS Sound Recognition the same way Alfred appears to.

#### Options compared
| Option | Cost | iOS | Output into HA | Motion | Sound | Low light | Verdict |
|---|---|---|---|---|---|---|---|
| **Vantage: RTSP ONVIF Camera** | free tier "works fully with HA"; some features paid (prices not found) | 17+ | ONVIF (camera + snapshots), RTSP | ONVIF motion binary sensor | not mentioned | not mentioned | **Recommended**: native ONVIF, so camera and motion arrive with no extra software ([HA thread, 2026-09-23](https://community.home-assistant.io/t/turn-a-spare-iphone-into-an-onvif-camera-for-home-assistant-no-cloud-no-account/1026097)). New, developer-posted, with no stability reports yet |
| **IP Camera Lite** | free with ads; paid edition removes them | 15+ | RTSP/RTSPS server with audio, HTTP server | none into HA | none | not mentioned | **Fallback**: older and still updated (v11.4.2, Nov 2026), rated 3.1/5 on 36 ratings; a 2020 review says the server stopped accepting connections after a few hours ([App Store](https://apps.apple.com/us/app/id1013455241)) |
| Guardian Eye WebCamera | not stated; "no subscription" | not stated | ONVIF S/T/M, RTSP `:8554/live` | on-device motion/person -> ONVIF events | no | not mentioned | TestFlight beta only, July 2026 ([HA thread](https://community.home-assistant.io/t/turn-an-old-iphone-into-a-local-onvif-rtsp-camera-for-home-assistant-frigate-no-cloud-beta/1016686)). Revisit if Vantage fails |
| Larix Broadcaster -> go2rtc | free; watermark reported after ~30min; Premium $9.99/month | 18+ | pushes RTSP/RTMP/SRT to a server (go2rtc accepts pushes) | no | no | no | **Rejected**: a broadcaster for live events, with a reported watermark and a subscription ([App Store](https://apps.apple.com/us/app/-/id1042474385)) |
| Alfred free tier | ₹0, with ads | - | none (cloud only) | yes | yes | low light mode | Keeps the cloud dependency and the mic clash; no HA. Premium-only features go away |
| Manything, AtHome Camera | - | - | cloud apps | yes | varies | varies | **Rejected**: cloud, the same problem as Alfred. Manything (Videoloft) still listed in 2026 |
| HA companion app as the camera | - | - | - | - | - | - | **Does not exist**: the iOS companion app has no camera-streaming feature |
| HomeKit camera via HA HomeKit Controller | - | - | - | - | - | - | **Rejected**: no iOS app found that publishes the phone itself as a HomeKit camera |
| GoPro HERO5 Black (owned; user asked 2026-11-07) | 0 | - | no RTSP and cannot join home WiFi: only its own-AP ~480p preview, or clean micro-HDMI out into a USB capture card (~₹1,000-1,500, estimate) on xero/a Pi -> go2rtc | none | mic over HDMI only | **poor**: small sensor, no IR, worse than the SE in a dark room | **Rejected**: fails the low-light must-have, overheats running video 24/7, and needs a capture card and a wired box by the cot. Model confirmed from file metadata, not the earlier HERO4 note |

#### Design notes
- **Recommended: Vantage -> HA ONVIF integration -> HA's built-in go2rtc** for the live view on the dashboard; motion is the ONVIF binary sensor. Nothing new runs on xero.
- **Alerts:** an HA automation turns motion (and sound, see below) into a ntfy push. Use a new topic or `baby-cry`, decided at build time; the `babycry` token is publish-only from the phone, so HA would need its own publisher.
- **Never lie about state.** Add a "baby monitor down" automation: the camera or ONVIF entity unavailable for more than ~2 min -> urgent ntfy. In the test, kill the app and time how long the ONVIF entities take to go unavailable. If they never do, check the RTSP port from xero instead (a script, or HA's `command_line`). Pinging the phone is not enough, because the phone still answers when the app is dead.
- **Sound, three routes (the mic test decides):**
  1. **Video-only stream, Sound Recognition keeps the mic:** this also fixes "Baby-cry alert via ntfy". Best case.
  2. **Stream with audio:** a cry still wakes you through the HA live view, but no cry *alert*.
  3. **Frigate audio detection on xero** listening to the RTSP audio: it has a `crying` label, not on by default ([Frigate docs](https://docs.frigate.video/configuration/audio_detectors)). One user could not get it to fire with a loud baby ([discussion #10241](https://github.com/blakeblackshear/frigate/discussions/10241)), so this is a separate bench test, not a given. Frigate is a new container; xero has 32GB since 2026-10-09, so RAM is fine, but run audio only (no object detection on CPU, because of heat).
- **Low light is a must-have (user, 2026-11-07) and a pass/fail gate, not a nice-to-have.** No option gets past phase 1 without a usable night view at the cot, judged against Alfred's low light mode on the same night. Ways to get there, cheapest first:
  1. **App exposure controls:** check whether Vantage (or IP Camera Lite) exposes exposure/ISO/frame-rate settings; a lower frame rate lets the sensor gather more light.
  2. **Software brightening on xero**, the same idea as Alfred's mode: go2rtc's ffmpeg source re-encodes the stream with a gamma/brightness filter (e.g. `eq=gamma=2:brightness=0.1`). Costs CPU on xero 24/7 (heat), so measure with `tools/host-stats/` before keeping it.
  3. **A dim warm night lamp** (₹150-300) out of the baby's line of sight.
  4. **Tapo C200/C210 with IR night vision** (₹1,300-2,550) if all of the above fail. An IR illuminator does not help the iPhone: its camera filters out IR.
- **Low light was the likely weak spot (original note).** Alfred's "low light mode" is software brightening; neither Vantage nor IP Camera Lite advertises one, and the SE's sensor is poor in the dark. Test in the real night-time room before cancelling Alfred. If it is too dark, a dim warm plug-in night lamp is the cheap fix. If that does not work either, see Readymade alternatives.
- **Power cuts:** the phone rides through on its battery; the stream needs the router up. That is no worse than Alfred, and better in an ISP outage: local viewing over LAN or Tailscale keeps working, where Alfred needs the internet.
- **Two-way audio is not used today** (not in Alfred's "features in use"), so it is not a requirement.
- **Remote viewing:** via HA over Tailscale, the same as the rest of the dashboard. No Alfred cloud.

#### Readymade alternatives
- **Tapo C200 / C210 camera:** around ₹1,300-2,550 in undated listings (Flipkart ₹1,499 and Variety Infotech ₹2,549, seen via search 2026-11-07; estimate). **Where to buy (checked by the user 2026-11-07):** the single C210 on [Reliance Digital](https://www.reliancedigital.in/product/tp-link-tapo-c210-security-camera-360-degree-rotational-views-3mp-high-definition-with-2-way-audio-and-night-vision-l2yy55) opens and works, or in a Reliance Digital/Croma store; Amazon.in shows it unavailable, the Flipkart links found do not open, and Variety Infotech is an unknown seller (skip). Check it is the single C210 (not the C210P2 2-pack) and not a mount: a ₹1,905 "Flexible Mount for Tapo C200 C210" on Amazon is the mount alone. It has **real IR night vision**, local RTSP, and the HA `tapo_control` integration ([HA thread](https://community.home-assistant.io/t/custom-component-tapo-cameras-control/231795)). Setup needs the cloud account, after which it can be firewalled.
  - Better than the SE at night, but it is new hardware, which the user does not prefer.
  - **Only if the SE fails the low-light test.** Even then, a year of Tapo costs less than two years of Alfred.
- **Dedicated baby monitors:** cloud-tied or closed RF, cannot be pointed at xero. Rejected, as in "Baby-cry alert via ntfy".

#### Parts
```parts
qty | item | est | note
1 | iPhone SE + charger by the cot | 0 | already there, running Alfred
1 | dim warm plug-in LED night lamp | 150-300 | local shop; ONLY if the low-light test fails - estimate
# Option 2 - if the SE cannot see in the dark
1 | Tapo C200 or C210 camera | 1300-2550 | online (Flipkart/Amazon) or a local electronics store; undated listings, estimate
```

**Cost:** ₹0 on Vantage's free tier, saving ₹799/year. ₹150-300 if a night lamp is needed. The fallback camera is ₹1,300-2,550, one-off.

#### Effort
~4-6 hours, plus an overnight soak.
1. **RTSP bench test, 1h + overnight (decides everything):**
   - Close Alfred, install Vantage, set Auto-Lock to Never, phone on the charger.
   - Add the phone in HA (Settings -> Devices -> ONVIF, phone IP, port 8080).
   - Check the live view and the motion sensor.
   - Kill the app: how long until the entity goes unavailable?
   - Play a crying clip with stream audio on, then off: does Sound Recognition fire?
   - Leave it overnight: is the stream still up in the morning, and how hot is the phone?
2. **HA side, 1-2h:** a camera tile in the room the user names (`projects/ha-dashboard/dashboards/home.yaml`), a motion -> ntfy automation, and a stream-down -> urgent ntfy alert. Add entries to `endpoints.toml` and `docs/hardware.md`.
3. **Placement and night-time view, 1-2h: this is the phase that will overrun.** Find the angle and mount by the cot (wall mount by default) where the phone sees the cot in the dark and stays in reach of its charger. Add the night lamp if needed.
4. **Run alongside Alfred for ~2 weeks, then cancel Alfred**: any time before 2027-05-19; Premium runs to that date anyway.
5. **Optional, 2-3h:** Frigate audio-only `crying` detection, only if the mic test leaves no cry alert.

#### Overlaps
- **"Baby-cry alert via ntfy (replace SMS Shortcut)":** Alfred is the suspect for Sound Recognition never firing on the SE. If the replacement streams video-only and Sound Recognition fires, that entry is fixed by removing Alfred. If not, Frigate audio here becomes its cry alert.
- **"Charge-limit the baby monitor iPhone SE with the smart plug":** the same phone, on its charger all day. Its timed 80->20% discharge should be re-measured on the replacement app, not Alfred, and its "flat phone = no monitor" watchdog sits naturally next to this entry's stream-down alert.
- **"A clean HA dashboard"** (`projects/ha-dashboard/`): where the camera tile goes.

#### Log
- 2026-11-07: idea recorded and researched (user: "use old iphone, currently using alfred camera ... replace alfred camera with free version"). The Alfred subscription details came from the user. The user asked for RTSP to be the first test, since the old rejection was never tested.
- 2026-11-07: user: low light is a must-have. Made the night-time view a pass/fail gate in the first test, with the fallbacks ranked (app exposure, ffmpeg brightening on xero, night lamp, Tapo IR camera).
- 2026-11-07: user said the camera need not be the iPhone; GoPro checked - it is a **HERO5 Black** (all 176 files on `datapool`), not the HERO4 noted in "ESP32 UPS LED monitor" (corrected there). Rejected for low light and 24/7 heat; the non-iPhone route stays the Tapo IR camera.
