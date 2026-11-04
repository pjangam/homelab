# Diwali lights (door outline)

A WS2812B outline around the front door, driven by its own ESP32 running WLED -
the second WLED board in the house after the aarti lights, and set up the same
way. Built 2026-10-30.

- [`wiring.html`](wiring.html) - the wiring and pixel layout as built.
- [`diwali_wled.sh`](diwali_wled.sh) - the whole setup path in one script:
  hand the board the house WiFi over USB serial (or its own AP), move it to a
  static IP, set count/pin/order/current cap/name, **load-test the supply**,
  then save the warm diya effect as boot preset 1.

Flash the board first with
[`tools/esp32-tools/flash-wled-audioreactive.sh --flash`](../../tools/esp32-tools/README.md).

The load test is not optional: the supply is a OnePlus fast charger labelled
5V 4A, and proprietary fast chargers may only deliver full current after a
handshake the ESP32 cannot do - so the usable ceiling has to be measured, not
read off the label.
