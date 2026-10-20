#!/usr/bin/env python3
"""
missing_boards.py - a MISSING board is judged by its ROLE in the attack, not counted
(oct. 20 2026, user: "evaluate the importance of the missing board before deciding
whether the run needs to be repeated ... based on the board's actual role in the
topology and the evidence required to validate the attack").

A board is MISSING when the ROOT heard it during the run (>= 100 probe arrivals in
phases 0-3, the run_summary.py rule) but this capture has no file for it (its SD card
recorded nothing / it was not imported), or when its file has no attack windows.

STEP 1 - WHERE did it sit? Structure only, never its delivery (fairness rule 1 of D-23:
placing a missing board by "its probes still arrived" would turn a victim the attack
failed to cut off into a 'bystander' and drop it - the outcome deciding the evidence).
Sources, best first:
  own file   its windows before it went silent (baseline edge), via the same exposure
             walk the verifier uses (attack_checks.exposure_timeline)
  root log   the root's PARENT/CHILD STRUCTURE table in datasets/run_logs/<cell>/ (every
             board's parent, from its heartbeats), attack-phase rows first
  data       boards in the table that name it as their parent; if the ATTACKER is one of
             them, it sat upstream of the attacker
  (none)     position unknown

STEP 2 - what does the attack's evidence need from that position? (blackhole)
  attacker            its own counters ARE the primary ForwardingRatio            CRITICAL
  victim (below the   one witness of the PDR collapse. CRITICAL when no other victim keeps
   attacker)          >= MIN_VICTIM_EVIDENCE_S traceable seconds (nothing left to show the
                      collapse), else YELLOW: the attacker's counters + the other victims
                      establish the attack; the missing one is not counted either way
  bystander (another  the CONTROL group (Karlof & Wagner 2003: only traffic routed through
   lineage from root) the attacker is lost). YELLOW while another bystander keeps >= 60 s of
                      attack windows; it is in no primary feature and in no baseline the
                      test uses. If it was the LAST bystander: UNDETERMINED - without a
                      control, network-wide loss cannot be ruled out by the data
  upstream relay      sits between the root and the attacker; its own probes are control
   of the attacker    traffic (as a bystander); judged like a bystander
  unknown position    UNDETERMINED: neither accepted nor rejected - investigate (root log,
                      card, teammate's laptop)
  wormhole: a tunnel end is CRITICAL (its own checks fail first); a plain child is YELLOW -
  the signature is B's TunnelIntensity + the ROOT's DuplicateRate, neither uses it.

YELLOW -> MINOR gap (grade MINOR GAPS, Campaign DONE - RECAPTURE ADVISED + footnote)
CRITICAL -> MAJOR gap (MAJOR GAPS, RECAPTURE REQUIRED)
UNDETERMINED -> grade UNDETERMINED, OUTCOME INCONCLUSIVE, Campaign CHECK "INVESTIGATE"

Missing-data basis: a board lost to an SD-card failure is missing for a reason unrelated
to the attack ("missing completely at random", Little & Rubin, Statistical Analysis with
Missing Data, 3rd ed., Wiley 2019) - dropping it costs precision, not validity. A board
lost because it CRASHED under the attack may not be (D9) - that is why a victim is only
YELLOW when other victims still carry the evidence, and why the verdict never counts a
missing board as delivered or as lost.
"""
import glob
import os
import re

import pandas as pd

import attack_checks as ac

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORTS = os.path.join(os.path.dirname(HERE), "datasets", "exports")
HEARD_MIN_ARRIVALS = 100          # the run_summary.py rule: a board that really took part
CONTROL_MIN_S = 60                # a bystander that still counts as a control group
_STRUCT = re.compile(r"MESH_SETUP:\s+H\d\d\s+([0-9A-Fa-f:]{17})\s+(\S+)\s+([0-9A-Fa-f:]{17}|--:--:--:--:--:--)"
                     r"\s+0x([0-9A-Fa-f]{2})")


def _m12(x):
    return re.sub(r"[^0-9A-F]", "", str(x).upper())[-12:]


def _short(m):
    return _m12(m)[-4:]


def _cell(df):
    out = []
    for c in ("attack", "topology", "location", "scenario"):
        v = str(df[c].dropna().iloc[0]) if c in df.columns and df[c].notna().any() else ""
        out.append(v)
    return out


def _root_stamp(df):
    if "source_file" not in df.columns or "node_role" not in df.columns:
        return None
    files = df.loc[df["node_role"].astype(str).str.lower() == "root", "source_file"].dropna().unique()
    st = [ac.stamp_from_name(str(f)) for f in files]
    st = [s for s in st if s]
    return max(st) if st else None


def heard_boards(df, exports=EXPORTS):
    """{mac12: arrivals} of the boards the root heard in phases 0-3 of THIS run's arrivals
    file, or None when no arrivals file can be matched (then only boards with a file that
    went silent can be judged)."""
    cell = _cell(df)
    if any(v in ("", "None", "nan") for v in cell):
        return None
    folder = os.path.join(exports, *cell)
    files = sorted(glob.glob(os.path.join(folder, "*_arrivals.csv")))
    if not files:
        return None
    ref = _root_stamp(df)
    if ref is not None and len(files) > 1:
        def dist(p):
            s = ac.stamp_from_name(os.path.basename(p))
            return abs((s - ref).total_seconds()) if s else 1e12
        files = [min(files, key=dist)]
    heard = {}
    for p in files[-1:]:
        try:
            a = pd.read_csv(p, usecols=["src_mac", "phase_id"], dtype=str, on_bad_lines="skip")
        except Exception:
            return None
        a = a[pd.to_numeric(a["phase_id"], errors="coerce").isin([0, 1, 2, 3])]
        for m, n in a["src_mac"].map(_m12).value_counts().items():
            if n >= HEARD_MIN_ARRIVALS:
                heard[m] = int(n)
    return heard


def root_log_parents(df, logs_root=ac.RUN_LOGS):
    """{mac12: (parent mac12 or None, role)} from the root's PARENT/CHILD STRUCTURE table
    in this capture's run log - attack-phase rows (0x01/0x02) first, else the last rows
    seen. None when no root log of this run was saved."""
    cell = _cell(df)
    ref = _root_stamp(df)
    folder = os.path.join(logs_root, *cell)
    if ref is None or not os.path.isdir(folder):
        return None
    best = None
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".log"):
            continue
        st = ac.stamp_from_name(name, ref.year)
        if not st or not (ref - ac.timedelta(hours=ac.RUN_LOG_WINDOW_H) <= st <= ref + ac.timedelta(minutes=5)):
            continue
        with open(os.path.join(folder, name), "r", encoding="utf-8", errors="replace") as fh:
            text = ac._ANSI.sub("", fh.read())
        if ac._ROOT_SAW.search(text) and (best is None or st > best[0]):
            best = (st, text)
    if not best:
        return None
    attack_rows, last = {}, {}
    for m in _STRUCT.finditer(best[1]):
        node, role, parent, phase = _m12(m.group(1)), m.group(2).lower(), m.group(3), m.group(4).upper()
        par = None if parent.startswith("--") else _m12(parent)
        last[node] = (par, role)
        if phase in ("01", "02"):
            attack_rows.setdefault(node, []).append((par, role))
    out = dict(last)
    for node, rows in attack_rows.items():
        pars = [p for p, _r in rows]
        out[node] = (max(set(pars), key=pars.count), rows[-1][1])
    return out or None


def _data_parents(df):
    """{mac12: parent mac12} - each board's dominant attack-window parent from its own
    file (parent_mac is the parent's SoftAP = its STA MAC + 1)."""
    atk = ac._seg(df, "attack")
    if atk.empty:
        atk = df
    out = {}
    for n, g in atk.dropna(subset=["parent_mac"]).groupby("node_id"):
        p = str(g["parent_mac"].mode().iloc[0])
        if p in ("", "nan", ac._exposure.ZERO_MAC):
            continue
        v = ac._exposure.mac_to_int(p)
        out[_m12(n)] = f"{v - 1:012X}" if v is not None else None
    return out


def _position(m, parents, attackers, roots):
    """victim | bystander | upstream | None, walking `parents` (mac12 -> parent mac12)."""
    for a in attackers:                      # upstream: on the attacker's own path to the root
        cur = a
        for _ in range(16):
            cur = parents.get(cur)
            if cur is None:
                break
            if cur == m:
                return "upstream"
            if cur in roots:
                break
    cur, seen_attacker = m, False
    for _ in range(16):
        if cur not in parents:
            return None
        cur = parents[cur]
        if cur is None:
            return None
        if cur in attackers:
            seen_attacker = True
        if cur in roots:
            return "victim" if seen_attacker else "bystander"
    return None


def assess(df, attack):
    """[attack_checks.Issue] - one WARN per missing board:
    'MISSING BOARD <id> (<position>): YELLOW|CRITICAL|UNDETERMINED - <why> [<source>]'."""
    if attack not in ("blackhole", "wormhole") or not {"node_id", "node_role"} <= set(df.columns):
        return []
    roles = {_m12(n): r for n, r in ac._roles(df).items()}
    present = set(roles)
    roots = {n for n, r in roles.items() if r in ac._exposure.ROOT_ROLES}
    attackers = {n for n, r in roles.items() if r == "blackhole"}
    ends = {n for n, r in roles.items() if r in ac.WORMHOLE_ROLES} if hasattr(ac, "WORMHOLE_ROLES") else \
        {n for n, r in roles.items() if r in ("wormhole_a", "wormhole_b")}
    atk_nodes = {_m12(n) for n in ac._seg(df, "attack")["node_id"].dropna()}
    base_nodes = {_m12(n) for n in ac._seg(df, "baseline")["node_id"].dropna()}
    silent = (base_nodes - atk_nodes) - roots               # a file, but no attack windows
    heard = heard_boards(df)
    nofile = (set(heard) - present - roots) if heard else set()
    missing = sorted(silent | nofile)
    if not missing:
        return []

    out = []
    if attack == "wormhole":
        for m in missing:
            if m in ends:
                continue                                    # wormhole_issues() fails it already
            how = "its file has no attack windows" if m in silent else "the root heard it, but there is no file"
            out.append(ac.Issue(ac.WARN, f"MISSING BOARD {_short(m)} (plain child): YELLOW - {how}; the wormhole's "
                                         f"signature is B's TunnelIntensity + the ROOT's DuplicateRate, neither uses "
                                         f"this board, so it adds no bias - footnote it [role: not a tunnel end]"))
        return out

    # blackhole: what the evidence still has without the missing boards
    tl = ac.exposure_timeline(df, "blackhole")
    vic_s = {_m12(n): sum(1 for _t, c in seq if c == "victim") for n, seq in tl.items()}
    bys_s = {_m12(n): sum(1 for _t, c in seq if c == "bystander") for n, seq in tl.items()}
    base_tl = ac.exposure_timeline(df, "blackhole", "baseline")
    log = root_log_parents(df)
    data_par = _data_parents(df)
    for m in missing:
        who = _short(m)
        how = "its file has no attack windows" if m in silent else "the root heard it, but its SD card / file has no data"
        if m in attackers:
            out.append(ac.Issue(ac.WARN, f"MISSING BOARD {who} (attacker): CRITICAL - {how}; the attacker's own "
                                         f"counters are the primary ForwardingRatio - the attack cannot be verified "
                                         f"without them [role: attacker]"))
            continue
        pos, src = None, ""
        node = next((n for n in base_tl if _m12(n) == m), None)
        if node is not None:
            pos = ac._majority(ac._edge(base_tl[node], "last")) or None
            src = "own file, last 60 s of the baseline"
        if pos is None and log:
            pos = _position(m, {k: v[0] for k, v in log.items()}, attackers, roots)
            src = "root run log (PARENT/CHILD STRUCTURE)" if pos else src
        if pos is None:
            if any(data_par.get(a) == m for a in attackers):
                pos, src = "upstream", "the attacker names it as its parent"
        kids = sorted(_short(k) for k, p in data_par.items() if p == m)
        kid_note = (f"; {len(kids)} board(s) hang under it ({', '.join(kids)}) - their paths are only traceable "
                    f"through it, so their windows without a resolvable path are left out of the test") if kids else ""
        rest_vic = sum(s for n, s in vic_s.items() if n != m)
        controls = [n for n, s in bys_s.items() if n != m and s >= CONTROL_MIN_S]
        if pos is None:
            out.append(ac.Issue(ac.WARN, f"MISSING BOARD {who} (position unknown): UNDETERMINED - {how}, and no "
                                         f"structure source places it (no file, no root run log, no board names it as "
                                         f"parent): it may have been a victim (evidence) or a bystander (control). "
                                         f"Neither accepted nor rejected - INVESTIGATE: get the root's run log or the "
                                         f"board's card{kid_note} [no structure source]"))
        elif pos == "victim":
            if rest_vic >= ac.MIN_VICTIM_EVIDENCE_S:
                out.append(ac.Issue(ac.WARN, f"MISSING BOARD {who} (victim): YELLOW - {how}; it sat behind the attacker, "
                                             f"but the attacker's own counters and {rest_vic} traceable victim-seconds "
                                             f"of the other victims still establish the attack. It is counted neither "
                                             f"as delivered nor as lost (missing at random only if its card failed - "
                                             f"check it did not crash){kid_note} [{src}]"))
            else:
                out.append(ac.Issue(ac.WARN, f"MISSING BOARD {who} (victim): CRITICAL - {how}; it sat behind the "
                                             f"attacker and the other victims keep only {rest_vic} traceable seconds "
                                             f"(< {ac.MIN_VICTIM_EVIDENCE_S}) - the delivery collapse cannot be shown "
                                             f"without it{kid_note} [{src}]"))
        else:   # bystander / upstream relay: the control group
            what = "bystander" if pos == "bystander" else "upstream relay of the attacker"
            if controls:
                out.append(ac.Issue(ac.WARN, f"MISSING BOARD {who} ({what}): YELLOW - {how}; it was NOT behind the "
                                             f"attacker, so it is in no primary feature and in no baseline the test "
                                             f"uses; it served as a control, and {len(controls)} other control board(s) "
                                             f"({', '.join(_short(c) for c in controls)}) still show the loss is specific "
                                             f"to the attacker's path{kid_note} [{src}]"))
            else:
                out.append(ac.Issue(ac.WARN, f"MISSING BOARD {who} ({what}): UNDETERMINED - {how}; it was the LAST "
                                             f"control board (not behind the attacker) - without a control the data "
                                             f"cannot rule out network-wide loss; the attacker's own counters still "
                                             f"point to a blackhole. INVESTIGATE: recapture, or footnote with the "
                                             f"attacker-counter argument{kid_note} [{src}]"))
    return out
