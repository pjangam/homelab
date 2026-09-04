# 2026-09-04: Two GPIO bridges sharing one lgpio notify FIFO ate the button presses

**Symptom:** the physical white-noise buttons on the wol-sender Pi stopped working - pressing start or stop did nothing in HA. Both bridge services looked perfectly healthy: `active (running)`, restart counter 0, TCP connection to Mosquitto established for 21h. The second bridge, `scene-buttons-mqtt`, has no buttons physically wired to it at the moment - it was still running and still claiming its pins, which turned out to be the whole problem.

**Root cause:** `lgpio` creates its edge-notification FIFO as `.lgd-nfy<N>` in the process's **current working directory**, picking the first free slot number at startup. Both button bridges ran with `WorkingDirectory=/home/pramod`, and at the 2026-09-03 boot systemd started them in the same second (both python processes stamped `14:22:55`). They raced, both picked slot 0, and ended up sharing one FIFO:

```
pid 1044 (scene-buttons)       fd 3,4 -> /home/pramod/.lgd-nfy0   inode=62680
pid 1045 (white-noise-buttons) fd 3,4 -> /home/pramod/.lgd-nfy0   inode=62680
```

A FIFO delivers each byte to exactly one reader, so every GPIO edge report went to whichever process read it first. The idle `scene-buttons-mqtt` process (no buttons wired, nothing of its own to receive) sat on the same FIFO consuming and discarding a share of the white-noise bridge's edge reports - which is why presses appeared dead but occasionally worked (a press at 11:31:23 on the day of the fix did get through and started white noise). The wasted reads also explain the ~5% steady CPU each process had been burning while "idle".

Note the failure needs no second *set of buttons* - only a second lgpio *process* sharing the working directory. A bridge with nothing wired to it is just as destructive as a busy one.

**Why it survived so long undetected:** the bridges had no logging at all. `journalctl -u white-noise-buttons-mqtt` showed one line - the systemd start message - and nothing else, so there was no way to tell "no press arrived" from "press arrived, publish failed".

**Diagnosis path** (`scripts/capture_white_noise_button_presses.sh` automates it):
1. Published a synthetic `PRESS` to `white_noise_buttons/start/pressed` - `switch.white_noise` went ON. MQTT -> HA -> SoX chain fine, so the break was upstream.
2. `pinctrl poll 17,18` on the Pi during real presses - clean edges on both pins. The wiring and buttons are fine, so the break was inside the bridge process.
3. `ls -l /proc/<pid>/fd` on both bridges - same `.lgd-nfy0`, same inode. Root cause.

**Fix:** each script now claims its own notify directory before creating any `Button`, so the collision cannot happen regardless of what `WorkingDirectory` the unit sets:

```python
run_dir = Path.home() / ".lgpio" / Path(__file__).stem
run_dir.mkdir(parents=True, exist_ok=True)
os.chdir(run_dir)
```

Both scripts also log now - notify dir, each watched pin/topic, MQTT connect/disconnect, and one line per press with the publish rc.

**Prevention:** any future `gpiozero`/`lgpio` service on the Pi must get its own working directory (or call the same helper). Two lgpio processes must never share a CWD. `scripts/deploy_button_bridges_pi.sh` pushes both scripts and restarts both services without needing the Pi's sudo password (the units run as `pramod` with `Restart=always`, so killing the main pid is enough).
