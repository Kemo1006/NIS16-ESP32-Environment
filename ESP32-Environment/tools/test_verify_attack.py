#!/usr/bin/env python3
"""
test_verify_attack.py - does verify_attack.py catch what it claims to catch?

Each test takes a GOOD real capture (blackhole/linear/DLSU_Library/stationary,
wormhole/linear/DLSU_Library/stationary - both verified by hand, #4 and #10),
breaks ONE thing the way a real run could break, and checks that the verdict
turns. A check that never fires on broken data is not a check.

    python tools/test_verify_attack.py          (skips if the tables are absent)
"""
import contextlib
import io
import os
import sys
import unittest

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import verify_attack as va          # noqa: E402
import attack_checks as ac          # noqa: E402

BH = os.path.join(ENV, "datasets/analysis/blackhole/linear/DLSU_Library/stationary/feature_table.csv")
WH = os.path.join(ENV, "datasets/analysis/wormhole/linear/DLSU_Library/stationary/feature_table.csv")


def run(df, attack):
    """(confirmed, setup_invalid, report text)."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        confirmed, _ = va.verify(df.copy(), attack, 3.0)
    return confirmed, va._LAST_SETUP_INVALID[0], buf.getvalue()


def fails(df, attack):
    return [i.text for i in ac.setup_issues(df, attack) if i.level == ac.FAIL]


def attack_rows(df):
    return df["segment"].astype(str) == "attack"


@unittest.skipUnless(os.path.exists(BH), "blackhole reference table not present")
class Blackhole(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.df = pd.read_csv(BH)
        cls.atk_id = cls.df.loc[cls.df.node_role == "blackhole", "node_id"].iloc[0]
        cls.victims = set(cls.df.loc[cls.df.exposure == "downstream", "node_id"])
        cls.bystanders = set(cls.df.loc[cls.df.exposure == "upstream", "node_id"])

    def test_good_capture_confirmed_and_clean(self):
        c, inv, _ = run(self.df, "blackhole")
        self.assertTrue(c)
        self.assertFalse(inv)
        self.assertEqual(fails(self.df, "blackhole"), [])

    def test_attacker_kept_forwarding(self):
        d = self.df.copy()
        m = attack_rows(d) & (d.node_id == self.atk_id)
        d.loc[m, "forward_count_delta"] = d.loc[m, "recv_count_delta"]
        self.assertTrue(any("still FORWARDED" in t for t in fails(d, "blackhole")))
        self.assertFalse(run(d, "blackhole")[0])

    def test_attacker_was_a_leaf(self):
        d = self.df.copy()
        m = attack_rows(d) & (d.node_id == self.atk_id)
        d.loc[m, ["recv_count_delta", "forward_count_delta"]] = 0
        self.assertTrue(any("received NOTHING" in t for t in fails(d, "blackhole")))

    def test_no_victim_behind_attacker(self):
        d = self.df.copy()
        d.loc[d.exposure == "downstream", "exposure"] = "upstream"
        self.assertTrue(any("no node sits BEHIND" in t for t in fails(d, "blackhole")))

    def test_root_outage_hits_everyone(self):
        # C5-style: the root loses arrivals from EVERY node, attacker or not.
        d = self.df.copy()
        d.loc[attack_rows(d) & d.node_id.isin(self.bystanders), "PDR"] = 0.0
        self.assertTrue(any("not specific" in t for t in fails(d, "blackhole")))
        self.assertFalse(run(d, "blackhole")[0])

    def test_victim_was_dead_not_blackholed(self):
        d = self.df.copy()
        v = sorted(self.victims)[0]
        d.loc[attack_rows(d) & (d.node_id == v), "n_samples_present"] = 0
        self.assertTrue(any("NO telemetry" in t for t in fails(d, "blackhole")))

    def test_victims_not_cut_off(self):
        d = self.df.copy()
        d.loc[attack_rows(d) & d.node_id.isin(self.victims), "PDR"] = 1.0
        self.assertTrue(any("not cut off" in t for t in fails(d, "blackhole")))

    def test_attacker_moved_mid_attack(self):
        d = self.df.copy()
        rows = d.index[attack_rows(d) & (d.node_id == self.atk_id)]
        d.loc[rows[: len(rows) // 2], "parent_mac"] = "B0:CB:D8:F3:32:19"   # the root's AP
        self.assertTrue(any("changed parent during the attack" in t for t in fails(d, "blackhole")))

    def test_linear_with_a_branch_is_not_linear(self):
        d = self.df.copy()
        root_ap = "B0:CB:D8:F3:32:19"
        kids = d.loc[attack_rows(d) & (d.node_role == "child"), "node_id"].unique()[:2]
        d.loc[attack_rows(d) & d.node_id.isin(kids), "parent_mac"] = root_ap
        self.assertTrue(any("is NOT linear" in t for t in fails(d, "blackhole")))

    def test_attacker_telemetry_missing(self):
        d = self.df[self.df.node_role != "blackhole"]
        self.assertTrue(any("no 'blackhole' node" in t for t in fails(d, "blackhole")))


@unittest.skipUnless(os.path.exists(WH), "wormhole reference table not present")
class Wormhole(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.df = pd.read_csv(WH)

    def test_good_capture_confirmed_and_clean(self):
        c, inv, _ = run(self.df, "wormhole")
        self.assertTrue(c)
        self.assertFalse(inv)
        self.assertEqual(fails(self.df, "wormhole"), [])

    def test_no_uart_cable(self):
        d = self.df.copy()
        d.loc[d.node_role == "wormhole_a", ["TunnelIntensity", "TunnelBytes"]] = 0.0
        self.assertTrue(any("carried nothing" in t for t in fails(d, "wormhole")))
        c, inv, _ = run(d, "wormhole")
        self.assertFalse(c)
        self.assertTrue(inv)

    def test_ends_reversed(self):
        d = self.df.copy()
        d["node_role"] = d.node_role.replace({"wormhole_a": "x", "wormhole_b": "wormhole_a"}) \
                                    .replace({"x": "wormhole_b"})
        self.assertTrue(any("REVERSED" in t for t in fails(d, "wormhole")))

    def test_role_switch_in_experiment_counts_but_not_before(self):
        d = self.df.copy()
        a = d.loc[d.node_role == "wormhole_a", "node_id"].iloc[0]
        pre = (d.node_id == a) & (d.segment == "pre_baseline")
        d.loc[d.index[pre][:5], "node_role"] = "wormhole_b"
        self.assertFalse(any("changed role" in t for t in fails(d, "wormhole")),
                         "a provisional flip before Phase 0 must not count")
        inexp = (d.node_id == a) & (d.segment == "baseline")
        d.loc[d.index[inexp][:5], "node_role"] = "wormhole_b"
        self.assertTrue(any("changed role" in t for t in fails(d, "wormhole")))

    def test_root_saw_no_duplicates(self):
        d = self.df.copy()
        d.loc[attack_rows(d), "TunnelLatency"] = np.nan
        self.assertTrue(any("no duplicate arrivals" in t for t in fails(d, "wormhole")))

    def test_two_b_ends(self):
        d = self.df.copy()
        d.loc[d.node_role == "wormhole_a", "node_role"] = "wormhole_b"
        self.assertTrue(fails(d, "wormhole"))


class Statistics(unittest.TestCase):
    def test_one_lost_probe_on_a_flat_baseline_is_not_an_attack(self):
        base = pd.Series([1.0] * 60)
        atk = pd.Series([1.0] * 35 + [0.8])          # one window lost 1 of 5 probes
        r = va.stat_verdict(base, atk, "down", 3.0, feature="PDR")
        self.assertEqual(r["status"], "FAIL")
        self.assertIn("too small", r["note"])

    def test_real_collapse_on_a_flat_baseline_passes(self):
        r = va.stat_verdict(pd.Series([1.0] * 60), pd.Series([0.0] * 36), "down", 3.0, feature="PDR")
        self.assertEqual(r["status"], "PASS")

    def test_too_few_attack_points(self):
        r = va.stat_verdict(pd.Series(np.random.default_rng(1).normal(1, .01, 60)),
                            pd.Series([0.0] * 3), "down", 3.0, feature="PDR")
        self.assertEqual(r["status"], "INCONCLUSIVE")


if __name__ == "__main__":
    unittest.main(verbosity=2)
