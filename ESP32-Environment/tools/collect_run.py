#!/usr/bin/env python3
"""collect_run.py — pull ONE run's telemetry off every plugged-in child's SD card.

After a capture the children usually still sit on their USB cables. Instead of
importing them one by one (oct. 18 2026: seven boards by hand, and a card whose
location.txt was wrong filed one under G402), this reads each port in turn,
picks the file of THIS run and files it under the run's own folder:

    python tools/collect_run.py --ports COM10,COM11,COM9 --attack wormhole \
        --topology linear --location DLSU_Library --scenario highload --repeat 1 \
        --since "2026-10-18 14:40" [--roster presets/Cal/x.json] [--skip-mac b0cbd8f33218] [--dry-run]

Per board it picks the newest CLEAN telemetry file started at/after --since
(the run's first flash). The card's own folder may name another LOCATION (a
location.txt left on the last site) - it is filed under --location anyway and
says so; another ATTACK or TOPOLOGY is a different run and is never taken. A
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


def pick(files, attack, topology, location, since, skip_macs):
    """(file, note) - this run's telemetry on one card - or (None, why)."""
    want_atk = "baseline" if attack in ("none", "baseline") else attack
    telem = [f for f in files if f.get("kind") == "telem"]
    if not telem:
        return None, "no telemetry file on this card"
    mac = str(telem[0].get("node", "")).replace("NODE_", "").lower()
    if mac in skip_macs:
        return None, "the root (exported over USB) - skipped"
    cand, other = [], []
    for f in telem:
        if f.get("live"):
            other.append("one file is STILL BEING WRITTEN (run not ended)")
            continue
        started = _when(f.get("started"))
        if since and started and started < since:
            continue
        same_run = f.get("filed_under") == want_atk and f.get("topology") == topology
        if not same_run:
            other.append(f"{f.get('filed_under')}/{f.get('topology')}/{f.get('location')} (another run)")
            continue
        cand.append(f)
    clean = [f for f in cand if f.get("clean") is not False]
    if not clean:
        why = "no clean file of this run"
        if cand:
            why += f" ({len(cand)} aborted piece(s) - import those from the Data page, 'show aborted')"
        elif other:
            why += " - found only: " + "; ".join(sorted(set(other)))
        return None, why
    best = max(clean, key=lambda f: (str(f.get("started") or ""), f.get("rows") or 0, f.get("bytes") or 0))
    note = "" if best.get("location") == location else f"card recorded {best.get('location')}, filed under {location}"
    if len(clean) > 1:
        note = (note + "; " if note else "") + f"{len(clean)} clean files of this run - took the newest"
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
    ap.add_argument("--roster", default=None)
    ap.add_argument("--skip-mac", default="", help="MACs to leave alone (the root), comma separated")
    ap.add_argument("--outdir", default=EXPORTS)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    topology = TOPO_DIR.get(a.topology, a.topology)
    attack_dir = "baseline" if a.attack in ("none", "baseline") else a.attack
    since = dt.datetime.strptime(a.since, "%Y-%m-%d %H:%M") if a.since else None
    skip = {re.sub(r"[^0-9a-f]", "", m.lower()) for m in a.skip_mac.split(",") if m.strip()}
    dest_dir = os.path.join(a.outdir, attack_dir, topology, a.location, a.scenario)
    sources = ([("port", p.strip()) for p in a.ports.split(",") if p.strip()] if a.ports
               else [("card", c.strip()) for c in a.cards.split(";") if c.strip()])
    ok = skipn = fail = 0
    for kind, s in sources:
        src_args = ["--port", s] if kind == "port" else ["--card", s]
        label = s if kind == "port" else os.path.basename(os.path.normpath(s)) or s
        print(f"\n-- {label}: reading the card ...", flush=True)
        try:
            files = _list(src_args, a.repeat, a.scenario, a.roster)
        except Exception as e:                       # one bad board never stops the rest
            _say(label, "", "FAIL", f"could not list the card: {e}")
            fail += 1
            continue
        f, note = pick(files, a.attack, topology, a.location, since, skip)
        mac = str((files[0] if files else {}).get("node", "")).replace("NODE_", "")
        if f is None:
            state = "SKIP" if ("root" in note or "no telemetry" in note) else "FAIL"
            _say(label, mac, state, note)
            skipn += state == "SKIP"
            fail += state == "FAIL"
            continue
        have = _already(dest_dir, mac, f.get("rows"), f.get("bytes"))
        if have:
            _say(label, mac, "SKIP", f"already in the run folder as {have}")
            skipn += 1
            continue
        imp = [_py(), os.path.join(HERE, "import_sdcard.py")] + src_args + [
            "--repeat", str(a.repeat), "--scenario", a.scenario, "--files", f["rel"], "--outdir", a.outdir]
        if f.get("clean") is None:
            imp.append("--include-aborted")          # no manifest on the card: unknown, not aborted
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
            fail += 1
            continue
        _say(label, mac, "OK", (("would copy " if a.dry_run else "") + f"{f.get('name')} ({f.get('rows') or '?'} rows, ran {f.get('started')})")
             + (f" - {note}" if note else ""))
        ok += 1
    print(f"\nCOLLECT_SUMMARY: ok={ok} skip={skipn} fail={fail}", flush=True)
    if not a.dry_run and os.path.isdir(dest_dir):
        print("", flush=True)
        subprocess.run([_py(), os.path.join(HERE, "run_summary.py"), dest_dir], cwd=HERE)
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main())
