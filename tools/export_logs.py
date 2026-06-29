#!/usr/bin/env python3
"""
export_logs.py — Pull CSV telemetry off an ESP32 node over USB serial.

This is the laptop-side counterpart to the on-device serial-export task in
components/mesh_common/src/csv_logger.c. After an experimental run finishes,
each ESP32 starts a task that listens on UART0 for these commands:

    EXPORT_LOGS      -> streams telem.csv     (all roles)
    EXPORT_ARRIVALS  -> streams arrivals.csv  (root only)
    LIST_FILES       -> lists stored file paths
    DELETE_LOGS      -> erases stored files

The device frames each file stream between two markers:

    READY_TO_SEND
    <csv header line>
    <csv data lines...>
    END_OF_FILE

This script connects to the given COM port, issues the command(s), captures
everything between those markers, strips any interleaved ESP-IDF log noise,
and writes a named CSV with run metadata baked into the filename.

NIS16 — CTTHES2 Milestone 1 — Raw Data Extraction

Usage examples
--------------
Pull the root node's telemetry AND probe-arrivals:
    python export_logs.py --port COM3 --role root \
        --topology star --attack none --repeat 1

Pull a victim node's telemetry:
    python export_logs.py --port COM6 --role victim \
        --topology star --attack none --repeat 1

Just see what's stored, don't download:
    python export_logs.py --port COM3 --list

Run this from inside the "ESP-IDF 5.3 PowerShell" window so `python` already
has pyserial available. (If running from a plain shell: pip install pyserial.)

IMPORTANT: close `idf.py monitor` first — it holds the COM port open and the
export task shares UART0 with the console, so only one program can read it.
"""

import argparse
import datetime as _dt
import os
import re
import sys
import time

try:
    import serial  # pyserial
except ImportError:
    sys.exit(
        "ERROR: pyserial is not installed.\n"
        "  Run this from the 'ESP-IDF 5.3 PowerShell' window, or:\n"
        "    pip install pyserial"
    )

BAUD = 115200          # must match SERIAL_BAUD in mesh_config.h
READ_TIMEOUT_S = 2.0   # per-line read timeout
OVERALL_TIMEOUT_S = 30 # give up on a stream after this long

# An ESP-IDF log line looks like: "I (12345) TAG: message"
_LOG_LINE = re.compile(r"^[IWEDV] \(\d+\)")

# A valid CSV row either starts with the header token or with a digit
# (timestamp_us is always numeric).
_CSV_HEADER_TOKEN = "timestamp_us"


def _looks_like_csv(line: str) -> bool:
    if not line:
        return False
    if _LOG_LINE.match(line):
        return False
    if line.startswith(_CSV_HEADER_TOKEN):
        return True
    return line[0].isdigit() and "," in line


def _drain(ser: serial.Serial) -> None:
    """Discard any bytes already sitting in the input buffer."""
    time.sleep(0.2)
    ser.reset_input_buffer()


def _send_command(ser: serial.Serial, command: str) -> None:
    ser.reset_input_buffer()
    ser.write((command + "\n").encode("ascii"))
    ser.flush()


def _capture_stream(ser: serial.Serial, command: str):
    """
    Send a command and capture the framed CSV between READY_TO_SEND and
    END_OF_FILE. Returns (lines, error_str). On success error_str is None.
    """
    _send_command(ser, command)

    started = False
    rows = []
    expected_cols = None   # field count locked in from the header row
    # Idle timeout: give up only after OVERALL_TIMEOUT_S of NO data. A large
    # telem.csv can take a while to stream; as long as bytes keep arriving we
    # keep going, so big files no longer trip a fixed total-time cap.
    deadline = time.time() + OVERALL_TIMEOUT_S

    while time.time() < deadline:
        raw = ser.readline()
        if not raw:
            continue
        deadline = time.time() + OVERALL_TIMEOUT_S  # got data — extend
        line = raw.decode("utf-8", errors="replace").strip()
        if not line:
            continue

        # Device-reported errors
        if line.startswith("ERROR:"):
            return [], line

        if line == "READY_TO_SEND":
            started = True
            continue
        if line == "END_OF_FILE":
            return rows, None

        if started and _looks_like_csv(line):
            ncols = line.count(",") + 1
            if line.startswith(_CSV_HEADER_TOKEN):
                expected_cols = ncols          # lock the schema width
                rows.append(line)
            elif expected_cols is None or ncols == expected_cols:
                rows.append(line)
            # else: a line whose field count doesn't match the header is
            # UART noise / a split line — drop it so a clean run captures
            # EVERYTHING valid and nothing garbled.

    return rows, "TIMEOUT: never saw END_OF_FILE"


def _list_files(ser: serial.Serial) -> None:
    _send_command(ser, "LIST_FILES")
    deadline = time.time() + 10
    print("Stored files on device:")
    while time.time() < deadline:
        raw = ser.readline()
        if not raw:
            continue
        line = raw.decode("utf-8", errors="replace").strip()
        if line == "END_LIST":
            return
        if line.startswith("FILE:"):
            print("   " + line[len("FILE:"):])


def _make_filename(args, kind: str) -> str:
    date = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    # e.g. root_COM3_star_none_r1_20260629_telem.csv
    safe_port = args.port.replace("/", "_").replace("\\", "_")
    name = (
        f"{args.role}_{safe_port}_{args.topology}_{args.attack}"
        f"_r{args.repeat}_{date}_{kind}.csv"
    )
    return os.path.join(args.outdir, name)


def _save(rows, path) -> int:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")
    return len(rows)


def main() -> int:
    p = argparse.ArgumentParser(
        description="Pull ESP32 telemetry CSVs over USB serial."
    )
    p.add_argument("--port", required=True, help="Serial port, e.g. COM3")
    p.add_argument(
        "--role",
        choices=["root", "victim"],
        default="victim",
        help="Node role. 'root' also pulls arrivals.csv.",
    )
    p.add_argument("--topology", default="unknown",
                   help="star | tree | linear | partial (for the filename)")
    p.add_argument("--attack", default="none",
                   help="none | blackhole | wormhole (for the filename)")
    p.add_argument("--repeat", default="1", help="Repeat number (for the filename)")
    p.add_argument("--outdir", default="exports", help="Output directory")
    p.add_argument("--list", action="store_true",
                   help="Only list stored files; download nothing.")
    p.add_argument("--delete", action="store_true",
                   help="After a successful download, erase logs on the device.")
    p.add_argument("--wipe", action="store_true",
                   help="Only erase logs on the device; download nothing. "
                        "Use before a clean run to clear stacked old data.")
    args = p.parse_args()

    try:
        # IMPORTANT: opening a serial port normally asserts DTR/RTS, which on an
        # ESP32 are wired to EN (reset) and GPIO0 (boot) — so a plain open would
        # REBOOT the board and kill the export task that's waiting for our
        # command. We deassert both lines BEFORE opening so the board keeps
        # running and stays in its post-run "export ready" state.
        ser = serial.Serial()
        ser.port = args.port
        ser.baudrate = BAUD
        ser.timeout = READ_TIMEOUT_S
        ser.dtr = False
        ser.rts = False
        ser.open()
    except serial.SerialException as e:
        print(f"ERROR: could not open {args.port}: {e}", file=sys.stderr)
        print("  Is idf.py monitor still open? Close it first.", file=sys.stderr)
        return 1

    with ser:
        _drain(ser)

        if args.list:
            _list_files(ser)
            return 0

        if args.wipe:
            print("-> DELETE_LOGS (wipe only) ...")
            _send_command(ser, "DELETE_LOGS")
            time.sleep(1.0)
            print("   wipe command sent. Device logs cleared.")
            return 0

        # Commands to run for this role
        jobs = [("EXPORT_LOGS", "telem")]
        if args.role == "root":
            jobs.append(("EXPORT_ARRIVALS", "arrivals"))

        any_failed = False
        for command, kind in jobs:
            print(f"-> {command} ...")
            rows, err = _capture_stream(ser, command)
            if err:
                print(f"   FAILED: {err}", file=sys.stderr)
                any_failed = True
                continue
            if not rows:
                print("   WARNING: stream was empty (0 rows).", file=sys.stderr)
            path = _make_filename(args, kind)
            n = _save(rows, path)
            data_rows = max(0, n - 1)  # minus header
            print(f"   saved {data_rows} data rows -> {path}")

        if args.delete and not any_failed:
            print("-> DELETE_LOGS ...")
            _send_command(ser, "DELETE_LOGS")
            time.sleep(1.0)
            print("   delete command sent.")

        return 1 if any_failed else 0


if __name__ == "__main__":
    sys.exit(main())
