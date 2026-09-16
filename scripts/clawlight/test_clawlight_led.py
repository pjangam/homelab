#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt", "gpiozero"]
# ///
"""Checks clawlight-led.py drives the two RG pins correctly, on gpiozero mock pins.

Runs anywhere (no Pi, no LED): ./scripts/clawlight/test_clawlight_led.py
"""
import importlib.util
import time
from pathlib import Path

from gpiozero import Device
from gpiozero.pins.mock import MockFactory, MockPWMPin

Device.pin_factory = MockFactory(pin_class=MockPWMPin)

spec = importlib.util.spec_from_file_location(
    "clawlight_led", Path(__file__).with_name("clawlight-led.py"))
led = importlib.util.module_from_spec(spec)
spec.loader.exec_module(led)

red = Device.pin_factory.pin(led.PINS["red"])
green = Device.pin_factory.pin(led.PINS["green"])


def pins():
    return (round(red.state, 3), round(green.state, 3))


def check(name, got, want):
    ok = all(abs(g - w) < 1e-6 for g, w in zip(got, want))
    print(f"{'ok  ' if ok else 'FAIL'} {name}: pins={got} want={want}")
    return ok


light = led.Light(use_gpio=True)
results = []

light.show("active")
results.append(check("active is green", pins(), (0.0, 1.0)))
light.show("waiting")
results.append(check("waiting is red", pins(), (1.0, 0.0)))
light.show("idle")
results.append(check("idle is dim amber", pins(), led.COLOURS["idle"]))

light.show("unknown")
samples = []
for _ in range(60):
    time.sleep(0.05)
    samples.append((red.state, green.state))
# Judge the fade on whichever channel AMBER leans on, so retuning the mix
# does not break the test.
ch = max(range(2), key=lambda i: led.AMBER[i])
levels = [smp[ch] for smp in samples]
fades = max(levels) > 0.8 * led.AMBER[ch] and min(levels) < 0.2 * led.AMBER[ch]
print(f"{'ok  ' if fades else 'FAIL'} unknown pulses: {('red', 'green')[ch]} ranged {min(levels):.2f}..{max(levels):.2f}")
results.append(fades)
lit = [(r, g) for r, g in samples if r > 0.05 and g > 0.05]
hue = all(abs(g / r - led.AMBER[1] / led.AMBER[0]) < 0.05 * led.AMBER[1] / led.AMBER[0] for r, g in lit)
print(f"{'ok  ' if hue else 'FAIL'} unknown pulse keeps the amber mix while fading")
results.append(hue)

light.show("active")
time.sleep(0.2)  # a pulse left running would overwrite the steady colour by now
results.append(check("steady colour after pulse stops it", pins(), (0.0, 1.0)))

light.led.close()
raise SystemExit(0 if all(results) else 1)
