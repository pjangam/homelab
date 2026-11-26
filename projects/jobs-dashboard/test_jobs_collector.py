#!/usr/bin/env python3
"""Tests for jobs_collector.py's history and stats (no systemd, no Prometheus).

    python3 -m unittest projects/jobs-dashboard/test_jobs_collector.py
"""
import json
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jobs_collector as jc  # noqa: E402

NOW = datetime(2026, 11, 26, 12, 0).timestamp()


def run(start, duration=0.05, cpu=0.05, ok=True, **kw):
    return {"start": start, "end": start + duration, "duration": duration, "exit": 0 if ok else 1,
            "ok": ok, "cpu": cpu, **kw}


class Tmp(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self._state, self._stats = jc.STATE, jc.STATS
        jc.STATE = Path(self.dir.name)
        jc.STATS = jc.STATE / "stats.json"

    def tearDown(self):
        jc.STATE, jc.STATS = self._state, self._stats
        self.dir.cleanup()


class Summarize(unittest.TestCase):
    def test_few_runs_give_max_only(self):
        s = jc.summarize([run(NOW - i * 60, cpu=i) for i in range(5)], NOW)
        self.assertEqual(s["fields"]["cpu"], {"n": 5, "max": 4})

    def test_percentiles_from_20_runs(self):
        s = jc.summarize([run(NOW - i * 60, cpu=float(i)) for i in range(1, 101)], NOW)
        f = s["fields"]["cpu"]
        self.assertEqual((f["p50"], f["p95"], f["max"]), (50.0, 95.0, 100.0))

    def test_missing_values_are_skipped(self):
        s = jc.summarize([run(NOW, cpu=None), run(NOW - 60, cpu=0.1, cpu_max=None)], NOW)
        self.assertEqual(s["fields"]["cpu"]["n"], 1)
        self.assertNotIn("cpu_max", s["fields"])
        self.assertNotIn("ram", s["fields"])   # old runs have no "ram" key

    def test_busiest_second_only_from_runs_of_a_second_or_more(self):
        s = jc.summarize([run(NOW, duration=0.03, cpu_max=93.0),
                          run(NOW - 60, duration=2, cpu_max=40.0)], NOW)
        self.assertEqual(s["fields"]["cpu_max"], {"n": 1, "max": 40.0})

    def test_temperatures_only_from_runs_of_a_minute_or_more(self):
        s = jc.summarize([run(NOW, duration=0.1, temps={"cpu": 70}),
                          run(NOW - 600, duration=300, temps={"cpu": 64, "ssd_data": 50})], NOW)
        self.assertEqual(s["fields"]["temp_cpu"]["max"], 64)
        self.assertEqual(s["fields"]["temp_ssd_data"]["max"], 50)

    def test_monthly_job_busiest_day_and_last_24h(self):
        runs = [run(NOW - 20 * 86400, duration=3600, cpu=900.0), run(NOW - 3600, cpu=1.0)]
        s = jc.summarize(runs, NOW)
        self.assertEqual(s["cpu_busiest_day"], 900.0)
        self.assertEqual(s["cpu_last_24h"], 1.0)

    def test_busiest_day_sums_runs_of_the_same_day(self):
        s = jc.summarize([run(NOW - i * 60, cpu=0.5) for i in range(10)], NOW)
        self.assertAlmostEqual(s["cpu_busiest_day"], 5.0)

    def test_history_shorter_than_a_day(self):
        s = jc.summarize([run(NOW - 60)], NOW)
        self.assertEqual(s["cpu_last_24h"], s["cpu_busiest_day"])

    def test_failures_in_a_row_and_last_success(self):
        runs = [run(NOW - 300), run(NOW - 200, ok=False), run(NOW - 100, ok=False)]
        s = jc.summarize(runs, NOW)
        self.assertEqual(s["fails"], 2)
        self.assertEqual(s["last_success"], NOW - 300 + 0.05)

    def test_empty_history(self):
        s = jc.summarize([], NOW)
        self.assertIsNone(s["last"])
        self.assertIsNone(s["cpu_busiest_day"])


class ApplyRun(unittest.TestCase):
    def test_updates_count_max_failures_but_not_percentiles(self):
        s = jc.summarize([run(NOW - i * 60, cpu=float(i)) for i in range(1, 30)], NOW)
        p95 = s["fields"]["cpu"]["p95"]
        jc.apply_run(s, run(NOW + 60, cpu=500.0, ok=False))
        f = s["fields"]["cpu"]
        self.assertEqual((f["n"], f["max"], f["p95"]), (30, 500.0, p95))
        self.assertEqual(s["fails"], 1)
        jc.apply_run(s, run(NOW + 120))
        self.assertEqual(s["fails"], 0)
        self.assertEqual(s["last"]["start"], NOW + 120)

    def test_first_value_of_a_new_field(self):
        s = jc.summarize([run(NOW - 60)], NOW)
        jc.apply_run(s, run(NOW, ram=1e6))
        self.assertEqual(s["fields"]["ram"], {"n": 1, "max": 1e6})


class Record(Tmp):
    def test_new_run_is_appended_once(self):
        stats = {}
        r = run(NOW)
        jc.record(stats, "x", dict(r), NOW)
        jc.record(stats, "x", dict(r), NOW)   # systemd shows the same run next minute
        lines = jc.history_path("x").read_text().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(stats["x"]["fields"]["duration"]["n"], 1)

    def test_lost_stats_are_rebuilt_from_the_file(self):
        stats = {}
        for i in range(3):
            jc.record(stats, "x", run(NOW + i * 60), NOW + i * 60)
        rebuilt = {}
        jc.record(rebuilt, "x", run(NOW + 120), NOW + 180)   # already in the file
        self.assertEqual(rebuilt["x"]["fields"]["duration"]["n"], 3)

    def test_enrich_runs_only_for_new_runs(self):
        seen = []
        stats = {}
        jc.record(stats, "x", run(NOW), NOW, enrich=lambda r: seen.append(r["start"]))
        jc.record(stats, "x", run(NOW), NOW, enrich=lambda r: seen.append(r["start"]))
        self.assertEqual(seen, [NOW])

    def test_old_runs_are_dropped_from_the_file(self):
        old = NOW - (jc.KEEP_DAYS + 2) * 86400
        p = jc.history_path("x")
        p.parent.mkdir(parents=True)
        p.write_text(json.dumps(run(old)) + "\n" + json.dumps(run(NOW - 60)) + "\n")
        runs = jc.read_history("x", NOW)
        self.assertEqual(len(runs), 1)
        self.assertEqual(len(p.read_text().splitlines()), 1)

    def test_stats_survive_a_save_and_load(self):
        stats = {}
        jc.record(stats, "x", run(NOW), NOW)
        jc.save_stats(stats)
        self.assertEqual(jc.load_stats(), json.loads(json.dumps(stats)))

    def test_torn_stats_file_reads_as_empty(self):
        jc.STATS.write_text("{not json")
        self.assertEqual(jc.load_stats(), {})


if __name__ == "__main__":
    unittest.main()
