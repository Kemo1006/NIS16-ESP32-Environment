"""
gui_monitor.py - the serial monitor run_gui.ps1 uses instead of idf.py monitor.

WHY (oct. 17 2026, user: "everything the CLI has, in the GUI - no CLI window"):
idf.py monitor needs a real console (it reads the keyboard for Ctrl+] and for
typed commands such as START), so a GUI cannot host it. This does the same job
with no console at all:

  * prints every line the board sends to stdout (run.ps1 -GuiMonitor sends it
    to a log file the GUI tails), flushed line by line;
  * sends what the GUI appends to <ctl>/send.txt (one command per line, e.g.
    START or START_ANYWAY) to the board, ending each with CR+LF like
    idf.py monitor (the firmware's dispatcher accepts either);
  * exits cleanly when <ctl>/stop appears - the GUI's "done with this board"
    button, the equivalent of Ctrl+].

Board safety, same rules as export_logs.py / serial_guard.py:
  * DTR/RTS are deasserted BEFORE the open, so opening the port never resets
    the board (the flash step has already reset it into the new firmware);
  * grow_rx_queue() right after open, and the loop READS non-stop - an open
    port that nobody reads is the CP210x 0xB8 blue-screen trigger. The control
    files are checked between reads, never with a sleep while bytes wait.

    python gui_monitor.py --port COM7 --ctl <folder>
"""

import argparse
import os
import sys
import time

import serial

import serial_guard

BAUD = 115200
CTL_POLL_S = 0.2


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--port", required=True)
    p.add_argument("--ctl", required=True, help="folder holding send.txt / stop")
    p.add_argument("--max-hours", type=float, default=0,
                   help="close by itself after this long (0 = never) - the GUI's background "
                        "crash watch uses it so a forgotten listener never holds a port forever")
    a = p.parse_args()
    os.makedirs(a.ctl, exist_ok=True)
    send_path = os.path.join(a.ctl, "send.txt")
    stop_path = os.path.join(a.ctl, "stop")
    # oct. 18 2026: a 'reset' file restarts the board (EN pulse through RTS - the
    # dev board's auto-reset circuit; DTR stays low so it boots normally, not into
    # the bootloader). The GUI uses it for a clean start between run attempts; the
    # monitor keeps listening, so the restart itself is in the log.
    reset_path = os.path.join(a.ctl, "reset")
    sent = 0                     # bytes of send.txt already sent

    ser = serial.Serial()
    ser.port = a.port
    ser.baudrate = BAUD
    ser.timeout = 0.05
    ser.dtr = False
    ser.rts = False
    try:
        ser.open()
    except serial.SerialException as e:
        print(f"[monitor] could not open {a.port}: {e}", flush=True)
        return 2
    serial_guard.grow_rx_queue(ser)
    print(f"[monitor] listening on {a.port} at {BAUD} baud", flush=True)

    out = sys.stdout.buffer
    pending = b""
    next_ctl = 0.0
    deadline = time.monotonic() + a.max_hours * 3600 if a.max_hours > 0 else None
    lost = False
    try:
        while True:
            try:
                chunk = ser.read(4096)
            except serial.SerialException as e:
                # The COM port vanished under us (oct. 18 2026: a traceback ending in
                # "ClearCommError failed (Access is denied)"): the board was unplugged,
                # its cable / hub dropped, or a reset re-enumerated it - Windows may
                # give it ANOTHER COM number when it comes back (COM3 -> COM30).
                print(f"[monitor] LOST {a.port}: the board disappeared (unplugged, cable/USB reset "
                      f"or a reset re-enumerated it) - plug it back; it may come back on ANOTHER "
                      f"COM number. ({e})", flush=True)
                lost = True
                break
            if chunk:
                pending += chunk
                *lines, pending = pending.split(b"\n")
                for ln in lines:
                    out.write(ln.rstrip(b"\r") + b"\n")
                out.flush()
            now = time.monotonic()
            if now < next_ctl:
                continue
            next_ctl = now + CTL_POLL_S
            if os.path.exists(stop_path):
                break
            if os.path.exists(reset_path):
                try:
                    os.remove(reset_path)
                except OSError:
                    pass
                ser.dtr = False
                ser.rts = True             # EN low
                time.sleep(0.12)
                ser.rts = False            # EN high -> normal boot
                print("[monitor] board restarted (EN pulse) - a clean start for the next attempt", flush=True)
            if deadline and now > deadline:
                print("[monitor] time limit reached - closing", flush=True)
                break
            try:
                size = os.path.getsize(send_path)
            except OSError:
                size = 0
            if size > sent:
                with open(send_path, "rb") as f:
                    f.seek(sent)
                    new = f.read()
                sent += len(new)
                for cmd in new.decode("utf-8", "replace").splitlines():
                    cmd = cmd.strip()
                    if cmd:
                        ser.write(cmd.encode("ascii", "replace") + b"\r\n")
                        print(f"[monitor] sent: {cmd}", flush=True)
    finally:
        if pending:
            out.write(pending + b"\n")
            out.flush()
        try:
            ser.close()
        except (serial.SerialException, OSError):
            pass                      # a vanished port cannot be closed cleanly
    print("[monitor] closed", flush=True)
    return 3 if lost else 0


if __name__ == "__main__":
    sys.exit(main())
