"""Per-second host samples, reported as percentiles and maxima.

Shared by projects/xero-stats/xero-stats-mqtt.py and
projects/pi-health/pi-health-mqtt.py. Both publish once a minute; a value
read once a minute (or HA System Monitor's average over its poll interval)
hides exactly the spikes worth seeing, so a background thread samples every
second and each report gives the p95 and the max of the minute since the
last one. Never an average: a minute of 50% could be a steady 50% or
thirty seconds pinned at 100%, and only the second one matters.

Metrics, each over the samples since the previous report():
  cpu           busy % of all cores, from /proc/stat deltas
  temperature   °C from a sysfs thermal zone
  memory        used % = 1 - MemAvailable/MemTotal (page cache is not "used")
  pressure      % of each second some task waited for CPU, from
                /proc/pressure/cpu "total" (only where the kernel has PSI)
  <name>_temperature
                °C of each SATA disk given as {name: drive_temp_file()},
                from the drivetemp hwmon, read every DRIVE_PERIOD seconds rather than every
                second: each read is a SMART command to the drive, which
                drains its NCQ queue, and a disk's temperature moves slowly
"""
import glob
import math
import os
import threading
import time

DRIVE_PERIOD = 10


def percentile(values, pct):
    """Nearest-rank percentile: always a value that was actually seen."""
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(pct / 100 * len(ordered)) - 1)]


def thermal_zone(zone_type=None):
    """Path of the temp file for a thermal zone of this type, else zone0."""
    for zone in sorted(glob.glob("/sys/class/thermal/thermal_zone*")):
        try:
            with open(f"{zone}/type") as f:
                if zone_type is None or f.read().strip() == zone_type:
                    return f"{zone}/temp"
        except OSError:
            continue
    return "/sys/class/thermal/thermal_zone0/temp"


def drive_temp_file(device):
    """drivetemp's temp file for the disk holding a block device (/dev/sda1 or
    sda), else None: the drivetemp module not loaded, or not a SATA disk."""
    block = os.path.realpath(f"/sys/class/block/{os.path.basename(device)}")
    if os.path.exists(f"{block}/partition"):
        block = os.path.dirname(block)
    found = glob.glob(f"{block}/device/hwmon/hwmon*/temp1_input")
    return found[0] if found else None


def _read_temp(path):
    with open(path) as f:
        return int(f.read()) / 1000


def _cpu_counters():
    with open("/proc/stat") as f:
        fields = [int(x) for x in f.readline().split()[1:]]
    return fields[3] + fields[4], sum(fields[:8])  # idle+iowait, total less guest


def _pressure_total():
    try:
        with open("/proc/pressure/cpu") as f:
            for line in f:
                if line.startswith("some "):
                    return int(line.rsplit("total=", 1)[1])  # microseconds
    except OSError:
        return None
    return None


def _memory_used_percent():
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, value = line.split(":")
            info[key] = int(value.split()[0])
    return 100 * (1 - info["MemAvailable"] / info["MemTotal"])


class Sampler:
    def __init__(self, temp_file, period=1.0, drive_temp_files=None):
        self.temp_file = temp_file
        self.period = period
        self.has_pressure = _pressure_total() is not None
        self._lock = threading.Lock()
        self._samples = {"cpu": [], "temperature": [], "memory": [], "pressure": []}
        drives = drive_temp_files or {}
        for name in drives:
            self._samples[f"{name}_temperature"] = []
        threading.Thread(target=self._run, daemon=True).start()
        for name, path in drives.items():
            # A thread each: a read waits on the drive, and a stalled drive
            # (the 44s one of 2026-10-21) must not stop the CPU samples or
            # the other drive's.
            threading.Thread(target=self._run_drive, args=(f"{name}_temperature", path),
                             daemon=True).start()

    def _run(self):
        prev_idle, prev_total = _cpu_counters()
        prev_psi, prev_t = _pressure_total(), time.monotonic()
        while True:
            time.sleep(self.period)
            try:
                idle, total = _cpu_counters()
                psi, now = _pressure_total(), time.monotonic()
                sample = {"temperature": _read_temp(self.temp_file), "memory": _memory_used_percent()}
                if total > prev_total:
                    sample["cpu"] = 100 * (1 - (idle - prev_idle) / (total - prev_total))
                if psi is not None and prev_psi is not None and now > prev_t:
                    sample["pressure"] = min(100.0, (psi - prev_psi) / ((now - prev_t) * 1e4))
                prev_idle, prev_total, prev_psi, prev_t = idle, total, psi, now
                with self._lock:
                    for key, value in sample.items():
                        self._samples[key].append(value)
            except Exception as e:  # one bad read must not kill sampling
                print(f"sample failed: {e!r}", flush=True)

    def _run_drive(self, key, path):
        while True:
            time.sleep(DRIVE_PERIOD)
            try:
                temp = _read_temp(path)
                with self._lock:
                    self._samples[key].append(temp)
            except Exception as e:
                print(f"drive sample failed: {e!r}", flush=True)

    def report(self):
        """{metric_p95, metric_max} over the samples since the last call; None when empty."""
        with self._lock:
            samples, self._samples = self._samples, {k: [] for k in self._samples}
        out = {}
        for key, values in samples.items():
            if key == "pressure" and not self.has_pressure:
                continue
            p95, peak = percentile(values, 95), (max(values) if values else None)
            out[f"{key}_p95"] = None if p95 is None else round(p95, 1)
            out[f"{key}_max"] = None if peak is None else round(peak, 1)
        out["samples"] = len(samples["temperature"])
        return out
