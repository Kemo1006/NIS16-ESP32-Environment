#!/usr/bin/env python3
"""
sniff.py - record what an ESP32 sniffer board hears into a Wireshark .pcap.

The laptop half of sniffer_node/ (see sniffer_main.c for the wire format). A
spare ESP32 flashed with sniffer_node listens on the mesh channel and streams
every frame over its USB cable; this script turns that stream into a standard
.pcap (radiotap link type, so Wireshark shows RSSI, rate and channel per frame)
- no SD card, no Mac, no monitor-mode adapter needed.

    python tools/sniff.py --port COM7                     Enter to stop
    python tools/sniff.py --port COM7 --live              + live Wireshark view
    python tools/sniff.py --port COM7 --out PCAP/x.pcap --stop-file PCAP/x.stop

Stops on: Enter (--stop-on-enter, the default on a console), Ctrl+C,
--minutes elapsed, or the --stop-file appearing (how run_wizard.ps1 stops a
capture running in its own window). The .pcap is flushed every second, so even
a killed process leaves a readable file (tools/check_pcap.py repairs a cut-off
last packet).

Next to the capture it writes <name>.json: what was recorded and HOW COMPLETE
it is - frames lost on the USB link (rec_seq gaps), frames the board itself
could not queue (ring full), board reboots. A figure built on a capture can
quote those numbers instead of assuming a lossless capture.

Timing: every frame carries the radio's own microsecond RX timestamp, so
spacing between frames is exact. The absolute wall-clock time is anchored to
this laptop's clock when the first frame arrives (USB latency: a few ms), and
the board's crystal drifts at most ~20 ms over a 30-minute capture. Good for
"which phase was this", not for sub-millisecond cross-device joins.

Needs pyserial (the ESP-IDF PowerShell has it). Everything else is stdlib.
"""
import argparse
import datetime as _dt
import json
import os
import shutil
import struct
import subprocess
import sys
import threading
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial is not installed.")
    print("  Run this from the ESP-IDF PowerShell window, or:  pip install pyserial")
    sys.exit(2)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

BAUD = 921600            # MUST match SNIFF_BAUD in sniffer_node/main/sniffer_main.c

MAGIC = b"\xA5\x5A"
REC_HELLO, REC_FRAME, REC_STATUS = 1, 2, 3
MAX_BODY = 600           # largest legal record body (FRAME: 18 + 256 snap)
FRAME_FIXED = 18

LINKTYPE_RADIOTAP = 127
PKT_TYPES = {0: "mgmt", 1: "ctrl", 2: "data", 3: "misc"}

# wifi_phy_rate_t (ESP-IDF) -> radiotap Rate field (units of 500 kbps).
# Codes 0-7 are 802.11b (CCK), 8-15 are 802.11g (OFDM).
LEGACY_RATE_500K = {0: 2, 1: 4, 2: 11, 3: 22, 5: 4, 6: 11, 7: 22,
                    8: 96, 9: 48, 10: 24, 11: 12, 12: 108, 13: 72, 14: 36, 15: 18}


def fletcher16(data):
    a = b = 0
    for x in data:
        a = (a + x) % 255
        b = (b + a) % 255
    return (b << 8) | a


class StreamParser:
    """Pulls checksummed records out of the byte stream. Anything that is not
    a valid record (boot text at the wrong baud, a corrupted byte) is skipped;
    a record is only accepted when its checksum matches."""

    def __init__(self):
        self.buf = bytearray()
        self.synced = False
        self.skipped_before_sync = 0
        self.skipped_after_sync = 0   # nonzero = corruption on the USB link

    def _skip(self, n):
        if self.synced:
            self.skipped_after_sync += n
        else:
            self.skipped_before_sync += n
        del self.buf[:n]

    def feed(self, data):
        self.buf.extend(data)
        out = []
        while True:
            i = self.buf.find(MAGIC)
            if i < 0:
                # Keep a trailing A5: it may be the first half of the next magic.
                keep = 1 if self.buf[-1:] == b"\xA5" else 0
                self._skip(len(self.buf) - keep)
                return out
            if i:
                self._skip(i)
            if len(self.buf) < 6:
                return out
            typ, pad = self.buf[2], self.buf[3]
            blen = struct.unpack_from("<H", self.buf, 4)[0]
            if pad != 0 or typ not in (REC_HELLO, REC_FRAME, REC_STATUS) or blen > MAX_BODY:
                self._skip(1)
                continue
            total = 6 + blen + 2
            if len(self.buf) < total:
                return out
            want = struct.unpack_from("<H", self.buf, 6 + blen)[0]
            if fletcher16(self.buf[2:6 + blen]) != want:
                self._skip(1)
                continue
            out.append((typ, bytes(self.buf[6:6 + blen])))
            del self.buf[:total]
            self.synced = True


def radiotap_header(rssi, noise, rate, sig_mode, mcs, flags, channel):
    """Minimal radiotap header: Flags, Rate (legacy only), Channel, dBm signal,
    dBm noise, MCS (HT only). Fields are added in ascending bit order with
    their natural alignment, as the radiotap spec requires. (The noise byte
    also puts MCS on an even offset: the spec aligns MCS to 1, but scapy pads
    it to 2, and a header every decoder reads the same way is worth a byte.)"""
    out = bytearray(8)
    present = 0

    def add(bit, align, data):
        nonlocal present
        present |= 1 << bit
        while len(out) % align:
            out.append(0)
        out.extend(data)

    add(1, 1, b"\x00")                                  # Flags: FCS not included
    legacy = sig_mode == 0
    if legacy and rate in LEGACY_RATE_500K:
        add(2, 1, bytes([LEGACY_RATE_500K[rate]]))
    freq = 2484 if channel == 14 else 2407 + 5 * channel
    chflags = 0x0080 | (0x0020 if (legacy and rate <= 7) else 0x0040)  # 2 GHz + CCK/OFDM
    add(3, 2, struct.pack("<HH", freq, chflags))
    add(5, 1, struct.pack("<b", rssi))                  # antenna signal, dBm
    add(6, 1, struct.pack("<b", noise))                 # antenna noise, dBm (SNR = signal - noise)
    if sig_mode == 1:                                   # 802.11n (HT)
        known = 0x01 | 0x02 | 0x04                      # bandwidth, MCS index, guard interval
        mflags = (1 if flags & 0x01 else 0) | (0x04 if flags & 0x02 else 0)
        add(19, 1, bytes([known, mflags, mcs]))
    struct.pack_into("<BBHI", out, 0, 0, 0, len(out), present)
    return bytes(out)


class BoardClock:
    """Board RX timestamp (32-bit us, wraps every ~71 min) -> wall-clock time."""

    def __init__(self):
        self.last_wall = 0.0
        self.reset()

    def reset(self):
        """Board rebooted: its timestamp restarts near 0, so anchor afresh."""
        self.hi = 0
        self.last = None
        self.anchor = None

    def wall(self, raw):
        if self.last is not None and raw < self.last and self.last - raw > 0x80000000:
            self.hi += 1 << 32
        self.last = raw
        ext = self.hi + raw
        if self.anchor is None:
            # Never before the last frame already written: after a reboot the
            # USB latency of the OLD anchor could otherwise put the first new
            # frames a few ms in the past, and the capture would run backwards.
            self.anchor = (max(time.time(), self.last_wall), ext)
        self.last_wall = self.anchor[0] + (ext - self.anchor[1]) / 1e6
        return self.last_wall


def find_wireshark():
    hit = shutil.which("Wireshark") or shutil.which("wireshark")
    if hit:
        return hit
    # A custom install folder is only in the installer's App Paths registry entry.
    try:
        import winreg
        for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            try:
                with winreg.OpenKey(hive, r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Wireshark.exe") as k:
                    p = winreg.QueryValue(k, None).strip('"')
                if os.path.isfile(p):
                    return p
            except OSError:
                pass
    except ImportError:  # not Windows
        pass
    for root in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
        if root:
            p = os.path.join(root, "Wireshark", "Wireshark.exe")
            if os.path.isfile(p):
                return p
    return None


def wireshark_env():
    # run_wizard.ps1's WIRESHARK category keeps its columns in its own settings
    # folder (not a -C profile: that becomes the laptop's "last used profile").
    # Use it for the live view too when it exists, else Wireshark's normal one.
    cfg = os.path.join(os.environ.get("APPDATA", ""), "Wireshark-ThesisMesh")
    return dict(os.environ, WIRESHARK_CONFIG_DIR=cfg) if os.path.isdir(cfg) else None


def fmt_bytes(n):
    if n >= 1024 * 1024:
        return "%.1f MB" % (n / (1024 * 1024))
    if n >= 1024:
        return "%.0f KB" % (n / 1024)
    return "%d B" % n


def fmt_dur(s):
    s = int(s)
    return "%d:%02d:%02d" % (s // 3600, (s % 3600) // 60, s % 60) if s >= 3600 else "%d:%02d" % (s // 60, s % 60)


def _enable_ansi():
    """True when stdout is a console that will render ANSI colours (turns on
    virtual-terminal processing on Windows; plain redirected output gets none)."""
    if not sys.stdout.isatty():
        return False
    if os.name == "nt":
        try:
            import ctypes
            k = ctypes.windll.kernel32
            h = k.GetStdHandle(-11)
            mode = ctypes.c_uint32()
            if not k.GetConsoleMode(h, ctypes.byref(mode)):
                return False
            return bool(k.SetConsoleMode(h, mode.value | 0x0004))
        except Exception:
            return False
    return True


ANSI = _enable_ansi()


def paint(text, code):
    """Wrap text in an ANSI colour code, or return it untouched off a console."""
    return "\x1b[%sm%s\x1b[0m" % (code, text) if ANSI else text


class StatusLine:
    """One line updated in place on a console. When stdout is not a console
    (captured by PowerShell, redirected to a file) a '\\r' redraw would turn
    into one line per update, so there it prints a plain line every 10 s."""

    def __init__(self):
        self.tty = sys.stdout.isatty()
        self.last_plain = 0.0

    def show(self, msg, final=False, style=None):
        if self.tty:
            width = max(40, shutil.get_terminal_size((100, 24)).columns - 1)
            line = msg[:width].ljust(width)      # colour AFTER trimming, or a cut escape code bleeds
            sys.stdout.write("\r" + (paint(line, style) if style else line))
            if final:
                sys.stdout.write("\n")
            sys.stdout.flush()
        elif final or time.time() - self.last_plain >= 10:
            print(msg, flush=True)
            self.last_plain = time.time()

    def note(self, msg):
        """A message that must stay on screen (not overwritten by the next update)."""
        if self.tty:
            sys.stdout.write("\r" + " " * (shutil.get_terminal_size((100, 24)).columns - 1) + "\r")
        print(msg, flush=True)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Record an ESP32 sniffer board's stream into a .pcap.")
    ap.add_argument("--port", required=True, help="COM port of the SNIFFER board (e.g. COM7)")
    ap.add_argument("--out", help="output .pcap (default: datasets/PCAP/esp32_sniffer_<time>.pcap in the repo)")
    ap.add_argument("--baud", type=int, default=BAUD, help="must match the firmware (default %d)" % BAUD)
    ap.add_argument("--minutes", type=float, default=120.0,
                    help="safety stop after this many minutes (default 120; 0 = never)")
    ap.add_argument("--stop-file", help="stop cleanly as soon as this file exists")
    ap.add_argument("--stop-on-enter", dest="stop_on_enter", action="store_true", default=None,
                    help="stop when Enter is pressed (default when run on a console)")
    ap.add_argument("--no-stop-on-enter", dest="stop_on_enter", action="store_false")
    ap.add_argument("--live", action="store_true", help="also open Wireshark and stream to it live")
    ap.add_argument("--start-paused", action="store_true",
                    help="begin PAUSED (frames heard but not saved) until P is pressed - for a manual "
                         "recording started before the experiment does")
    ap.add_argument("--label", default="", help="free text saved in the .json sidecar (run description)")
    args = ap.parse_args()

    if args.stop_on_enter is None:
        args.stop_on_enter = sys.stdin.isatty() and not args.stop_file

    out = args.out or os.path.join(
        REPO, "datasets", "PCAP", "esp32_sniffer_%s.pcap" % _dt.datetime.now().strftime("%Y%m%d_%H%M%S"))
    out = os.path.abspath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sidecar = os.path.splitext(out)[0] + ".json"
    if args.stop_file and os.path.exists(args.stop_file):
        os.remove(args.stop_file)   # a leftover from an earlier run would stop us instantly

    ser = serial.Serial()
    ser.port = args.port
    ser.baudrate = args.baud
    ser.timeout = 0.1
    ser.dtr = False   # both low BEFORE open: DTR/RTS are EN/GPIO0, so a plain
    ser.rts = False   # open would reset the board (same rule as export_logs.py)
    try:
        ser.open()
    except Exception as ex:
        print("ERROR: could not open %s (%s)." % (args.port, ex))
        print("  Close any idf.py monitor / serial window on that port, check the cable, retry.")
        return 2

    live = None
    live_note = ""
    if args.live:
        ws = find_wireshark()
        if not ws:
            live_note = "Wireshark not found - recording to file only."
        else:
            try:
                live = subprocess.Popen([ws, "-k", "-i", "-"], stdin=subprocess.PIPE,
                                        env=wireshark_env())
            except OSError as ex:
                live_note = "could not start Wireshark (%s) - recording to file only." % ex

    gh = struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, LINKTYPE_RADIOTAP)
    f = open(out, "wb")
    f.write(gh)
    if live:
        try:
            live.stdin.write(gh)
            live.stdin.flush()
        except OSError:
            live = None

    stop = threading.Event()
    stop_reason = ["?"]
    # Pause = keep reading the port (so the board's buffers never back up and
    # the rec_seq/clock tracking stays continuous) but write nothing. Every
    # pause is recorded in the .json, so a gap in the capture is never silent.
    paused = threading.Event()
    keys = sys.stdin.isatty()
    if args.start_paused:
        paused.set()

    def toggle_pause():
        if paused.is_set():
            paused.clear()
        else:
            paused.set()

    if keys:
        def read_keys():
            try:
                import msvcrt            # Windows: single keypress, no Enter needed
                while not stop.is_set():
                    ch = msvcrt.getwch()
                    if ch in ("p", "P"):
                        toggle_pause()
                    elif ch in ("\r", "\n") and args.stop_on_enter:
                        stop_reason[0] = "Enter pressed"
                        stop.set()
            except ImportError:          # elsewhere: 'p' + Enter pauses, a bare Enter stops
                while not stop.is_set():
                    line = sys.stdin.readline()
                    if not line:
                        return
                    if line.strip().lower() == "p":
                        toggle_pause()
                    elif not line.strip() and args.stop_on_enter:
                        stop_reason[0] = "Enter pressed"
                        stop.set()
            except Exception:
                return
        threading.Thread(target=read_keys, daemon=True).start()

    started_wall = time.time()
    started_iso = _dt.datetime.now().astimezone().isoformat(timespec="seconds")
    print("Sniffer on %s at %d baud -> %s" % (args.port, args.baud, out))
    if live_note:
        print("  " + live_note)
    how = []
    if keys:
        how.append("P = pause/resume")
    if args.stop_on_enter:
        how.append("Enter = stop")
    how.append("Ctrl+C = stop")
    if args.stop_file:
        how.append("the wizard stops it for you")
    print("  Keys: " + " / ".join(how) + ".  (Close this window only as a last resort.)")
    if args.start_paused:
        bar = "=" * 62
        print()
        print(paint(bar, "1;33"))
        print(paint("  PAUSED - NOTHING IS BEING SAVED YET", "1;33"))
        print(paint("  Press  P  to START recording (press P again to pause/resume).", "1;33"))
        print(paint(bar, "1;33"))
        print()
        if not keys:
            print("  WARNING: no keyboard on this console, so P cannot be pressed - the capture "
                  "would stay paused. Rerun without --start-paused.")

    parser = StreamParser()
    clock = BoardClock()
    status = StatusLine()
    hello = {}
    board = {}           # latest STATUS from the board
    board_base = None    # counters at this boot's first STATUS (per-boot deltas)
    loss_totals = {"ring_dropped": 0, "bad_fcs": 0, "seen": 0}
    nonce = None
    reboots = 0
    next_seq = None
    usb_lost = 0
    frames = 0
    bytes_written = len(gh)
    by_type = {"mgmt": 0, "ctrl": 0, "data": 0, "misc": 0}
    last_flush = time.time()
    last_frame_at = None
    warned_silent = warned_nothing = False
    rate_window = []     # (time, frames) for a short-term frames/s
    pauses = []          # closed pauses, for the .json
    cur_pause = None     # the open one, while paused

    def iso_now():
        return _dt.datetime.now().astimezone().isoformat(timespec="seconds")

    def close_pause(now):
        nonlocal cur_pause
        cur_pause["ended"] = iso_now()
        cur_pause["seconds"] = round(now - cur_pause.pop("t0"), 1)
        pauses.append(cur_pause)
        cur_pause = None

    def fold_board_counters():
        """Bank this boot's counters before a reboot resets them to 0."""
        if board and board_base is not None:
            for k in loss_totals:
                loss_totals[k] += board.get(k, 0) - board_base.get(k, 0)

    try:
        while not stop.is_set():
            if args.stop_file and os.path.exists(args.stop_file):
                stop_reason[0] = "stop file (wizard)"
                break
            now = time.time()
            if args.minutes and now - started_wall >= args.minutes * 60:
                stop_reason[0] = "time limit (%g min)" % args.minutes
                break
            if paused.is_set() and cur_pause is None:
                cur_pause = {"started": iso_now(), "t0": now, "frames_not_saved": 0}
                status.note(paint("  PAUSED %s - frames are heard but NOT saved. Press P to %s."
                                  % (time.strftime("%H:%M:%S"), "START" if not pauses and frames == 0 and args.start_paused else "resume"),
                                  "1;33"))
            elif not paused.is_set() and cur_pause is not None:
                n_skip = cur_pause["frames_not_saved"]
                close_pause(now)
                status.note(paint("  RECORDING %s - %d frame(s) were not saved during the pause."
                                  % (time.strftime("%H:%M:%S"), n_skip), "1;32"))

            chunk = ser.read(ser.in_waiting or 1)
            for typ, body in parser.feed(chunk):
                if typ == REC_HELLO and len(body) >= 9:
                    n, ch, sm, sd = struct.unpack_from("<IBHH", body, 0)
                    if nonce is not None and n != nonce:
                        reboots += 1
                        fold_board_counters()
                        board, board_base = {}, None
                        clock.reset()
                        next_seq = None
                        status.note("  NOTE: the sniffer board REBOOTED (power/cable?) - timing re-anchored, capture continues.")
                    nonce = n
                    hello = {"channel": ch, "snap_mgmt": sm, "snap_data": sd,
                             "firmware": body[9:].decode("ascii", "replace")}
                elif typ == REC_STATUS and len(body) >= 24:
                    up, seen, queued, dropped, bad, free = struct.unpack_from("<IIIIII", body, 0)
                    board = {"uptime_ms": up, "seen": seen, "queued": queued,
                             "ring_dropped": dropped, "bad_fcs": bad, "ring_free": free}
                    if board_base is None:
                        board_base = dict(board)
                elif typ == REC_FRAME and len(body) >= FRAME_FIXED:
                    seq, ts = struct.unpack_from("<II", body, 0)
                    rssi = struct.unpack_from("<b", body, 8)[0]
                    rate, sig_mode, mcs, flags, ch, ptype = body[9:15]
                    orig = struct.unpack_from("<H", body, 15)[0]
                    noise = struct.unpack_from("<b", body, 17)[0]
                    payload = body[FRAME_FIXED:]
                    if next_seq is not None and seq > next_seq:
                        usb_lost += seq - next_seq
                    next_seq = seq + 1
                    t = clock.wall(ts)   # even while paused: keeps the 32-bit wrap tracking right
                    last_frame_at = now
                    if cur_pause is not None:
                        cur_pause["frames_not_saved"] += 1
                        continue
                    rt = radiotap_header(rssi, noise, rate, sig_mode, mcs, flags, ch or hello.get("channel", 11))
                    rec = struct.pack("<IIII", int(t), int((t % 1) * 1e6),
                                      len(rt) + len(payload), len(rt) + orig) + rt + payload
                    f.write(rec)
                    bytes_written += len(rec)
                    if live:
                        try:
                            live.stdin.write(rec)
                        except OSError:
                            live = None
                            status.note("  Wireshark closed - still recording to the file.")
                    frames += 1
                    by_type[PKT_TYPES.get(ptype, "misc")] += 1

            if now - last_flush >= 1.0:
                f.flush()
                if live:
                    try:
                        live.stdin.flush()
                    except OSError:
                        live = None
                last_flush = now
                rate_window.append((now, frames))
                rate_window = [(t, n) for t, n in rate_window if now - t <= 5]
                fps = 0.0
                if len(rate_window) >= 2 and rate_window[-1][0] > rate_window[0][0]:
                    fps = (rate_window[-1][1] - rate_window[0][1]) / (rate_window[-1][0] - rate_window[0][0])
                drop_now = loss_totals["ring_dropped"] + (board.get("ring_dropped", 0) - (board_base or {}).get("ring_dropped", 0))
                msg = ("  %s %s  %d frames (%d data)  %.0f/s  %s  lost: usb %d, board %d  ch %s"
                       % ("PAUSED" if cur_pause is not None else "REC", fmt_dur(now - started_wall),
                          frames, by_type["data"], fps,
                          fmt_bytes(bytes_written), usb_lost, drop_now, hello.get("channel", "?")))
                if cur_pause is not None:
                    msg = msg + "  << PRESS P TO " + ("START" if args.start_paused and not pauses else "RESUME")
                    status.show(msg, style="1;33")
                else:
                    status.show(msg)

                # Fail loudly, early: an empty capture that "looks fine" for 11
                # minutes is exactly how the sep. 23 Mac run was lost.
                if not parser.synced and now - started_wall > 8 and not warned_nothing:
                    warned_nothing = True
                    status.note("  WARNING: nothing from the sniffer after 8 s. Is sniffer_node flashed on %s?"
                                " Wrong port? Press the board's EN/RST button once." % args.port)
                if parser.synced and (last_frame_at is None or now - last_frame_at > 15) and not warned_silent \
                        and now - started_wall > 15:
                    warned_silent = True
                    status.note("  WARNING: the sniffer is alive but has heard NO frames for 15 s -"
                                " is the mesh powered and on channel %s?" % hello.get("channel", "?"))
                if last_frame_at is not None and now - last_frame_at < 5:
                    warned_silent = False
    except KeyboardInterrupt:
        stop_reason[0] = "Ctrl+C"
    finally:
        f.flush()
        f.close()
        ser.close()
        if live:
            try:
                live.stdin.close()
            except OSError:
                pass

    if stop.is_set() and stop_reason[0] == "?":
        stop_reason[0] = "stopped"
    fold_board_counters()
    ended = time.time()
    if cur_pause is not None:
        close_pause(ended)
    paused_total = round(sum(p["seconds"] for p in pauses), 1)
    not_saved = sum(p["frames_not_saved"] for p in pauses)
    status.show("  REC %s  %d frames (%d data)  %s  - stopped (%s)"
                % (fmt_dur(ended - started_wall), frames, by_type["data"], fmt_bytes(bytes_written),
                   stop_reason[0]), final=True)

    board_seen = loss_totals["seen"]
    summary = {
        "tool": "tools/sniff.py",
        "capture": os.path.basename(out),
        "label": args.label,
        "port": args.port,
        "baud": args.baud,
        "sniffer_firmware": hello.get("firmware"),
        "channel": hello.get("channel"),
        "snaplen": {"mgmt": hello.get("snap_mgmt"), "data": hello.get("snap_data")},
        "started": started_iso,
        "ended": _dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "duration_s": round(ended - started_wall, 1),
        "stop_reason": stop_reason[0],
        "frames_written": frames,
        "frames_by_type": by_type,
        "loss": {
            "usb_link_lost_frames": usb_lost,
            "board_ring_dropped_frames": loss_totals["ring_dropped"],
            "bad_fcs_frames_discarded": loss_totals["bad_fcs"],
            "board_frames_heard": board_seen,
            "corrupt_bytes_skipped_after_sync": parser.skipped_after_sync,
            "note": "board_ring_dropped / usb_link_lost are frames the sniffer HEARD but "
                    "did not deliver; frames the radio never decoded are unknowable.",
        },
        "sniffer_reboots": reboots,
        "paused_s": paused_total,
        "frames_not_saved_while_paused": not_saved,
        "pauses": pauses,
        "timing": "per-frame radio RX timestamp (us); wall clock anchored to this laptop "
                  "at the first frame (few ms USB latency) and re-anchored after a reboot",
    }
    with open(sidecar, "w", encoding="utf-8") as jf:
        json.dump(summary, jf, indent=2)

    lost = usb_lost + loss_totals["ring_dropped"]
    print("  Saved: %s" % out)
    print("         %s" % sidecar)
    if frames == 0:
        if not parser.synced:
            print("RESULT: FAIL - no data at all from %s. Not the sniffer firmware, wrong port," % args.port)
            print("  or the board is off. Flash it from the wizard (sniffer menu) and retry.")
        elif not_saved:
            print("RESULT: EMPTY - frames were heard, but it was PAUSED the whole time, so none were saved.")
        else:
            print("RESULT: FAIL - the sniffer ran but heard no frames. Mesh off, or a different channel?")
        return 1
    if lost:
        pct = 100.0 * lost / (frames + lost)
        print("  NOTE: %d frame(s) heard but not delivered (%.2f%%) - recorded in the .json." % (lost, pct))
    if reboots:
        print("  NOTE: the sniffer rebooted %d time(s) during the capture - see the .json." % reboots)
    if pauses:
        print("  NOTE: paused %d time(s), %s in total - %d frame(s) heard then were not saved. Times are in the .json;"
              % (len(pauses), fmt_dur(paused_total), not_saved))
        print("        the capture has GAPS there, so don't read a quiet stretch as the mesh going silent.")
    print("Open it in Wireshark, or check it:  python tools\\check_pcap.py \"%s\"" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
