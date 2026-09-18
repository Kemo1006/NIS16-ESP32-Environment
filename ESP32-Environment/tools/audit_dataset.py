"""
audit_dataset.py - audit raw capture CSVs, group them into runs WITHOUT a clock,
and write a cleaned, analysis-ready copy. The raw files are only ever read.

Why this exists: an export folder is keyed by <attack>/<topology>/<location> and
the repeat number, so captures from different runs - and different boots of the
same board - end up side by side under the same "r1". Nothing inside a telemetry
CSV names its run (boards have no RTC, and provenance is deliberately kept out of
the rows), so the grouping has to be proven from counters that survive a missing
clock:

  root telem <-> root arrivals   same node_id, last probes_count == last probes_received
  victim     -> run              the victim's own send counter (probes + retries,
                                 == seq_num) at its phase-0 exit matches the last
                                 baseline seq_num the root logged from that MAC,
                                 and its final value matches the root's max seq
  attacker   -> run              probes it forwarded during cooldown == probes the
                                 root received during cooldown (exact, unique)

Anything that can't be proven is left UNASSIGNED with the reason - never guessed.

Cleaning is additive: raw columns keep their raw values; derived columns sit next
to them and say what they are (see docs/DATASET-AUDIT-2026-09-18.md for the dictionary).

  - rssi_dbm        0 -> empty. esp_wifi_sta_get_rssi() leaves 0 when there is no
                    parent link (the root; a node not yet joined). 0 dBm is not a
                    reading any of these links can produce.
  - layer           -1 -> empty (the stack's "not in a mesh"), in_mesh = False.
  - parent_mac      00:00:00:00:00:00 -> empty; parent_node_id resolves the parent's
                    SoftAP BSSID (STA + 1) back to its node_id.
  - t_anchor_s      seconds from the node's own first exit from phase 0. The phase
                    change is a mesh broadcast, so it is the one instant every board
                    observes (to within its broadcast delivery) - a common origin
                    without a common clock.
  - segment         phase 0 is also what a board logs before it has heard any phase
                    broadcast (phase_listener.c starts at 0) and during the root's
                    stabilise window, so only the last PHASE_BASELINE_S seconds
                    before the phase-0 exit are "baseline"; earlier phase-0 rows
                    are "pre_baseline". gt_label itself is left as logged.
  - rel_latency_us  arrivals latency_us subtracts two unsynchronised boot clocks, so
                    it is the true one-way delay plus a constant per (run, src) offset.
                    Subtracting the per-(run, src) minimum cancels the offset; the
                    result is delay relative to that source's fastest probe.

Usage (from tools\\):
    python audit_dataset.py <dir> [<dir> ...] --out <folder>
      [--location G402]
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import topology_graph as tg  # noqa: E402

TELEM_COLS = ["timestamp_us", "node_id", "role", "layer", "parent_mac", "rssi_dbm",
              "retry_count", "tx_count", "probes_count", "phase_id", "gt_label"]
ARRIVAL_COLS = TELEM_COLS[:8] + ["probes_received", "phase_id", "gt_label",
                                 "src_mac", "seq_num", "latency_us"]
TEXT_COLS = ("node_id", "role", "parent_mac", "src_mac")
MAC_RE = re.compile(r"^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$")
ZERO_MAC = "00:00:00:00:00:00"
NAME_RE = re.compile(
    r"^(?P<prefix>[a-z]+)_(?P<nick>.+?)_(?P<topology>linear|star|tree|partial_mesh|partial)_"
    r"(?P<attack>none|baseline|blackhole|wormhole)_r(?P<repeat>\d+)_"
    r"(?P<date>\d{8})_(?P<time>\d{6})_(?P<kind>telem|arrivals)\.csv$")
PHASE_NAMES = {0: "baseline", 1: "attack", 2: "attack", 3: "cooldown", 4: "terminate"}
PHASE_TO_LABEL = {0: 0, 1: 1, 2: 2, 3: 0, 4: 0}   # phase_listener.c phase_id_to_label()
SEQ_TOL = 2   # the last probe(s) before a phase change may be lost in flight


def mesh_config_seconds(name: str) -> int:
    """Read a phase length from mesh_config.h so it is never duplicated here."""
    path = os.path.join(HERE, "..", "components", "mesh_common", "include", "mesh_config.h")
    with open(path, encoding="utf-8") as f:
        m = re.search(rf"#define\s+{name}\s+(\d+)U?", f.read())
    if not m:
        raise SystemExit(f"{name} not found in {path}")
    return int(m.group(1))


def mac_of(node_id: str) -> str:
    h = node_id.split("_", 1)[1]
    return ":".join(h[i:i + 2] for i in range(0, 12, 2)).upper()


def sta_of_bssid(bssid: str) -> str:
    """Parent links are the parent's SoftAP BSSID, which is its STA MAC + 1."""
    v = (int(bssid.replace(":", ""), 16) - 1) & 0xFFFFFFFFFFFF
    h = f"{v:012X}"
    return ":".join(h[i:i + 2] for i in range(0, 12, 2))


# ── Step 1: load + per-file audit ───────────────────────────────────────────

class Capture:
    def __init__(self, path):
        self.path = path
        self.name = os.path.basename(path)
        self.issues: list[str] = []
        self.df: pd.DataFrame | None = None
        m = NAME_RE.match(self.name)
        self.meta = m.groupdict() if m else {}
        if not m:
            self.issues.append("filename does not follow the export naming scheme")
        self.kind = self.meta.get("kind") or ("arrivals" if "arrivals" in self.name else "telem")
        self.run_id = ""
        self.assignment = "unassigned"
        self.evidence = ""
        self.anchor_ts = None
        self._load()

    def _load(self):
        if os.path.getsize(self.path) == 0:
            self.issues.append("EMPTY FILE (0 bytes) - card file never written/closed")
            return
        raw = pd.read_csv(self.path, dtype=str, keep_default_na=False)
        expected = ARRIVAL_COLS if self.kind == "arrivals" else TELEM_COLS
        if list(raw.columns) != expected:
            self.issues.append(f"header mismatch: {list(raw.columns)}")
            return
        repeated = raw["timestamp_us"] == "timestamp_us"
        if repeated.any():
            self.issues.append(f"{int(repeated.sum())} repeated header row(s) inside the data")
            raw = raw[~repeated]
        if raw.empty:
            self.issues.append("HEADER ONLY - no data rows")
            return
        df = raw.copy()
        for c in expected:
            if c in TEXT_COLS:
                df[c] = df[c].str.strip().str.upper() if c != "role" else df[c].str.strip()
                continue
            v = pd.to_numeric(df[c], errors="coerce")
            if v.isna().any():
                self.issues.append(f"{c}: {int(v.isna().sum())} non-numeric cell(s)")
            df[c] = v
        bad = df[[c for c in expected if c not in TEXT_COLS]].isna().any(axis=1)
        if bad.any():
            self.issues.append(f"{int(bad.sum())} malformed row(s) excluded from the cleaned copy")
            df = df[~bad]
        for c in [c for c in expected if c not in TEXT_COLS]:
            df[c] = df[c].astype("int64")
        dups = df.duplicated()
        if dups.any():
            self.issues.append(f"{int(dups.sum())} exact duplicate row(s) removed")
            df = df[~dups]
        for c in ("parent_mac", "src_mac"):
            if c in df and (~df[c].str.match(MAC_RE)).any():
                self.issues.append(f"{c}: invalid MAC format in {(~df[c].str.match(MAC_RE)).sum()} row(s)")
        if df["node_id"].nunique() > 1 or df["role"].nunique() > 1:
            self.issues.append(f"mixed identity in one file: {df['node_id'].unique()} / {df['role'].unique()}")
        steps = np.diff(df["timestamp_us"].to_numpy())
        if (steps < 0).any():
            self.issues.append(f"{int((steps < 0).sum())} timestamp regression(s) - board rebooted "
                               f"mid-file; rows after it are a different boot")
        counters = ["retry_count", "tx_count",
                    "probes_received" if self.kind == "arrivals" else "probes_count"]
        for c in counters:
            if (np.diff(df[c].to_numpy()) < 0).any() and not (steps < 0).any():
                self.issues.append(f"{c} decreases without a reboot")
        mism = df["gt_label"] != df["phase_id"].map(PHASE_TO_LABEL)
        if mism.any():
            self.issues.append(f"{int(mism.sum())} row(s) where gt_label != label of phase_id")
        self.df = df.reset_index(drop=True)
        self.node_id = df["node_id"].iloc[0]
        self.role = df["role"].iloc[0]
        prefix = self.meta.get("prefix")
        expect_prefix = {"root": "root", "victim": "victim"}.get(self.role)
        if prefix and prefix != "child" and expect_prefix != prefix:
            self.issues.append(f"filename says '{prefix}' but every row says role={self.role}")
        nick = self.meta.get("nick", "")
        if nick.startswith("NODE-") and nick.replace("-", "_") != self.node_id:
            self.issues.append(f"filename node {nick} != node_id {self.node_id} in rows")
        ph = df["phase_id"].to_numpy()
        out = np.nonzero(ph != 0)[0]
        if len(out):
            self.anchor_ts = int(df["timestamp_us"].iloc[out[0]])
        else:
            self.issues.append("never left phase 0 - no phase broadcast received (orphan/aborted)")

    @property
    def ok(self):
        return self.df is not None

    def seq(self):
        return self.df["probes_count"] + self.df["retry_count"]

    def seq_at_phase_exit(self):
        if self.anchor_ts is None:
            return None
        i = int(np.argmax(self.df["timestamp_us"].to_numpy() >= self.anchor_ts))
        return int(self.seq().iloc[i])

    def delta_in_phase(self, col, phase):
        d = self.df[self.df["phase_id"] == phase]
        return int(d[col].iloc[-1] - d[col].iloc[0]) if len(d) else None


# ── Step 2: group into runs by counters, not clocks ─────────────────────────

def assemble_runs(caps):
    runs = {}
    arrivals = [c for c in caps if c.ok and c.kind == "arrivals"]
    telems = [c for c in caps if c.ok and c.kind == "telem"]
    for a in arrivals:
        last = int(a.df["probes_received"].iloc[-1])
        partner = [t for t in telems if t.role == "root" and t.node_id == a.node_id
                   and int(t.df["probes_count"].iloc[-1]) == last]
        run_id = "_".join([a.meta.get("topology", "?"), a.meta.get("attack", "?"),
                           a.meta.get("date", "?"), a.meta.get("time", "?")])
        runs[run_id] = {"arrivals": a, "root": partner[0] if len(partner) == 1 else None,
                        "members": []}
        a.run_id, a.assignment = run_id, "anchor"
        a.evidence = f"root arrivals log, {len(a.df)} probes"
        if len(partner) == 1:
            p = partner[0]
            p.run_id, p.assignment = run_id, "assigned"
            p.evidence = f"same node_id, last probes_count {last} == last probes_received"

    # victims: match their own send counter against what the root logged
    for v in [t for t in telems if t.role == "victim"]:
        mac = mac_of(v.node_id)
        exit_seq, final_seq = v.seq_at_phase_exit(), int(v.seq().iloc[-1])
        hits = []
        for run_id, r in runs.items():
            g = r["arrivals"].df[r["arrivals"].df["src_mac"] == mac]
            if g.empty:
                continue
            base = g[g["phase_id"] == 0]
            last_base = int(base["seq_num"].iloc[-1]) if len(base) else None
            max_seq = int(g["seq_num"].max())
            ok_final = abs(final_seq - max_seq) <= SEQ_TOL
            ok_exit = (exit_seq is not None and last_base is not None
                       and 0 <= exit_seq - last_base <= SEQ_TOL)
            if ok_final and ok_exit:
                hits.append((run_id, f"seq at phase exit {exit_seq} vs root's last baseline "
                                     f"seq {last_base}; final seq {final_seq} vs root max {max_seq}"))
        if len(hits) == 1:
            v.run_id, v.assignment, v.evidence = hits[0][0], "assigned", hits[0][1]
            runs[hits[0][0]]["members"].append(v)
        elif hits:
            v.assignment, v.evidence = "ambiguous", "; ".join(h[0] for h in hits)
        else:
            v.evidence = ("no root arrivals log carries this board's probes with a matching "
                          "sequence range - its root file is missing, or none of its probes "
                          "reached the root")

    # Attackers carry no seq_num, so the only link is a count: probes forwarded in
    # cooldown == probes the root got in cooldown. That count is set by the design
    # (victims x PHASE_COOLDOWN_S at 1 probe/s), so two runs with the same victim
    # count can match the same file, or one run two files. Either way nothing is
    # assigned - a count can support a link but never break a tie.
    claims = defaultdict(list)
    for b in [t for t in telems if t.role == "blackhole"]:
        fwd = b.delta_in_phase("tx_count", 3)
        hits = [rid for rid, r in runs.items()
                if fwd is not None and int((r["arrivals"].df["phase_id"] == 3).sum()) == fwd]
        b.evidence = f"forwarded {fwd} probes in cooldown"
        if len(hits) == 1:
            claims[hits[0]].append(b)
        elif hits:
            b.assignment = "ambiguous"
            b.evidence += f"; equals the cooldown arrivals of {len(hits)} runs: {hits}"
        else:
            b.evidence += "; no root log in these folders agrees"
    for rid, bs in claims.items():
        if len(bs) == 1:
            b = bs[0]
            b.run_id, b.assignment = rid, "assigned (count only)"
            b.evidence += " == root's cooldown arrivals (weak: a design-driven count)"
            runs[rid]["members"].append(b)
        else:
            for b in bs:
                b.assignment = "ambiguous"
                b.evidence += (f"; {len(bs)} attacker files match run {rid} equally - "
                               f"one board can't be in a run twice")
    for c in caps:
        if not c.run_id:
            c.run_id = "UNASSIGNED"
    return runs


# ── Step 3: cleaned rows ────────────────────────────────────────────────────

def segment_of(t_anchor_s, phase, baseline_s):
    seg = np.array([PHASE_NAMES.get(int(p), "unknown") for p in phase], dtype=object)
    before = (phase == 0) & (t_anchor_s < -baseline_s)
    seg[before] = "pre_baseline"
    after = (phase == 0) & (t_anchor_s >= 0)   # phase 0 again after leaving it
    seg[after] = "baseline_rebroadcast"
    return seg


def clean_telemetry(c: Capture, baseline_s, location):
    df = c.df
    out = pd.DataFrame({
        "run_id": c.run_id,
        "source_file": c.name,
        "node_id": df["node_id"],
        "mac_address": mac_of(c.node_id),
        "role": df["role"],
        "topology": c.meta.get("topology", ""),
        "attack_type": c.meta.get("attack", ""),
        "location": location,
        "timestamp_us": df["timestamp_us"],
    })
    if c.anchor_ts is not None:
        t = (df["timestamp_us"] - c.anchor_ts) / 1e6
        out["t_anchor_s"] = t.round(3)
        out["segment"] = segment_of(t.to_numpy(), df["phase_id"].to_numpy(), baseline_s)
    else:
        out["t_anchor_s"] = np.nan
        out["segment"] = "no_phase_seen"
    out["phase_id"] = df["phase_id"]
    out["gt_label"] = df["gt_label"]
    out["in_mesh"] = df["layer"] >= 1
    out["layer_reported"] = df["layer"].where(df["layer"] >= 1)
    out["layer_derived"] = np.nan
    pm = df["parent_mac"].where(df["parent_mac"] != ZERO_MAC)
    out["parent_mac"] = pm
    out["parent_node_id"] = pm.map(lambda b: "NODE_" + sta_of_bssid(b).replace(":", ""),
                                   na_action="ignore")
    out["rssi_dbm"] = df["rssi_dbm"].where(df["rssi_dbm"] != 0)
    out["retry_count"] = df["retry_count"]
    out["tx_count"] = df["tx_count"]
    out["probes_count"] = df["probes_count"]
    out["seq_sent"] = (df["probes_count"] + df["retry_count"]) if c.role == "victim" else np.nan
    out["usable"] = (out["run_id"] != "UNASSIGNED") & out["in_mesh"] & \
        out["segment"].isin(["baseline", "attack", "cooldown"])
    return out


def derive_layers(run_rows: pd.DataFrame, topology: str, step_s=1.0):
    """Rebuild the tree at 1 s steps of anchored time from every node's current
    parent link, BFS it, and compare with what each node's stack reported."""
    topo = "partial" if topology.startswith("partial") else topology
    nodes = {n: g.sort_values("t_anchor_s") for n, g in run_rows.groupby("node_id")
             if g["t_anchor_s"].notna().any()}
    if len(nodes) < 2:
        return [], {}
    lo = max(g["t_anchor_s"].min() for g in nodes.values())
    hi = min(g["t_anchor_s"].max() for g in nodes.values())
    snaps, derived = [], {}
    for t in np.arange(np.ceil(lo), np.floor(hi) + step_s, step_s):
        links, reported, idx = {}, {}, {}
        for n, g in nodes.items():
            i = g["t_anchor_s"].searchsorted(t, side="right") - 1
            if i < 0:
                continue
            row = g.iloc[i]
            if not row["in_mesh"]:
                continue
            par = row["parent_node_id"]
            links[n] = par if isinstance(par, str) else None
            reported[n] = int(row["layer_reported"])
            idx[n] = row.name
        if len(links) < 2:
            continue
        graph = tg.build_graph(links)
        status, reason = tg.validate(topo, graph)
        agree = sum(1 for n in graph.layer if reported.get(n) == graph.layer[n])
        snaps.append({"t_anchor_s": t, "nodes": len(links), "status": status,
                      "unresolved_parents": len(graph.unresolved),
                      "max_layer": graph.max_layer,
                      "layers_agree": f"{agree}/{len(graph.layer)}", "reason": reason})
        for n, ly in graph.layer.items():
            derived[idx[n]] = ly
    return snaps, derived


def clean_arrivals(a: Capture, members):
    df = a.df.copy()
    out = pd.DataFrame({
        "run_id": a.run_id, "source_file": a.name, "root_node_id": df["node_id"],
        "root_timestamp_us": df["timestamp_us"],
        "src_mac": df["src_mac"], "src_node_id": "NODE_" + df["src_mac"].str.replace(":", ""),
        "seq_num": df["seq_num"],
        "root_phase_id": df["phase_id"], "root_gt_label": df["gt_label"],
        "probes_received": df["probes_received"],
        "latency_us_raw": df["latency_us"],
    })
    out["rel_latency_us"] = df["latency_us"] - df.groupby("src_mac")["latency_us"].transform("min")
    # the phase the SENDER was in when it sent that seq, from its own counter
    out["sender_segment"] = ""
    for v in members:
        if v.role != "victim":
            continue
        seqs = (v.df["probes_count"] + v.df["retry_count"]).to_numpy()
        segs = v._segments
        mask = out["src_mac"] == mac_of(v.node_id)
        pos = np.searchsorted(seqs, out.loc[mask, "seq_num"].to_numpy(), side="left")
        pos = np.clip(pos, 0, len(segs) - 1)
        out.loc[mask, "sender_segment"] = segs[pos]
    return out


def pdr_table(run_id, a: Capture, members):
    rows = []
    for v in members:
        if v.role != "victim":
            continue
        mac = mac_of(v.node_id)
        got = set(a.df.loc[a.df["src_mac"] == mac, "seq_num"].astype(int))
        seqs = (v.df["probes_count"] + v.df["retry_count"]).to_numpy()
        segs = v._segments
        sent_by_seg = defaultdict(set)
        prev = 0
        for s, seg in zip(seqs, segs):
            for k in range(prev + 1, int(s) + 1):
                sent_by_seg[seg].add(k)
            prev = max(prev, int(s))
        for seg in ("pre_baseline", "baseline", "attack", "cooldown"):
            sent = sent_by_seg.get(seg, set())
            if not sent:
                continue
            dlv = len(sent & got)
            rows.append({"run_id": run_id, "node_id": v.node_id, "segment": seg,
                         "probes_sent": len(sent), "probes_delivered": dlv,
                         "pdr": round(dlv / len(sent), 4)})
    return rows


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--location", default="", help="location tag written into rows")
    args = ap.parse_args()

    baseline_s = mesh_config_seconds("PHASE_BASELINE_S")
    files = sorted(os.path.join(r, f) for d in args.dirs for r, _, fs in os.walk(d)
                   for f in fs if f.endswith(".csv") and f != "run_ledger.csv"
                   and "_archive" not in r and "trimmed" not in r)
    caps = [Capture(p) for p in files]
    runs = assemble_runs(caps)
    for c in caps:
        if c.ok and c.kind == "telem":
            c._segments = clean_telemetry(c, baseline_s, "")["segment"].to_numpy()

    os.makedirs(args.out, exist_ok=True)
    telem = pd.concat([clean_telemetry(c, baseline_s, args.location)
                       for c in caps if c.ok and c.kind == "telem"], ignore_index=True)
    snap_rows = []
    for run_id, g in telem[telem["run_id"] != "UNASSIGNED"].groupby("run_id"):
        snaps, derived = derive_layers(g, g["topology"].iloc[0])
        for s in snaps:
            s["run_id"] = run_id
        snap_rows += snaps
        for i, ly in derived.items():
            telem.at[i, "layer_derived"] = ly
    telem.to_csv(os.path.join(args.out, "clean_telemetry.csv"), index=False)

    arr, pdr = [], []
    for run_id, r in runs.items():
        arr.append(clean_arrivals(r["arrivals"], r["members"]))
        pdr += pdr_table(run_id, r["arrivals"], r["members"])
    if arr:
        pd.concat(arr, ignore_index=True).to_csv(os.path.join(args.out, "clean_arrivals.csv"),
                                                  index=False)
    pd.DataFrame(pdr).to_csv(os.path.join(args.out, "pdr_by_segment.csv"), index=False)
    snaps = pd.DataFrame(snap_rows)
    snaps.to_csv(os.path.join(args.out, "topology_snapshots.csv"), index=False)
    manifest = pd.DataFrame([{
        "source_file": c.name, "source_dir": os.path.dirname(c.path), "kind": c.kind,
        "node_id": getattr(c, "node_id", ""), "role_in_rows": getattr(c, "role", ""),
        "rows": 0 if c.df is None else len(c.df), "run_id": c.run_id,
        "assignment": c.assignment, "evidence": c.evidence, "issues": " | ".join(c.issues),
    } for c in caps])
    manifest.to_csv(os.path.join(args.out, "run_manifest.csv"), index=False)

    # console report
    print(f"Files: {len(caps)}  loaded: {sum(c.ok for c in caps)}  runs: {len(runs)}")
    for run_id, r in runs.items():
        root = r["root"].name if r["root"] else "MISSING"
        print(f"\nRUN {run_id}\n  root telem: {root}")
        for m in r["members"]:
            print(f"  {m.role:9s} {m.node_id}  {m.name}")
        s = snaps[snaps["run_id"] == run_id] if len(snaps) else snaps
        if len(s):
            print(f"  topology snapshots: {len(s)}  "
                  f"{s['status'].value_counts().to_dict()}  max layer {int(s['max_layer'].max())}")
    print("\nNOT IN ANY RUN:")
    for c in caps:
        if c.run_id == "UNASSIGNED":
            print(f"  [{c.assignment}] {c.name}: {c.evidence or '; '.join(c.issues)}")
    print("\nFILE ISSUES:")
    for c in caps:
        for i in c.issues:
            print(f"  {c.name}: {i}")
    if pdr:
        print("\nPDR BY SEGMENT (joined on seq_num):")
        print(pd.DataFrame(pdr).to_string(index=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
