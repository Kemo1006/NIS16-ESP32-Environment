#!/usr/bin/env python3
"""
run_matrix.py — Milestone 4 (Phase-Controlled Experiment Execution) driver.

Milestone 4 requires the full experimental matrix:

    4 topologies x 2 attack types x >= 3 repeats  =  minimum 24 runs

Every run already produces phase-labelled telemetry (the root broadcasts the
phase ID and the firmware embeds it in each row). The physical parts — placing
boards per topology and running the ~10-minute timeline — happen on hardware;
this tool is the bookkeeping + command generator that keeps those 24 runs
organised:

  * plans and tracks progress in  exports/run_ledger.csv,
  * emits the exact per-board run.ps1 command block for a cell (correct
    -Topology / -Attack / -WormholeEnd / -DestAttack, in the required boot
    order: victims first, root LAST),
  * marks a cell "done" only once its exported CSVs are present AND pass
    validate_integrity.py.

It does NOT flash boards or drive the monitor for you — placement and the live
run are manual — but it removes every "which run am I on / what were the flags"
error from a 24-run campaign.

BRANCH NOTE (integration-test): the board->role mapping below is copied verbatim
from the authoritative "Board assignment" table in ../../ATTACKS-Commands.md.
This branch has NO attacker_a_node/attacker_b_node projects — the wormhole is the
combined victim firmware selected with -WormholeEnd A (exit) / B (entry). If the
board table in ATTACKS-Commands.md changes, update BOARDS here to match.

    COM20  root   — always; announces the phase; boots LAST; gets -Analyze.
    COM25  victim — blackhole ATTACKER / wormhole Node A (exit, -WormholeEnd A).
    COM26  victim — blackhole control / wormhole Node B (entry, -WormholeEnd B).
    COM21  victim — control in every attack run.

Standard library only.

NIS16 — CTTHES2 Milestone 4
"""

import argparse
import csv
import glob
import os
import subprocess
import sys
from datetime import datetime

TOPOLOGIES = ["star", "tree", "linear", "partial"]
ATTACKS = ["blackhole", "wormhole"]

# Export subfolder per topology (mirrors export_logs.py's _TOPOLOGY_DIR); a run's
# CSVs land in exports/<attack>/<this>/.
TOPO_DIR = {
    "star": "star_topology",
    "tree": "tree_topology",
    "linear": "linear_topology",
    "partial": "partial_mesh_topology",
}

# Default port per board. Override with --root-port / --attacker-port /
# --nodeb-port / --control-port if your layout differs.
DEFAULT_PORTS = {
    "root": "COM20",
    "attacker": "COM25",   # blackhole attacker / wormhole Node A
    "nodeb": "COM26",      # blackhole control  / wormhole Node B
    "control": "COM21",    # control in every attack run
}

LEDGER = "run_ledger.csv"
LEDGER_COLS = ["topology", "attack", "repeat", "status", "recorded_at", "files"]

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))


# ── Ledger I/O ──────────────────────────────────────────────────────────────
def ledger_path(outdir):
    return os.path.join(outdir, LEDGER)


def load_ledger(outdir):
    path = ledger_path(outdir)
    rows = {}
    if os.path.exists(path):
        with open(path, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                rows[(r["topology"], r["attack"], int(r["repeat"]))] = r
    return rows


def save_ledger(outdir, rows):
    os.makedirs(outdir, exist_ok=True)
    with open(ledger_path(outdir), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=LEDGER_COLS)
        w.writeheader()
        for key in sorted(rows):
            w.writerow(rows[key])


def all_cells(repeats):
    for topo in TOPOLOGIES:
        for atk in ATTACKS:
            for rep in range(1, repeats + 1):
                yield (topo, atk, rep)


# ── Command generation ──────────────────────────────────────────────────────
def _board_lines(topo, attack, rep, ports, export):
    """Yield (comment, run.ps1-command) pairs for one cell, in BOOT ORDER —
    victims first, root LAST — mirroring ../../ATTACKS-Commands.md exactly.
    export=True puts -Export on victims and -Analyze on the root (the flash+run
    is identical either way; the flags only add the CSV pull / analysis)."""
    vic_tail = " -Wipe -Flash" + (" -Export" if export else "")
    root_tail = " -Wipe -Flash" + (" -Analyze" if export else "")
    common = f"-Topology {topo} -Repeat {rep}"
    att, nodeb, ctl, root = (ports["attacker"], ports["nodeb"],
                             ports["control"], ports["root"])

    if attack == "blackhole":
        # Relay model: attacker forwards/drops the victims' probes; the victim
        # boards address the attacker's MAC (BLACKHOLE_ATTACKER_MAC must be set
        # to the attacker board's STA MAC first — see BLACKHOLE-SETUP.md).
        yield ("blackhole ATTACKER relay (forwards/drops victim probes)",
               f".\\run.ps1 -Port {att} -Role child  -Attack blackhole "
               f"-BlackholeRole attacker {common}{vic_tail}")
        for p in (nodeb, ctl):
            # Victim boards target the attacker; -Attack blackhole auto-files
            # their CSVs into exports/blackhole/ (no -DestAttack needed).
            yield ("victim -> sends its probes to the attacker's MAC",
                   f".\\run.ps1 -Port {p} -Role child  -Attack blackhole "
                   f"-BlackholeRole victim {common}{vic_tail}")
        yield ("root - announces the phase, boots LAST",
               f".\\run.ps1 -Port {root} -Role root -Attack blackhole "
               f"{common}{root_tail}")

    else:  # wormhole
        yield ("wormhole Node A (exit)",
               f".\\run.ps1 -Port {att} -Role child  -Attack wormhole "
               f"-WormholeEnd A {common}{vic_tail}")
        yield ("wormhole Node B (entry)",
               f".\\run.ps1 -Port {nodeb} -Role child  -Attack wormhole "
               f"-WormholeEnd B {common}{vic_tail}")
        dest = " -DestAttack wormhole" if export else ""
        yield ("control (plain victim, no attack)",
               f".\\run.ps1 -Port {ctl} -Role child {dest} {common}{vic_tail}")
        yield ("root - announces the phase, boots LAST",
               f".\\run.ps1 -Port {root} -Role root -Attack wormhole "
               f"{common}{root_tail}")


def print_cmds(topo, attack, rep, ports, export):
    print(f"# == Run cell:  topology={topo}  attack={attack}  repeat={rep} ==")
    print("# Boot order: run the victim lines FIRST (they sit scanning), the "
          "root LAST")
    print("#   - the root's 60 s stabilise window must overlap the victims' "
          "join (see BASELINE-SETUP.md / BLACKHOLE-SETUP.md / WORMHOLE-SETUP.md).")
    if attack == "wormhole":
        print("# Reminder: the A<->B tunnel is a WIRED UART CABLE (crossed "
              "GPIO17/16 + GND) — wire the two attacker boards together before "
              "powering on. No MAC to set. See WORMHOLE-SETUP.md.")
    print("# Each board in its OWN ESP-IDF PowerShell; Ctrl+] at 'terminate' "
          "to export.")
    for comment, cmd in _board_lines(topo, attack, rep, ports, export):
        print(f"{cmd}   # {comment}")


def print_export_cmds(topo, attack, rep, ports):
    """Fallback: standalone export_logs.py commands, for when a board was run
    WITHOUT -Export (data still on SPIFFS). Root last so its arrivals.csv is in
    place for -Analyze. Mirrors run.ps1's 'To export later' hint."""
    print(f"# == Export later:  topology={topo}  attack={attack}  "
          f"repeat={rep}  (run from tools/, monitor closed) ==")
    tdir = topo  # export_logs.py takes the short topology name
    if attack == "blackhole":
        specs = [(ports["attacker"], "victim", "blackhole", None),
                 (ports["nodeb"], "victim", "none", "blackhole"),
                 (ports["control"], "victim", "none", "blackhole"),
                 (ports["root"], "root", "blackhole", None)]
    else:
        specs = [(ports["attacker"], "victim", "wormhole", None),
                 (ports["nodeb"], "victim", "wormhole", None),
                 (ports["control"], "victim", "none", "wormhole"),
                 (ports["root"], "root", "wormhole", None)]
    for port, role, atk, dest in specs:
        line = (f"python export_logs.py --port {port} --role {role} "
                f"--topology {tdir} --attack {atk} --repeat {rep}")
        if dest:
            line += f" --attack-dir {dest}"
        print(line)


# ── File discovery + validation ─────────────────────────────────────────────
def cell_dir(outdir, topo, attack):
    return os.path.join(outdir, attack, TOPO_DIR[topo])


def find_files(outdir, topo, attack, rep):
    """All CSVs for a cell. Controls export as `..._none_...` but live in the
    attack folder (via -DestAttack), so match on the repeat token, not the
    attack token, inside the cell's own folder."""
    folder = cell_dir(outdir, topo, attack)
    pat = os.path.join(folder, f"*_r{rep}_*.csv")
    return sorted(os.path.basename(p) for p in glob.glob(pat))


def coverage(files):
    """(has_root_telem, has_root_arrivals, victim_telem_count) for a cell's
    files — a complete 4-board run has root telem+arrivals and 3 victim telems."""
    root_telem = any(f.startswith("root_") and f.endswith("_telem.csv")
                     for f in files)
    root_arr = any(f.startswith("root_") and f.endswith("_arrivals.csv")
                   for f in files)
    vic = sum(1 for f in files
              if f.startswith("victim_") and f.endswith("_telem.csv"))
    return root_telem, root_arr, vic


def validate_cell(outdir, topo, attack, sample_interval_ms):
    """Run validate_integrity.py against the cell's folder. Returns (ok, output)."""
    folder = cell_dir(outdir, topo, attack)
    cmd = [sys.executable, os.path.join(_THIS_DIR, "validate_integrity.py"), folder]
    if sample_interval_ms is not None:
        cmd += ["--sample-interval-ms", str(sample_interval_ms)]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e:
        return False, f"(could not run validate_integrity.py: {e})"
    return res.returncode == 0, (res.stdout or "") + (res.stderr or "")


# ── Views ───────────────────────────────────────────────────────────────────
def print_status(outdir, repeats):
    rows = load_ledger(outdir)
    done = 0
    total = 0
    print(f"Experiment matrix  (repeats target = {repeats})   [x]=done  [ ]=pending\n")
    header = "topology  attack     " + "  ".join(f"r{r}" for r in range(1, repeats + 1))
    print(header)
    print("-" * len(header))
    for topo in TOPOLOGIES:
        for atk in ATTACKS:
            cells = []
            for rep in range(1, repeats + 1):
                total += 1
                st = rows.get((topo, atk, rep), {}).get("status")
                if st == "done":
                    done += 1
                    cells.append("[x]")
                else:
                    cells.append("[ ]")
            print(f"{topo:<9} {atk:<10} " + "  ".join(cells))
    print(f"\nProgress: {done}/{total} runs collected "
          f"(Milestone-4 minimum is 24).")
    for cell in all_cells(repeats):
        if rows.get(cell, {}).get("status") != "done":
            print(f"Next pending: topology={cell[0]} attack={cell[1]} "
                  f"repeat={cell[2]}   (--cmds to see its command block)")
            break
    else:
        print("All planned runs collected. [done]")


def record(outdir, topo, attack, rep, do_validate, sample_interval_ms):
    files = find_files(outdir, topo, attack, rep)
    if not files:
        print(f"(!) No exported CSVs found for {topo}/{attack}/r{rep} under "
              f"{cell_dir(outdir, topo, attack)}.\n"
              f"    Run the cell first (--cmds), or export it (--export-cmds), "
              f"then re-run --record.")
        return 1

    root_t, root_a, vic = coverage(files)
    if not (root_t and root_a and vic >= 3):
        print(f"(!) Incomplete capture for {topo}/{attack}/r{rep}: "
              f"root_telem={root_t} root_arrivals={root_a} victim_telems={vic} "
              f"(expected root telem+arrivals and >=3 victim telems).")
        print(f"    Found {len(files)} file(s): " + ", ".join(files))
        print("    Fix the missing board(s), or pass --allow-incomplete to "
              "record anyway.")
        if not getattr(record, "_allow_incomplete", False):
            return 1

    if do_validate:
        ok, out = validate_cell(outdir, topo, attack, sample_interval_ms)
        tail = out.strip().splitlines()[-6:] if out.strip() else []
        for ln in tail:
            print("   " + ln)
        if not ok:
            print(f"(!) integrity validation FAILED for {topo}/{attack}/r{rep} "
                  f"- not marking done. Fix/re-capture, or --no-validate to "
                  f"force-record.")
            return 1

    rows = load_ledger(outdir)
    rows[(topo, attack, rep)] = {
        "topology": topo, "attack": attack, "repeat": rep,
        "status": "done",
        "recorded_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "files": ";".join(files),
    }
    save_ledger(outdir, rows)
    verdict = "validated + recorded" if do_validate else "recorded (unvalidated)"
    print(f"{verdict}: {topo}/{attack}/r{rep} - {len(files)} file(s):")
    for fn in files:
        print(f"  - {fn}")
    return 0


# ── Main ────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Milestone-4 experiment-matrix driver.")
    ap.add_argument("--outdir", default="exports", help="Where CSVs and the ledger live.")
    ap.add_argument("--repeats", type=int, default=3, help="Target repeats per cell (>=3).")

    ap.add_argument("--status", action="store_true", help="Show the matrix progress grid.")
    ap.add_argument("--plan", action="store_true", help="List every planned run.")
    ap.add_argument("--cmds", action="store_true",
                    help="Print the run.ps1 command block for a cell "
                         "(needs --topology --attack; --repeat optional).")
    ap.add_argument("--export-cmds", action="store_true",
                    help="Print standalone export_logs.py commands for a cell "
                         "(fallback when run without -Export).")
    ap.add_argument("--next", action="store_true",
                    help="Print the next pending cell AND its run.ps1 block.")
    ap.add_argument("--record", action="store_true",
                    help="Validate a cell's CSVs and mark it done "
                         "(needs --topology --attack; --repeat optional).")

    ap.add_argument("--topology", choices=TOPOLOGIES)
    ap.add_argument("--attack", choices=ATTACKS)
    ap.add_argument("--repeat", type=int, default=1)

    ap.add_argument("--dry-run", action="store_true",
                    help="With --cmds: emit the no-export (dry) block (no "
                         "-Export/-Analyze/-DestAttack).")
    ap.add_argument("--no-validate", action="store_true",
                    help="With --record: skip validate_integrity.py.")
    ap.add_argument("--allow-incomplete", action="store_true",
                    help="With --record: record even if some boards are missing.")
    ap.add_argument("--sample-interval-ms", type=float, default=None,
                    help="Passed to validate_integrity.py (use 1000 for pre-2026-07-12 "
                         "1 Hz captures; omit for the firmware default).")

    ap.add_argument("--root-port", default=DEFAULT_PORTS["root"])
    ap.add_argument("--attacker-port", default=DEFAULT_PORTS["attacker"])
    ap.add_argument("--nodeb-port", default=DEFAULT_PORTS["nodeb"])
    ap.add_argument("--control-port", default=DEFAULT_PORTS["control"])
    args = ap.parse_args()

    ports = {
        "root": args.root_port,
        "attacker": args.attacker_port,
        "nodeb": args.nodeb_port,
        "control": args.control_port,
    }

    if args.plan:
        for cell in all_cells(args.repeats):
            print(f"{cell[0]:<9} {cell[1]:<10} r{cell[2]}")
        return 0

    if args.next:
        rows = load_ledger(args.outdir)
        for cell in all_cells(args.repeats):
            if rows.get(cell, {}).get("status") != "done":
                print_cmds(cell[0], cell[1], cell[2], ports, export=not args.dry_run)
                return 0
        print("All planned runs collected. [done]")
        return 0

    if args.cmds:
        if not (args.topology and args.attack):
            ap.error("--cmds needs --topology and --attack")
        print_cmds(args.topology, args.attack, args.repeat, ports,
                   export=not args.dry_run)
        return 0

    if args.export_cmds:
        if not (args.topology and args.attack):
            ap.error("--export-cmds needs --topology and --attack")
        print_export_cmds(args.topology, args.attack, args.repeat, ports)
        return 0

    if args.record:
        if not (args.topology and args.attack):
            ap.error("--record needs --topology and --attack (and --repeat)")
        record._allow_incomplete = args.allow_incomplete
        return record(args.outdir, args.topology, args.attack, args.repeat,
                      do_validate=not args.no_validate,
                      sample_interval_ms=args.sample_interval_ms)

    # Default view.
    print_status(args.outdir, args.repeats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
