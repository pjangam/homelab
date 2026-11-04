# esp32-tools

Flashing and bring-up for the WLED boards
([`projects/aarti-lights/`](../../projects/aarti-lights/README.md),
[`projects/diwali-lights/`](../../projects/diwali-lights/README.md)). These work
on both xero and the MacBook, because a board can plausibly be plugged into
either.

| | |
|---|---|
| `flash-wled-audioreactive.sh` | flash WLED with the AudioReactive usermod. **Default is a read-only verify** - finds the port, reads the chip back, says whether it is flashable. `--flash` actually writes |
| `improv_wifi.py` | give a board the house WiFi over the USB cable (Improv serial), so you never have to join its AP - which on xero needs sudo for the WiFi card. Prints the DHCP address it joined on; set a static one afterwards over WLED's JSON API |
| `read-esp32-serial.py` | reset the board and capture its boot log - the only thing that separates "never booted" from "booted and crashed" from "booted fine, the AP is up, the client just cannot see it" |
| `watch-usb-serial.sh` | watch the USB bus for a serial adapter appearing. Separates "kernel sees nothing" (cable/port/power) from "enumeration fails" (flaky cable, dying bridge) from "it enumerated fine" (then it was only ever permissions) |
