#!/usr/bin/env python3
"""
run_matrix.py — Milestone 4 (Phase-Controlled Experiment Execution) driver.

Milestone 4 requires the full experimental matrix:

    4 topologies x 2 attack types x >= 3 repeats  =  minimum 24 runs

Every run already produces phase-labelled telemetry (the firmware embeds the
root's broadcast phase ID in each row). The physical parts — placing boards per
topology and running the ~11-minute timeline — happen on hardware; this tool is
the bookkeeping and command generator that keeps those 24 runs organised:

  * plans and tracks progress in exports/run_ledger.csv,
  * emits the exact per-role BUILD commands (correct MESH_TOPOLOGY / ACTIVE_ATTACK),
  * emits the exact per-board EXPORT commands (correct metadata in filenames),
  * records a run as done once its CSVs are present.

It does NOT flash boards or drive the monitor for you — placement and the live
run are manual — but it removes every "which run am I on / what were the flags"
error from a 24-run campaign.

Standard library only.

NIS16 — CTTHES2 Milestone 4
"""

import argparse
import csv
import glob
import os
from datetime import datetime

TOPOLOGIES = ["star", "tree", "linear", "partial"]
ATTACKS = ["blackhole", "wormhole"]

# Build-flag mappings (mirror mesh_config.h).
TOPO_CODE = {"star": 0, "tree": 1, "linear": 2, "partial": 3}
ATTACK_CODE = {"blackhole": 1, "wormhole": 2}

# Node folders and their export --role labels.
ROLES = [
    ("root_node", "root"),
    ("victim_node", "victim"),
    ("attacker_a_node", "attacker_a"),
    ("attacker_b_node", "attacker_b"),
]

LEDGER = "run_ledger.csv"
LEDGER_COLS = ["topology", "attack", "repeat", "status", "recorded_at", "files"]


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


# ── Commands ────────────────────────────────────────────────────────────────
def build_cmds(topo, attack):
    topo_c = TOPO_CODE[topo]
    atk_c = ATTACK_CODE[attack]
    print(f"# BUILD & FLASH for topology={topo}  attack={attack}")
    print(f"#   (root also gets ACTIVE_ATTACK={atk_c}; every node gets MESH_TOPOLOGY={topo_c})")
    for folder, _role in ROLES:
        extra = f" -DACTIVE_ATTACK={atk_c}" if folder == "root_node" else ""
        print(f"cd {folder}")
        print(f"idf.py -DMESH_TOPOLOGY={topo_c}{extra} -p <PORT> flash monitor")
        print("cd ..")
    print("# (For blackhole runs, build the blackhole attacker folder instead of the")
    print("#  two wormhole attacker folders — that module is owned by your teammate.)")


def export_cmds(args):
    topo, attack, rep = args.topology, args.attack, args.repeat
    ports = {
        "root": args.root_port,
        "victim": args.victim_port,
        "attacker_a": args.attacker_a_port,
        "attacker_b": args.attacker_b_port,
    }
    print(f"# EXPORT for topology={topo} attack={attack} repeat={rep} "
          f"(run from tools/, monitor closed)")
    for _folder, role in ROLES:
        port = ports.get(role)
        if not port:
            continue
        print(f"python export_logs.py --port {port} --role {role} "
              f"--topology {topo} --attack {attack} --repeat {rep}")


def find_files(outdir, topo, attack, rep):
    pat = os.path.join(outdir, f"*_{topo}_{attack}_r{rep}_*.csv")
    return sorted(os.path.basename(p) for p in glob.glob(pat))


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
    # Suggest the next pending run.
    for cell in all_cells(repeats):
        if rows.get(cell, {}).get("status") != "done":
            print(f"Next pending: topology={cell[0]} attack={cell[1]} repeat={cell[2]}")
            break
    else:
        print("All planned runs collected. ✔")


def record(outdir, topo, attack, rep):
    rows = load_ledger(outdir)
    files = find_files(outdir, topo, attack, rep)
    if not files:
        print(f"(!) No exported CSVs found for {topo}/{attack}/r{rep} in {outdir}. "
              f"Export the boards first (see --export-cmds), then re-run --record.")
        return 1
    rows[(topo, attack, rep)] = {
        "topology": topo, "attack": attack, "repeat": rep,
        "status": "done",
        "recorded_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "files": ";".join(files),
    }
    save_ledger(outdir, rows)
    print(f"Recorded {topo}/{attack}/r{rep} as done with {len(files)} file(s):")
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

    ap.add_argument("--build-cmds", action="store_true",
                    help="Print BUILD/FLASH commands (needs --topology --attack).")
    ap.add_argument("--export-cmds", action="store_true",
                    help="Print EXPORT commands (needs --topology --attack --repeat + ports).")
    ap.add_argument("--record", action="store_true",
                    help="Mark a run done by finding its CSVs (needs --topology --attack --repeat).")

    ap.add_argument("--topology", choices=TOPOLOGIES)
    ap.add_argument("--attack", choices=ATTACKS)
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--root-port")
    ap.add_argument("--victim-port")
    ap.add_argument("--attacker-a-port")
    ap.add_argument("--attacker-b-port")
    args = ap.parse_args()

    if args.plan:
        for cell in all_cells(args.repeats):
            print(f"{cell[0]:<9} {cell[1]:<10} r{cell[2]}")
        return 0

    if args.build_cmds:
        if not (args.topology and args.attack):
            ap.error("--build-cmds needs --topology and --attack")
        build_cmds(args.topology, args.attack)
        return 0

    if args.export_cmds:
        if not (args.topology and args.attack):
            ap.error("--export-cmds needs --topology and --attack")
        export_cmds(args)
        return 0

    if args.record:
        if not (args.topology and args.attack):
            ap.error("--record needs --topology and --attack (and --repeat)")
        return record(args.outdir, args.topology, args.attack, args.repeat)

    # Default view.
    print_status(args.outdir, args.repeats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
