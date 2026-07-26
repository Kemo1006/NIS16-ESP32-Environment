#!/usr/bin/env python3
"""
trim_run.py — keep only the EXPERIMENT RUN from an exported telemetry CSV.

WHY THIS EXISTS
───────────────
The firmware logs to a single fixed file, /spiffs/telem.csv, opened in APPEND
mode (components/mesh_common/src/csv_logger.c). A board therefore keeps adding
to the same file across every boot, and the rows carry no run-id column. One
exported CSV can hold several boot sessions:

  * Phase 2  — the board logs for ~30 s while you flash and watch it.
  * THE RUN  — the real experiment, ending at the root's TERMINATE broadcast.
  * Export   — plugging the board into USB power-cycles it; it boots, starts
               logging again, and (with no root broadcasting phases) never
               receives a terminate, so it logs until you unplug it. Those rows
               are stamped layer=-1 (disconnected) and gt_label=0 (benign).

Those extra sessions are not cosmetic. They break the two validators and the
preprocessing pipeline:

  * verify_topology.py reports each node's FINAL layer — the last value in the
    file — so a trailing disconnected session makes a perfect chain report as
    "layer histogram {-1: 5, 1: 1}" and WARN instead of PASS.
  * validate_integrity.py FAILs on the timestamp regression at each reboot.
  * preprocess.py assumes "one file = one run for one node" (see its
    handle_missing_values docstring). Sessions restart t_rel at 0, so a
    trailing session COLLIDES with the run's opening seconds on the synthetic
    1 Hz grid, and the dedup step may keep the disconnected sample instead of
    the real one.

HOW IT DECIDES WHAT THE RUN IS
──────────────────────────────
esp_timer_get_time() resets to ~0 on every boot, so a timestamp going BACKWARDS
is an unambiguous session boundary. We split there and keep the LONGEST
segment. For a real capture the experiment (~8-11 min) dwarfs a flash-monitor
session (~30 s) and an export session (seconds to a couple of minutes), so
"longest" is a safe proxy for "the run". The report prints every segment so you
can confirm that before trusting it.

SAFETY
──────
Raw captures are irreplaceable — the boards get wiped for the next run. So:
  * default is a DRY RUN: it reports and writes nothing.
  * --apply writes trimmed COPIES into a separate folder (originals untouched).
  * --in-place overwrites, but only after saving <name>.orig next to each file.

USAGE
─────
    cd tools
    python trim_run.py exports/baseline/linear_topology                 # report
    python trim_run.py exports/baseline/linear_topology --apply         # -> .../trimmed/
    python trim_run.py exports/baseline/linear_topology --apply --in-place
    python trim_run.py --files a_telem.csv b_arrivals.csv --apply

Works on both telem.csv and arrivals.csv (both start with timestamp_us).

MIXED-SCHEMA CAPTURES
─────────────────────
An export can occasionally contain TWO different streams concatenated: a full
copy of telem.csv followed by the real arrivals stream, each introduced by its
own "timestamp_us,..." header line. (Seen on the 20260725_233820 root export —
if the END_OF_FILE marker of an EXPORT_LOGS stream is corrupted, export_logs.py
keeps capturing and splices the next stream onto the same file.)

That is lethal here if unhandled: the telemetry copy is the LONGER block, so
"keep the longest segment" keeps the telemetry and silently discards every
probe-arrival row — the trimmed arrivals file comes out byte-identical to the
trimmed telem file, and features.py dies later with `KeyError: 'src_mac'`.

So before segmenting by boot session, we split the file into SCHEMA BLOCKS at
each embedded header line and keep only the block(s) whose schema matches what
the filename says the file is (arrivals = has src_mac; telem = has not).
"""

from __future__ import annotations

import argparse
import glob
import os
import shutil
import sys

TS_COL = 0  # timestamp_us is the first column in both schemas
HEADER_TOKEN = "timestamp_us"
ARRIVALS_MARKER = "src_mac"  # only the probe-arrival schema carries this column


def _is_arrivals_header(header: str) -> bool:
    return ARRIVALS_MARKER in header


def _wanted_schema_is_arrivals(path: str) -> bool:
    """What the FILENAME says this file is meant to hold."""
    return os.path.basename(path).endswith("_arrivals.csv")


def _read(path):
    """Return (header_line, [(ts, raw_line), ...], n_skipped, schema_note).

    Splits the file into schema blocks at every embedded header line and keeps
    only the block(s) matching the filename's schema — see MIXED-SCHEMA
    CAPTURES in the module docstring. schema_note is None for an ordinary
    single-schema file, or a human-readable string describing what was
    separated out, for the report.
    """
    with open(path, "r", newline="", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    if not lines:
        return None, [], 0, None

    # ── Split into blocks: [(header, [(ts, raw), ...], n_skipped), ...] ──
    blocks, skipped = [], 0
    cur_header, cur_rows = None, []
    for ln in lines:
        if not ln.strip():
            continue
        if ln.startswith(HEADER_TOKEN):
            if cur_header is not None:
                blocks.append((cur_header, cur_rows))
            cur_header, cur_rows = ln, []
            continue
        if cur_header is None:
            # Data before any header — malformed capture; count as unparsable
            # rather than guessing a schema for it.
            skipped += 1
            continue
        first = ln.split(",", 1)[0].strip()
        try:
            cur_rows.append((int(first), ln))
        except ValueError:
            # ESP-IDF log noise or a torn line — keep it out of the timeline,
            # but count it so the report is honest about what was dropped.
            skipped += 1
    if cur_header is not None:
        blocks.append((cur_header, cur_rows))

    if not blocks:
        return None, [], skipped, None

    if len(blocks) == 1:
        return blocks[0][0], blocks[0][1], skipped, None

    # ── Mixed schema: keep only the blocks this filename asks for ──
    want_arrivals = _wanted_schema_is_arrivals(path)
    keep = [b for b in blocks if _is_arrivals_header(b[0]) == want_arrivals]
    drop = [b for b in blocks if _is_arrivals_header(b[0]) != want_arrivals]

    if not keep:
        # The file contains none of the schema its name promises. Do NOT
        # silently emit the wrong stream under the right name — that is exactly
        # the failure this guard exists to stop. Refuse the file instead.
        kinds = ", ".join("arrivals" if _is_arrivals_header(h) else "telem"
                          for h, _ in blocks)
        note = (f"SCHEMA MISMATCH: name says "
                f"{'arrivals' if want_arrivals else 'telem'}, file holds only "
                f"[{kinds}] — refusing to trim")
        return None, [], skipped, note

    dropped_rows = sum(len(r) for _, r in drop)
    kind = "arrivals" if want_arrivals else "telem"
    if not drop:
        # Every block is the schema we want — this is the SAME file streamed
        # more than once into one capture (a lost END_OF_FILE makes the host
        # keep reading, so the device's re-send lands in the same file). No
        # schema separation needed; the boot-session split below drops the
        # repeats, since a re-read restarts at the run's first timestamp.
        note = (f"repeated capture: {len(blocks)} header block(s), all {kind} "
                f"schema — the export streamed this file "
                f"{len(blocks)}x. Nothing separated; the session split below "
                f"picks the real run.")
    else:
        note = (f"mixed capture: {len(blocks)} schema block(s); kept "
                f"{kind} schema ({sum(len(r) for _, r in keep)} rows), "
                f"separated out {dropped_rows} row(s) of the other schema")
    body = [row for _, rows in keep for row in rows]
    return keep[0][0], body, skipped, note


def _segments(body):
    """Split at every backwards jump in timestamp. Returns [(start, end)]."""
    cuts = [0]
    for i in range(len(body) - 1):
        if body[i + 1][0] < body[i][0]:
            cuts.append(i + 1)
    cuts.append(len(body))
    return [(cuts[i], cuts[i + 1]) for i in range(len(cuts) - 1)]


def process(path, apply_changes, in_place, out_dir):
    header, body, skipped, schema_note = _read(path)
    name = os.path.basename(path)
    if header is None or not body:
        print(f"  [SKIP] {name}: {schema_note or 'empty or unreadable'}")
        return None

    segs = _segments(body)
    best = max(segs, key=lambda ab: ab[1] - ab[0])

    print(f"  {name}")
    if schema_note:
        print(f"      [!] {schema_note}")
    print(f"      {len(body)} data rows, {len(segs)} boot session(s)"
          + (f", {skipped} unparsable line(s) dropped" if skipped else ""))
    for i, (a, b) in enumerate(segs):
        span = (body[b - 1][0] - body[a][0]) / 1e6
        tag = "  <-- KEEPING (longest)" if (a, b) == best else ""
        print(f"        session {i+1}: rows {b-a:>6}  span {span:>8.1f}s{tag}")

    a, b = best
    dropped = len(body) - (b - a)
    # A single-session file still needs rewriting if the schema split removed
    # foreign rows — otherwise a stale (or wrong-schema) trimmed copy survives.
    if len(segs) == 1 and schema_note is None:
        if apply_changes and not in_place:
            # COPY IT ANYWAY. The trimmed/ folder is the analysis input, so it
            # has to be COMPLETE — preprocess.py and features.py glob it, not
            # the raw folder. A clean single-session file that never got copied
            # silently leaves the run short a board; when that file is the
            # root's *_arrivals.csv it takes PDR, LatencyHopRatio and
            # TunnelLatency down with it and features.py just reports NaN.
            os.makedirs(out_dir, exist_ok=True)
            target = os.path.join(out_dir, name)
            shutil.copy2(path, target)
            print(f"      single session — copied unchanged -> "
                  f"{os.path.relpath(target)}")
            return {"file": name, "kept": b - a, "dropped": 0,
                    "changed": False, "copied": True}
        print("      already a single session — nothing to trim")
        return {"file": name, "kept": b - a, "dropped": 0, "changed": False}

    if not apply_changes:
        print(f"      would drop {dropped} row(s)   [dry run — use --apply]")
        return {"file": name, "kept": b - a, "dropped": dropped, "changed": False}

    if in_place:
        backup = path + ".orig"
        if not os.path.exists(backup):
            shutil.copy2(path, backup)
        target = path
    else:
        os.makedirs(out_dir, exist_ok=True)
        target = os.path.join(out_dir, name)

    with open(target, "w", newline="", encoding="utf-8") as f:
        f.write(header if header.endswith("\n") else header + "\n")
        for _, raw in body[a:b]:
            f.write(raw if raw.endswith("\n") else raw + "\n")

    where = "in place (.orig saved)" if in_place else os.path.relpath(target)
    print(f"      wrote {b - a} row(s), dropped {dropped} -> {where}")
    return {"file": name, "kept": b - a, "dropped": dropped, "changed": True}


def main():
    p = argparse.ArgumentParser(
        description="Keep only the experiment run from exported telemetry CSVs.")
    p.add_argument("directory", nargs="?",
                   help="Folder of exported CSVs (e.g. exports/baseline/linear_topology)")
    p.add_argument("--files", nargs="*", help="Explicit CSVs instead of a folder.")
    p.add_argument("--apply", action="store_true",
                   help="Actually write output. Without this it is a dry run.")
    p.add_argument("--in-place", action="store_true",
                   help="Overwrite originals (a <name>.orig backup is saved first).")
    p.add_argument("--out",
                   help="Output folder for --apply (default: <directory>/trimmed).")
    args = p.parse_args()

    if args.files:
        paths = []
        for pat in args.files:
            paths.extend(glob.glob(pat))
    elif args.directory:
        paths = sorted(glob.glob(os.path.join(args.directory, "*.csv")))
    else:
        p.error("give a directory or --files")

    paths = [q for q in paths if not q.endswith(".orig")]
    if not paths:
        print("No CSVs found.")
        return 1

    out_dir = args.out or (os.path.join(args.directory, "trimmed")
                           if args.directory else "trimmed")

    print(f"{'APPLYING' if args.apply else 'DRY RUN'} — {len(paths)} file(s)\n")
    results = [r for r in (process(q, args.apply, args.in_place, out_dir)
                           for q in paths) if r]

    tot_kept = sum(r["kept"] for r in results)
    tot_drop = sum(r["dropped"] for r in results)
    changed = sum(1 for r in results if r["changed"])
    copied = sum(1 for r in results if r.get("copied"))
    # ASCII only: Windows consoles default to cp1252 and cannot encode box-drawing
    # characters, which would crash the summary after the work is already done.
    print("\n" + "-" * 60)
    print(f"  files            : {len(results)}")
    print(f"  rows kept        : {tot_kept}")
    print(f"  rows dropped     : {tot_drop}")
    if args.apply:
        print(f"  files rewritten  : {changed}")
        if not args.in_place:
            print(f"  files copied as-is: {copied}")
            print(f"  files in output  : {changed + copied} of {len(results)}")
            print(f"  output folder    : {os.path.abspath(out_dir)}")
            print("  NOTE: point preprocess.py / features.py at that folder —")
            print("        it is the COMPLETE analysis input (trimmed files plus")
            print("        untouched copies of anything that needed no trimming).")
    if not args.in_place:
        _warn_on_stale_outputs(paths, out_dir)
    if not args.apply:
        print("  (dry run — nothing written. Re-run with --apply)")
    return 0


def _warn_on_stale_outputs(source_paths, out_dir):
    """Flag files sitting in trimmed/ whose raw source no longer exists.

    This folder is written but never cleaned, so anything deleted or renamed
    upstream leaves its trimmed copy behind — and every analysis tool reads the
    FOLDER, not a file list, so the orphan is silently picked up.

    Cost of not saying it, from star/wormhole/r1 (2026-07-26): a bad arrivals
    export was deleted from the raw folder and re-pulled correctly, but the bad
    trimmed copy stayed. features.py then loaded BOTH arrivals files and died on
    the stale one, after the re-export had already fixed the problem. The
    duplicate root telem in the same folder was quietly inflating the root's
    window count to 264 against ~155 for every other node.

    Warn rather than delete: this folder holds derived data, but it is one
    command away from being someone's only copy if a raw export went missing.
    """
    try:
        present = {os.path.basename(p) for p in glob.glob(os.path.join(out_dir, "*.csv"))}
    except OSError:
        return
    expected = {os.path.basename(p) for p in source_paths}
    stale = sorted(present - expected)
    if not stale:
        return
    print()
    print(f"  [!] {len(stale)} STALE file(s) in {os.path.abspath(out_dir)}")
    print("      — present in the output folder but with no matching raw source.")
    print("      Every analysis tool reads this folder, so these WILL be loaded:")
    for name in stale:
        print(f"        {name}")
    print("      Delete them, or re-trim into a clean folder, before analysing.")


if __name__ == "__main__":
    sys.exit(main())
