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
from the authoritative "Board assignment" table in ../docs/_archive/guides/ATTACKS-Commands.md.
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

# Deployment sites (thesis panel problem P4 — environment must be RECORDED,
# never inferred). Must match export_logs.py's LOCATIONS and SD_LOCATION_* in
# mesh_config.h. A whole matrix campaign runs at ONE site (the 6 boards don't
# move mid-campaign), so --location is a required, session-wide argument, not
# an extra dimension auto-crossed with topology/attack/repeat.
LOCATIONS = ["home", "G402", "DLSU_Library", "Goks"]

# Run-to-run variation (panel, sep. 2026 — see run.ps1 -Scenario). Like
# --location, a whole matrix campaign runs at ONE scenario at a time — this is
# an extra session-wide axis, not auto-crossed with topology/attack/repeat.
# "none" is the pre-scenario default, so an un-scenario'd campaign's ledger
# key/folder path is unchanged from before this feature existed.
SCENARIOS = ["none", "burst", "highload", "mobility", "powercycle"]

# burst/mobility/powercycle need exactly one TARGET board — the burst sender,
# the node moved, or the node power-cycled. In this fixed 4-board table only
# "nodeb"/"control" ever build plain victim_main.c (attacker relays and
# wormhole ends don't), so those are the only valid --scenario-target values.
SCENARIO_TARGETS = ["nodeb", "control"]

# Export subfolder per topology (mirrors export_logs.py's _TOPOLOGY_DIR, and
# MUST stay byte-identical to it and to s_topo_dirs in sd_status.c); a run's
# CSVs land in exports/<attack>/<this>/. "partial" keeps the longer
# "partial_mesh" folder name so it stays distinguishable from the CLI value.
TOPO_DIR = {
    "star": "star",
    "tree": "tree",
    "linear": "linear",
    "partial": "partial_mesh",
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
LEDGER_COLS = ["topology", "attack", "location", "scenario", "scenario_target",
               "repeat", "status", "recorded_at", "files"]

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))


# ── Ledger I/O ──────────────────────────────────────────────────────────────
def ledger_path(outdir):
    return os.path.join(outdir, LEDGER)


def load_ledger(outdir):
    """Keys are (topology, attack, location, scenario, repeat). Rows written
    before the location/scenario columns existed have no such key at all
    (DictReader only populates keys the CSV header actually had) — r.get(...),
    not r["location"]/r["scenario"], or every pre-existing row KeyErrors on
    load. Location is backfilled as "unrecorded" (not a guessed site);
    scenario is backfilled as "none" (the pre-scenario default, matching every
    run that predates this feature) — both in the returned dict and in the row
    itself, so the next save_ledger() call persists the columns for them."""
    path = ledger_path(outdir)
    rows = {}
    if os.path.exists(path):
        with open(path, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                loc = r.get("location") or "unrecorded"
                r["location"] = loc
                scenario = r.get("scenario") or "none"
                r["scenario"] = scenario
                r.setdefault("scenario_target", "")
                rows[(r["topology"], r["attack"], loc, scenario, int(r["repeat"]))] = r
    return rows


def save_ledger(outdir, rows):
    os.makedirs(outdir, exist_ok=True)
    with open(ledger_path(outdir), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=LEDGER_COLS, extrasaction="ignore")
        w.writeheader()
        for key in sorted(rows):
            w.writerow(rows[key])


def all_cells(location, repeats, scenario="none"):
    for topo in TOPOLOGIES:
        for atk in ATTACKS:
            for rep in range(1, repeats + 1):
                yield (topo, atk, location, scenario, rep)


# ── Command generation ──────────────────────────────────────────────────────
def _board_lines(topo, attack, location, rep, ports, export, scenario="none", scenario_target=None):
    """Yield (comment, run.ps1-command) pairs for one cell, in BOOT ORDER —
    victims first, root LAST — mirroring ../docs/_archive/guides/ATTACKS-Commands.md exactly.
    export=True puts -Export on victims and -Analyze on the root (the flash+run
    is identical either way; the flags only add the CSV pull / analysis).
    -Location routes the export/analysis path only — the firmware itself reads
    its site from /sdcard/location.txt, not from a build or run flag.

    scenario/scenario_target follow run.ps1 -Scenario/-ScenarioTarget: every
    board gets -Scenario (root needs it too, for the burst baseline-run window
    — see mesh_config.h TRAFFIC_PROFILE), and ONLY the board named by
    scenario_target ('nodeb' or 'control' — see SCENARIO_TARGETS) gets
    -ScenarioTarget. scenario_target is ignored for highload/none/mobility/
    powercycle need it but this fixed table has no per-run prompt for it, so
    the caller (main()) validates and defaults it."""
    vic_tail = " -Wipe -Flash" + (" -Export" if export else "")
    root_tail = " -Wipe -Flash" + (" -Analyze" if export else "")
    common = f"-Topology {topo} -Repeat {rep} -Location {location} -Scenario {scenario}"
    att, nodeb, ctl, root = (ports["attacker"], ports["nodeb"],
                             ports["control"], ports["root"])

    def tgt(name):
        return " -ScenarioTarget" if scenario_target == name else ""

    if attack == "blackhole":
        # Relay model: attacker forwards/drops the victims' probes; the victim
        # boards address the attacker's MAC (BLACKHOLE_ATTACKER_MAC must be set
        # to the attacker board's STA MAC first — see BLACKHOLE-SETUP.md).
        yield ("blackhole ATTACKER relay (forwards/drops victim probes)",
               f".\\run.ps1 -Port {att} -Role child  -Attack blackhole "
               f"-BlackholeRole attacker {common}{vic_tail}")
        for name, p in (("nodeb", nodeb), ("control", ctl)):
            # Victim boards target the attacker; -Attack blackhole auto-files
            # their CSVs into exports/blackhole/ (no -DestAttack needed).
            yield ("victim -> sends its probes to the attacker's MAC",
                   f".\\run.ps1 -Port {p} -Role child  -Attack blackhole "
                   f"-BlackholeRole victim {common}{tgt(name)}{vic_tail}")
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
               f".\\run.ps1 -Port {ctl} -Role child {dest} {common}{tgt('control')}{vic_tail}")
        yield ("root - announces the phase, boots LAST",
               f".\\run.ps1 -Port {root} -Role root -Attack wormhole "
               f"{common}{root_tail}")


def print_cmds(topo, attack, location, rep, ports, export, scenario="none", scenario_target=None):
    print(f"# == Run cell:  topology={topo}  attack={attack}  location={location}  "
          f"scenario={scenario}  repeat={rep} ==")
    print("# Boot order: run the victim lines FIRST (they sit scanning), the "
          "root LAST")
    print("#   - the root's 60 s stabilise window must overlap the victims' "
          "join (see BASELINE-SETUP.md / BLACKHOLE-SETUP.md / WORMHOLE-SETUP.md).")
    if attack == "wormhole":
        print("# Reminder: the A<->B tunnel is a WIRED UART CABLE (crossed "
              "GPIO17/16 + GND) — wire the two attacker boards together before "
              "powering on. No MAC to set. See WORMHOLE-SETUP.md.")
    if scenario in ("mobility", "powercycle"):
        print(f"# SCENARIO ({scenario}) is HUMAN: run.ps1 prints the checklist "
              f"itself right before the {scenario_target} board boots — do the "
              f"{'move' if scenario == 'mobility' else 'unplug/replug'} when it tells you to.")
    print("# Each board in its OWN ESP-IDF PowerShell; Ctrl+] at 'terminate' "
          "to export.")
    print(f"# Confirm /sdcard/location.txt on EVERY board reads \"{location}\" "
          f"before powering on — that is what sd_status.c actually records; "
          f"-Location here only routes the export/analysis path.")
    for comment, cmd in _board_lines(topo, attack, location, rep, ports, export,
                                      scenario, scenario_target):
        print(f"{cmd}   # {comment}")


def print_export_cmds(topo, attack, location, rep, ports, scenario="none"):
    """Fallback: standalone export_logs.py commands, for when a board was run
    WITHOUT -Export (data still on SPIFFS). Root last so its arrivals.csv is in
    place for -Analyze. Mirrors run.ps1's 'To export later' hint."""
    print(f"# == Export later:  topology={topo}  attack={attack}  "
          f"location={location}  scenario={scenario}  repeat={rep}  "
          f"(run from tools/, monitor closed) ==")
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
                f"--topology {tdir} --attack {atk} --location {location} "
                f"--scenario {scenario} --repeat {rep}")
        if dest:
            line += f" --attack-dir {dest}"
        print(line)


# ── File discovery + validation ─────────────────────────────────────────────
def cell_dir(outdir, topo, attack, location, scenario="none"):
    # 'none' must NOT become a real folder segment - see the SCENARIOS comment
    # above ("folder path is unchanged from before this feature existed").
    # Must stay byte-identical to _subdir_for() in export_logs.py and
    # Get-RunDirs in run_wizard.ps1/run.ps1.
    if scenario and scenario != "none":
        return os.path.join(outdir, attack, TOPO_DIR[topo], location, scenario)
    return os.path.join(outdir, attack, TOPO_DIR[topo], location)


def find_files(outdir, topo, attack, location, rep, scenario="none"):
    """All CSVs for a cell. Controls export as `..._none_...` but live in the
    attack folder (via -DestAttack), so match on the repeat token, not the
    attack token, inside the cell's own folder."""
    folder = cell_dir(outdir, topo, attack, location, scenario)
    pat = os.path.join(folder, f"*_r{rep}_*.csv")
    return sorted(os.path.basename(p) for p in glob.glob(pat))


# export_logs.py's --role takes root | child | victim, and CHILD IS THE DEFAULT
# (victim is kept only as an alias). Every runbook uses `--role child`, so real
# captures are named child_*.csv. Counting only "victim_" made a complete 6-board
# run report victim_telems=0 and refuse to record — same class of bug as the
# 2026-07-24 filename-parser fix in validate_integrity.py. Accept both.
_CHILD_PREFIXES = ("child_", "victim_")


def coverage(files):
    """(has_root_telem, has_root_arrivals, child_telem_count) for a cell's
    files — a complete run has root telem+arrivals and >=3 child telems."""
    root_telem = any(f.startswith("root_") and f.endswith("_telem.csv")
                     for f in files)
    root_arr = any(f.startswith("root_") and f.endswith("_arrivals.csv")
                   for f in files)
    vic = sum(1 for f in files
              if f.startswith(_CHILD_PREFIXES) and f.endswith("_telem.csv"))
    return root_telem, root_arr, vic


def validate_cell(outdir, topo, attack, location, sample_interval_ms, scenario="none"):
    """Run validate_integrity.py against the cell's folder. Returns (ok, output).

    Prefers the `trimmed\\` subfolder when it exists. That folder — not the raw
    one — is what the analysis actually consumes, and the raw files still carry
    the flash-session and export-session rows by design, so validating raw
    reports timestamp regressions as FAIL for every board. (validate_integrity
    also recurses, so pointing at the parent validated raw AND trimmed together:
    14 files for a 7-file run, 6 of them failing.)
    """
    folder = cell_dir(outdir, topo, attack, location, scenario)
    trimmed = os.path.join(folder, "trimmed")
    if os.path.isdir(trimmed):
        folder = trimmed
    cmd = [sys.executable, os.path.join(_THIS_DIR, "validate_integrity.py"), folder]
    if sample_interval_ms is not None:
        cmd += ["--sample-interval-ms", str(sample_interval_ms)]
    # BOTH halves of this are needed to echo validate_integrity.py's output
    # without mojibake, and fixing only one leaves it broken:
    #   * the CHILD picks its stdout encoding from the locale (cp1252 here) as
    #     soon as stdout is a pipe rather than a console, so it emits an em-dash
    #     as b'\x97'. PYTHONIOENCODING forces UTF-8 regardless.
    #   * the PARENT with text=True alone decodes using that same locale
    #     codepage, so encoding= has to match what the child now sends.
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    try:
        res = subprocess.run(cmd, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", env=env)
    except OSError as e:
        return False, f"(could not run validate_integrity.py: {e})"
    return res.returncode == 0, (res.stdout or "") + (res.stderr or "")


# ── Views ───────────────────────────────────────────────────────────────────
def scan_unrecorded(outdir, location, repeats, scenario="none"):
    """Cells whose CSVs are on disk and complete, but which are NOT ticked off.

    Exists because the failure is silent and easy: the repeat number lives in
    THREE places (root -Repeat, export --repeat, record --repeat) and getting
    the last one wrong records the previous repeat again. The captures sit on
    disk looking finished while the matrix still says pending, and nothing
    complains. Verified on 2026-07-26: r2 was exported and trimmed, then
    `--record ... --repeat 1` re-recorded r1 and the grid stayed at 1/24.
    """
    ledger = load_ledger(outdir)
    found = []
    for topo, atk, loc, scn, rep in all_cells(location, repeats, scenario):
        if ledger.get((topo, atk, loc, scn, rep), {}).get("status") == "done":
            continue
        files = find_files(outdir, topo, atk, loc, rep, scn)
        if not files:
            continue
        root_t, root_a, vic = coverage(files)
        complete = root_t and root_a and vic >= 3
        found.append((topo, atk, loc, scn, rep, len(files), complete))
    return found


def print_status(outdir, location, repeats, scenario="none", show_unrecorded=True):
    rows = load_ledger(outdir)
    done = 0
    total = 0
    print(f"Experiment matrix  location={location}  scenario={scenario}  "
          f"(repeats target = {repeats})   [x]=done  [ ]=pending\n")
    header = "topology  attack     " + "  ".join(f"r{r}" for r in range(1, repeats + 1))
    print(header)
    print("-" * len(header))
    for topo in TOPOLOGIES:
        for atk in ATTACKS:
            cells = []
            for rep in range(1, repeats + 1):
                total += 1
                st = rows.get((topo, atk, location, scenario, rep), {}).get("status")
                if st == "done":
                    done += 1
                    cells.append("[x]")
                else:
                    cells.append("[ ]")
            print(f"{topo:<9} {atk:<10} " + "  ".join(cells))
    print(f"\nProgress: {done}/{total} runs collected at {location}/{scenario} "
          f"(Milestone-4 minimum is 24 PER SITE PER SCENARIO).")
    for cell in all_cells(location, repeats, scenario):
        if rows.get(cell, {}).get("status") != "done":
            print(f"Next pending: topology={cell[0]} attack={cell[1]} "
                  f"location={cell[2]} scenario={cell[3]} repeat={cell[4]}   "
                  f"(--cmds to see its command block)")
            break
    else:
        print(f"All planned runs collected at {location}/{scenario}. [done]")

    if not show_unrecorded:
        return
    pending = scan_unrecorded(outdir, location, repeats, scenario)
    if not pending:
        return
    print("\n" + "!" * 62)
    print("  CAPTURED BUT NOT RECORDED — data is on disk, matrix says pending:")
    for topo, atk, loc, scn, rep, n, complete in pending:
        tag = f"{n} file(s)" if complete else f"{n} file(s), INCOMPLETE"
        print(f"    {topo}/{atk}/{loc}/{scn}/r{rep}   {tag}")
    print()
    print("  Usually the --repeat number on --record did not match the one you")
    print("  exported with. Record them all in one go:")
    print(f"      python run_matrix.py --location {location} --scenario {scenario} --autorecord")
    print("!" * 62)


def _untrimmed(outdir, topo, attack, location, files, scenario="none"):
    """Of this cell's raw captures, which are absent from trimmed/.

    The analysis pipeline and the validator both read trimmed/, so a capture that
    never got trimmed is invisible to every downstream stage even though its raw
    file sits right there in the cell folder.
    """
    trimmed = os.path.join(cell_dir(outdir, topo, attack, location, scenario), "trimmed")
    if not os.path.isdir(trimmed):
        return list(files)
    present = {os.path.basename(p)
               for p in glob.glob(os.path.join(trimmed, "*.csv"))}
    return [f for f in files if f not in present]


def record(outdir, topo, attack, location, rep, do_validate, sample_interval_ms,
           scenario="none", scenario_target=""):
    files = find_files(outdir, topo, attack, location, rep, scenario)
    if not files:
        print(f"(!) No exported CSVs found for {topo}/{attack}/{location}/{scenario}/r{rep} under "
              f"{cell_dir(outdir, topo, attack, location, scenario)}.\n"
              f"    Run the cell first (--cmds), or export it (--export-cmds), "
              f"then re-run --record.")
        return 1

    root_t, root_a, vic = coverage(files)
    if not (root_t and root_a and vic >= 3):
        print(f"(!) Incomplete capture for {topo}/{attack}/{location}/{scenario}/r{rep}: "
              f"root_telem={root_t} root_arrivals={root_a} victim_telems={vic} "
              f"(expected root telem+arrivals and >=3 victim telems).")
        print(f"    Found {len(files)} file(s): " + ", ".join(files))
        print("    Fix the missing board(s), or pass --allow-incomplete to "
              "record anyway.")
        if not getattr(record, "_allow_incomplete", False):
            return 1

    if do_validate:
        # validate_cell() validates the whole trimmed/ FOLDER, not this cell. If the
        # cell was exported but never trimmed, that folder holds some OTHER repeat --
        # which passes, and the cell gets marked done while its own data was never
        # checked and is absent from the analysis input.
        #
        # Seen on star/blackhole/r2 (2026-07-27): raw had r1+r2 (14 files), trimmed
        # had r1 only (7). --autorecord validated r1's arrivals file, printed
        # "7 PASS / 0 FAIL", and recorded r2.
        missing = _untrimmed(outdir, topo, attack, location, files, scenario)
        if missing:
            print(f"(!) {len(missing)} file(s) for {topo}/{attack}/{location}/{scenario}/r{rep} "
                  f"are NOT in trimmed/ — validation would check a different repeat's data:")
            for fn in sorted(missing)[:8]:
                print(f"      {fn}")
            print(f"    Run:  python tools\\trim_run.py "
                  f"{cell_dir(outdir, topo, attack, location, scenario)} --apply")
            print("    then re-run this command.")
            return 1

        ok, out = validate_cell(outdir, topo, attack, location, sample_interval_ms, scenario)
        tail = out.strip().splitlines()[-6:] if out.strip() else []
        for ln in tail:
            print("   " + ln)
        if not ok:
            print(f"(!) integrity validation FAILED for {topo}/{attack}/{location}/{scenario}/r{rep} "
                  f"- not marking done. Fix/re-capture, or --no-validate to "
                  f"force-record.")
            return 1

    rows = load_ledger(outdir)
    rows[(topo, attack, location, scenario, rep)] = {
        "topology": topo, "attack": attack, "location": location,
        "scenario": scenario, "scenario_target": scenario_target, "repeat": rep,
        "status": "done",
        "recorded_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "files": ";".join(files),
    }
    save_ledger(outdir, rows)
    verdict = "validated + recorded" if do_validate else "recorded (unvalidated)"
    print(f"{verdict}: {topo}/{attack}/{location}/{scenario}/r{rep} - {len(files)} file(s):")
    for fn in files:
        print(f"  - {fn}")
    return 0


# ── Main ────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Milestone-4 experiment-matrix driver.")
    # Resolve the default RELATIVE TO THIS SCRIPT, not to the shell's CWD.
    # The runbooks invoke this as `python tools\run_matrix.py ...` from the repo
    # root, where a bare "exports" points at a non-existent .\exports\ and the
    # tool reports "No exported CSVs found" for a cell that is fully captured.
    # An explicit --outdir still overrides this.
    ap.add_argument("--outdir", default=os.path.join(_THIS_DIR, "exports"),
                    help="Where CSVs and the ledger live "
                         "(default: the exports/ folder next to this script).")
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
    ap.add_argument("--autorecord", action="store_true",
                    help="Scan exports/ for captures that are complete but not "
                         "yet ticked off, validate and record each one. Use "
                         "this instead of remembering --topology/--attack/"
                         "--repeat by hand.")
    ap.add_argument("--record", action="store_true",
                    help="Validate a cell's CSVs and mark it done "
                         "(needs --topology --attack; --repeat optional).")

    ap.add_argument("--topology", choices=TOPOLOGIES)
    ap.add_argument("--attack", choices=ATTACKS)
    ap.add_argument("--location", choices=LOCATIONS,
                    help="Deployment site for this WHOLE campaign — the 6 boards "
                         "don't move mid-matrix, so this applies to every cell in "
                         "the run, not just one. Required for every mode below "
                         "except plain --plan.")
    ap.add_argument("--scenario", choices=SCENARIOS, default="none",
                    help="Run scenario for this WHOLE campaign (run.ps1 -Scenario) "
                         "— like --location, one value applies to every cell, not "
                         "an extra axis auto-crossed with topology/attack/repeat. "
                         "Defaults to 'none' (today's behaviour).")
    ap.add_argument("--scenario-target", choices=SCENARIO_TARGETS, default="control",
                    help="With --scenario burst/mobility/powercycle: which fixed-"
                         "table board carries it. 'control' works for both "
                         "blackhole and wormhole; 'nodeb' is blackhole-only "
                         "(wormhole's Node B can't carry a burst).")
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

    # burst/mobility/powercycle need a target board; wormhole's Node B can't
    # carry a burst (only victim_main.c-based boards can — see mesh_config.h
    # TRAFFIC_PROFILE_BURST), so reject that one invalid combination up front
    # rather than silently emitting a no-op -ScenarioTarget.
    needs_target = args.scenario in ("burst", "mobility", "powercycle")
    scenario_target = args.scenario_target if needs_target else ""
    if needs_target and args.scenario == "burst" and args.attack == "wormhole" \
            and args.scenario_target == "nodeb":
        ap.error("--scenario burst --scenario-target nodeb is invalid with "
                 "--attack wormhole (Node B builds wormhole_victim.c, not "
                 "victim_main.c) — use --scenario-target control instead.")

    if args.plan:
        # No disk/ledger I/O here, so this is the one mode that works without a
        # site — it just enumerates the theoretical matrix. Print the location
        # only when the caller gave one, so a bare --plan output doesn't lie.
        loc_label = args.location or "<location>"
        for cell in all_cells(loc_label, args.repeats, args.scenario):
            print(f"{cell[0]:<9} {cell[1]:<10} {cell[2]:<14} {cell[3]:<11} r{cell[4]}")
        return 0

    # Every other mode touches the ledger and/or the exports/ tree for one
    # specific site (the 6 boards don't move mid-campaign) — require it
    # explicitly rather than defaulting/guessing (thesis panel P4: environment
    # must be RECORDED, never inferred).
    if not args.location:
        ap.error("--location is required (home | G402 | DLSU_Library | Goks) "
                 "for every mode except --plan.")

    if args.next:
        rows = load_ledger(args.outdir)
        for cell in all_cells(args.location, args.repeats, args.scenario):
            if rows.get(cell, {}).get("status") != "done":
                print_cmds(cell[0], cell[1], cell[2], cell[4], ports,
                           export=not args.dry_run, scenario=cell[3],
                           scenario_target=scenario_target)
                return 0
        print(f"All planned runs collected at {args.location}/{args.scenario}. [done]")
        return 0

    if args.cmds:
        if not (args.topology and args.attack):
            ap.error("--cmds needs --topology and --attack")
        print_cmds(args.topology, args.attack, args.location, args.repeat, ports,
                   export=not args.dry_run, scenario=args.scenario,
                   scenario_target=scenario_target)
        return 0

    if args.export_cmds:
        if not (args.topology and args.attack):
            ap.error("--export-cmds needs --topology and --attack")
        print_export_cmds(args.topology, args.attack, args.location, args.repeat, ports,
                          scenario=args.scenario)
        return 0

    if args.autorecord:
        # record() reads this off itself (see its coverage check); the single
        # --record path sets it the same way further down.
        record._allow_incomplete = args.allow_incomplete
        pending = scan_unrecorded(args.outdir, args.location, args.repeats, args.scenario)
        if not pending:
            print("Nothing to record — every capture on disk is already ticked "
                  "off.")
            print_status(args.outdir, args.location, args.repeats, args.scenario, show_unrecorded=False)
            return 0
        print(f"Found {len(pending)} unrecorded capture(s) on disk.\n")
        failed = 0
        for topo, atk, loc, scn, rep, _n, complete in pending:
            if not complete and not args.allow_incomplete:
                print(f"[SKIP] {topo}/{atk}/{loc}/{scn}/r{rep} — incomplete "
                      f"(--allow-incomplete to force)\n")
                failed += 1
                continue
            print(f"--- {topo}/{atk}/{loc}/{scn}/r{rep}")
            rc = record(args.outdir, topo, atk, loc, rep,
                        do_validate=not args.no_validate,
                        sample_interval_ms=args.sample_interval_ms,
                        scenario=scn, scenario_target=scenario_target)
            if rc:
                failed += 1
            print()
        print_status(args.outdir, args.location, args.repeats, args.scenario, show_unrecorded=False)
        return 1 if failed else 0

    if args.record:
        if not (args.topology and args.attack):
            ap.error("--record needs --topology and --attack (and --repeat)")
        record._allow_incomplete = args.allow_incomplete
        return record(args.outdir, args.topology, args.attack, args.location, args.repeat,
                      do_validate=not args.no_validate,
                      sample_interval_ms=args.sample_interval_ms,
                      scenario=args.scenario, scenario_target=scenario_target)

    # Default view.
    print_status(args.outdir, args.location, args.repeats, args.scenario)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
