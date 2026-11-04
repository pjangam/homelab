# wol_on_boot (ESP32)

An ESP32 whose **own power state is the signal**. Plugged into a regular wall
outlet - deliberately **not** the UPS - it can only boot when mains is back, so
on every boot it joins WiFi and sends a Wake-on-LAN magic packet to xero.

That closes the gap left by
[`projects/power-watchdog/`](../../projects/power-watchdog/README.md): it shuts
xero down cleanly while the UPS still has charge, but because the UPS keeps the
PSU powered throughout, the BIOS's "restore on AC power loss" never fires -
there is no AC-loss-then-restore event at the PSU to fire it. Full context is
the "Power-outage watchdog" entry in `PROJECTS.md`.

PlatformIO, `esp32dev`, Arduino framework. `src/secrets.h` holds the WiFi
credentials and is gitignored - copy `src/secrets.h.example` and fill it in.
The target MAC and broadcast address are constants at the top of the sketch.

```bash
pio run -t upload       # from this folder
pio device monitor      # 115200
```

`.pio/` is gitignored. The board's own entry is in `docs/hardware.md`.
