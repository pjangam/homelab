# 2026-09-04: Two GPIO bridges sharing one lgpio notify FIFO ate the button presses

**Impact:** the physical white-noise start/stop buttons on the wol-sender Pi were dead for ~21 hours (2026-09-03 14:22 boot -> 2026-09-04 11:32 fix). White noise remained fully controllable from HA/dashboard/scenes throughout - only the physical buttons were affected, which is exactly the household/house-help path they exist to serve.

## Symptom

Pressing either button did nothing in HA. Everything that would normally be checked looked healthy:

- `white-noise-buttons-mqtt.service`: `active (running)`, restart counter 0, up 21h.
- TCP connection from the Pi to Mosquitto on xero: `ESTAB`, held open the whole time (so the paho network loop was alive and answering keepalives).
- The deployed script on the Pi: byte-identical (`md5sum`) to the repo copy.
- `switch.white_noise` itself: working, `whitenoise/available` = `online`.

## Root cause, in plain terms

**What `.lgd-nfy0` is.** When a button is pressed, the Linux kernel is what actually notices the pin change. The `lgpio` library has to carry that event from the kernel into our Python code, and the way it does that is with a **named pipe** - a small queue that one part of the program writes into and another part reads out of. That queue has to exist somewhere in the filesystem, so lgpio creates it as a hidden file called `.lgd-nfy0`. It is not a log or a data file: it holds nothing, is always 0 bytes, and it exists only while the process is running. `ls -l` shows it with a leading `p`, for pipe:

```
prw-rw-r-- 1 pramod pramod 0 Sep  4 11:32 .lgd-nfy0
```

**Where it lives.** In whatever directory the process happens to be running from - its working directory. Nothing else decides the location. For our services that was `WorkingDirectory=/home/pramod` in the systemd units, so the file appeared at `/home/pramod/.lgd-nfy0`. After the fix each bridge sits in its own directory, so they are now `/home/pramod/.lgpio/white-noise-buttons-mqtt/.lgd-nfy0` and `/home/pramod/.lgpio/scene-buttons-mqtt/.lgd-nfy0`.

**Why the name collided.** The number in the filename is lgpio's internal handle number, counted **per process**, starting at zero. Every lgpio process therefore calls its first pipe `.lgd-nfy0`. Two such processes in the same directory do not get `.lgd-nfy0` and `.lgd-nfy1` - they both get `.lgd-nfy0`, meaning one shared pipe. Verified directly on the Pi, two processes started in a shared empty directory:

```
proc handle= 0
proc handle= 0
--- files created in shared dir ---
prw-rw-r-- 1 pramod pramod 0 Sep  4 11:46 .lgd-nfy0     <- one pipe, both processes
```

This is worth being precise about: it is **not a race and not bad luck**. Any two lgpio processes sharing a working directory collide, every time, on every boot.

**Why sharing the pipe loses presses.** A pipe is a queue that empties as it is read: each item goes to exactly one reader. With both bridges reading the same pipe, a button event written by the white-noise bridge could be picked up by the scene bridge instead - which sees an event for a pin it does not own, discards it, and moves on. The press is simply gone. Nothing errors, nothing is logged, both processes remain perfectly healthy. That is why a press occasionally landed (11:31:23 on the day of the fix) while most did nothing.

The scene bridge has no buttons physically wired to it. That made no difference at all: an lgpio process with nothing attached still opens the pipe and still reads from it, so it swallows its neighbour's events just as effectively as a busy one would.

Environment: Pi 3B, kernel `6.18.34+rpt-rpi-v8`, `GPIOZERO_PIN_FACTORY=lgpio`, gpiozero 2.0.1.post3, lgpio 0.2.2 (build 0), rpi-lgpio 0.6, paho-mqtt 2.1.0.

## Was this a code issue or an infrastructure issue?

**Infrastructure, with a library design flaw underneath it and a code-side gap that made it expensive.** Breaking that down:

- **Not our application logic.** Neither bridge script was wrong. The same code, unchanged, works correctly now - the only edit was telling it where to put its pipe.
- **Not the hardware.** `pinctrl poll` showed clean, correct edges on both pins throughout.
- **The actual defect was configuration:** two systemd units, both with `WorkingDirectory=/home/pramod`. That single shared line is the whole bug. It was introduced when the second bridge was installed (scene buttons, 2026-08-26) and it made the two services quietly incompatible from that moment.
- **Underneath it, a library design flaw:** lgpio puts per-process state in the working directory under a name that is identical for every process, with no locking, no error, and no warning when two processes land on the same file. A library that named the pipe after the pid, or refused to share one, would have made the misconfiguration impossible or at least loud.
- **The code-side failure was the silence, not the logic.** Neither script logged anything. That is what turned a misconfiguration into a 21-hour outage that took a full walk down the chain to find: with a single "press ->" line per press, the answer would have been obvious in a minute.

**Why the fix is in code anyway.** The obvious fix is infrastructure - give each unit its own `WorkingDirectory`. It was deliberately not done that way, because that leaves the trap armed: the next person to add a third GPIO service, copy an existing unit file, or edit `WorkingDirectory` re-creates the same silent failure. Having each script claim its own directory means no unit-file change can bring it back.

**Timing note.** Because the collision is deterministic rather than a race, it was armed from the moment both bridges first ran together, not created by the 2026-09-03 reboot. Why the buttons passed their 2026-08-31 verification and were near-totally dead afterwards is not established - the Pi's journal is volatile and retains nothing before the 09-03 boot, so there is no evidence to settle it. The shared pipe is confirmed; the change in severity is not explained.

## Detection gap

The bridges had no logging at all. `journalctl -u white-noise-buttons-mqtt` showed exactly one line - systemd's start message - for the entire 21 hours. There was no way to distinguish "no press arrived" from "press arrived, publish failed", which is what made an otherwise 20-minute diagnosis take a full walk down the chain.

## Timeline

| When | What |
| --- | --- |
| 2026-08-26 | Scene-buttons bridge installed with the same `WorkingDirectory` as the white-noise bridge. Collision armed from here. |
| 2026-08-31 | White-noise buttons built and confirmed working end to end. |
| 2026-09-03 14:18:01 | Pi boots, systemd starts both bridge units. |
| 2026-09-03 14:22:55 | Both python processes reach lgpio init and both claim `.lgd-nfy0` (deterministic, not a race). Buttons dead from here. |
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
- **`LG_WD` is the config-level equivalent, if it is ever wanted.** liblgpio reads that environment variable and `chdir()`s the whole process to it at init (verified: `cwd before: /tmp/nfycwd` -> `cwd after: /tmp/nfywd`), so `Environment=LG_WD=...` in a unit does the same job as the in-script chdir - but the directory must already exist, and it is undone by anyone editing the unit. The in-script version creates its own directory and travels with the script.
- `scene-buttons-mqtt.service` still runs with nothing wired to it. Harmless now, but it is the process that broke the working one - if those buttons are not going to be wired, `sudo systemctl disable --now scene-buttons-mqtt` removes the whole class of interaction.

## Not part of this bug

Each bridge process burns a steady ~4-5% of one core while idle. That was initially assumed to be the collision (two processes churning through reports they do not own), but it measured the same after the fix (99 CPU ticks per 20s per process) - it is just what `gpiozero` + `lgpio` costs at rest on this Pi 3B. Roughly 10% of one core across both services; not worth chasing for now, but noted so it is not mistaken for a symptom next time.
