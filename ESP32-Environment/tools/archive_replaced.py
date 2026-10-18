#!/usr/bin/env python3
"""archive_replaced.py — move a run's OLD capture out of the way when it is re-captured.

User, oct. 18 2026: "if I repeat a run I have done already, once the root exports
the new data the old one should go to the archive." A re-capture of the SAME run
(same attack / topology / location / scenario AND the same repeat number) replaces
the old one; a different repeat (r2 next to r1) is a separate capture and stays.

What moves (only files written BEFORE --before, i.e. before this run started):
  exports/<cell>/*_r<N>_*.csv     the old telemetry / arrivals of that repeat
  exports/<cell>/manifest.json    the old trim manifest
  exports/<cell>/trimmed/         derived from the old files (analyze.ps1 re-trims)
  analysis/<cell>/                built from the old files (Analyse rebuilds it)
  run_logs/<cell>/*               logs older than --logs-before (run.ps1: 3 h before the
                                  root's flash - this run's own children were flashed before
                                  its root, so "older than the root" would catch them)
  the GUI's verification of the run: %LOCALAPPDATA%/NIS16/reports/<run>.txt and its
                                  entry in verdicts.json (else the Analyse / Campaign pages
                                  show the OLD verdict next to the new capture)
docs/dataset-verification.md is never edited (project rule): REPLACED.txt lists the
verification blocks that covered the old capture instead.
PCAP captures are never moved (timestamped, they cannot be mixed up).

Destination: archive/<YYYY-MM-DD>_<attack>-<topology>-<location>-<scenario>-r<N>-replaced/
  {exports,analysis,run_logs}/... + REPLACED.txt (what, why, which run replaced it).

    python tools/archive_replaced.py --attack blackhole --topology tree --location G402 \
        --scenario stationary --repeat 1 --before "2026-10-18 18:00" [--logs] [--dry-run]

Prints "ARCHIVED: <n> file(s) -> <folder>" or "ARCHIVE: nothing older to move".
"""
import argparse
import datetime as dt
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
DS = os.path.join(BASE, "datasets")
TOPO = {"partial": "partial_mesh"}


def _old(path, before):
    return dt.datetime.fromtimestamp(os.path.getmtime(path)) < before


def plan(attack, topology, location, scenario, repeat, before, logs_before):
    """[(src, rel_dest)] - nothing is touched."""
    cell = os.path.join(attack, topology, location, scenario)
    out = []
    exp = os.path.join(DS, "exports", cell)
    rx = re.compile(rf"_r{repeat}_", re.I)
    if os.path.isdir(exp):
        for n in sorted(os.listdir(exp)):
            p = os.path.join(exp, n)
            if os.path.isfile(p) and n.lower().endswith(".csv") and rx.search(n) and _old(p, before):
                out.append((p, os.path.join("exports", n)))
    if not out:
        return out                      # no old capture of this repeat: nothing derived to move either
    man = os.path.join(exp, "manifest.json")
    if os.path.isfile(man) and _old(man, before):
        out.append((man, os.path.join("exports", "manifest.json")))
    tr = os.path.join(exp, "trimmed")
    if os.path.isdir(tr):
        out.append((tr, os.path.join("exports", "trimmed")))
    ana = os.path.join(DS, "analysis", cell)
    if os.path.isdir(ana) and all(_old(os.path.join(r, f), before) for r, _d, fs in os.walk(ana) for f in fs):
        out.append((ana, "analysis"))
    if logs_before:
        lg = os.path.join(DS, "run_logs", cell)
        if os.path.isdir(lg):
            for n in sorted(os.listdir(lg)):
                p = os.path.join(lg, n)
                if os.path.isfile(p) and _old(p, logs_before):
                    out.append((p, os.path.join("run_logs", n)))
    return out


def gui_state_dir():
    return os.path.join(os.environ.get("LOCALAPPDATA", ""), "NIS16")


def archive_verdict(key, dest, dry):
    """Move the GUI's verify report of `key` into dest/verification/ and take its
    entry out of verdicts.json (kept there as verdict.json). Returns a description list."""
    done = []
    st = gui_state_dir()
    rep = os.path.join(st, "reports", key.replace("/", "__") + ".txt")
    if os.path.isfile(rep):
        done.append(f"GUI verify report {os.path.basename(rep)}")
        if not dry:
            os.makedirs(os.path.join(dest, "verification"), exist_ok=True)
            shutil.move(rep, os.path.join(dest, "verification", os.path.basename(rep)))
    vj = os.path.join(st, "verdicts.json")
    if os.path.isfile(vj):
        try:
            with open(vj, encoding="utf-8-sig") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            d = {}
        if key in d:
            done.append(f"verdict '{str(d[key].get('Line', ''))[:60]}'")
            if not dry:
                os.makedirs(os.path.join(dest, "verification"), exist_ok=True)
                with open(os.path.join(dest, "verification", "verdict.json"), "w", encoding="utf-8") as fh:
                    json.dump({key: d[key]}, fh, indent=1)
                d.pop(key)
                tmp = vj + ".tmp"
                with open(tmp, "w", encoding="utf-8") as fh:
                    json.dump(d, fh, indent=1)
                os.replace(tmp, vj)
    return done


def verification_blocks(attack, topology, location, scenario):
    """Numbers of the dataset-verification.md blocks that covered this run (read only)."""
    p = os.path.join(BASE, "docs", "dataset-verification.md")
    if not os.path.isfile(p):
        return []
    want = [attack.lower(), topology.lower(), location.lower(), scenario.lower()]
    hit, cur = [], None
    for line in open(p, encoding="utf-8", errors="replace"):
        m = re.match(r"^##\s.*VERIFICATION #(\d+)", line)
        if m:
            cur = int(m.group(1))
            low = line.lower()
            if all(w in low for w in want) and cur not in hit:
                hit.append(cur)
            continue
        if cur is not None and line.startswith("|"):
            cells = [c.strip().lower().replace("*", "") for c in line.split("|")]
            if all(w in cells for w in want) and cur not in hit:
                hit.append(cur)
    return sorted(hit)


def new_reached_phase0(attack, topology, location, scenario, repeat, before):
    """A telemetry file of this repeat written after `before` holds a phase 0 row."""
    exp = os.path.join(DS, "exports", attack, topology, location, scenario)
    if not os.path.isdir(exp):
        return False
    rx = re.compile(rf"_r{repeat}_.*_telem\.csv$", re.I)
    for n in os.listdir(exp):
        p = os.path.join(exp, n)
        if not (rx.search(n) and os.path.isfile(p)) or _old(p, before):
            continue
        with open(p, encoding="utf-8", errors="replace") as fh:
            head = fh.readline().strip().split(",")
            if "phase_id" not in head:
                continue
            i = head.index("phase_id")
            for line in fh:
                cols = line.split(",")
                if len(cols) > i and cols[i].strip() == "0":
                    return True
    return False


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description="Archive the OLD capture of a run that is being re-captured.")
    ap.add_argument("--attack", required=True)
    ap.add_argument("--topology", required=True)
    ap.add_argument("--location", required=True)
    ap.add_argument("--scenario", default="stationary")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--before", required=True, help="'YYYY-MM-DD HH:MM' - this run's start; only older files move")
    ap.add_argument("--logs", action="store_true", help="also move run logs older than --before")
    ap.add_argument("--logs-before", default=None, help="'YYYY-MM-DD HH:MM' - move run logs older than this")
    ap.add_argument("--no-verdict", action="store_true", help="leave the GUI's verify report / verdict alone")
    ap.add_argument("--by", default="", help="what replaced it (written into REPLACED.txt)")
    ap.add_argument("--require-new", action="store_true",
                    help="move nothing unless a telemetry file written AFTER --before reached "
                         "Phase 0 (a failed attempt that never started must not archive a good run)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    attack = "baseline" if a.attack in ("none", "baseline") else a.attack
    topology = TOPO.get(a.topology, a.topology)
    before = dt.datetime.strptime(a.before, "%Y-%m-%d %H:%M")
    if a.require_new and not new_reached_phase0(attack, topology, a.location, a.scenario, a.repeat, before):
        print("ARCHIVE: skipped - the new export never reached Phase 0 (the run did not start); "
              "the old capture stays where it is")
        return 0
    logs_before = (dt.datetime.strptime(a.logs_before, "%Y-%m-%d %H:%M") if a.logs_before
                   else before if a.logs else None)
    items = plan(attack, topology, a.location, a.scenario, a.repeat, before, logs_before)
    if not items:
        print(f"ARCHIVE: nothing older to move in {attack}/{topology}/{a.location}/{a.scenario} r{a.repeat}")
        return 0
    name = f"{dt.date.today().isoformat()}_{attack}-{topology}-{a.location}-{a.scenario}-r{a.repeat}-replaced"
    dest = os.path.join(BASE, "archive", name)
    k = 2
    while os.path.exists(dest) and not a.dry_run:
        dest = os.path.join(BASE, "archive", f"{name}-{k}"); k += 1
    nfiles = 0
    for src, rel in items:
        n = sum(len(fs) for _r, _d, fs in os.walk(src)) if os.path.isdir(src) else 1
        nfiles += n
        print(f"  {'WOULD MOVE' if a.dry_run else 'MOVE'}  {os.path.relpath(src, BASE)}  ({n} file(s))")
        if not a.dry_run:
            target = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.move(src, target)
    key = f"{attack}/{topology}/{a.location}/{a.scenario}"
    ver = [] if a.no_verdict else archive_verdict(key, dest, a.dry_run)
    for v in ver:
        print(f"  {'WOULD MOVE' if a.dry_run else 'MOVE'}  {v}")
    blocks = verification_blocks(attack, topology, a.location, a.scenario)
    if a.dry_run:
        print(f"DRY RUN: {nfiles} file(s) would go to archive/{os.path.basename(dest)}"
              + (f"; verification blocks of this run: {', '.join('#' + str(b) for b in blocks)}" if blocks else ""))
        return 0
    with open(os.path.join(dest, "REPLACED.txt"), "w", encoding="utf-8") as fh:
        fh.write(f"{attack}/{topology}/{a.location}/{a.scenario} repeat {a.repeat}\n"
                 f"archived {dt.datetime.now():%Y-%m-%d %H:%M} - files written before {a.before}\n"
                 f"why: the same run (same repeat) was captured again{(' - ' + a.by) if a.by else ''}\n"
                 f"also moved: {', '.join(ver) if ver else 'no GUI verification on this laptop'}\n"
                 f"verification log blocks that covered the OLD capture (docs/dataset-verification.md, "
                 f"never edited): {', '.join('#' + str(b) for b in blocks) if blocks else 'none found'}\n"
                 f"restore: move exports/, analysis/, run_logs/ back into datasets/ under the same run folder;\n"
                 f"         verification/ back into %LOCALAPPDATA%\\NIS16\\reports (+ its verdicts.json entry)\n")
    print(f"ARCHIVED: {nfiles} file(s) -> archive/{os.path.basename(dest)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
