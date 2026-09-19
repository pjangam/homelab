#!/usr/bin/env python3
# Fullscreen analog clock for the wol-sender Pi's desktop, meant to run as a
# screensaver. The desktop is labwc (Wayland), where xscreensaver and the X11
# clocks misbehave; GTK3 runs natively there and fullscreens itself.
# Any key, click or mouse movement closes it.
#
# Needs: sudo apt install python3-gi-cairo
# Deploy: scp scripts/wol-sender/analog_clock.py pramod@192.168.1.124:~/
# Run on the Pi's desktop: python3 ~/analog_clock.py
import math
import time

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
    return False


def main():
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
