#!/usr/bin/env python3
"""
erase_board.py - PERMANENTLY erase every run file a board holds: all run folders on its
SD card (every attack / topology / location folder, _archive sub-folders included) and
its internal flash (SPIFFS). Oct. 20 2026 (user: "a button on the Data page that deletes
the whole storage of the selected board").

    python tools/erase_board.py --port COM3 [--expect-mac b0:cb:d8:f3:32:18] [--end-run]

KEPT on purpose: the card's settings at its top level - location.txt, scenario.txt,
node_config.txt, the clock anchor - so the board keeps recording under the right site.
The firmware re-creates its empty folder tree at the next boot.

One USB connection, opened like export_logs.py (no reset). The folder the board is
logging into RIGHT NOW is refused by the firmware (ERROR:SD_PATH_IN_USE); with --end-run
the board's own current run is ended first (END_RUN: files closed, card unmounted) and the
folder deleted after - never use it while a real capture is running. --expect-mac refuses
to touch a board that is not the one picked (GET_ID). Read-only checks first, then:

  ERASE: <folder> deleted <n> file(s) | not there | IN USE | FAILED ...
  ERASE_RESULT: ok=<0|1> files=<n> failed=<n> flash=<OK|FAILED>
Exit 0 = everything erased, 1 = something was not.
"""
import argparse
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_logs as el  # noqa: E402

ATTACKS = ("baseline", "blackhole", "wormhole")
TOPOLOGIES = ("star", "tree", "linear", "partial_mesh")
LOCATIONS = ("home", "G402", "DLSU_Library", "Yuchengco")


def ask(ser, cmd, done, timeout=20):
    el._send_command(ser, cmd)
    return el._read_reply(ser, done, timeout)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description="Erase all run files of one board (SD card + internal flash).")
    ap.add_argument("--port", required=True)
    ap.add_argument("--expect-mac", default="", help="refuse unless the board on --port has this MAC")
    ap.add_argument("--end-run", action="store_true",
                    help="end the board's own current run if its folder is in use (only when no capture runs)")
    ap.add_argument("--no-flash", action="store_true", help="leave the internal flash (SPIFFS) alone")
    a = ap.parse_args()
    # oct. 20 2026: an operator hold - %TEMP%\HOLD_ERASE present = refuse (used to pause a batch erase)
    if os.path.exists(os.path.join(os.environ.get("TEMP", ""), "HOLD_ERASE")):
        print("ERASE: REFUSED - erase is on hold (%TEMP%/HOLD_ERASE exists)")
        print("ERASE_RESULT: ok=0 files=0 failed=1 flash=SKIPPED")
        return 1

    ser = el._open_port(a.port)
    files = failed = 0
    with ser:
        el._drain(ser)
        if a.expect_mac:
            want = re.sub(r"[^0-9A-F]", "", a.expect_mac.upper())[-12:]
            line = ask(ser, "GET_ID", lambda l: l.startswith(("ID:", "ERROR:")), 5)
            have = re.sub(r"[^0-9A-F]", "", (line or "").upper())[-12:]
            if have != want:
                print(f"ERASE: REFUSED - the board on {a.port} answered {line or 'nothing'}, not {a.expect_mac}")
                print("ERASE_RESULT: ok=0 files=0 failed=1 flash=SKIPPED")
                return 1
        busy = []
        ended = False
        for atk in ATTACKS:
            for topo in TOPOLOGIES:
                for loc in LOCATIONS:
                    rel = f"{atk}/{topo}/{loc}"
                    # oct. 20 2026: a wormhole board needs several seconds after END_RUN to stop its
                    # UART tunnel and close its files - retry the folder for up to ~20 s, not once
                    for attempt in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10):
                        r = ask(ser, f"DELETE_SD_PATH={rel}",
                                lambda l: l.startswith(("SD_PATH_DELETED:", "ERROR:")), 60)
                        if r and r.startswith("SD_PATH_DELETED:"):
                            n = int(r.split(":", 1)[1] or 0)
                            files += n
                            if n:
                                print(f"ERASE: {rel} deleted {n} file(s)", flush=True)
                        elif r == "ERROR:SD_PATH_NOT_FOUND":
                            pass
                        elif r == "ERROR:SD_PATH_IN_USE" and attempt == 1 and a.end_run and not ended:
                            e = ask(ser, "END_RUN", lambda l: l.startswith(("END_RUN:", "ERROR:")), 15)
                            ended = True
                            print(f"ERASE: {rel} is in use - ended the board's own run first ({e})", flush=True)
                            time.sleep(2)
                            continue
                        elif r == "ERROR:SD_PATH_IN_USE" and ended and attempt < 10:
                            time.sleep(2)    # still closing its files - ask again
                            continue
                        elif r == "ERROR:SD_PATH_IN_USE":
                            busy.append(rel)
                            failed += 1
                            print(f"ERASE: {rel} IN USE - the board is logging into it right now (not deleted)", flush=True)
                        elif r == "ERROR:SD_NO_CARD":
                            print("ERASE: NO SD CARD answered - nothing on the card could be erased", flush=True)
                            failed += 1
                            break
                        else:
                            failed += 1
                            print(f"ERASE: {rel} FAILED ({r or 'no answer'})", flush=True)
                        break
        flash = "SKIPPED"
        if not a.no_flash:
            r = ask(ser, "DELETE_LOGS", lambda l: l in ("LOGS_DELETED",) or l.startswith("ERROR:"), 60)
            flash = "OK" if r == "LOGS_DELETED" else "FAILED"
            if flash == "FAILED":
                failed += 1
            print(f"ERASE: internal flash (SPIFFS) {'formatted' if flash == 'OK' else 'NOT formatted: ' + str(r)}", flush=True)
    if busy:
        print("ERASE: still on the card (in use): " + ", ".join(busy)
              + " - run again with 'end its current run' ticked once no capture is running")
    print(f"ERASE_RESULT: ok={int(not failed)} files={files} failed={failed} flash={flash}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
