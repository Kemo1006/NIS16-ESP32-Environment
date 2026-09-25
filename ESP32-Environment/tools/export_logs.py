#!/usr/bin/env python3
"""
export_logs.py — Pull CSV telemetry off an ESP32 node over USB serial.

This is the laptop-side counterpart to the on-device serial-export task in
components/mesh_common/src/csv_logger.c. After an experimental run finishes,
each ESP32 starts a task that listens on UART0 for these commands:

    EXPORT_LOGS      -> streams telem.csv     (all roles)
    EXPORT_ARRIVALS  -> streams arrivals.csv  (root only)
    LIST_FILES       -> lists stored file paths
    DELETE_LOGS      -> erases stored files (SPIFFS only)
    ARCHIVE_SD       -> archives (never deletes) this run's SD-card mirror CSVs
    GET_LOCATION     -> reports location.txt as it stands, changing nothing
    SET_LOCATION=x   -> writes/overwrites location.txt on the board's SD card
    SET_TIME=<epoch> -> hands the board a real clock and saves it to the card
    GET_TIME         -> reports the board's clock and where it came from

SET_TIME is sent AUTOMATICALLY on every connection (see _push_host_time), not
only when asked for. The board has no RTC and never reaches NTP, so without it
every file, folder and manifest row is dated from the firmware's BUILD time --
the same value on every boot of one flash, which says nothing about when a
capture ran. This script is one of the few moments a board is attached to
something that owns a real clock, so it always spends that moment re-anchoring
it.

The device frames each file stream between two markers:

    READY_TO_SEND
    <csv header line>
    <csv data lines...>
    END_OF_FILE

This script connects to the given COM port, issues the command(s), captures
everything between those markers, strips any interleaved ESP-IDF log noise,
and writes a named CSV with run metadata baked into the filename.

Files are routed into  exports/<attack-or-baseline>/<topology>/  so each
run's CSVs are grouped by attack then topology (e.g. exports/blackhole/star/,
exports/baseline/tree/). Pass --flat to write straight into exports/.

NIS16 — CTTHES2 Milestone 1 — Raw Data Extraction

Usage examples
--------------
Pull the root node's telemetry AND probe-arrivals (-> exports/blackhole/star/):
    python export_logs.py --port COM3 --role root \
        --topology star --attack blackhole --repeat 1

Pull a victim node's telemetry (-> exports/baseline/tree/):
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

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))

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


def _open_port(port: str) -> serial.Serial:
    """Open a board's serial port WITHOUT resetting it.

    IMPORTANT: opening a serial port normally asserts DTR/RTS, which on an
    ESP32 are wired to EN (reset) and GPIO0 (boot) — so a plain open would
    REBOOT the board and kill the export task that's waiting for our command.
    Both lines are deasserted BEFORE the open, so the board keeps running and
    stays in its post-run "export ready" state.

    Factored out of main() so import_sdcard.py's --port mode reaches a board
    through exactly this door — a second, subtly different open() is precisely
    how one of the two paths would end up resetting boards.
    """
    ser = serial.Serial()
    ser.port = port
    ser.baudrate = BAUD
    ser.timeout = READ_TIMEOUT_S
    ser.dtr = False
    ser.rts = False
    ser.open()
    _push_host_time(ser)
    return ser


def _push_host_time(ser: serial.Serial) -> None:
    """Give the board this laptop's clock, and let it save that to the card.

    WHY THIS IS UNCONDITIONAL: an ESP32 with no RTC boots at the 1970 epoch, so
    the firmware falls back to dating everything from its own BUILD timestamp.
    That value is baked in at link time and is therefore IDENTICAL on every boot
    of one flash -- delete a card's CSVs, re-run, and the "date" is unchanged,
    because it never described the run in the first place. The board cannot fix
    this alone; only something holding a real clock can, and this function is
    the moment one is attached.

    The board persists what we send to SD_CLOCK_FILE, so a single connection
    also fixes the NEXT boot, including runs done later on a powerbank with no
    laptop present. Every path that opens a port therefore refreshes the anchor
    -- export, MAC read, SET_LOCATION, import_sdcard.py --port -- which is why
    this lives in _open_port() rather than in one command's branch.

    The epoch sent is true UTC (time.time() is timezone-free), so two laptops
    always agree. The firmware only RENDERS it as Philippine time (PHT, UTC+8,
    SD_CLOCK_TZ in mesh_config.h), which is why the prints below say PHT.

    Best-effort by design. Firmware predating SET_TIME ignores unknown commands
    silently, and a board that is busy or unresponsive must never fail an export
    over a timestamp -- so every failure here is swallowed and the board simply
    keeps its build-time estimate.
    """
    prev_timeout = getattr(ser, "timeout", READ_TIMEOUT_S)
    try:
        _send_command(ser, f"SET_TIME={int(time.time())}")
        # Read the ack rather than firing and forgetting: leaving TIME_SET in
        # the buffer would make it the first line the NEXT command's parser
        # sees.
        #
        # On a SHORT timeout, not the port's usual one: firmware predating
        # SET_TIME ignores unknown commands silently, so this read would
        # otherwise burn the full READ_TIMEOUT_S on every single connection to
        # a board that has not been reflashed yet. A board that does support
        # the command answers immediately.
        ser.timeout = 0.4
        ser.read_until(b"\n")
    except Exception:
        pass
    finally:
        try:
            ser.timeout = prev_timeout
            ser.reset_input_buffer()
        except Exception:
            pass


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


def _fmt_eta(seconds: float) -> str:
    """Remaining time as M:SS (or H:MM:SS past an hour, though an export is
    never that slow in practice)."""
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


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
        # ETA only where the percentage above is real (total is a true byte
        # count, not the "unknown total" degraded case below) and only once
        # there's an actual rate to divide by — the very first call, before
        # any bytes have arrived, would otherwise print "ETA 0:00" instead of
        # just not showing a number yet. Omitted on the final line too: once
        # done there is nothing left to count down.
        if not final and rate > 0:
            remaining = (total - received) / rate
            msg += f"  ETA {_fmt_eta(remaining)}"
    else:
        spin = "|/-\\"[int(elapsed * 4) % 4]
        tag = "done" if final else spin
        msg = (f"   [{tag}] {_fmt_bytes(received)}  "
               f"{rows} rows  {_fmt_bytes(int(rate))}/s")
    # Pad to clear any leftover from a longer previous line, then \r. Widened
    # from 64: the ETA field adds up to "  ETA H:MM:SS" (~13 chars) to the
    # longest line above (measured worst case ~82 chars: full bar, 99.9%,
    # 3.0 MB/3.0 MB, 99999 rows, 999 KB/s, ETA 1:01:01), and a shrinking line
    # (ETA counting down through fewer digits, or the final line dropping the
    # field entirely) must not leave fragments of a longer previous one on
    # the terminal.
    sys.stderr.write("\r" + msg.ljust(90))
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
                if not rows and total_bytes > 0:
                    # The device announced a real file size and then closed the
                    # frame without sending a single row. Nothing was lost in
                    # transit — the board could not read its OWN file. In the
                    # firmware that is EXPORT_LOGS doing
                    # fseek(END)/ftell/fseek(SET) then fgets() returning NULL on
                    # the first call (csv_logger.c), which is why the size is
                    # right but the payload is empty. Retrying cannot help, so
                    # say what actually happened instead of reporting a
                    # transport timeout.
                    return [], (
                        f"device announced {_fmt_bytes(total_bytes)} then sent "
                        f"END_OF_FILE with 0 rows — the BOARD could not read its "
                        f"own telem.csv (not a cable/serial problem). "
                        f"Power-cycle the board and export again before it logs "
                        f"more; if it repeats, the file is unreadable on the "
                        f"device and only DELETE_LOGS will clear it.")
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


def _check_expected_schema(rows, kind: str):
    """Did the device actually send the file we ASKED for? Returns an error
    string when it didn't, else None.

    Observed on star/wormhole/r1 (2026-07-26): EXPORT_ARRIVALS streamed
    telem.csv instead of arrivals.csv, so a perfectly good run was saved with a
    *_arrivals.csv name holding an exact copy of the telemetry. Every later
    stage happily accepted it — trim_run split it, preprocess windowed it — and
    the truth only surfaced ~20 minutes later when features.py refused to build
    PDR. By then the board is usually unplugged, and if --delete ran, wiped.

    The two schemas are trivially distinguishable (arrivals carries src_mac and
    seq_num; telemetry does not), so check it here, while the board is still on
    the desk and the file is still on its flash.
    """
    headers = [r for r in rows if r.startswith(_CSV_HEADER_TOKEN)]
    if not headers:
        return None  # no header at all — the empty/partial paths report that
    got_arrivals = "src_mac" in headers[0] and "seq_num" in headers[0]
    want_arrivals = kind == "arrivals"
    if got_arrivals == want_arrivals:
        return None
    got, want = ("telemetry", "arrivals") if want_arrivals else ("arrivals", "telemetry")
    return (
        f"device sent {got} data when asked for {want}. The stream's header is "
        f"{headers[0][:70]}... Nothing is lost on the device — the file is only "
        f"removed by --delete/--wipe, which is being SKIPPED for this run. "
        f"Re-issue the same export command; if it repeats, power-cycle the "
        f"board first."
    )


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
    # Seed with None, not a placeholder string: when EVERY attempt returns 0
    # rows the "keep the fullest attempt" test below is 0 > 0 == False, so the
    # placeholder survived and got reported as the failure reason —
    # "FAILED after 4 tries: no attempt made" — hiding the real error from the
    # device. Track the last real error instead.
    best_rows, best_err = [], None
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
        elif err is not None:
            # No improvement in rows, but a real reason — keep the latest one so
            # a run that never gets a single row still reports WHY.
            best_err = err
    return best_rows, best_err or "no rows and no error reported by the device", \
        EXPORT_ATTEMPTS


def _archive_sd(ser: serial.Serial) -> None:
    """Send ARCHIVE_SD and wait briefly for its ack.

    Never fatal to the export: a board running firmware from before ARCHIVE_SD
    existed simply won't ack (treated the same as --wipe/--set-location on old
    firmware elsewhere in this file), and "this boot had no SD run" is exactly
    the no-card/bad-location.txt case sd_status.c already reports at boot, not
    a reason to fail an otherwise-good download.
    """
    print("-> ARCHIVE_SD ...")
    _send_command(ser, "ARCHIVE_SD")
    deadline = time.time() + 5
    while time.time() < deadline:
        raw = ser.readline()
        if not raw:
            continue
        line = raw.decode("utf-8", errors="replace").strip()
        if line == "SD_ARCHIVED":
            print("   SD mirror archived on the card (see <run_dir>/_archive/).")
            return
        if line == "ERROR:NO_SD_RUN":
            print("   SD archive skipped: this board had no SD run this boot "
                  "(no card / bad location.txt).")
            return
        if line.startswith("ERROR:"):
            print(f"   SD archive FAILED: {line}", file=sys.stderr)
            return
    print("   no ack (older firmware without ARCHIVE_SD, or the card was "
          "unreachable) -- SD mirror left as-is.")


def _list_files(ser: serial.Serial) -> None:
    """Print the two LIVE files this boot is writing.

    Newer firmware answers FILE:<path>|<bytes>|<rows>; older firmware answers a
    bare FILE:<path>. Both are rendered — the extra fields are shown when they
    are there and simply omitted when they are not, so this keeps working
    against a board that has not been reflashed yet.

    A count of -1 means the device could not read the file at all, which is
    "unknown" and is NOT the same as an empty file (0 rows)."""
    _send_command(ser, "LIST_FILES")
    # Counting rows means reading the files, so allow more than the old 10 s.
    deadline = time.time() + 30
    print("Stored files on device:")
    while time.time() < deadline:
        raw = ser.readline()
        if not raw:
            continue
        line = raw.decode("utf-8", errors="replace").strip()
        if line == "END_LIST":
            return
        if not line.startswith("FILE:"):
            continue
        body = line[len("FILE:"):]
        parts = body.split("|")
        if len(parts) < 3:
            print("   " + body)
            continue
        path, bytes_s, rows_s = parts[0], parts[1], parts[2]
        size_txt = (_fmt_bytes(int(bytes_s))
                    if _is_known_count(bytes_s) else "size unknown")
        rows_txt = (f"{int(rows_s)} rows"
                    if _is_known_count(rows_s) else "rows unknown")
        print(f"   {path}  ({size_txt}, {rows_txt})")


def _is_known_count(text: str) -> bool:
    """True for a non-negative integer field. The device sends -1 for a value it
    could not determine, which must read as "unknown" rather than as zero."""
    try:
        return int(text) >= 0
    except (TypeError, ValueError):
        return False


# Map a run's topology to its export subfolder. These names match the folders
# under exports/<attack>/ so CSVs land where expected — and MUST stay
# byte-identical to s_topo_dirs in components/mesh_common/src/sd_status.c, since
# the export tree mirrors the SD card tree. An unlisted topology falls back to
# its own name unchanged. "partial" keeps the longer "partial_mesh" folder name
# (kept from the pre-shortening "partial_mesh_topology") so it stays
# distinguishable from the --topology CLI value; the other three now match
# their CLI value exactly.
_TOPOLOGY_DIR = {
    "star": "star",
    "tree": "tree",
    "linear": "linear",
    "partial": "partial_mesh",
}

# Deployment sites (thesis panel problem P4 — environment must be RECORDED,
# never inferred). Must match SD_LOCATION_* in mesh_config.h and the card's
# own folder names exactly, since the export tree mirrors the SD card tree.
LOCATIONS = ["home", "G402", "DLSU_Library", "Goks"]

# Run-to-run variation (panel, sep. 2026 — see run.ps1 -Scenario). A FOLDER
# level, deliberately never the filename: several tools downstream parse the
# filename's fields by position (see _make_filename below), and a run's
# scenario is not one of them.
#
# "stationary" (sep. 24 2026) is the no-variation scenario, formerly "none".
# "none" is still ACCEPTED as an alias everywhere (old presets, commands, ledgers)
# and converted by canon_scenario() - the one place that rename lives. Must stay
# in sync with run.ps1 -Scenario's ValidateSet (jitter was missing here, so
# every jitter run's export failed with "invalid choice").
SCENARIOS = ["stationary", "burst", "highload", "jitter", "mobility", "powercycle"]
SCENARIO_ALIASES = {"none": "stationary"}


def canon_scenario(scenario):
    """Canonical scenario name; empty/None/"none" -> "stationary"."""
    s = scenario or "stationary"
    return SCENARIO_ALIASES.get(s, s)


def _subdir_for(args) -> str:
    """Route exports into
    <outdir>/<attack-or-baseline>/<topology>/<location>/<scenario>/  so a run's
    CSVs land in a folder named for its attack, then its topology, then its
    site, then its scenario — e.g. a blackhole-on-star burst run captured at
    G402 -> exports/blackhole/star/G402/burst/, a plain one -> .../G402/stationary/.

    EVERY scenario gets a folder since sep. 24 2026, stationary included, so a
    capture never sits loose beside other scenarios' subfolders. Captures from
    before that have NO scenario folder; every reader treats that as
    stationary. Must stay byte-identical to Get-RunDirs in run_wizard.ps1 /
    menu.ps1, run.ps1's -Analyze paths and cell_dir() in run_matrix.py.

    --attack-dir overrides ONLY the attack folder (not the filename): a control
    victim in a blackhole run is flashed attack=none but belongs with that run's
    data, so `--attack blackhole` on the ROOT and `--attack none --attack-dir
    blackhole` on the control victim file both under exports/blackhole/.
    Pass --flat to disable nesting and write straight into <outdir>."""
    if getattr(args, "flat", False):
        return args.outdir
    attack_dir = getattr(args, "attack_dir", None) or args.attack
    attack_dir = attack_dir if attack_dir and attack_dir != "none" else "baseline"
    topo_dir = _TOPOLOGY_DIR.get(args.topology, args.topology)
    scenario = canon_scenario(getattr(args, "scenario", None))
    return os.path.join(args.outdir, attack_dir, topo_dir, args.location, scenario)


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
    p.add_argument("--location", choices=LOCATIONS, default=None,
                   help="Deployment site: home | G402 | DLSU_Library | Goks. "
                        "Folder level only, never the filename — DLSU_Library "
                        "contains '_', this scheme's reserved field separator. "
                        "Required for an actual export unless --flat.")
    p.add_argument("--attack", default="none",
                   help="none | blackhole | wormhole (for the filename)")
    p.add_argument("--scenario", choices=SCENARIOS + list(SCENARIO_ALIASES),
                   default="stationary",
                   help="Run scenario (run.ps1 -Scenario): " + " | ".join(SCENARIOS)
                        + " ('none' = old name for stationary). Folder level "
                        "only, never the filename — see SCENARIOS above.")
    p.add_argument("--repeat", default="1", help="Repeat number (for the filename)")
    # Resolve the default RELATIVE TO THIS SCRIPT, not the shell's CWD. This is
    # the most damaging of the four CWD-relative defaults that existed: it does
    # not merely scan the wrong folder, it WRITES irreplaceable captures into
    # it. Running an export from root_node\ or child_node\ (where you already
    # are for `idf.py set-target` / flashing) silently created
    # root_node\exports\ and child_node\exports\ and filed a whole
    # baseline-tree run in there, invisible to every analysis command. An
    # explicit --outdir still wins.
    p.add_argument("--outdir", default=os.path.join(_THIS_DIR, "exports"),
                   help="Output directory (default: the exports/ folder next "
                        "to this script, NOT one relative to your shell).")
    p.add_argument("--flat", action="store_true",
                   help="Write straight into --outdir instead of the default "
                        "<outdir>/<attack-or-baseline>/<topology>/ subfolders.")
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
    p.add_argument("--archive-sd", dest="archive_sd", action="store_true",
                   help="After a successful download, ARCHIVE (never delete) this "
                        "run's SD-card mirror CSVs into <run_dir>/_archive/ on the "
                        "board's own SD card, so a location's folder (e.g. "
                        "blackhole/linear/home/) doesn't stay cluttered with this "
                        "run's files until the board's next power-cycle. Implied by "
                        "--delete, since a good SPIFFS download is the same 'this "
                        "capture is safe' signal for the SD mirror. No-op if this "
                        "board had no SD run this boot (no card / bad location.txt), "
                        "and never fatal to the export either way.")
    p.add_argument("--set-location", dest="set_location", choices=LOCATIONS, default=None,
                   help="Write/overwrite location.txt on this board's SD card over "
                        "USB -- no need to remove the card. Fixes SD_STATUS_NO_LOCATION_FILE "
                        "/ SD_STATUS_BAD_LOCATION at boot. Takes effect on the NEXT boot, "
                        "not this session. Standalone: downloads/wipes nothing, and is "
                        "ignored if combined with --wipe/--list/an actual export in the "
                        "same invocation -- run it by itself.")
    p.add_argument("--get-location", dest="get_location", action="store_true",
                   help="Print what location.txt on this board's SD card says right "
                        "now and change nothing. Use it BEFORE --set-location to see "
                        "what you would be overwriting. Prints the site name, 'NONE' "
                        "if the file is missing, or the rejected raw text if it holds "
                        "something unrecognised. Standalone: exports/wipes nothing.")
    p.add_argument("--end-run", dest="end_run", action="store_true",
                   help="End this board's run NOW and close its files cleanly "
                        "(firmware END_RUN), for a board the card listing shows as "
                        "STILL RUNNING. If the board was already in cooldown the "
                        "capture is complete; if not, it is cut short and stays "
                        "marked ABORTED. Prints one 'END_RUN_RESULT: <x>' line "
                        "(COMPLETE | CUT_SHORT | ALREADY | FAIL). Standalone: "
                        "exports nothing.")
    p.add_argument("--set-time", dest="set_time", action="store_true",
                   help="Give this board a real clock and save it to its SD card, "
                        "then exit. Every connection does this anyway (see "
                        "_push_host_time); this flag exists so it can be done "
                        "DELIBERATELY at a moment that matters -- above all "
                        "immediately BEFORE reflashing. The new firmware's build "
                        "stamp is newer than an anchor written days ago and would "
                        "win over it, making the first run after a flash a "
                        "build-time ESTIMATE; an anchor written seconds before the "
                        "flash is newer still, so the very first run is already on "
                        "a real clock. run.ps1 does this automatically. "
                        "Standalone: exports/wipes nothing.")
    p.add_argument("--set-attacker-mac", dest="set_attacker_mac", default=None,
                   metavar="AA:BB:CC:DD:EE:FF",
                   help="F2: point this blackhole VICTIM board at a different "
                        "attacker, without recompiling it. Stored in NVS and "
                        "read at boot, so it takes effect on the NEXT power "
                        "cycle. This is what makes 'vary the attacker position' "
                        "affordable: previously the attacker MAC was a #define "
                        "and moving it meant re-flashing every victim.")
    p.add_argument("--get-attacker-mac", dest="get_attacker_mac",
                   action="store_true",
                   help="Report the attacker MAC this board will target, and "
                        "whether it came from NVS or the compiled default. Run "
                        "this on every victim before a blackhole run — a stale "
                        "value fails SILENTLY (zero root arrivals, PDR and "
                        "ForwardingRatio 100%% NaN, every board looking fine).")
    p.add_argument("--clear-attacker-mac", dest="clear_attacker_mac",
                   action="store_true",
                   help="Drop the NVS override so BLACKHOLE_ATTACKER_MAC from "
                        "mesh_config.h applies again on the next boot.")
    p.add_argument("--delete-sd-path", dest="delete_sd_path", default=None,
                   metavar="ATTACK/TOPOLOGY/LOCATION",
                   help="PERMANENTLY delete a folder (and everything under it) on this "
                        "board's SD card over USB, e.g. blackhole/linear/G402. The first "
                        "part must be baseline, blackhole or wormhole. The board refuses "
                        "if it is logging into that folder right now. Standalone: "
                        "exports/wipes nothing.")
    p.add_argument("--delete-sd-file", dest="delete_sd_file", default=None,
                   metavar="ATTACK/TOPOLOGY/LOCATION/FILE.csv",
                   help="PERMANENTLY delete ONE capture CSV on this board's SD card "
                        "over USB, e.g. blackhole/linear/G402/victim_NODE_AABBCC_r1_b3"
                        "_telem.csv. The per-file counterpart to --delete-sd-path, for "
                        "clearing an aborted run without taking the rest of the folder "
                        "with it. The board accepts only *_telem.csv / *_arrivals.csv, "
                        "so runs.csv and location.txt cannot be removed this way, and "
                        "refuses a file it has open right now. Standalone: exports "
                        "nothing.")
    args = p.parse_args()
    args.scenario = canon_scenario(args.scenario)

    if args.delete_sd_path is not None:
        args.delete_sd_path = args.delete_sd_path.strip().strip("/\\").replace("\\", "/")
        if not re.fullmatch(r"(?i)(baseline|blackhole|wormhole)(/[A-Za-z0-9_-]+){0,4}",
                            args.delete_sd_path):
            print(f"ERROR: --delete-sd-path {args.delete_sd_path!r} is not <attack>[/<topology>"
                  "[/<location>...]] (attack = baseline | blackhole | wormhole; letters, "
                  "digits, _ and - only).", file=sys.stderr)
            return 1

    try:
        ser = _open_port(args.port)
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

        if args.set_time:
            # _open_port() already pushed the clock and the board already saved
            # it. All that is left is to report what the board now believes, so
            # an operator can SEE that it took -- a silent success here is
            # indistinguishable from firmware that ignored the command.
            print("-> SET_TIME (host clock -> board + SD card) ...")
            _send_command(ser, "GET_TIME")
            deadline = time.time() + 3
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line.startswith("TIME:"):
                    # TIME:<YYYY-MM-DD HH:MM:SS>:<host|build|none>
                    body = line[len("TIME:"):]
                    stamp, _, src = body.rpartition(":")
                    if src == "host":
                        print(f"   board clock: {stamp} PHT (real clock, from this laptop)")
                        print("   Saved to clock.txt on the card — the next boot starts "
                              "from it, so captures get true dates.")
                    else:
                        print(f"   board clock: {stamp} PHT (still an ESTIMATE from the "
                              f"firmware build time)")
                        print("   The board did not take the clock. It is almost "
                              "certainly running firmware from before SET_TIME existed "
                              "— reflash it.")
                    return 0
            print("   no answer — this board predates SET_TIME/GET_TIME. Reflash it "
                  "to give it a real clock.")
            return 0

        if args.end_run:
            print("-> END_RUN ...")
            _send_command(ser, "END_RUN")
            # The reply shares UART0 with the board's own log output, so it can
            # arrive glued to a log line ("I (1234) mesh: ...END_RUN:OK:..."). An
            # exact whole-line match missed that and reported "no answer" for
            # boards whose firmware DOES have END_RUN (sep. 25, 2026: boards built
            # 10:38 that day). Match the token anywhere in the line, and also take
            # the board's own "END_RUN from USB" warning as proof it was accepted.
            # Never resend: if the first END_RUN landed and only its reply was
            # lost, a second one answers ALREADY_ENDED and hides that it worked.
            result = None
            closed = False
            deadline = time.time() + 10
            while time.time() < deadline and result is None:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if "END_RUN:OK:COMPLETE" in line or "cooldown reached, data complete" in line:
                    result = "COMPLETE"
                elif "END_RUN:OK:CUT_SHORT" in line or "BEFORE cooldown, capture is cut short" in line:
                    result = "CUT_SHORT"
                elif "END_RUN:ALREADY_ENDED" in line:
                    print("END_RUN_RESULT: ALREADY")
                    print("   the run had already ended on this board — nothing to do.")
                    return 0
                elif "END_RUN_NOT_RUNNING" in line:
                    print("END_RUN_RESULT: FAIL")
                    print(f"   end-run FAILED: {line}", file=sys.stderr)
                    return 1
                if "Telemetry file closed" in line:
                    closed = True
            if result is None:
                print("END_RUN_RESULT: FAIL")
                print("   no END_RUN reply within 10 s. The board may be busy, or its reply was "
                      "lost in its own log output. Open idf.py monitor on this port and type "
                      "END_RUN + Enter to see what it says. Do NOT reset it to 'fix' this - a "
                      "reset moves this file into _archive\\ and starts a new one.", file=sys.stderr)
                return 1
            # The close runs on the board's main task; wait for its log line so
            # the caller never lists the card while the file is still open.
            deadline = time.time() + 20
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace")
                if "Telemetry file closed" in line or "SD card unmounted" in line:
                    closed = True
                    if "SD card unmounted" in line:
                        break
            if not closed:
                print("END_RUN_RESULT: FAIL")
                print("   the board accepted END_RUN but never reported closing its "
                      "file. Check it in idf.py monitor.", file=sys.stderr)
                return 1
            print(f"END_RUN_RESULT: {result}")
            if result == "COMPLETE":
                print("   run ended in cooldown — capture is complete and closed.")
            else:
                print("   run ended BEFORE cooldown — file is closed and safe to copy, "
                      "but the capture is cut short and stays marked ABORTED.")
            return 0

        if args.get_location:
            print("-> GET_LOCATION ...")
            _send_command(ser, "GET_LOCATION")
            # Every outcome prints one "CURRENT_LOCATION: <x>" line and nothing
            # else on that line, so run_wizard.ps1 can match it without parsing
            # prose. UNKNOWN means "could not read", never "the card is blank" —
            # the two must not be conflated or the wizard would offer to
            # overwrite a location it simply failed to see.
            deadline = time.time() + 5
            for_wizard = None
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line == "LOCATION:NONE":
                    print("CURRENT_LOCATION: NONE")
                    print("   location.txt is missing — this board records NO data to "
                          "its SD card until one is written.")
                    for_wizard = "NONE"
                    break
                if line.startswith("LOCATION:INVALID:"):
                    bad = line[len("LOCATION:INVALID:"):]
                    print(f"CURRENT_LOCATION: INVALID:{bad}")
                    print(f"   location.txt holds {bad!r}, which is not one of "
                          f"{', '.join(LOCATIONS)} — the board treats this the same "
                          f"as missing and writes no SD data.")
                    for_wizard = "INVALID"
                    break
                if line.startswith("LOCATION:"):
                    print(f"CURRENT_LOCATION: {line[len('LOCATION:'):]}")
                    for_wizard = "OK"
                    break
                if line.startswith("ERROR:"):
                    print("CURRENT_LOCATION: UNKNOWN")
                    print(f"   get-location FAILED: {line}", file=sys.stderr)
                    return 1
            if for_wizard is None:
                print("CURRENT_LOCATION: UNKNOWN")
                print("   no ack — this board is running firmware from before "
                      "GET_LOCATION existed. Reflash it to read locations back.",
                      file=sys.stderr)
                return 1
            return 0

        # ── F2: attacker-MAC commands ───────────────────────────────────────
        # Same ack-wait shape as --set-location below. Firmware from before F2
        # simply never acks, which is reported as such rather than as a success.
        if args.get_attacker_mac:
            _send_command(ser, "GET_ATTACKER_MAC")
            deadline = time.time() + 5
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line.startswith("ATTACKER_MAC:"):
                    print(f"ATTACKER_MAC: {line[len('ATTACKER_MAC:'):].strip()}")
                    return 0
                if line.startswith("ERROR:"):
                    print(f"   get-attacker-mac FAILED: {line}", file=sys.stderr)
                    return 1
            print("ATTACKER_MAC: UNKNOWN")
            print("   no ack — firmware from before F2. Reflash to read it back.",
                  file=sys.stderr)
            return 1

        if args.clear_attacker_mac:
            print("-> CLEAR_ATTACKER_MAC ...")
            _send_command(ser, "CLEAR_ATTACKER_MAC")
            deadline = time.time() + 5
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line == "ATTACKER_MAC_CLEARED":
                    print("   override cleared — the compiled "
                          "BLACKHOLE_ATTACKER_MAC applies on the next boot.")
                    return 0
                if line.startswith("ERROR:"):
                    print(f"   clear-attacker-mac FAILED: {line}", file=sys.stderr)
                    return 1
            print("   no ack — firmware from before F2.", file=sys.stderr)
            return 1

        if args.set_attacker_mac:
            print(f"-> SET_ATTACKER_MAC={args.set_attacker_mac} ...")
            _send_command(ser, f"SET_ATTACKER_MAC={args.set_attacker_mac}")
            deadline = time.time() + 5
            acked = False
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line == "ATTACKER_MAC_SET":
                    print(f"   target set to {args.set_attacker_mac} — takes "
                          f"effect on next boot. POWER-CYCLE this board before "
                          f"the run, or it will still probe the old address.")
                    acked = True
                    break
                if line.startswith("ERROR:"):
                    hint = {
                        "ERROR:BAD_MAC":
                            f"the board rejected {args.set_attacker_mac!r}. It "
                            f"needs six hex bytes (aa:bb:cc:dd:ee:ff), and "
                            f"refuses all-zero, broadcast and multicast "
                            f"addresses because those reproduce exactly the "
                            f"silent-failure mode this flag exists to prevent. "
                            f"Nothing was written.",
                        "ERROR:MAC_WRITE_FAILED":
                            "NVS would not take the write. The board is still "
                            "targeting whatever it targeted before — re-read it "
                            "with --get-attacker-mac.",
                    }.get(line)
                    print(f"   set-attacker-mac FAILED: {line}", file=sys.stderr)
                    if hint:
                        print(f"   {hint}", file=sys.stderr)
                    return 1
            if not acked:
                print("   no ack — firmware from before F2. Reflash with the "
                      "current firmware and retry.")
                return 1
            return 0

        if args.set_location:
            print(f"-> SET_LOCATION={args.set_location} ...")
            _send_command(ser, f"SET_LOCATION={args.set_location}")
            # Same ack-wait pattern as --wipe, but this is a plain file write —
            # no reason for it to take anywhere near as long, so a short deadline
            # is enough. Older firmware without this command just won't ack.
            deadline = time.time() + 5
            acked = False
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line == "LOCATION_SET":
                    print(f"   location.txt set to {args.set_location} — takes effect on next boot.")
                    acked = True
                    break
                if line.startswith("ERROR:"):
                    # Spell out what each failure actually means — these are read
                    # by someone standing over a breadboard, and "BAD_LOCATION"
                    # vs "WRITE_FAILED" need opposite fixes.
                    hint = {
                        "ERROR:BAD_LOCATION":
                            f"the board rejected the name {args.set_location!r} "
                            f"(it accepts {', '.join(LOCATIONS)}). Nothing was "
                            f"written — whatever location.txt held is still there.",
                        "ERROR:LOCATION_NO_CARD":
                            "the SD card could not be mounted — reseat the card and "
                            "check the wiring/power. location.txt was not touched.",
                        "ERROR:LOCATION_WRITE_FAILED":
                            "the card mounted but the write failed — it may be "
                            "write-protected, full, or failing. location.txt may be "
                            "unchanged; re-read it with --get-location.",
                        "ERROR:BAD_LOCATION_OR_WRITE_FAILED":
                            "older firmware that cannot say which went wrong: either "
                            "the name was rejected or the card would not take the "
                            "write. Reflash to get the specific reason.",
                    }.get(line)
                    print(f"   set-location FAILED: {line}", file=sys.stderr)
                    if hint:
                        print(f"   {hint}", file=sys.stderr)
                    return 1
            if not acked:
                print("   set-location command sent (no ack — older firmware without "
                      "this command). Reflash with the current firmware and retry.")
            return 0

        if args.delete_sd_file:
            print(f"-> DELETE_SD_FILE={args.delete_sd_file} ...")
            _send_command(ser, f"DELETE_SD_FILE={args.delete_sd_file}")
            # One unlink, unlike the folder walk below - but the card is still
            # SPI at 4 MHz and may have to be mounted first, so allow for that.
            deadline = time.time() + 30
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line == "SD_FILE_DELETED":
                    print("SD_DELETE_RESULT: OK 1")
                    print(f"   deleted {args.delete_sd_file} from the SD card.")
                    return 0
                if line.startswith("ERROR:"):
                    hint = {
                        "ERROR:BAD_SD_FILE":
                            "the board rejected that name. It deletes only *_telem.csv / "
                            "*_arrivals.csv under <attack>/<topology>/<location>[/<scenario>] "
                            "- runs.csv and location.txt are deliberately out of reach.",
                        "ERROR:SD_FILE_IN_USE":
                            "the board has that file OPEN - it is the run in progress. Let it "
                            "reach TERMINATE (or reboot the board) first.",
                        "ERROR:SD_NO_CARD":
                            "the SD card could not be mounted - reseat it and check wiring/power.",
                        "ERROR:SD_FILE_NOT_FOUND":
                            "no such file on this card (nothing deleted).",
                        "ERROR:SD_DELETE_FAILED":
                            "the card refused the unlink - it may be write-protected or failing.",
                        "ERROR:COMMAND_TOO_LONG":
                            "the path is too long for the board's command buffer.",
                    }.get(line)
                    print(f"SD_DELETE_RESULT: {line}")
                    print(f"   delete-sd-file FAILED: {line}", file=sys.stderr)
                    if hint:
                        print(f"   {hint}", file=sys.stderr)
                    return 1
            print("SD_DELETE_RESULT: NO_ACK")
            print("   no ack - older firmware without DELETE_SD_FILE, or the board is not "
                  "running. Reflash with the current firmware and retry.", file=sys.stderr)
            return 1

        if args.delete_sd_path:
            print(f"-> DELETE_SD_PATH={args.delete_sd_path} ...")
            _send_command(ser, f"DELETE_SD_PATH={args.delete_sd_path}")
            # A folder with hundreds of CSVs over SPI at 4 MHz takes a while.
            deadline = time.time() + 90
            while time.time() < deadline:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if line.startswith("SD_PATH_DELETED:"):
                    count = line[len("SD_PATH_DELETED:"):]
                    print(f"SD_DELETE_RESULT: OK {count}")
                    print(f"   deleted {args.delete_sd_path} from the SD card ({count} file(s)).")
                    return 0
                if line.startswith("ERROR:"):
                    hint = {
                        "ERROR:BAD_SD_PATH":
                            "the board rejected the path, or it names a file rather than a folder.",
                        "ERROR:SD_PATH_IN_USE":
                            "the board is logging into that folder right now. Let the run "
                            "finish (or reboot the board with a different location) first.",
                        "ERROR:SD_NO_CARD":
                            "the SD card could not be mounted - reseat it and check wiring/power.",
                        "ERROR:SD_PATH_NOT_FOUND":
                            "that folder does not exist on this card (nothing deleted).",
                        "ERROR:COMMAND_TOO_LONG":
                            "the path is too long for the board's command buffer.",
                    }.get(line)
                    if line.startswith("ERROR:SD_DELETE_FAILED"):
                        hint = ("some files were removed but not all - the card may be "
                                "write-protected or failing. Re-run to retry the rest.")
                    print(f"SD_DELETE_RESULT: {line}")
                    print(f"   delete-sd-path FAILED: {line}", file=sys.stderr)
                    if hint:
                        print(f"   {hint}", file=sys.stderr)
                    return 1
            print("SD_DELETE_RESULT: NO_ACK")
            print("   no ack - older firmware without DELETE_SD_PATH, or the board is not "
                  "running. Reflash with the current firmware and retry.", file=sys.stderr)
            return 1

        # --location is required for an actual export (not --list/--wipe, which
        # write nothing) unless --flat disables the topology/location nesting
        # entirely. Checked here, not via argparse required=True, so --list and
        # --wipe keep working without a site.
        if not args.location and not args.flat:
            print("ERROR: --location is required (home | G402 | DLSU_Library | Goks), "
                  "or pass --flat to skip topology/location nesting.", file=sys.stderr)
            return 1

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
                schema_err = _check_expected_schema(rows, kind)
                if schema_err:
                    # Park it OUTSIDE every downstream glob (*.csv / *_telem.csv
                    # / *_arrivals.csv) so trim_run, preprocess and validate
                    # cannot pick it up, but keep the bytes for diagnosis rather
                    # than discarding a capture we may need to look at.
                    path += ".rejected"
                n = _save(rows, path)
                data_rows = max(0, n - 1)  # minus header
                tries = f" after {attempts} tries" if attempts > 1 else ""
                tag = " (PARTIAL — see error below)" if err else ""
                if schema_err:
                    print(f"   WRONG FILE: {schema_err}", file=sys.stderr)
                    print(f"   quarantined {data_rows} rows -> {path}", file=sys.stderr)
                    any_failed = True
                else:
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

        # --delete implies --archive-sd: a good SPIFFS download is the same
        # "this capture is safe" signal for the SD mirror. Still runs when
        # --archive-sd was passed on its own (no --delete), since tidying the
        # card and wiping SPIFFS are independent decisions.
        if (args.archive_sd or args.delete) and not any_failed:
            _archive_sd(ser)

        return 1 if any_failed else 0


if __name__ == "__main__":
    sys.exit(main())
