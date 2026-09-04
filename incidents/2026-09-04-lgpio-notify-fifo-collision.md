# 2026-09-04: Two GPIO bridges sharing one lgpio notify FIFO ate the button presses

**Impact:** the physical white-noise start/stop buttons on the wol-sender Pi were dead for ~21 hours (2026-09-03 14:22 boot -> 2026-09-04 11:32 fix). White noise remained fully controllable from HA/dashboard/scenes throughout - only the physical buttons were affected, which is exactly the household/house-help path they exist to serve.

## Symptom

Pressing either button did nothing in HA. Everything that would normally be checked looked healthy:

- `white-noise-buttons-mqtt.service`: `active (running)`, restart counter 0, up 21h.
- TCP connection from the Pi to Mosquitto on xero: `ESTAB`, held open the whole time (so the paho network loop was alive and answering keepalives).
- The deployed script on the Pi: byte-identical (`md5sum`) to the repo copy.
- `switch.white_noise` itself: working, `whitenoise/available` = `online`.

## Root cause

`lgpio` creates its edge-notification FIFO as `.lgd-nfy<N>` in the process's **current working directory**, picking the first free slot number at startup. Both button bridges ran with `WorkingDirectory=/home/pramod`, and at the 2026-09-03 boot systemd started them in the same second - both python processes stamped `14:22:55`. They raced, both picked slot 0, and ended up sharing one FIFO:

```
pid 1044 (scene-buttons)       fd 3,4 -> /home/pramod/.lgd-nfy0   inode=62680
pid 1045 (white-noise-buttons) fd 3,4 -> /home/pramod/.lgd-nfy0   inode=62680
```

A FIFO delivers each byte to exactly one reader. The idle `scene-buttons-mqtt` process - which has no buttons physically wired to it right now, so nothing of its own to receive - sat on the shared FIFO consuming and discarding a share of the white-noise bridge's edge reports. Presses mostly vanished and occasionally got through: one press at 11:31:23 on the day of the fix landed and started white noise, 40 seconds before the fix was even deployed.

Two things about this are worth remembering:

- **The failure needs no second set of buttons, only a second lgpio process sharing the CWD.** A bridge with nothing wired to it is just as destructive as a busy one.
- **Nothing in the usual health signals can show it.** Both services are genuinely healthy; the loss happens in a kernel FIFO between two processes that each believe they are fine.

Environment: Pi 3B, kernel `6.18.34+rpt-rpi-v8`, `GPIOZERO_PIN_FACTORY=lgpio`, gpiozero 2.0.1.post3, lgpio 0.2.2.0, rpi-lgpio 0.6, paho-mqtt 2.1.0.

## Detection gap

The bridges had no logging at all. `journalctl -u white-noise-buttons-mqtt` showed exactly one line - systemd's start message - for the entire 21 hours. There was no way to distinguish "no press arrived" from "press arrived, publish failed", which is what made an otherwise 20-minute diagnosis take a full walk down the chain.

## Timeline

| When | What |
| --- | --- |
| 2026-08-31 | Buttons built and confirmed working end to end. |
| 2026-09-03 14:18:01 | Pi boots, systemd starts both bridge units. |
| 2026-09-03 14:22:55 | Both python processes reach lgpio init in the same second, race, both claim `.lgd-nfy0`. Buttons dead from here. |
| 2026-09-04 ~11:20 | Reported. Synthetic `PRESS` proves MQTT -> HA -> SoX is fine. |
| 2026-09-04 11:26-11:31 | `pinctrl poll` proves the wiring is fine; `/proc/<pid>/fd` finds the shared FIFO. |
| 2026-09-04 11:31:23 | A real press slips through the FIFO lottery and starts white noise, 40s before the fix. |
| 2026-09-04 11:32:06 | Fix deployed, both services restarted with private notify dirs. |
| 2026-09-04 11:35:02-13 | 7 real presses, all published (`rc=0`), `switch.white_noise` follows each within 1-2s. |

## Diagnosis path

Each step splits the chain in half, which is what made it quick once logging was ruled out as unavailable:

1. **MQTT -> HA -> SoX?** Publish a synthetic press:
   `mosquitto_pub -t white_noise_buttons/start/pressed -m PRESS` -> `switch.white_noise` went ON. Downstream is fine, so the break is upstream of MQTT.
2. **Buttons and wiring?** `pinctrl poll 17,18` on the Pi during real presses -> clean edges on both pins (`pinctrl` reads the registers directly, so it works alongside the service that owns the pins). Hardware is fine, so the break is inside the bridge process.
3. **Inside the process?** `ls -l /proc/<pid>/fd` on both bridges -> same `.lgd-nfy0`, same inode. Root cause.

`scripts/capture_white_noise_button_presses.sh` automates steps 1-2, logging `pinctrl poll` edges on the Pi next to the broker's MQTT traffic; edges with no matching MQTT message is the signature of this bug class. `scripts/diagnose_white_noise_buttons.sh --inject` covers step 1 alone.

## Fix

Each script now claims its own notify directory before creating any `Button`, so the collision cannot recur regardless of what `WorkingDirectory` the unit sets:

```python
run_dir = Path.home() / ".lgpio" / Path(__file__).stem
run_dir.mkdir(parents=True, exist_ok=True)
os.chdir(run_dir)
```

Verified after restart - separate FIFOs, separate inodes:

```
white-noise-buttons-mqtt -> /home/pramod/.lgpio/white-noise-buttons-mqtt/.lgd-nfy0  inode=550812
scene-buttons-mqtt       -> /home/pramod/.lgpio/scene-buttons-mqtt/.lgd-nfy0        inode=550811
```

Both scripts also log now: notify dir, each watched pin/topic, MQTT connect/disconnect, and one line per press with the publish rc.

Deployed with `scripts/deploy_button_bridges_pi.sh`, which needs no sudo on the Pi - the units run as `pramod` with `Restart=always`, so killing the main pid is enough to restart them with the new code.

## Prevention

- **Any future `gpiozero`/`lgpio` service on this Pi must get its own working directory** (or call the same `isolate_lgpio_notify_dir()` helper). Two lgpio processes must never share a CWD. This is the rule to check first whenever a third GPIO service is added.
- **Every bridge logs its presses.** The fix that matters as much as the chdir: a silent service is indistinguishable from a broken one, and this bug was invisible for 21h purely because nothing wrote a line.
- `scene-buttons-mqtt.service` still runs with nothing wired to it. Harmless now, but it is the process that broke the working one - if those buttons are not going to be wired, `sudo systemctl disable --now scene-buttons-mqtt` removes the whole class of interaction.

## Not part of this bug

Each bridge process burns a steady ~4-5% of one core while idle. That was initially assumed to be the collision (two processes churning through reports they do not own), but it measured the same after the fix (99 CPU ticks per 20s per process) - it is just what `gpiozero` + `lgpio` costs at rest on this Pi 3B. Roughly 10% of one core across both services; not worth chasing for now, but noted so it is not mistaken for a symptom next time.
