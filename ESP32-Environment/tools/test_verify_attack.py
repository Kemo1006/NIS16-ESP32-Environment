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


TREE = os.path.join(ENV, "archive/2026-10-18_blackhole-tree-G402-stationary-r1-replaced-2/analysis/feature_table.csv")


@unittest.skipUnless(os.path.exists(TREE), "tree re-route reference table not present")
class TreeReroute(unittest.TestCase):
    """oct. 18 2026: a parent change is judged by what it did to the attack's reach.
    The 7:21 PM capture: F4:18 (under the attacker) crashed, its children D7B4 / ED80
    re-joined - D7B4 straight under the attacker - so both stayed VICTIMS."""
    @classmethod
    def setUpClass(cls):
        cls.df = pd.read_csv(TREE)

    def test_victim_to_victim_reroute_is_tolerated(self):
        self.assertEqual(fails(self.df, "blackhole"), [])
        txt = [i.text for i in ac.setup_issues(self.df, "blackhole")]
        self.assertTrue(any("D7B4" in t and "TOLERATED" in t for t in txt))

    def test_victim_becoming_bystander_still_fails(self):
        d = self.df.copy()
        m = attack_rows(d) & (d.node_id == "NODE_F42DC973E618")
        late = d[m].sort_values("t_anchor_s").index[len(d[m]) // 2:]
        d.loc[late, "parent_mac"] = "B0:CB:D8:F3:32:19"     # straight under the root
        d.loc[late, "PDR"] = 1.0
        self.assertTrue(any("VICTIM" in t and "BYSTANDER" in t for t in fails(d, "blackhole")))

    def test_long_outage_is_excluded_not_fatal(self):
        # oct. 19 2026: 30 s without a path (> the 10 % of a brief re-join) -> those windows are
        # EXCLUDED from the 3-sigma test and named; the run is not failed for them
        d = self.df.copy()
        m = attack_rows(d) & (d.node_id == "NODE_2805A532D7B4")
        d.loc[d[m].sort_values("t_anchor_s").index[:30], "parent_mac"] = "00:00:00:00:00:00"
        txt = [i.text for i in ac.setup_issues(d, "blackhole") if i.level == ac.WARN]
        self.assertTrue(any("D7B4" in t and "TOLERATED WITH EXCLUSION" in t for t in txt))
        self.assertGreaterEqual(len(ac.unresolved_windows(d, "blackhole")), 30)
        self.assertIn("EXCLUDED from the test", run(d, "blackhole")[2])

    def test_exclusion_never_makes_it_easier(self):
        # fairness rule 6: excluded windows are dead-path windows (PDR 0); dropping them can
        # only weaken the attack evidence - the attack mean of PDR must not go DOWN
        d = self.df.copy()
        m = attack_rows(d) & (d.node_id == "NODE_2805A532D7B4")
        idx = d[m].sort_values("t_anchor_s").index[:30]
        d.loc[idx, "parent_mac"] = "00:00:00:00:00:00"
        d.loc[idx, "PDR"] = 0.0
        bad = ac.unresolved_windows(d, "blackhole")
        keep = ~pd.Series([(n, round(float(t), 3)) in bad for n, t in zip(d.node_id, d.t_anchor_s)], index=d.index)
        a = attack_rows(d)
        self.assertGreaterEqual(d.loc[a & keep, "PDR"].mean(), d.loc[a, "PDR"].mean())

    def test_good_reroute_is_robust(self):
        c, inv, txt = run(self.df, "blackhole")
        self.assertTrue(c and not inv)
        self.assertIn("ROBUST: the", txt)

    def test_signature_only_after_the_reroute_is_not_robust(self):
        # fairness rule 5: the attack windows BEFORE the re-route must confirm on their own
        d = self.df.copy()
        pre = attack_rows(d) & (d.t_anchor_s < ac.reroute_onset(d, "blackhole"))
        d.loc[pre, "forward_count_delta"] = d.loc[pre, "recv_count_delta"]
        d.loc[pre, ["ForwardingRatio", "NeighbourForwardingRatio", "PDR"]] = 1.0
        c, inv, txt = run(d, "blackhole")
        self.assertIn("NOT ROBUST", txt)
        self.assertFalse(c and not inv)

    def test_flapping_victim_warns_not_fails(self):
        # S1: many parent changes but always under the attacker -> WARN FLAPPED, not a failure
        d = self.df.copy()
        m = attack_rows(d) & (d.node_id == "NODE_2805A532D7B4")
        idx = d[m].sort_values("t_anchor_s").index
        for k, i in enumerate(range(0, 60, 10)):          # 6 switches between two victim parents
            d.loc[idx[i:i + 10], "parent_mac"] = "20:50:0D:E7:1C:39" if k % 2 else "F4:2D:C9:73:E6:19"
        txt = [i for i in ac.setup_issues(d, "blackhole") if "FLAPPED" in i.text]
        self.assertTrue(txt and all(i.level == ac.WARN for i in txt))
        self.assertFalse(any("D7B4" in t and "BYSTANDER" in t for t in fails(d, "blackhole")))

    def test_baseline_role_change_is_a_footnote(self):
        # S4: a victim sat under the root for 20 s of the BASELINE -> WARN only (no attack then)
        d = self.df.copy()
        m = (d.segment.astype(str) == "baseline") & (d.node_id == "NODE_F42DC973E618")
        d.loc[d[m].sort_values("t_anchor_s").index[:20], "parent_mac"] = "B0:CB:D8:F3:32:19"
        w = [i for i in ac.setup_issues(d, "blackhole") if "during the BASELINE" in i.text]
        self.assertTrue(w and w[0].level == ac.WARN)

    def test_confidence_grades(self):
        # 7:21 PM run: E618 kept 151 s of its attack and lost its cooldown -> MINOR gaps,
        # and the impact check (the test re-run without E618) still confirms
        c, inv, txt = run(self.df, "blackhole")
        self.assertIn("CONFIDENCE: MINOR GAPS", txt)
        self.assertIn("MINOR GAP (result not affected): E618 (victim): only 151 of", txt)
        self.assertIn("MINOR GAP (result not affected): E618: only 0 of", txt)
        self.assertIn("impact check: without E618", txt)
        self.assertIn('REPORT AS: "BLACKHOLE CONFIRMED - minor gaps"', txt)

    def test_short_attack_is_judged_by_the_impact_check(self):
        # cut E618's attack to its first 28 s: no fixed "< 60 s = major" rule - the attack
        # still holds without E618, so it is MINOR (tree/G402/stationary, B768, oct. 19 2026)
        d = self.df.copy()
        a = attack_rows(d)
        t0 = d.loc[a, "t_anchor_s"].min()
        d = d[~(a & (d.node_id == "NODE_F42DC973E618") & (d.t_anchor_s > t0 + 28))]
        d = d[~((d.segment.astype(str) == "cooldown") & (d.node_id == "NODE_F42DC973E618"))]
        txt = run(d, "blackhole")[2]
        # (this cut also leaves 66% of victim time with no path - a separate MAJOR gap, so the
        # grade itself is not asserted; the 28 s board alone must be MINOR)
        self.assertIn("MINOR GAP (result not affected): E618 (victim): only 28 of", txt)
        self.assertNotIn("MAJOR GAP (affects the result): E618", txt)
        self.assertIn("impact check: without E618", txt)

    def test_failed_impact_check_makes_it_major(self):
        # the same gaps, but the attack is NOT confirmed without the board: MAJOR
        W = ac.WARN
        iss = [ac.Issue(W, "E618 (child) - a victim - has NO attack windows after +28 s (151 s before the end): x"),
               ac.Issue(W, "IMPACT CHECK FAILED: without E618 the attack is not confirmed - the result depends on them")]
        g = va._confidence(True, False, True, iss)
        self.assertEqual(g[0], "MAJOR GAPS")
        self.assertEqual(len(g[2]), 1)
        self.assertTrue(g[1][0].startswith("the small gaps DO change the result"))
        self.assertEqual(va._confidence(True, False, True, iss[:1])[0], "MINOR GAPS")

    def test_decision_ignores_delivery(self):
        # fairness rule 1: the tolerate / reject decision must not read PDR
        d = self.df.copy()
        d.loc[attack_rows(d), "PDR"] = 1.0
        lv = {i.text.split(" ", 1)[0]: i.level for i in ac.topology_issues(d, "blackhole", {"NODE_2805A532D7B4", "NODE_B4BFE934ED80"})
              if "TOLERATED" in i.text}
        self.assertEqual(lv, {"D7B4": ac.WARN, "ED80": ac.WARN})


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

    def test_clean_run_is_strong_and_broken_run_says_why(self):
        # STRONG needs EVERY check to pass, the force-start check included (a normal
        # START in the run log); without a run log the same run is GOOD (a note, no data gap)
        real = ac.start_anyway_issues
        try:
            ac.start_anyway_issues = lambda df, **k: [ac.Issue("OK", "normal START - no START_ANYWAY in the root's run log")]
            self.assertIn("CONFIDENCE: STRONG", run(self.df, "blackhole")[2])
        finally:
            ac.start_anyway_issues = real
        txt = run(self.df, "blackhole")[2]
        self.assertIn("could not be checked (no run log saved)", txt)
        self.assertIn("CONFIDENCE: GOOD", txt)                  # nothing missing -> a note, not a data gap
        self.assertIn("DATA: every board has usable data", txt)
        d = self.df.copy()
        m = attack_rows(d) & (d.node_id == self.atk_id)
        d.loc[m, "forward_count_delta"] = d.loc[m, "recv_count_delta"]
        txt = run(d, "blackhole")[2]
        self.assertIn("CONFIDENCE: NOT CONFIRMED", txt)

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

    def test_node_a_unlabelled_is_not_a_cable_fault(self):
        # oct. 16 2026 wormhole/tree/DLSU: A's raw counter went 0 -> 181 but all
        # its windows were no_phase_seen, and the check claimed "carried nothing".
        d = self.df.copy()
        d.loc[d.node_role == "wormhole_a", "segment"] = "no_phase_seen"
        self.assertFalse(any("carried nothing" in t for t in fails(d, "wormhole")))
        texts = [i.text for i in ac.setup_issues(d, "wormhole")]
        self.assertTrue(any("cannot check UART delivery" in t for t in texts))
        self.assertTrue(any("NO labelled window" in t for t in texts))
        self.assertFalse(any("tunnel carried data" in t for t in texts))

    def test_node_a_attack_windows_discarded_but_root_saw_duplicates(self):
        # A kept its baseline, lost its attack windows (too few samples); the
        # root's duplicates prove A re-injected -> WARN, not SETUP INVALID.
        d = self.df.copy()
        d = d[~((d.node_role == "wormhole_a") & (d.segment == "attack"))]
        self.assertEqual(fails(d, "wormhole"), [])
        texts = [i.text for i in ac.setup_issues(d, "wormhole")]
        self.assertTrue(any("only A re-injects them" in t for t in texts))
        # ...but with NO duplicates at the root, a missing A still fails.
        d2 = d.copy()
        d2["TunnelLatency"] = np.nan
        self.assertNotEqual(fails(d2, "wormhole"), [])

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


class StartAnyway(unittest.TestCase):
    """START_ANYWAY is only in the root's run log - the check must find a real
    forced start, ignore help text, and blame only THIS capture's log."""
    ROOT_OK = ("I (6048) ROOT_MAIN: [CTRL] Waiting 60 s for mesh to stabilise...\n"
               "W (66058) ROOT_MAIN: [CTRL] WAITING: 6/7 children. Fix it, or type START_ANYWAY.\n"
               "I (90000) ROOT_MAIN: [CTRL] START received after 3 s - starting the run.\n")
    ROOT_FORCED = ("I (6048) ROOT_MAIN: [CTRL] Waiting 60 s for mesh to stabilise...\n"
                   "\x1b[0;31mE (99000) ROOT_MAIN: [CTRL] START_ANYWAY after 120 s - starting with 6/7 children.\x1b[0m\n")

    def setUp(self):
        import tempfile
        self.tmp = tempfile.mkdtemp()
        self.cell = os.path.join(self.tmp, "blackhole", "tree", "G402", "highload")
        os.makedirs(self.cell)
        self.df = pd.DataFrame({"attack": ["blackhole"], "topology": ["tree"], "location": ["G402"],
                                "scenario": ["highload"],
                                "source_file": ["root_root_tree_blackhole_r1_oct17_0541PM_telem.csv"]})

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def log(self, name, text):
        with open(os.path.join(self.cell, name), "w", encoding="utf-8") as fh:
            fh.write(text)

    def level(self):
        return ac.start_anyway_issues(self.df, logs_root=self.tmp)[0].level

    def test_forced_start_warns(self):
        self.log("blackhole-tree-g402-highload_r1_oct17_0524PM.log", self.ROOT_FORCED)
        self.assertEqual(self.level(), ac.WARN)

    def test_normal_start_with_help_text_is_ok(self):
        self.log("blackhole-tree-g402-highload_r1_oct17_0524PM.log", self.ROOT_OK)
        self.assertEqual(self.level(), "OK")

    def test_gui_prestart_override_is_reported(self):
        # gui/PreStart.ps1 writes this line when a RED pre-START check is overridden
        self.log("blackhole-tree-g402-highload_r1_oct17_0524PM.log", self.ROOT_OK
                 + "PRESTART_OVERRIDE: Location = G402 (WRONG on c2 (DLSU_Library)) | reason: c2 fixed, not rebooted\n")
        txt = ac.start_anyway_issues(self.df, logs_root=self.tmp)
        self.assertTrue(any(i.level == ac.WARN and "overridden by the operator" in i.text and "c2 fixed" in i.text
                            for i in txt))
        self.assertTrue(any(i.level == "OK" for i in txt))     # still a normal START at the root

    def test_older_forced_attempt_is_not_this_run(self):
        self.log("blackhole-tree-g402-highload_r1_oct17_0458PM.log", self.ROOT_FORCED)
        self.log("blackhole-tree-g402-highload_r1_oct17_0524PM.log", self.ROOT_OK)
        self.assertEqual(self.level(), "OK")

    def test_no_log_skips(self):
        self.assertEqual(self.level(), ac.SKIP)

    def test_log_from_another_day_is_ignored(self):
        self.log("blackhole-tree-g402-highload_r1_oct15_0524PM.log", self.ROOT_FORCED)
        self.assertEqual(self.level(), ac.SKIP)


if __name__ == "__main__":
    unittest.main(verbosity=2)
