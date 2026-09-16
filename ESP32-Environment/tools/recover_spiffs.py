#!/usr/bin/env python3
"""
recover_spiffs.py — pull telemetry out of a board that can no longer read its own files.

WHY THIS EXISTS
───────────────
When SPIFFS fills up (or its garbage collection thrashes), the ESP32 stops being
able to READ its own telem.csv even though the data is physically intact on the
flash. The symptom from export_logs.py is unmistakable:

    -> EXPORT_LOGS ...
       [####################] 100.0%  0 B/1.1 MB  0 rows  0 B/s
       FAILED: device announced 1.1 MB then sent END_OF_FILE with 0 rows

The size is right (ftell worked) but not a single row comes out (fgets returned
NULL on the first call). Power-cycling does not help — the fault is in the
filesystem, not in a stuck file handle. See esp32-issues I-016/I-017, where the
same exhaustion starved sampling to 0.75 Hz and produced corrupt lines.

DELETE_LOGS would fix the board — by formatting the partition, destroying the
run. This script gets the data off FIRST.

HOW IT WORKS
────────────
esptool reads the raw `spiffs` partition straight off the flash chip, bypassing
the ESP32's filesystem code completely. Telemetry rows are plain ASCII, so they
survive in the dump; we scan for anything shaped like a valid CSV row, validate
it against the real schema, de-duplicate, and sort by timestamp.

SPIFFS interleaves page metadata every ~256 bytes, so a minority of rows are
split or have bytes injected mid-line. Those fail validation and are counted as
unrecoverable rather than being written out corrupt — a malformed row silently
entering the dataset is worse than a missing one.

USAGE
─────
    cd tools

    # one step: dump the flash and extract (board must be on a COM port)
    python recover_spiffs.py --port COM20 -o recovered_node5_telem.csv

    # or, if you already have a dump
    python recover_spiffs.py --dump node5_spiffs.bin -o recovered_node5_telem.csv

    # arrivals schema instead of telemetry (root boards)
    python recover_spiffs.py --port COM20 --kind arrivals -o recovered_arrivals.csv

The recovered CSV goes through trim_run.py / preprocess.py exactly like a normal
export. Treat the row count as a floor, not a guarantee — check the report.

NIS16 — CTTHES2 — data recovery
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(_THIS_DIR)

TELEM_HEADER = ("timestamp_us,node_id,role,layer,parent_mac,rssi_dbm,"
                "retry_count,tx_count,probes_count,phase_id,gt_label")
ARRIVALS_HEADER = ("timestamp_us,node_id,role,layer,parent_mac,rssi_dbm,"
                   "retry_count,tx_count,probes_received,phase_id,gt_label,"
                   "src_mac,seq_num,latency_us")

SCHEMA = {
    "telem": {"header": TELEM_HEADER, "fields": 11},
    "arrivals": {"header": ARRIVALS_HEADER, "fields": 14},
}

# A row as the firmware writes it (csv_logger.c):
#   <int>,NODE_<12 hex>,<role>,<int>,<MAC>,<int>,<uint>,<uint>,<uint>,<u8>,<u8>
# Roles seen in real captures: root, victim, blackhole, wormhole_a, wormhole_b.
ROW_RE = re.compile(
    r"^(?P<ts>\d{1,12}),"
    r"NODE_[0-9A-Fa-f]{12},"
    r"[a-z_]{3,12},"
    r"-?\d{1,2},"
    r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2},"
    r"-?\d{1,3},"
    r"\d{1,10},\d{1,10},\d{1,10},"
    r"\d{1,3},\d{1,3}"
    r"(?P<tail>(?:,(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2},\d{1,10},-?\d{1,15})?)$"
)


def read_partition_table():
    """(offset, size) of the spiffs partition, from the project's own table."""
    path = os.path.join(_REPO_ROOT, "partitions.csv")
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.lstrip().startswith("#") or not line.strip():
                continue
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 5 and parts[0] == "spiffs":
                return int(parts[3], 16), int(parts[4], 16)
    raise SystemExit(f"No 'spiffs' row found in {path}")


def dump_flash(port, offset, size, out_path, baud):
    """esptool read_flash — talks to the bootloader, not to SPIFFS."""
    cmd = [sys.executable, "-m", "esptool", "--port", port, "--baud", str(baud),
           "read_flash", hex(offset), hex(size), out_path]
    print(f"-> dumping {size // 1024} KB from {hex(offset)} at {baud} baud")
    print("   (this reads the raw flash; the board's filesystem is not involved)")
    print("   " + " ".join(cmd[2:]))
    try:
        rc = subprocess.call(cmd)
    except FileNotFoundError:
        raise SystemExit("esptool not found. Run from the ESP-IDF shell, or: "
                         "pip install esptool")
    if rc != 0:
        raise SystemExit(
            f"esptool failed (exit {rc}). Close any serial monitor holding "
            f"{port} and retry; hold BOOT if it will not connect.")
    return out_path


def extract_rows(blob, kind):
    """Return (rows, stats). Only rows that validate against the schema.

    THE RULE THAT KEEPS THIS HONEST: a row is accepted only if it is a run of
    bytes delimited by \\n ON BOTH SIDES in the raw flash, containing nothing
    but printable ASCII.

    That matters more than it looks. The obvious implementation — strip the
    binary page metadata, then split the remaining text on newlines — FABRICATES
    ROWS. Stripping the metadata welds the tail of the row before the page
    boundary onto the head of the row after it, and the splice frequently passes
    a field-by-field regex while being data that never existed. Measured on a
    real 7,303-row capture with page headers injected: 303 invented rows, none
    of them flagged.

    Scanning between newlines in the ORIGINAL bytes makes that impossible — a
    row straddling a page header contains the header bytes, fails the
    printable-ASCII test, and is dropped. We lose the straddling rows (about one
    per page) and gain the guarantee that every row written out is a row the
    board actually logged.
    """
    want_fields = SCHEMA[kind]["fields"]

    seen, rows = set(), []
    considered = rejected = straddled = 0

    for raw in blob.split(b"\n"):
        raw = raw.rstrip(b"\r")
        if not raw or raw.startswith(b"timestamp_us"):
            continue
        # Any non-printable byte means this segment crosses page metadata (or
        # erased 0xFF flash), so it is a fragment — never a whole row.
        if not all(0x20 <= b <= 0x7E for b in raw):
            straddled += 1
            continue
        piece = raw.decode("ascii")
        if "," not in piece:
            continue
        considered += 1
        m = ROW_RE.match(piece)
        if not m or piece.count(",") + 1 != want_fields:
            rejected += 1
            continue
        if piece in seen:
            continue
        seen.add(piece)
        rows.append((int(m.group("ts")), piece))

    rows.sort(key=lambda r: r[0])
    return [r[1] for r in rows], {
        "considered": considered,
        "rejected": rejected,
        "straddled": straddled,
    }


def main():
    ap = argparse.ArgumentParser(
        description="Recover telemetry from a board whose SPIFFS can no longer "
                    "be read by the firmware.")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--port", help="Serial port, e.g. COM20 (dumps the flash)")
    src.add_argument("--dump", help="An existing raw partition dump to parse")
    ap.add_argument("-o", "--output", required=True, help="Recovered CSV path")
    ap.add_argument("--kind", choices=["telem", "arrivals"], default="telem",
                    help="Which schema to recover (default: telem)")
    ap.add_argument("--baud", type=int, default=460800,
                    help="esptool baud for the dump (default: 460800)")
    ap.add_argument("--keep-dump", action="store_true",
                    help="Keep the raw .bin next to the output CSV")
    args = ap.parse_args()

    offset, size = read_partition_table()

    if args.port:
        dump_path = os.path.splitext(args.output)[0] + "_spiffs.bin"
        dump_flash(args.port, offset, size, dump_path, args.baud)
    else:
        dump_path = args.dump
        if not os.path.isfile(dump_path):
            raise SystemExit(f"No such dump: {dump_path}")

    with open(dump_path, "rb") as f:
        blob = f.read()
    print(f"-> scanning {len(blob) // 1024} KB for {args.kind} rows ...")

    rows, stats = extract_rows(blob, args.kind)

    if not rows:
        print("\n  NOTHING RECOVERED. Either the partition was already "
              "formatted, or this is the wrong --kind for this board.",
              file=sys.stderr)
        return 1

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        f.write(SCHEMA[args.kind]["header"] + "\n")
        for r in rows:
            f.write(r + "\n")

    span = (int(rows[-1].split(",", 1)[0]) - int(rows[0].split(",", 1)[0])) / 1e6
    print("\n" + "-" * 62)
    print(f"  rows recovered   : {len(rows)}")
    print(f"  time span        : {span:.1f}s")
    print(f"  complete lines   : {stats['considered']}")
    print(f"  failed schema    : {stats['rejected']}")
    print(f"  straddled a page : {stats['straddled']} "
          f"(crossed SPIFFS metadata — dropped, never spliced)")
    print(f"  output           : {args.output}")
    if not args.keep_dump and args.port:
        os.remove(dump_path)
    elif args.port:
        print(f"  raw dump kept    : {dump_path}")
    print("-" * 62)
    print("  NEXT: treat this like any other export — trim_run.py, then M6-M8.")
    print("  The row count is a FLOOR. Check the span against your run length")
    print("  before trusting it as a complete capture.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
