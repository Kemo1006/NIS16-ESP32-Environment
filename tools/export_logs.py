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

Files are routed into  exports/<attack-or-baseline>/<topology>_topology/  so each
run's CSVs are grouped by attack then topology (e.g. exports/blackhole/star_topology/,
exports/baseline/tree_topology/). Pass --flat to write straight into exports/.

NIS16 — CTTHES2 Milestone 1 — Raw Data Extraction

Usage examples
--------------
Pull the root node's telemetry AND probe-arrivals (-> exports/blackhole/star_topology/):
    python export_logs.py --port COM3 --role root \
        --topology star --attack blackhole --repeat 1

Pull a victim node's telemetry (-> exports/baseline/tree_topology/):
    python export_logs.py --port COM6 --role child  \
        --topology tree --attack none --repeat 1

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

BAUD = 115200          # MUST match the firmware console baud
                       # (CONFIG_ESP_CONSOLE_UART_BAUDRATE in each project's
                       # sdkconfig). It is 115200 — a 460800 experiment was
                       # reverted because sdkconfig kept regenerating back to
                       # 115200, leaving export/wipe talking a baud the device
                       # wasn't listening on (garbage -> "never saw END_OF_FILE").
                       # See esp32-issues.md I-007. If you ever DO get a higher
                       # console baud to stick in sdkconfig, change this to match.
READ_TIMEOUT_S = 2.0   # per-line read timeout
OVERALL_TIMEOUT_S = 30 # give up on a stream after this long
POST_TOTAL_GRACE_S = 2.5  # once the device's announced byte total has fully
                       # arrived, wait only this long for the END_OF_FILE marker
                       # before completing anyway. The marker can be lost when a
                       # still-running task (e.g. the blackhole ATTACKER's relay
                       # task, which never exits) logs to UART0 during export and
                       # its bytes splice into the "END_OF_FILE" line. The file
                       # itself already arrived intact, so recovering it beats a
                       # 30 s idle TIMEOUT. See esp32-issues-Part3.md I-001.

# Resilience over speed. The console baud is fixed at 115200 (see BAUD above,
# I-007) which is the safest choice on a low-quality cable — raw CSV streaming
# has no error correction, so a faster baud would only trade dropped rows for
# speed and punch gaps in the telemetry. Instead we make the transfer
# self-healing: every failure seen in practice (the post-reset 0-row race, a
# lost END_OF_FILE at ~99%, a transient cable glitch) is a TRANSIENT that a
# re-read cures. The device holds the file until an explicit wipe, so re-issuing
# EXPORT_LOGS is always safe and idempotent. We retry a few times and keep the
# MOST COMPLETE capture, so a bad cable degrades gracefully instead of failing.
EXPORT_ATTEMPTS = 4       # total tries per file before giving up
RETRY_SETTLE_S  = 2.0     # let the board settle / finish flushing between tries

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


def _fmt_bytes(n: int) -> str:
    """Human-readable byte size, e.g. 1.9 MB / 812 KB."""
    if n >= 1024 * 1024:
        return f"{n / (1024 * 1024):.1f} MB"
    if n >= 1024:
        return f"{n / 1024:.0f} KB"
    return f"{n} B"


def _render_progress(received: int, total: int, rows: int,
                     start: float, final: bool = False) -> None:
    """Draw a single-line progress bar on stderr, updated in place with '\\r'.

    If the device announced a byte total (total > 0) this is a true percentage;
    otherwise it degrades to a live byte/row counter (old firmware that sends a
    bare READY_TO_SEND). Pass final=True to close the line with a newline."""
    elapsed = max(time.time() - start, 1e-6)
    rate = received / elapsed  # bytes/sec
    if total > 0:
        pct = 100.0 if final else min(99.9, received * 100.0 / total)
        filled = int(pct / 5)  # 20-cell bar
        bar = "#" * filled + "-" * (20 - filled)
        msg = (f"   [{bar}] {pct:5.1f}%  "
               f"{_fmt_bytes(received)}/{_fmt_bytes(total)}  "
               f"{rows} rows  {_fmt_bytes(int(rate))}/s")
    else:
        spin = "|/-\\"[int(elapsed * 4) % 4]
        tag = "done" if final else spin
        msg = (f"   [{tag}] {_fmt_bytes(received)}  "
               f"{rows} rows  {_fmt_bytes(int(rate))}/s")
    # Pad to clear any leftover from a longer previous line, then \r.
    sys.stderr.write("\r" + msg.ljust(64))
    if final:
        sys.stderr.write("\n")
    sys.stderr.flush()


def _capture_stream(ser: serial.Serial, command: str):
    """
    Send a command and capture the framed CSV between READY_TO_SEND and
    END_OF_FILE. Returns (lines, error_str). On success error_str is None.
    """
    _send_command(ser, command)

    started = False
    rows = []
    expected_cols = None   # field count locked in from the header row
    total_bytes = 0        # announced file size (READY_TO_SEND:<bytes>); 0 = unknown
    recv_bytes = 0         # bytes seen so far, for the progress bar
    start_ts = time.time()
    last_draw = 0.0
    last_data_ts = time.time()  # wall-clock of the most recent byte received
    # Idle timeout: give up only after OVERALL_TIMEOUT_S of NO data. A large
    # telem.csv can take a while to stream; as long as bytes keep arriving we
    # keep going, so big files no longer trip a fixed total-time cap.
    deadline = time.time() + OVERALL_TIMEOUT_S

    buf = bytearray()

    def handle_line(raw_line: bytes):
        """Process one complete line (bytes, incl. trailing newline). Returns
        ('done', None) / ('error', msg) to stop, or None to keep going."""
        nonlocal started, expected_cols, total_bytes, recv_bytes
        line = raw_line.decode("utf-8", errors="replace").strip()
        if not line:
            return None
        # Device-reported errors
        if line.startswith("ERROR:"):
            return ("error", line)
        # READY_TO_SEND  or  READY_TO_SEND:<byte-size>  (newer firmware)
        if line == "READY_TO_SEND" or line.startswith("READY_TO_SEND:"):
            started = True
            if ":" in line:
                try:
                    total_bytes = int(line.split(":", 1)[1])
                except ValueError:
                    total_bytes = 0
            return None
        if line == "END_OF_FILE":
            return ("done", None)
        if started:
            recv_bytes += len(raw_line)  # count wire bytes toward the bar
            if _looks_like_csv(line):
                ncols = line.count(",") + 1
                if line.startswith(_CSV_HEADER_TOKEN):
                    expected_cols = ncols          # lock the schema width
                    rows.append(line)
                elif expected_cols is None or ncols == expected_cols:
                    rows.append(line)
                # else: a line whose field count doesn't match the header is
                # UART noise / a split line — drop it so a clean run captures
                # EVERYTHING valid and nothing garbled.
        return None

    while time.time() < deadline:
        # Read whatever is already buffered in ONE call, else block briefly for
        # the first byte. pyserial's readline() reads a byte at a time, which
        # caps a big export at ~1 KB/s; chunked reads run near the 115200 line
        # rate (~11 KB/s), a ~10x speedup — the device streams at line rate, the
        # old bottleneck was purely here on the host.
        n = ser.in_waiting
        chunk = ser.read(n if n > 0 else 1)
        if not chunk:
            # No data this poll. If the device announced a byte total and we've
            # already received the whole file, the END_OF_FILE marker was lost
            # (interleaved device log output corrupted it — common on an
            # actively-logging attacker node). After a short grace with nothing
            # new arriving, treat the complete file as done instead of waiting
            # out the full idle TIMEOUT and discarding a good capture.
            if (started and total_bytes > 0 and recv_bytes >= total_bytes
                    and time.time() - last_data_ts >= POST_TOTAL_GRACE_S):
                _render_progress(recv_bytes, total_bytes, len(rows),
                                 start_ts, final=True)
                sys.stderr.write(
                    "   NOTE: END_OF_FILE marker was missing, but the full "
                    f"{_fmt_bytes(total_bytes)} arrived — recovered.\n")
                sys.stderr.flush()
                return rows, None
            continue
        last_data_ts = time.time()
        deadline = time.time() + OVERALL_TIMEOUT_S  # got data — extend
        buf.extend(chunk)

        # Pull out every complete line; keep any partial tail buffered.
        nl = buf.find(b"\n")
        while nl >= 0:
            raw_line = bytes(buf[:nl + 1])
            del buf[:nl + 1]
            result = handle_line(raw_line)
            if result is not None:
                kind, payload = result
                if kind == "error":
                    return [], payload
                _render_progress(recv_bytes, total_bytes, len(rows),
                                 start_ts, final=True)
                return rows, None
            nl = buf.find(b"\n")

        # Throttle redraws to ~10 fps so rendering never slows the transfer.
        now = time.time()
        if started and now - last_draw >= 0.1:
            _render_progress(recv_bytes, total_bytes, len(rows), start_ts)
            last_draw = now

    if started:
        # Close the in-place bar so the TIMEOUT message lands on its own line.
        sys.stderr.write("\n")
        sys.stderr.flush()
    return rows, "TIMEOUT: never saw END_OF_FILE"


def _warn_on_mixed_schema(rows, kind: str) -> None:
    """Flag a capture that spliced two different streams into one file.

    If an EXPORT_LOGS stream's END_OF_FILE marker is corrupted, _capture_stream
    keeps reading and the NEXT command's stream lands in the same row list —
    telem.csv followed by arrivals.csv, each with its own header. The raw file
    still holds everything, but the mismatch is invisible until preprocessing
    blows up much later, so say it here while the board is still on the desk.
    trim_run.py separates the blocks back out on --apply.
    """
    headers = [r for r in rows if r.startswith(_CSV_HEADER_TOKEN)]
    if len(headers) <= 1:
        return
    kinds = ["arrivals" if "src_mac" in h else "telem" for h in headers]
    print(f"   WARNING: capture contains {len(headers)} concatenated streams "
          f"({', '.join(kinds)}) — expected only '{kind}'. Nothing is lost, but "
          f"you MUST run trim_run.py --apply to split them before analysis.",
          file=sys.stderr)


def _capture_with_retries(ser: serial.Serial, command: str):
    """Capture a stream, retrying transient failures and keeping the most
    complete result. Returns (rows, error_str, attempts_used).

    A clean capture (error_str is None with at least one row) returns
    immediately. Otherwise we keep re-issuing the command — the device streams
    the same file each time — and hold onto whichever attempt yielded the most
    rows. This turns the flaky cases (post-reset 0-row race, a marker lost at
    ~99 %, an occasional glitch on a poor cable) into a brief, automatic retry
    instead of a hard failure. Re-reads are safe: the file is untouched until an
    explicit DELETE_LOGS/wipe.
    """
    best_rows, best_err = [], "no attempt made"
    for attempt in range(1, EXPORT_ATTEMPTS + 1):
        if attempt > 1:
            # Give the board a moment to settle (a just-closed monitor may have
            # reset it) and clear any stale bytes before re-issuing.
            time.sleep(RETRY_SETTLE_S)
            _drain(ser)
            print(f"   retry {attempt}/{EXPORT_ATTEMPTS} "
                  f"(best so far: {len(best_rows)} rows) ...")
        rows, err = _capture_stream(ser, command)
        # Perfect, complete capture — nothing to gain from more tries.
        if err is None and rows:
            return rows, None, attempt
        # Keep the fullest attempt seen so far (more rows == closer to complete).
        if len(rows) > len(best_rows):
            best_rows, best_err = rows, err
    return best_rows, best_err, EXPORT_ATTEMPTS


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


# Map a run's topology to its export subfolder. These names match the folders
# under exports/<attack>/ so CSVs land where expected. An unlisted topology
# falls back to "<topology>_topology".
_TOPOLOGY_DIR = {
    "star": "star_topology",
    "tree": "tree_topology",
    "linear": "linear_topology",
    "partial": "partial_mesh_topology",
}


def _subdir_for(args) -> str:
    """Route exports into  <outdir>/<attack-or-baseline>/<topology>_topology/  so a
    run's CSVs land in a folder named for its attack, then its topology — e.g. a
    blackhole-on-star run -> exports/blackhole/star_topology/, a baseline-on-tree
    run -> exports/baseline/tree_topology/. Keeps the four topologies from mixing.

    --attack-dir overrides ONLY the attack folder (not the filename): a control
    victim in a blackhole run is flashed attack=none but belongs with that run's
    data, so `--attack blackhole` on the ROOT and `--attack none --attack-dir
    blackhole` on the control victim file both under exports/blackhole/.
    Pass --flat to disable nesting and write straight into <outdir>."""
    if getattr(args, "flat", False):
        return args.outdir
    attack_dir = getattr(args, "attack_dir", None) or args.attack
    attack_dir = attack_dir if attack_dir and attack_dir != "none" else "baseline"
    topo_dir = _TOPOLOGY_DIR.get(args.topology, f"{args.topology}_topology")
    return os.path.join(args.outdir, attack_dir, topo_dir)


def _make_filename(args, kind: str) -> str:
    date = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    # e.g. exports/blackhole/star/root_COM3_star_blackhole_r1_20260629_..._telem.csv
    #
    # The board tag is normally the COM port, but a COM number does NOT reliably
    # identify a board here: these CP210x bridges report duplicate/blank USB
    # serials, so Windows assigns COM per USB SOCKET. If you deliberately export
    # every child through one socket, all five files would be named "..._COM26_..."
    # and differ only by timestamp. --label overrides the tag so the board stays
    # identifiable in the filename.
    #
    # Underscore is this scheme's field separator, so the tag must not contain one
    # or downstream filename parsing shifts by a field.
    tag = args.label if getattr(args, "label", None) else args.port
    safe_tag = re.sub(r"[^A-Za-z0-9-]", "-", tag)
    name = (
        f"{args.role}_{safe_tag}_{args.topology}_{args.attack}"
        f"_r{args.repeat}_{date}_{kind}.csv"
    )
    return os.path.join(_subdir_for(args), name)


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
        choices=["root", "child", "victim"],
        default="child",
        help="Mesh-position role for the filename (root | child). 'root' also "
             "pulls arrivals.csv. 'victim' is kept as an alias for 'child'. This "
             "only names the file — the CSV's node_role column is written by the "
             "firmware per thesis Table 4.12 and is unaffected.",
    )
    p.add_argument("--topology", default="unknown",
                   help="star | tree | linear | partial (for the filename)")
    p.add_argument("--attack", default="none",
                   help="none | blackhole | wormhole (for the filename)")
    p.add_argument("--repeat", default="1", help="Repeat number (for the filename)")
    p.add_argument("--outdir", default="exports", help="Output directory")
    p.add_argument("--flat", action="store_true",
                   help="Write straight into --outdir instead of the default "
                        "<outdir>/<attack-or-baseline>/<topology>_topology/ subfolders.")
    p.add_argument("--attack-dir", dest="attack_dir", default=None,
                   help="Override ONLY the attack subfolder (not the filename). "
                        "Use for a control victim (flashed attack=none) that "
                        "belongs with an attack run: --attack none --attack-dir blackhole.")
    p.add_argument("--label", default=None,
                   help="Board tag used in the FILENAME instead of the COM port "
                        "(e.g. --label node5). Use when several boards are exported "
                        "through the same COM/USB socket, so the files stay "
                        "distinguishable. Does not change what is exported, only "
                        "the name. Underscores are converted to '-' (underscore is "
                        "the filename field separator).")
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
            # The device now FORMATS the whole SPIFFS partition (not just a file
            # delete), which takes longer than the old fixed 1 s — a full format
            # erases every sector. Wait for the device's own ack ("LOGS_DELETED"
            # / "ERROR:...") instead of guessing, so a slow format isn't cut off
            # mid-way by the reflash that follows -Wipe. Fall back to a message if
            # the board is old firmware that doesn't ack.
            deadline = time.time() + 20
            acked = False
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line == "LOGS_DELETED":
                    print("   SPIFFS formatted — flash reset to empty.")
                    acked = True
                    break
                if line.startswith("ERROR:"):
                    print(f"   wipe FAILED: {line}", file=sys.stderr)
                    return 1
            if not acked:
                print("   wipe command sent (no ack — older firmware, or already "
                      "clean). Give it a moment before reflashing.")
            return 0

        # Commands to run for this role
        jobs = [("EXPORT_LOGS", "telem")]
        if args.role == "root":
            jobs.append(("EXPORT_ARRIVALS", "arrivals"))

        any_failed = False
        for command, kind in jobs:
            print(f"-> {command} ...")
            rows, err, attempts = _capture_with_retries(ser, command)
            # Persist whatever arrived, even when the stream timed out partway.
            # A partial CSV is far more useful than silently discarding the
            # thousands of rows that already transferred cleanly — previously an
            # error 'continue'd straight past _save() and threw them all away.
            if rows:
                path = _make_filename(args, kind)
                _warn_on_mixed_schema(rows, kind)
                n = _save(rows, path)
                data_rows = max(0, n - 1)  # minus header
                tries = f" after {attempts} tries" if attempts > 1 else ""
                tag = " (PARTIAL — see error below)" if err else ""
                print(f"   saved {data_rows} data rows{tries} -> {path}{tag}")
            elif not err:
                print("   WARNING: stream was empty (0 rows).", file=sys.stderr)
            if err:
                print(f"   FAILED after {attempts} tries: {err}", file=sys.stderr)
                any_failed = True

        if args.delete and not any_failed:
            print("-> DELETE_LOGS ...")
            _send_command(ser, "DELETE_LOGS")
            time.sleep(1.0)
            print("   delete command sent.")

        return 1 if any_failed else 0


if __name__ == "__main__":
    sys.exit(main())
