#!/usr/bin/env python3
# Fullscreen analog clock for the wol-sender Pi's desktop, meant to run as a
# screensaver. The desktop is labwc (Wayland), where xscreensaver and the X11
# clocks misbehave; GTK3 runs natively there and fullscreens itself.
# Any key, click or mouse movement closes it.
#
# Either side of the clock: HA's weather (temperature, humidity, condition)
# and the chance of rain on the left, and clawlight's sessions on the right - one cwd name per line,
# red when it needs input, green while working, amber while only its own
# background shells run. Both are fetched from xero over the LAN in a
# background thread; a source that stops answering fades out rather than
# freezing a stale value on screen.
#
# The rain chance comes from Open-Meteo, not HA: HA's met.no forecast only
# carries expected millimetres here, no probability. The coordinates are
# taken from HA's own config, so they live in HA rather than this repo.
#
# The HA token is read from ~/.config/analog-clock.env (HA_TOKEN=...), which
# deploy_clock_screensaver.sh writes. Without it the weather side stays blank.
#
# Needs: sudo apt install python3-gi-cairo
# Deploy: scripts/wol-sender/deploy_clock_screensaver.sh
# Run on the Pi's desktop: python3 ~/analog_clock.py
import json
import math
import os
import threading
import time
import urllib.request
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

BG = (0.0, 0.0, 0.0)
FACE = (0.07, 0.07, 0.08)
TICK = (0.55, 0.55, 0.58)
HAND = (0.93, 0.93, 0.95)
SECOND = (1.0, 0.42, 0.18)
NUMBER = (0.78, 0.78, 0.80)
TEXT = (0.45, 0.45, 0.48)
DIM = (0.30, 0.30, 0.32)
STATE_COLORS = {
    "waiting": (0.95, 0.25, 0.22),
    "input_needed": (0.95, 0.25, 0.22),
    "active": (0.30, 0.85, 0.40),
    "shells": (0.95, 0.70, 0.20),
}
# Most urgent first, matching the order clawlight's own aggregate uses.
STATE_RANK = {"waiting": 0, "input_needed": 0, "active": 1, "shells": 2}
MAX_SESSIONS = 8

XERO = os.environ.get("XERO_HOST", "192.168.1.123")
HA_URL = f"http://{XERO}:8123/api/states/weather.forecast_home"
HA_CONFIG_URL = f"http://{XERO}:8123/api/config"
CLAWLIGHT_URL = f"http://{XERO}:8126/clawlight/api/status"
RAIN_URL = (
    "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
    "&hourly=precipitation_probability&forecast_hours={hours}&timezone=auto"
)
RAIN_HOURS = 3
ENV_FILE = Path.home() / ".config" / "analog-clock.env"
WEATHER_EVERY = 300
RAIN_EVERY = 900
CLAWLIGHT_EVERY = 3
# Drop a value that has not been refreshed for this long.
WEATHER_STALE = 45 * 60
RAIN_STALE = 60 * 60
CLAWLIGHT_STALE = 60

CONDITIONS = {
    "clear-night": "Clear", "cloudy": "Cloudy", "exceptional": "Exceptional",
    "fog": "Fog", "hail": "Hail", "lightning": "Thunder",
    "lightning-rainy": "Thunderstorm", "partlycloudy": "Partly cloudy",
    "pouring": "Heavy rain", "rainy": "Rain", "snowy": "Snow",
    "snowy-rainy": "Sleet", "sunny": "Sunny", "windy": "Windy",
    "windy-variant": "Windy",
}

# (fetched_at, value) per source, written by the poller threads.
data = {"weather": (0, None), "rain": (0, None), "clawlight": (0, None)}

# Ignore input for this long after opening, so the event that triggered the
# screensaver (or the window mapping under the pointer) doesn't close it.
GRACE_SECONDS = 1.5
MOVE_THRESHOLD_PX = 8


def hand(cr, cx, cy, angle, length, tail, width, rgb):
    dx, dy = math.sin(angle), -math.cos(angle)
    cr.set_source_rgb(*rgb)
    cr.set_line_width(width)
    cr.set_line_cap(1)  # round
    cr.move_to(cx - dx * tail, cy - dy * tail)
    cr.line_to(cx + dx * length, cy + dy * length)
    cr.stroke()


def read_token():
    try:
        for line in ENV_FILE.read_text().splitlines():
            key, _, value = line.partition("=")
            if key.strip() == "HA_TOKEN":
                return value.strip().strip('"')
    except OSError:
        pass
    return ""


def fetch_json(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.load(resp)


def poll(key, every, fetch):
    while True:
        try:
            data[key] = (time.monotonic(), fetch())
        except Exception:
            pass  # keep the last value until it goes stale
        time.sleep(every)


def fetch_weather():
    token = read_token()
    if not token:
        return None
    w = fetch_json(HA_URL, {"Authorization": f"Bearer {token}"})
    a = w.get("attributes", {})
    return {
        "temp": a.get("temperature"),
        "unit": a.get("temperature_unit", "°C"),
        "humidity": a.get("humidity"),
        "condition": CONDITIONS.get(w.get("state"), ""),
    }


def fetch_rain():
    token = read_token()
    if not token:
        return None
    cfg = fetch_json(HA_CONFIG_URL, {"Authorization": f"Bearer {token}"})
    url = RAIN_URL.format(lat=cfg["latitude"], lon=cfg["longitude"], hours=RAIN_HOURS)
    chances = fetch_json(url)["hourly"]["precipitation_probability"]
    return max(c for c in chances if c is not None)


def fetch_clawlight():
    return fetch_json(CLAWLIGHT_URL).get("sessions", [])


def fresh(key, max_age):
    at, value = data[key]
    return value if value is not None and time.monotonic() - at < max_age else None


def text_at(cr, text, x, y, size, rgb, align="left"):
    cr.set_font_size(size)
    ext = cr.text_extents(text)
    if align == "right":
        x -= ext.x_advance
    cr.set_source_rgb(*rgb)
    cr.move_to(x, y)
    cr.show_text(text)
    return ext.x_advance


def draw_weather(cr, x, cy, r):
    w = fresh("weather", WEATHER_STALE)
    if not w or w["temp"] is None:
        return
    cr.select_font_face("Sans", 0, 1)
    text_at(cr, f"{w['temp']:.0f}{w['unit']}", x, cy - r * 0.05, r * 0.30, HAND)
    cr.select_font_face("Sans", 0, 0)
    y = cy + r * 0.14
    if w["condition"]:
        text_at(cr, w["condition"], x, y, r * 0.09, NUMBER)
        y += r * 0.14
    if w["humidity"] is not None:
        text_at(cr, f"Humidity {w['humidity']:.0f}%", x, y, r * 0.09, TEXT)
        y += r * 0.14
    rain = fresh("rain", RAIN_STALE)
    if rain is not None:
        text_at(cr, f"Rain {rain:.0f}% next {RAIN_HOURS}h", x, y, r * 0.09, TEXT)


def draw_clawlight(cr, x, cy, r, max_w):
    sessions = fresh("clawlight", CLAWLIGHT_STALE)
    cr.select_font_face("Sans", 0, 0)
    if sessions is None:
        text_at(cr, "clawlight offline", x, cy, r * 0.07, DIM, "right")
        return
    shown = sorted(
        (s for s in sessions if s.get("state") in STATE_COLORS),
        key=lambda s: (STATE_RANK[s["state"]], s.get("label", "")),
    )[:MAX_SESSIONS]
    if not shown:
        text_at(cr, "no sessions", x, cy, r * 0.07, DIM, "right")
        return
    names = [s.get("label", "") for s in shown]
    # The host only earns space when two sessions share a directory name.
    labels = [
        f"{s.get('host', '')}/{n}" if names.count(n) > 1 else n
        for s, n in zip(shown, names)
    ]
    cr.select_font_face("Sans", 0, 1)
    size = r * 0.10
    cr.set_font_size(size)
    widest = max(cr.text_extents(label).x_advance for label in labels)
    if widest > max_w:
        size *= max_w / widest
    step = size * 1.5
    y = cy - step * (len(shown) - 1) / 2 + size * 0.35
    for s, label in zip(shown, labels):
        text_at(cr, label, x, y, size, STATE_COLORS[s["state"]], "right")
        y += step


def draw(widget, cr):
    w, h = widget.get_allocated_width(), widget.get_allocated_height()
    cr.set_source_rgb(*BG)
    cr.paint()

    r = min(w, h) * 0.42
    cx, cy = w / 2, h / 2 - min(w, h) * 0.03

    cr.set_source_rgb(*FACE)
    cr.arc(cx, cy, r, 0, 2 * math.pi)
    cr.fill()

    cr.set_line_cap(1)
    for i in range(60):
        a = i * math.pi / 30
        major = i % 5 == 0
        inner = r * (0.84 if major else 0.91)
        cr.set_source_rgb(*TICK)
        cr.set_line_width(r * (0.022 if major else 0.008))
        cr.move_to(cx + math.sin(a) * inner, cy - math.cos(a) * inner)
        cr.line_to(cx + math.sin(a) * r * 0.95, cy - math.cos(a) * r * 0.95)
        cr.stroke()

    cr.select_font_face("Sans", 0, 0)
    cr.set_font_size(r * 0.13)
    cr.set_source_rgb(*NUMBER)
    for n in range(1, 13):
        a = n * math.pi / 6
        label = str(n)
        ext = cr.text_extents(label)
        x = cx + math.sin(a) * r * 0.69
        y = cy - math.cos(a) * r * 0.69
        cr.move_to(x - ext.width / 2 - ext.x_bearing, y - ext.height / 2 - ext.y_bearing)
        cr.show_text(label)

    t = time.localtime()
    sec = t.tm_sec
    minute = t.tm_min + sec / 60
    hour = (t.tm_hour % 12) + minute / 60

    hand(cr, cx, cy, hour * math.pi / 6, r * 0.52, r * 0.08, r * 0.045, HAND)
    hand(cr, cx, cy, minute * math.pi / 30, r * 0.80, r * 0.08, r * 0.030, HAND)
    hand(cr, cx, cy, sec * math.pi / 30, r * 0.86, r * 0.16, r * 0.010, SECOND)

    cr.set_source_rgb(*SECOND)
    cr.arc(cx, cy, r * 0.028, 0, 2 * math.pi)
    cr.fill()

    date = time.strftime("%A, %d %B", t)
    cr.select_font_face("Sans", 0, 0)
    cr.set_font_size(r * 0.075)
    ext = cr.text_extents(date)
    cr.set_source_rgb(*TEXT)
    cr.move_to(w / 2 - ext.width / 2 - ext.x_bearing, cy + r + r * 0.16)
    cr.show_text(date)

    # Side panels only when the screen is wide enough to leave room for them.
    margin = (w - 2 * r) / 2
    if margin > r * 0.6:
        draw_weather(cr, margin * 0.12, cy, r)
        draw_clawlight(cr, w - margin * 0.12, cy, r, margin * 0.8)
    return False


def main():
    for key, every, fetch in (
        ("weather", WEATHER_EVERY, fetch_weather),
        ("rain", RAIN_EVERY, fetch_rain),
        ("clawlight", CLAWLIGHT_EVERY, fetch_clawlight),
    ):
        threading.Thread(target=poll, args=(key, every, fetch), daemon=True).start()

    opened = time.monotonic()
    first_pos = {}

    def settled():
        return time.monotonic() - opened > GRACE_SECONDS

    def quit_on_input(*_):
        if settled():
            Gtk.main_quit()
        return True

    def quit_on_motion(_widget, event):
        if not settled():
            return True
        if "xy" not in first_pos:
            first_pos["xy"] = (event.x, event.y)
            return True
        x0, y0 = first_pos["xy"]
        if abs(event.x - x0) + abs(event.y - y0) > MOVE_THRESHOLD_PX:
            Gtk.main_quit()
        return True

    win = Gtk.Window(title="clock")
    area = Gtk.DrawingArea()
    area.connect("draw", draw)
    win.add(area)
    win.add_events(
        Gdk.EventMask.KEY_PRESS_MASK
        | Gdk.EventMask.BUTTON_PRESS_MASK
        | Gdk.EventMask.POINTER_MOTION_MASK
        | Gdk.EventMask.TOUCH_MASK
    )
    win.connect("key-press-event", quit_on_input)
    win.connect("button-press-event", quit_on_input)
    win.connect("touch-event", quit_on_input)
    win.connect("motion-notify-event", quit_on_motion)
    win.connect("destroy", Gtk.main_quit)

    def hide_cursor(widget):
        widget.get_window().set_cursor(
            Gdk.Cursor.new_from_name(widget.get_display(), "none")
        )

    win.connect("realize", hide_cursor)
    win.fullscreen()
    win.show_all()

    def tick():
        area.queue_draw()
        # Re-arm on the next whole second so the second hand stays in step.
        GLib.timeout_add(1000 - int(time.time() * 1000) % 1000 + 5, tick)
        return False

    tick()
    Gtk.main()


if __name__ == "__main__":
    main()
