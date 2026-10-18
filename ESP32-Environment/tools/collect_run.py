#!/usr/bin/env python3
"""collect_run.py — pull ONE run's telemetry off every plugged-in child's SD card.

After a capture the children usually still sit on their USB cables. Instead of
importing them one by one (oct. 18 2026: seven boards by hand, and a card whose
location.txt was wrong filed one under G402), this reads each port in turn,
picks the file of THIS run and files it under the run's own folder:

    python tools/collect_run.py --ports COM10,COM11,COM9 --attack wormhole \
        --topology linear --location DLSU_Library --scenario highload --repeat 1 \
        --since "2026-10-18 14:40" [--roster presets/Cal/x.json] [--skip-mac b0cbd8f33218] [--dry-run]
    (scan, copies nothing:  --dry-run --plan-json plan.json ; copy exactly what was ticked:  --pick "COM10=<rel>;COM11=<rel>")

Per board it takes THE clean telemetry file of this attack + topology + location
started at/after --since - and refuses when there are two (a card has no scenario
folder, so it cannot tell a stationary run from a burst one). A file recorded under
another LOCATION is taken only with --allow-other-location (a location.txt left on
the last site) and is then filed under --location. A
board whose file is already in exports (same MAC, same rows) is skipped.

The copy itself is tools/import_sdcard.py --port (unchanged), one port at a
time: never two serial reads at once (the CP210x blue-screen history). Then
run_summary.py prints the run's health card.

Lines for the GUI:  COLLECT: <port> <mac> OK|SKIP|FAIL <text>
                    COLLECT_SUMMARY: ok=<n> skip=<n> fail=<n>
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
EXPORTS = os.path.join(BASE, "datasets", "exports")
TOPO_DIR = {"partial": "partial_mesh"}


def _py():
    return sys.executable or "python"


def _say(port, mac, state, text):
    print(f"COLLECT: {port} {mac or '-'} {state} {text}", flush=True)


def _list(src_args, repeat, scenario, roster):
    a = [_py(), os.path.join(HERE, "import_sdcard.py")] + src_args + ["--repeat", str(repeat), "--scenario", scenario, "--list-json"]
    if roster:
        a += ["--roster", roster]
    p = subprocess.run(a, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=HERE)
    line = next((l for l in reversed(p.stdout.splitlines()) if l.lstrip().startswith("[")), None)
    if p.returncode != 0 or line is None:
        err = (p.stderr.strip().splitlines() or p.stdout.strip().splitlines() or ["no answer"])[-1]
        raise RuntimeError(err)
    return json.loads(line)


def _when(text):
    try:
        return dt.datetime.strptime(str(text)[:19], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


CRASH_ENDS = ("PANIC", "INT_WDT", "TASK_WDT", "WDT")


def _crashed_leaves(files, attack_dir, topology):
    """The card folders where this board CRASHED in this attack + topology (ended_by)."""
    return sorted({f"{f.get('attack')}/{f.get('topology')}/{f.get('location')}" for f in files
                   if f.get("kind") == "telem" and f.get("filed_under") == attack_dir and f.get("topology") == topology
                   and str(f.get("ended_by") or "").upper() in CRASH_ENDS})


def _fetch_crashes(kind, s, leaves, node, run_logs):
    """tools/fetch_crashes.py for one board: copy + decode crashes_<node>.csv (oct. 18 2026)."""
    a = [_py(), os.path.join(HERE, "fetch_crashes.py")] + (["--port", s] if kind == "port" else ["--card", s])
    for lf in leaves:
        a += ["--leaf", lf]
    a += ["--node", node, "--out", run_logs]
    p = subprocess.run(a, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=HERE)
    for line in p.stdout.splitlines():
        if line.strip():
            print("   " + line, flush=True)


def _rows_in(path):
    with open(path, "rb") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def _already(dest_dir, mac, rows, size):
    """An export of THIS card file is already in the run folder: same board and
    the same rows - or, over USB where the card does not report rows, about the
    same size (the GUI Data page's rule). Same board alone is not enough: repeat
    r1 and r2 of a run share the folder."""
    for f in glob.glob(os.path.join(dest_dir, f"*{mac.upper()}*_telem.csv")):
        try:
            if rows is not None:
                if abs(_rows_in(f) - int(rows)) <= 2:
                    return os.path.basename(f)
            elif size and size > 0:
                if abs(os.path.getsize(f) - size) <= 0.03 * size:
                    return os.path.basename(f)
        except OSError:
            continue
    return None


def _size(f):
    """A piece's size for comparing pieces of one run: bytes, else rows x ~80 B."""
    b = f.get("bytes")
    if b is not None and int(b) >= 0:
        return int(b)
    return int(f.get("rows") or 0) * 80


def pick(files, attack, topology, location, since, skip_macs, allow_other_location=False):
    """(file, note) - this run's telemetry on one card - or (None, why).

    Safety net (oct. 18 2026): a card has NO scenario folder (only
    attack/topology/location), so a card holding two runs of the same attack +
    topology (a stationary and a burst one, two days at two sites) is ambiguous.
    Never guess: exactly ONE clean candidate in the window, or nothing. A file
    recorded under ANOTHER location is only taken with allow_other_location (a
    card whose location.txt was left on the last site) - else it is another run."""
    want_atk = "baseline" if attack in ("none", "baseline") else attack
    telem = [f for f in files if f.get("kind") == "telem"]
    if not telem:
        return None, "no telemetry file on this card"
    mac = str(telem[0].get("node", "")).replace("NODE_", "").lower()
    if mac in skip_macs:
        return None, "the root (exported over USB) - skipped"
    cand, other, elsewhere = [], [], []
    for f in telem:
        if f.get("live"):
            other.append("one file is STILL BEING WRITTEN (run not ended)")
            continue
        started = _when(f.get("started"))
        if since and started and started < since:
            continue
        if not (f.get("filed_under") == want_atk and f.get("topology") == topology):
            other.append(f"{f.get('filed_under')}/{f.get('topology')}/{f.get('location')} (another run)")
            continue
        if f.get("location") != location and not allow_other_location:
            elsewhere.append(f"{f.get('location')} ran {f.get('started') or '?'}")
            continue
        cand.append(f)
    clean = [f for f in cand if f.get("clean") is not False]
    aborted = [f for f in cand if f.get("clean") is False]
    crash = [f for f in aborted if str(f.get("ended_by") or "").upper() not in ("", "POWERON")]
    if not clean and crash:
        # oct. 18 2026: no clean file, but the board CRASHED mid-run - its biggest
        # piece holds most of the run (baseline included); take it and say so
        best = max(crash, key=_size)
        return best, (f"the board CRASHED during the run ({best.get('ended_by')}) - took its biggest piece; "
                      f"its data stops at the crash ({len(cand)} piece(s) on the card)")
    if not clean:
        why = "no clean file of this run in the time window"
        if cand:
            why += f" ({len(cand)} aborted piece(s) - import those from the Data page, 'show aborted')"
        if elsewhere:
            why += (f" - this attack + topology was recorded at ANOTHER location ({'; '.join(elsewhere)}); "
                    f"tick 'cards may have recorded the wrong location' only if this run really was at {location}")
        elif other and not cand:
            why += " - found only: " + "; ".join(sorted(set(other)))
        return None, why
    if len(clean) > 1:
        when = "; ".join(f"{f.get('location')} ran {f.get('started') or '?'}" for f in sorted(clean, key=lambda f: str(f.get("started") or "")))
        return None, (f"{len(clean)} runs of this attack + topology in the time window ({when}) - the card cannot "
                      f"say which scenario each was. Narrow the time window, or pick the file in Data > Import")
    best = clean[0]
    # oct. 18 2026 (F4:18): a board that CRASHED mid-run and rebooted closes only its
    # post-crash TAIL cleanly (cooldown, no baseline); the run itself is in the bigger,
    # crash-ended piece. A clean file under half the size of a crash-ended piece of the
    # same run is that tail - take the big piece instead and say why.
    big = max(crash, key=_size) if crash else None
    if big is not None and _size(best) < 0.5 * _size(big):
        note = (f"the board CRASHED during the run ({big.get('ended_by')}) - took the crash-ended piece "
                f"({_size(big):,} B) over the clean post-crash tail ({_size(best):,} B); its data stops at the crash")
        if big.get("location") != location:
            note += f"; card recorded {big.get('location')}, filed under {location}"
        return big, note
    note = "" if best.get("location") == location else f"card recorded {best.get('location')}, filed under {location}"
    return best, note


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description="Collect one run's telemetry from every plugged-in child's SD card.")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--ports", help="COM10,COM11,... (cards still in the boards)")
    src.add_argument("--cards", help="card folders (pulled cards in readers) - also for testing")
    ap.add_argument("--attack", required=True)
    ap.add_argument("--topology", required=True)
    ap.add_argument("--location", required=True)
    ap.add_argument("--scenario", default="stationary")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--since", default=None, help="'YYYY-MM-DD HH:MM' - ignore files started before this")
    ap.add_argument("--allow-other-location", action="store_true",
                    help="also take a file the card recorded under another location (location.txt left on the last site)")
    ap.add_argument("--pick", default=None,
                    help="'COM10=<rel>;COM11=<rel>' - copy EXACTLY these files (what a scan showed and the user ticked)")
    ap.add_argument("--plan-json", default=None, help="write the per-board plan here (with --dry-run = a scan)")
    ap.add_argument("--roster", default=None)
    ap.add_argument("--skip-mac", default="", help="MACs to leave alone (the root), comma separated")
    ap.add_argument("--outdir", default=EXPORTS)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    topology = TOPO_DIR.get(a.topology, a.topology)
    attack_dir = "baseline" if a.attack in ("none", "baseline") else a.attack
    since = dt.datetime.strptime(a.since, "%Y-%m-%d %H:%M") if a.since else None
    skip = {re.sub(r"[^0-9a-f]", "", m.lower()) for m in a.skip_mac.split(",") if m.strip()}
    picks = {}
    for part in (a.pick or "").split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            picks[k.strip().upper()] = v.strip()
    dest_dir = os.path.join(a.outdir, attack_dir, topology, a.location, a.scenario)
    sources = ([("port", p.strip()) for p in a.ports.split(",") if p.strip()] if a.ports
               else [("card", c.strip()) for c in a.cards.split(";") if c.strip()])
    plan_rows = []
    ok = skipn = fail = 0
    for kind, s in sources:
        src_args = ["--port", s] if kind == "port" else ["--card", s]
        label = s if kind == "port" else os.path.basename(os.path.normpath(s)) or s
        print(f"\n-- {label}: reading the card ...", flush=True)
        row = {"port": label, "mac": "", "state": "", "why": "", "rel": "", "name": "", "started": "", "rows": None, "cell": ""}
        plan_rows.append(row)
        try:
            files = _list(src_args, a.repeat, a.scenario, a.roster)
        except Exception as e:                       # one bad board never stops the rest
            _say(label, "", "FAIL", f"could not list the card: {e}")
            row.update(state="FAIL", why=f"could not list the card: {e}")
            fail += 1
            continue
        mac = str((files[0] if files else {}).get("node", "")).replace("NODE_", "")
        row["mac"] = mac
        if picks:
            want = picks.get(label.upper())
            if not want:
                _say(label, mac, "SKIP", "not ticked")
                row.update(state="SKIP", why="not ticked")
                skipn += 1
                continue
            f = next((x for x in files if str(x.get("rel", "")).replace(chr(92), "/").lower() == want.replace(chr(92), "/").lower()), None)
            note = "" if not f or f.get("location") == a.location else f"card recorded {f.get('location')}, filed under {a.location}"
            if f is None:
                _say(label, mac, "FAIL", f"the ticked file is no longer on the card: {want}")
                row.update(state="FAIL", why="the ticked file is no longer on the card")
                fail += 1
                continue
        else:
            f, note = pick(files, a.attack, topology, a.location, since, skip, a.allow_other_location)
        if f is not None:
            row.update(rel=f.get("rel", ""), name=f.get("name", ""), started=str(f.get("started") or ""), rows=f.get("rows"),
                       cell=f"{f.get('filed_under')}/{f.get('topology')}/{f.get('location')}")
        if f is None:
            state = "SKIP" if ("root" in note or "no telemetry" in note) else "FAIL"
            _say(label, mac, state, note)
            row.update(state=state, why=note)
            skipn += state == "SKIP"
            fail += state == "FAIL"
            continue
        have = _already(dest_dir, mac, f.get("rows"), f.get("bytes"))
        if have:
            _say(label, mac, "SKIP", f"already in the run folder as {have}")
            row.update(state="SKIP", why=f"already imported as {have}")
            skipn += 1
            continue
        row.update(state="OK", why=note)
        if a.dry_run and a.plan_json:           # a scan: nothing is copied, no second card read
            _say(label, mac, "OK", f"would copy {f.get('name')} ({f.get('rows') or '?'} rows, ran {f.get('started')})" + (f" - {note}" if note else ""))
            ok += 1
            continue
        imp = [_py(), os.path.join(HERE, "import_sdcard.py")] + src_args + [
            "--repeat", str(a.repeat), "--scenario", a.scenario, "--files", f["rel"], "--outdir", a.outdir]
        if f.get("clean") is not True:
            imp.append("--include-aborted")          # no manifest (unknown) or a crash-ended piece picked on purpose
        if f.get("location") != a.location:
            imp += ["--file-location", a.location]
        if a.roster:
            imp += ["--roster", a.roster]
        if a.dry_run:
            imp.append("--dry-run")
        p = subprocess.run(imp, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=HERE)
        for line in p.stdout.splitlines():
            if line.strip():
                print("   " + line, flush=True)
        if p.returncode != 0:
            _say(label, mac, "FAIL", f"import_sdcard.py exited {p.returncode}: {(p.stderr.strip().splitlines() or [''])[-1]}")
            row.update(state="FAIL", why=f"import failed (exit {p.returncode})")
            fail += 1
            continue
        _say(label, mac, "OK", (("would copy " if a.dry_run else "") + f"{f.get('name')} ({f.get('rows') or '?'} rows, ran {f.get('started')})")
             + (f" - {note}" if note else ""))
        ok += 1
        # the board crashed in this run: its card also holds WHERE (crash_record.c,
        # firmware since oct. 18 2026) - fetch + decode it next to the run's logs
        crashed = _crashed_leaves(files, attack_dir, topology)
        if crashed and not a.dry_run:
            node = str(f.get("node") or "")
            _fetch_crashes(kind, s, crashed, node,
                           os.path.join(BASE, "datasets", "run_logs", attack_dir, topology, a.location, a.scenario, "crashes"))
    print(f"\nCOLLECT_SUMMARY: ok={ok} skip={skipn} fail={fail}", flush=True)
    if a.plan_json:
        with open(a.plan_json, "w", encoding="utf-8") as fh:
            json.dump(plan_rows, fh, indent=1, default=str)
    if not a.dry_run and os.path.isdir(dest_dir):
        print("", flush=True)
        subprocess.run([_py(), os.path.join(HERE, "run_summary.py"), dest_dir], cwd=HERE)
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main())
