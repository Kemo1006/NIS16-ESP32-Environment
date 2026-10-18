#!/usr/bin/env python3
"""
redo_list.py - Which captured runs must be REDONE, and why (oct. 16 2026).

The campaign board (inventory_cells.py --board) only knows whether a capture is
COMPLETE. This answers the next question: of what we HAVE, what has to be
captured again before the numbers are final - with every reason traced to its
evidence, so nobody redoes a run on a hunch or skips one that is broken.

EVIDENCE, per live cell (datasets/exports/<attack>/<topology>/<location>/<scenario>):
  capture    inventory_cells.judge(): root/arrivals present, >= MIN_CHILDREN
             boards, every board >= 95 % sample coverage (M4/M5 criteria).
  topology   verify_topology.py's own rules on the raw CSVs (oct. 17 2026):
             wrong shape / cycle / boards not attached -> REDO; a partial
             match or re-routing during the baseline -> CHECK.
  verifier   tools/verify_attack.py on the cell's feature_table.csv: the 3-sigma
             signature + setup checks (attack cells only).
  analysis   feature table missing, or older than the capture.
  log        the NEWEST block about the cell in docs/dataset-verification.md.
  checklist  open D-rows in THESIS-UPDATE-CHECKLIST.md naming the cell.

NEWER EVIDENCE WINS. A log block or D-row that said "recapture" but is OLDER than
the cell's latest capture is reported as "re-verify, then close it", not REDO:
the recapture may already have fixed it (e.g. a D-row written on another
laptop before the redo was imported here).

SEVERITY: REDO (must, before the numbers are final) > CHECK (decide: redo or
footnote) > OK. Off-plan cells (not in tools/campaign_plan.json) are counted but
never listed as REDO - the campaign does not need them.

Usage:  python tools/redo_list.py              coloured terminal list
        python tools/redo_list.py --all        also list the OK cells
        python tools/redo_list.py --json PATH  machine-readable copy
        python tools/redo_list.py --no-color
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import re
import sys
from datetime import datetime

_THIS = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_THIS)
sys.path.insert(0, _THIS)
import inventory_cells as inv  # noqa: E402

EXPORTS = os.path.join(_REPO, "datasets", "exports")
ANALYSIS = os.path.join(_REPO, "datasets", "analysis")
VLOG = os.path.join(_REPO, "docs", "dataset-verification.md")
CHECKLIST = os.path.join(_REPO, "docs", "deviations-limitations", "THESIS-UPDATE-CHECKLIST.md")

REDO, CHECK, OK = 2, 1, 0
LOG_BLOCKS = []   # verification numbers found in THIS laptop's log
SEV_WORD = {REDO: "REDO ", CHECK: "CHECK", OK: "OK   "}
ATTACKS = ("blackhole", "wormhole", "baseline")
W = 96   # report width


# ── evidence sources ─────────────────────────────────────────────────────────
def _parse_date(text):
    """Date AND time of a log header ('Oct 14, 2026 · 2:27 PM'). A same-day
    recapture must count as newer than the block that asked for it, so the
    time matters; a header without one is taken as the END of that day (the
    conservative side: an unknown-time block is never treated as older)."""
    m = re.search(r"([A-Z][a-z]{2})[a-z]*\.? (\d{1,2}),? (\d{4})", text)
    if not m:
        return None
    try:
        d = datetime.strptime(f"{m.group(1)} {m.group(2)} {m.group(3)}", "%b %d %Y")
    except ValueError:
        return None
    t = re.search(r"(\d{1,2}):(\d{2})\s*([AP]M)", text[m.end():m.end() + 30])
    if t:
        h = int(t.group(1)) % 12 + (12 if t.group(3) == "PM" else 0)
        return d.replace(hour=h, minute=int(t.group(2)))
    return d.replace(hour=23, minute=59)


_EMOJI = re.compile("[✅❌⚠️🌀-🫿]")


def _clean(text, n):
    """Plain, one-line, emoji-free (PS 5.1 consoles), cut at a word boundary."""
    import textwrap
    t = _EMOJI.sub("", re.sub(r"\*\*", "", text))
    return textwrap.shorten(" ".join(t.split()), width=n, placeholder=" ...")


def _cell_from_tokens(tokens):
    """('wormhole','tree','DLSU_Library','stationary') from a ' · '-split header."""
    for i, t in enumerate(tokens):
        if t.strip().lower() in ATTACKS and i + 3 < len(tokens):
            rest = [x.strip().split()[0] if x.strip() else "" for x in tokens[i + 1:i + 4]]
            return (t.strip().lower(), *rest)
    return None


def load_vlog():
    """{cell: (block_no, date, verdict_text)} - newest block per cell (file is newest-first)."""
    out, dates = {}, {}
    if not os.path.isfile(VLOG):
        return out, dates
    text = open(VLOG, encoding="utf-8").read()
    blocks = re.split(r"\n(?=## \S* ?VERIFICATION #)", text)
    for b in blocks:
        m = re.match(r"## \S* ?VERIFICATION #(\d+) — (.+)", b)
        if not m:
            continue
        no, head = int(m.group(1)), m.group(2)
        date = _parse_date(head)
        dates[no] = date
        cell = _cell_from_tokens(head.split(" · "))
        if cell is None:
            # "— Oct 16, 2026 · ~3:15 PM — WORMHOLE ... · tree · DLSU_Library · stationary"
            parts = head.split(" — ")
            cell = _cell_from_tokens(" · ".join(parts[-1:]).split(" · "))
            if cell is None:
                tail = parts[-1].split(" · ")
                words = [w.lower() for w in re.findall(r"[A-Za-z_]+", parts[-1])]
                atk = next((a for a in ATTACKS if a in words), None)
                cell = (atk, *[x.strip().split()[0] for x in tail[-3:]]) if atk and len(tail) >= 3 else None
        v = re.search(r"\*\*Verdict[^*]*\*\*[^\n]*|\*\*Verdict:?(.*)", b)
        verdict = v.group(0) if v else ""
        verdict = re.sub(r"\*\*", "", verdict).replace("Verdict:", "").strip()
        if cell and cell not in out:
            out[cell] = (no, date, verdict)
    return out, dates


def load_drows(vdates):
    """{cell: [(id, what, why, source_date)]} for OPEN D-rows that name one cell."""
    out = {}
    if not os.path.isfile(CHECKLIST):
        return out
    for line in open(CHECKLIST, encoding="utf-8"):
        m = re.match(r"\| (D\d+) \| ⬜ \| (.*?) \| (.*?) \| (.*?) \|\s*$", line)
        if not m:
            continue
        did, what, why, src = m.groups()
        c = re.search(r"(blackhole|wormhole|baseline)/(\w+)/(\w+)/(\w+)", what)
        if not c:
            continue
        nums = [int(n) for n in re.findall(r"#(\d+)", src)]
        sdate = max((vdates[n] for n in nums if vdates.get(n)), default=None)
        out.setdefault(c.groups(), []).append((did, re.sub(r"\*\*", "", what), why, sdate))
    return out


def run_verifier(ft, attack):
    """(verdict_word, first FAIL text, [data-gap WARN texts]) or None."""
    try:
        import pandas as pd
        import verify_attack as va
        import attack_checks as ac
        df = pd.read_csv(ft, low_memory=False)
        if attack in ("baseline", "none"):
            # a benign capture: shown normal by verify_benign (oct. 19 2026)
            with contextlib.redirect_stdout(io.StringIO()):
                benign, conclusive = va.verify_benign(df)
            b = va._LAST_BENIGN[0]
            if b["word"] == "BENIGN CONFIRMED":
                tag = "major: " if b["major"] else "minor: "
                return ("CONFIRMED " + b["grade"], "", [tag + g for g in b["gaps"]])
            return ("INCONCLUSIVE" if not conclusive else "NOT CONFIRMED", "; ".join(b["why"][:2]), [])
        with contextlib.redirect_stdout(io.StringIO()):
            confirmed, conclusive = va.verify(df, attack, 3.0)
        # the verifier's own issues (incl. its re-test) - the same footnotes as the report
        issues = list(getattr(va, "_LAST_ISSUES", [[]])[0]) or ac.setup_issues(df, attack)
    except Exception as e:          # never let one broken table stop the list
        return ("ERROR", f"verifier could not run: {e}", [])
    fails = [i.text for i in issues if i.level == ac.FAIL]
    gaps = [i.text for i in issues if i.level == ac.WARN]
    if va._LAST_SETUP_INVALID[0]:
        return ("SETUP INVALID", fails[0] if fails else "", gaps)
    if confirmed:
        # oct. 19 2026: the grade + its short footnotes (verify_attack._confidence) -
        # the notes panel shows ONE line per run, not every raw warning
        try:
            grade, major_, minor_, notes_, _ = va._confidence(True, False, True, issues)
            # tagged so the three kinds are counted apart
            notes = (["major: " + g for g in major_] + ["minor: " + g for g in minor_]
                     + ["note: " + n for n in notes_ if not n.startswith(("the re-test on the part BEFORE", "impact check:"))])
        except Exception:
            grade, notes = "", []
        return ("CONFIRMED " + grade if grade else "CONFIRMED", "", notes if grade else gaps)
    return ("INCONCLUSIVE" if not conclusive else "NOT CONFIRMED", fails[0] if fails else "", gaps)


def topology_evidence(paths, topology):
    """[(severity, text)] from verify_topology.py's rules on the raw CSVs."""
    try:
        import verify_topology as vt
        import topology_graph as tg
    except Exception as e:
        return [(CHECK, f"topology check could not run: {e}")]
    expect = {"partial_mesh": "partial"}.get(topology, topology)
    if expect not in vt.TOPOLOGIES:
        return []
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            nodes = vt.load_files(paths)
            graph, union, _unres = vt.build_graph(nodes)
            status, reason = tg.validate(expect, graph, union)
    except Exception as e:
        return [(CHECK, f"topology check could not run: {e}")]
    out = []
    if graph.cycle:
        out.append((REDO, "parent links form a CYCLE - no valid mesh structure"))
    elif status == tg.FAIL:
        out.append((REDO, f"structure is NOT {expect}: {reason}"))
    elif status == tg.WARN:
        out.append((CHECK, f"structure only partly {expect}: {reason}"))
    if graph.detached and not graph.cycle:
        out.append((REDO if status == tg.FAIL else CHECK,
                    f"{len(graph.detached)} board(s) never attached to the root"))
    moved = sorted(nid[-4:] for nid, n in nodes.items()
                   if n.baseline_parent_switches or n.baseline_layer_changes)
    if moved:
        out.append((CHECK, "re-routed DURING THE BASELINE (parent/layer changed): "
                    + ", ".join(moved) + " - the normal phase is not one stable mesh"))
    return [(sev, _short_board(t)) for sev, t in out]


# ── per-cell judgement ───────────────────────────────────────────────────────
def _short_board(text):
    return re.sub(r"NODE_[0-9A-F]{8}([0-9A-F]{4})", r"\1", text)


def assess(cell, runs, planned, vlog, drows):
    attack, topo, loc, scn = cell
    latest = max((r for r in runs), key=lambda r: r["when"] or datetime.min)
    when = latest["when"]
    reasons = []   # (severity, text, evidence, fix)

    def add(sev, text, ev, fix=""):
        reasons.append((sev, text, ev, fix))

    if latest["verdict"] != "COMPLETE":
        low = []
        for path, _g in latest["run"]["telem"]:
            m = inv._read_meta(path, inv.DEFAULT_SAMPLE_INTERVAL_MS)
            if m and m["rows"] and m["coverage"] < inv.COVERAGE_FLOOR:
                name = re.split(r"_(?:linear|tree|star|partial|partial_mesh)_",
                                os.path.basename(path))[0]
                low.append(f"{name} {m['coverage']:.0%}")
        text = "capture incomplete: " + _short_board(latest["reasons"])
        if low:
            text += " - boards: " + ", ".join(low)
        add(REDO, text, "capture",
            "recapture; check every board's SD card before leaving the site")

    for sev, text in topology_evidence([p for p, _g in latest["run"]["telem"]], topo):
        add(sev, text, "topology",
            "re-place the boards (wait for the root's topology table to show the right shape, "
            "then type START) and recapture" if sev == REDO else
            "usable with a footnote describing the structure - or recapture")

    ft = os.path.join(ANALYSIS, attack, topo, loc, scn, "feature_table.csv")
    if latest["analysis"] == "missing":
        add(CHECK, "captured but never analysed", "analysis", "run analyze.ps1 for this cell")
    elif latest["analysis"] == "stale":
        add(CHECK, "analysis is older than the capture", "analysis", "re-run analyze.ps1")

    if os.path.isfile(ft):
        v = run_verifier(ft, attack)
        word, fail, gaps = v
        if word == "SETUP INVALID":
            add(REDO, "signature moved but the attack did not run as designed: "
                + _short_board(fail), "verifier", "fix the setup, then recapture")
        elif word in ("NOT CONFIRMED", "INCONCLUSIVE") and attack == "baseline":
            add(REDO, f"benign {word.lower()}: " + (fail or "too little data"), "verifier",
                "not a clean normal reference - recapture the benign run (check load / placement first)")
        elif word in ("NOT CONFIRMED", "INCONCLUSIVE"):
            add(REDO, f"attack {word.lower()}" + (f": {_short_board(fail)}" if fail else
                " - no primary signature reached 3-sigma"), "verifier",
                "check the attacker build / placement, then recapture")
        elif word == "ERROR":
            add(CHECK, fail, "verifier", "re-run analyze.ps1, then the verifier")
        if word.startswith("CONFIRMED "):
            grade = word.split(" ", 1)[1]
            dmaj = [g[len("major: "):] for g in gaps if g.startswith("major: ")]
            dmin = [g[len("minor: "):] for g in gaps if g.startswith("minor: ")]
            dnote = [g[len("note: "):] for g in gaps if g.startswith("note: ")]
            if grade == "MAJOR GAPS":
                # the attack is visible but data the result relies on is missing: orange
                # RECAPTURE REQUIRED ('verifier-data' = not the verifier rejecting the attack)
                add(REDO, "CONFIRMED - MAJOR GAPS: " + "; ".join(dmaj)
                    + (" | minor: " + "; ".join(dmin) if dmin else "") + (" | notes: " + "; ".join(dnote) if dnote else ""),
                    "verifier-data", "recapture required: data the result relies on is missing")
            elif grade == "MINOR GAPS":
                # data missing, but not data the result needs (impact check passed): yellow
                # DONE - RECAPTURE ADVISED - usable with the gaps as footnotes
                add(CHECK, f"CONFIRMED - MINOR GAPS ({len(dmin)} minor gap{'' if len(dmin) == 1 else 's'}, result not affected): "
                    + "; ".join(dmin) + (" | notes: " + "; ".join(dnote) if dnote else ""), "verifier",
                    "recapture advised (optional): usable as is, the gaps are footnotes")
            elif grade == "GOOD":
                # nothing missing - the notes are for the report, nothing to do
                add(OK, f"CONFIRMED - GOOD ({len(dnote)} note{'' if len(dnote) == 1 else 's'} for the report): "
                    + "; ".join(dnote), "verifier")
            gaps = []
        for g in gaps:
            text = _short_board(g)
            if "no attack-window telemetry" in g:
                text = text.split(" (")[0]
                fix = "decide: recapture for a complete cell, or footnote the missing boards"
            elif "changed parent" in g:
                fix = "footnote the re-parenting (or recapture if it is the attacker / a tunnel end)"
            else:
                fix = "read it in the verifier report; footnote or recapture"
            add(CHECK, text, "verifier", fix)

    if cell in vlog:
        no, date, verdict = vlog[cell]
        # a ✅ verdict may still MENTION a recapture ("the 3:02 PM recapture fixes ...")
        good = verdict.lstrip().startswith("✅")
        bad = not good and re.search(r"❌|NOT USABLE|RECAPTURE|RE-CAPTURE", verdict, re.I)
        meh = not good and re.search(r"⚠️|DEGRADED|caveat|PARTIAL", verdict, re.I)
        newer = bool(when and date and when > date)
        short = _clean(verdict, 170)
        if bad and not newer:
            add(REDO, short, f"verification #{no}", "see the block in docs/dataset-verification.md")
        elif bad and newer:
            add(CHECK, f"verification #{no} said redo, but a newer capture exists "
                       f"({when:%b %d %H:%M}) - re-verify it AND log a new block in docs/dataset-verification.md "
                       f"(the GUI Verify button checks but does not log - ask Claude to verify it)",
                f"verification #{no}")
        elif meh and not newer:
            add(CHECK, short, f"verification #{no}", "usable with a footnote - or redo")

    logged_ok = False
    if cell in vlog:
        _no, _date, _verdict = vlog[cell]
        logged_ok = bool(_date and when and _date >= when.replace(hour=0, minute=0, second=0, microsecond=0)
                         and _verdict.lstrip().startswith("✅"))
    for did, what, why, sdate in drows.get(cell, []):
        newer = bool(when and sdate and when > sdate)
        if newer and logged_ok:
            add(CHECK, f"{did} (an old recapture request) is DONE - the newer capture was verified ✅ "
                       f"(verification #{vlog[cell][0]}). Tick {did} in THESIS-UPDATE-CHECKLIST.md", did)
        elif newer:
            add(CHECK, f"{did} asks for a recapture, but a newer capture exists ({when:%b %d %H:%M}) - "
                       f"re-verify, then tick {did} in THESIS-UPDATE-CHECKLIST.md (the Verify button does not tick it)", did)
        else:
            add(REDO, f"{did}: " + _clean(why, 170), did, _clean(what, 120))

    sev = max([r[0] for r in reasons], default=OK)
    return {"attack": attack, "topology": topo, "location": loc, "scenario": scn,
            "planned": planned, "severity": sev, "when": when, "reasons": reasons,
            "logged": cell in vlog}


def collect(only=None):
    """only: a set of (attack, topology, location, scenario) - assess just those
    cells (the GUI re-checks only what changed since its last full list)."""
    sample = inv.DEFAULT_SAMPLE_INTERVAL_MS
    runs = inv.scan(EXPORTS, "live", sample)
    rows = []
    for key in sorted(runs):
        source, attack, topo, loc, scn, rep = key
        # oct. 19 2026: judge ONLY the asked cells - judge() + analysis_status() read every
        # file of a run, which for all 57 cells was ~11 s of a one-cell re-check
        if only is not None and (attack, topo, loc or "-", inv.canon_scenario(scn or "-")) not in only:
            continue
        verdict, reasons, stats = inv.judge(runs[key], sample)
        rows.append({"attack": attack, "topology": topo, "location": loc or "-",
                     "scenario": scn or "-", "repeat": rep, "verdict": verdict,
                     "reasons": "; ".join(reasons), "when": stats["when"],
                     "analysis": inv.analysis_status(runs[key], ANALYSIS),
                     "run": runs[key]})
    assign = inv.load_plan(False, None)
    planned = set()
    for (loc, topo, atk), scns in assign.items():
        for s in scns:
            planned.add((atk, topo, loc, inv.canon_scenario(s)))
        if atk == inv.PLAN_ATTACKS[0]:
            for s in inv.benign_for(assign, loc, topo):
                planned.add(("baseline", topo, loc, inv.canon_scenario(s)))
    vlog, vdates = load_vlog()
    drows = load_drows(vdates)
    global LOG_BLOCKS
    LOG_BLOCKS = sorted(vdates)
    cells = {}
    for r in rows:
        cells.setdefault((r["attack"], r["topology"], r["location"],
                          inv.canon_scenario(r["scenario"])), []).append(r)
    out = []
    keys = sorted(c for c in cells if only is None or c in only)
    for i, cell in enumerate(keys, 1):
        print(f"\r  checking {i}/{len(keys)} cells ...", end="", file=sys.stderr, flush=True)
        out.append(assess(cell, cells[cell], cell in planned, vlog, drows))
    print("\r" + " " * 40 + "\r", end="", file=sys.stderr, flush=True)
    return out


# ── rendering ────────────────────────────────────────────────────────────────
def _wrap(text, first, rest, width=W):
    import textwrap
    return textwrap.fill(" ".join(text.split()), width=width, initial_indent=first,
                         subsequent_indent=rest, break_on_hyphens=False,
                         break_long_words=False)


SHARED_MIN = 4   # a CHECK reason seen in this many cells is reported once, at the top


def _shape(text):
    """A reason with its numbers and board ids blanked, so the same finding in
    different cells compares equal ('8 nodes ... depth 4' == '9 nodes ... depth 5')."""
    t = re.sub(r"\b[0-9A-F]{4}\b", "#", text)
    t = re.sub(r"\d+(\.\d+)?", "#", t)
    return re.sub(r"^(structure only partly \w+|topology during the attack): ", "", t)


def split_shared(items):
    """Move repeated CHECK reasons out of the cells into a shared list.
    Returns {shape: (example text, [cells])}; cells keep only their own reasons
    and get their severity recomputed."""
    count = {}
    for x in items:
        if not x["planned"]:
            continue
        for sev, text, ev, _f in x["reasons"]:
            if sev == CHECK and ev in ("topology", "verifier"):
                count.setdefault(_shape(text), set()).add(id(x))
    shared_shapes = {k for k, v in count.items() if len(v) >= SHARED_MIN}
    shared = {}
    for x in items:
        keep = []
        for r in x["reasons"]:
            sev, text, ev, _f = r
            k = _shape(text)
            if sev == CHECK and ev in ("topology", "verifier") and k in shared_shapes:
                ex, cells = shared.setdefault(k, (text, []))
                label = (x["location"], f"{x['attack']}/{x['topology']}", x["scenario"])
                if label not in cells:
                    cells.append(label)
            else:
                keep.append(r)
        x["reasons"] = keep
        x["severity"] = max([r[0] for r in keep], default=OK)
    return shared


def render(items, show_all, color):
    C = inv._ansi(color)
    red = "\033[31;1m" if color else ""
    col = {REDO: red, CHECK: C["y"], OK: C["g"]}
    badge = {REDO: " REDO  ", CHECK: " CHECK ", OK: " OK    "}
    shared = split_shared(items)
    planned = [x for x in items if x["planned"]]
    off = [x for x in items if not x["planned"]]
    n = {s_: sum(1 for x in planned if x["severity"] == s_) for s_ in (REDO, CHECK, OK)}
    unlogged = [x for x in planned if x["severity"] == OK and not x["logged"]]
    rule = "  " + "=" * (W - 2)
    thin = "  " + "-" * (W - 2)

    print()
    print(rule)
    head = "  REDO LIST"
    stamp = f"live data  |  {datetime.now():%b %d, %H:%M}"
    print(f"{C['b']}{head}{C['x']}{' ' * (W - len(head) - len(stamp))}{C['d']}{stamp}{C['x']}")
    print(rule)
    print(f"  {col[REDO]}{n[REDO]:>4}  REDO {C['x']}   capture again before the numbers are final")
    print(f"  {col[CHECK]}{n[CHECK]:>4}  CHECK{C['x']}   decide: recapture, or keep it with a footnote")
    print(f"  {col[OK]}{n[OK]:>4}  OK   {C['x']}   verified and complete"
          + (f"   {C['d']}({len(unlogged)} never checked by a person){C['x']}" if unlogged else ""))
    if off:
        print(f"  {C['d']}{len(off):>4}  off-plan cells - not in campaign_plan.json, never needed{C['x']}")

    # trip plan: one line, locations with the most REDOs first
    todo = {}
    for x in planned:
        if x["severity"] > OK:
            t = todo.setdefault(x["location"], [0, 0])
            t[0 if x["severity"] == REDO else 1] += 1
    if todo:
        print(thin)
        legs = []
        for loc in sorted(todo, key=lambda k: (-todo[k][0], -todo[k][1])):
            r, c = todo[loc]
            bits = ([f"{r} redo"] if r else []) + ([f"{c} check"] if c else [])
            legs.append(f"{loc} ({', '.join(bits)})")
        print(_wrap("TRIPS  " + "  ->  ".join(legs), "  ", "         "))
    print(thin)
    notes = ["Live data only (datasets/exports + datasets/analysis); archive/ is ignored."]
    if LOG_BLOCKS:
        gaps = sorted(set(range(1, LOG_BLOCKS[-1] + 1)) - set(LOG_BLOCKS))
        note = f"This laptop's verification log: #{LOG_BLOCKS[0]}-#{LOG_BLOCKS[-1]}"
        if gaps:
            note += (f", but #{gaps[0]}-#{gaps[-1]} are missing here - git pull first, "
                     f"or their verdicts are not counted")
        notes.append(note + ".")
    for t in notes:
        print(C["d"] + _wrap(t, "  ", "  ") + C["x"])
    if shared:
        print()
        print(f"  {C['y']}{C['b']}SHARED FINDINGS{C['x']}  {C['d']}one issue seen in many cells - "
              f"decide it ONCE for the whole team, not per cell{C['x']}")
        for _k, (example, cells) in sorted(shared.items(), key=lambda kv: -len(kv[1][1])):
            print(_wrap(f"{C['y']}~{C['x']} {example}", "    ", "      ", width=W))
            kinds = sorted({c[1] for c in cells})
            print(f"      {C['d']}in {len(cells)} cell(s), {' + '.join(kinds)}:{C['x']}")
            for loc in inv.PLAN_LOCATIONS:
                scn = [c[2] if len(kinds) == 1 else f"{c[1]}/{c[2]}" for c in cells if c[0] == loc]
                if scn:
                    print(f"      {C['d']}{loc:<14}{', '.join(sorted(scn))}{C['x']}")

    def sev_order(x):
        topo_i = (inv.PLAN_TOPOLOGIES.index(x["topology"])
                  if x["topology"] in inv.PLAN_TOPOLOGIES else 9)
        return (-x["severity"], topo_i, x["attack"], x["scenario"])

    for loc in inv.PLAN_LOCATIONS:
        group = sorted([x for x in planned if x["location"] == loc
                        and (show_all or x["severity"] > OK)], key=sev_order)
        if not group:
            continue
        print()
        print(f"  {C['c']}{C['b']}{loc}{C['x']} {C['d']}" + "." * (W - 4 - len(loc)) + C["x"])
        for x in group:
            sv = x["severity"]
            what = f"{x['attack']}  /  {x['topology']}  /  {x['scenario']}"
            when = f"captured {x['when']:%b %d}" if x["when"] else ""
            print()
            print(f"  {col[sv]}{badge[sv]}{C['x']} {C['b']}{what}{C['x']}"
                  f"{' ' * max(2, W - 12 - len(what) - len(when))}{C['d']}{when}{C['x']}")
            seen, first = set(), True
            for rsv, text, ev, fix in sorted(x["reasons"], key=lambda r: -r[0]):
                if (text, ev) in seen:
                    continue
                seen.add((text, ev))
                label = "why " if first else "    "
                first = False
                mark = f"{col[rsv]}{'!' if rsv == REDO else '~'}{C['x']}"
                body = _wrap(f"{text}  {C['d']}[{ev}]{C['x']}", "", "", width=W - 16)
                lines = body.split("\n")
                print(f"          {C['d']}{label}{C['x']}{mark} {lines[0]}")
                for ln in lines[1:]:
                    print(f"                 {ln}")
            prio = {"capture": 1, "topology": 2, "verifier": 3, "analysis": 4}
            def fix_rank(r):
                ev = r[2]
                return (-r[0], 0 if re.match(r"D\d+$", ev) else prio.get(ev, 5))
            fixes = [f for rsv, _t, _e, f in sorted(x["reasons"], key=fix_rank)
                     if f and rsv == sv and not f.startswith("see the block")]
            if fixes:
                do = _wrap(fixes[0], "", "", width=W - 16).split("\n")
                print(f"          {C['m']}do  {C['x']}  {do[0]}")
                for ln in do[1:]:
                    print(f"                 {ln}")
    if n[REDO] + n[CHECK] == 0:
        print()
        print(f"  {C['g']}Nothing to redo - every captured planned cell is verified and complete.{C['x']}")
    print()
    print(thin)
    print(f"  {C['d']}!  must fix          [capture]   completeness (all boards, >= 95 % samples)"
          f"{C['x']}")
    print(f"  {C['d']}~  judgement call    [topology]  structure rebuilt from the raw CSVs{C['x']}")
    print(f"  {C['d']}                     [verifier]  verify_attack.py, run now{C['x']}")
    print(f"  {C['d']}                     [verification #n]  docs/dataset-verification.md"
          f"   [Dn]  thesis checklist{C['x']}")
    print(C["d"] + "  Not captured yet is the campaign board's job (Campaign -> [1] all sessions)."
          + C["x"])
    print()


def main():
    # verdicts quote the verification log (arrows, emoji); a cp1252 console
    # crashed on them before the JSON was written (oct. 17 2026)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description="Which captured runs must be redone, and why.")
    ap.add_argument("--all", action="store_true", help="Also list the cells that are OK.")
    ap.add_argument("--json", metavar="PATH", help="Also write the list as JSON.")
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--only", metavar="CELLS", default=None,
                    help="attack/topology/location/scenario[,...] - assess only these cells "
                         "(the rest of the list is not printed or written)")
    args = ap.parse_args()
    color = not args.no_color and sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    if color and os.name == "nt":
        os.system("")
    only = None
    if args.only:
        only = set()
        for c in args.only.split(","):
            p = [x.strip() for x in c.replace("\\", "/").split("/")]
            if len(p) == 4:
                only.add((p[0], p[1], p[2], inv.canon_scenario(p[3])))
    items = collect(only)
    render(items, args.all, color)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump([dict(x, severity=SEV_WORD[x["severity"]].strip(),
                            reasons=[{"severity": SEV_WORD[s].strip(), "text": t,
                                      "evidence": e, "fix": f} for s, t, e, f in x["reasons"]])
                       for x in items], fh, indent=1, default=str)
        print(f"  wrote {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
