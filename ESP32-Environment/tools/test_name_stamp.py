"""
Tests for tools/name_stamp.py.   Run:  python -m unittest tools.test_name_stamp
(or from tools/:  python -m unittest test_name_stamp)
"""

import datetime as dt
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import name_stamp as ns  # noqa: E402


class MakeTests(unittest.TestCase):
    def test_format(self):
        self.assertEqual(ns.make(dt.datetime(2026, 9, 27, 3, 11, 30)), "sept27_0311AM")
        self.assertEqual(ns.make(dt.datetime(2026, 9, 27, 15, 5)), "sept27_0305PM")
        self.assertEqual(ns.make(dt.datetime(2026, 1, 3, 0, 7)), "jan03_1207AM")
        self.assertEqual(ns.make(dt.datetime(2026, 1, 3, 12, 7)), "jan03_1207PM")
        self.assertEqual(ns.make_date(dt.datetime(2026, 9, 27)), "sept27")

    def test_round_trip_every_minute_of_a_day(self):
        start = dt.datetime(2026, 9, 27)
        for i in range(24 * 60):
            t = start + dt.timedelta(minutes=i)
            s = ns.make(t)
            self.assertRegex(s, "^" + ns.STAMP + "$")
            got, seq = ns.parse(s)
            self.assertEqual((got.month, got.day, got.hour, got.minute, seq),
                             (t.month, t.day, t.hour, t.minute, 1))


class ParseTests(unittest.TestCase):
    def test_old_format(self):
        self.assertEqual(ns.parse("20260927_031130"), (dt.datetime(2026, 9, 27, 3, 11, 30), 1))

    def test_suffix(self):
        self.assertEqual(ns.parse("sept27_0311AM-3")[1], 3)

    def test_rejects_garbage(self):
        for bad in ("sep27_0311AM", "sept27_1311AM", "sept27_0011AM", "sept27_0360AM",
                    "20260927_0311", "hello", "sept27_0311am"):
            with self.assertRaises(ValueError, msg=bad):
                ns.parse(bad)
            self.assertIsNone(re.fullmatch(ns.STAMP, bad), bad)

    def test_year_from_mtime_and_dec_to_jan(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "f.csv")
            open(p, "w").close()
            jan = dt.datetime(2027, 1, 2, 10, 0).timestamp()
            os.utime(p, (jan, jan))
            self.assertEqual(ns.parse("dec31_1100PM", p)[0].year, 2026)
            self.assertEqual(ns.parse("jan02_0900AM", p)[0].year, 2027)

    def test_chronological_not_alphabetical(self):
        names = ["sept27_1012AM", "sept27_0312PM", "aug30_1100PM", "20260926_235900"]
        ordered = sorted(names, key=lambda s: ns.parse(s))
        self.assertEqual(ordered, ["aug30_1100PM", "20260926_235900", "sept27_1012AM", "sept27_0312PM"])


class UniquePathTests(unittest.TestCase):
    def test_suffix_goes_after_stamp(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "root_node1_linear_blackhole_r1_sept27_0311AM_telem.csv")
            self.assertEqual(ns.unique_path(p), p)
            open(p, "w").close()
            p2 = ns.unique_path(p)
            self.assertEqual(os.path.basename(p2), "root_node1_linear_blackhole_r1_sept27_0311AM-2_telem.csv")
            p3 = ns.unique_path(p, taken={p2})
            self.assertTrue(p3.endswith("sept27_0311AM-3_telem.csv"))

    def test_log_and_folder(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "linear-blackhole-stationary-home_sept27_0205AM.log")
            open(log, "w").close()
            self.assertTrue(ns.unique_path(log).endswith("_sept27_0205AM-2.log"))
            self.assertEqual(ns.find("sept27_test-only"), None)
            self.assertEqual(ns.find("x_r1_20260927_031130_telem.csv"), "20260927_031130")


if __name__ == "__main__":
    unittest.main()
