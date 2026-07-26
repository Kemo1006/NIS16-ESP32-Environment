#!/usr/bin/env python3
"""
board_check.py — is this ESP32 dead, blank, or fine?

Diagnoses a suspect board WITHOUT erasing anything. Runs four independent
checks so you can tell the failure modes apart:

  1. SERIAL PORT      — does Windows see a USB-serial device at all?
                        FAIL => cable is charge-only, bad port/hub, or no driver.
  2. BOOTLOADER       — does the ESP32 ROM bootloader answer esptool?
                        PASS proves the chip powers up, the USB-serial bridge
                        works, and DTR/RTS auto-reset is wired correctly.
                        FAIL after check 1 passed => genuinely suspect hardware.
  3. FLASH CHIP       — is the SPI flash detected and the expected size?
                        FAIL => flash chip or its solder joints are bad.
  4. FIRMWARE RUNTIME — is an app actually running and talking on UART0?
                        Listens for boot/mesh output, then sends LIST_FILES and
                        waits for the csv_logger's FILE: reply.
                        FAIL with 1-3 PASS => hardware is FINE, board is just
                        blank or crash-looping. Re-flash it.

The MAC read in check 2 is matched against this project's known board roster,
so it also tells you WHICH board you are holding.

NON-DESTRUCTIVE: only reads. Never erases, never writes flash.

USAGE
    cd tools
    python board_check.py --port COM28          # check one board
    python board_check.py --list                # just list serial ports
    python board_check.py --port COM28 --wait 15   # longer runtime listen
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("ERROR: pyserial missing. Run this from the ESP-IDF PowerShell, "
             "or: pip install pyserial")

BAUD = 115200          # must match the firmware console baud (mesh_config/sdkconfig)
EXPECTED_FLASH = "4MB"  # partitions.csv needs the 4MB layout

# Known boards in this project, by STA MAC. The AP MAC is normally STA+1, so we
# match on a prefix-of-5-octets basis too. Sourced from captured telemetry
# (node_id = NODE_<MAC>) and mesh_config.h's BLACKHOLE_ATTACKER_MAC.
KNOWN = {
    "28:05:a5:32:d7:b4": "COM20  (ROOT)",
    "b0:cb:d8:f3:32:18": "COM26  (blackhole ATTACKER / wormhole Node A)",
    "f4:2d:c9:73:e6:18": "COM27  (wormhole Node B)",
    "b4:bf:e9:34:ed:80": "COM21",
    "b4:bf:e9:32:fe:90": "COM25",
    "70:4b:ca:25:b7:68": "COM22",
}


def _mark(ok):
    return "PASS" if ok else "FAIL"


def check_port(port):
    ports = {p.device.upper(): p for p in list_ports.comports()}
    p = ports.get(port.upper())
    if p:
        return True, f"{p.description}"
    return False, f"not present (seen: {', '.join(sorted(ports)) or 'none'})"


ESPTOOL_CMD = None          # resolved once by find_esptool()
ESPTOOL_HOW = "not resolved"


def find_esptool():
    """Locate esptool however it happens to be available on this machine.

    esptool is NOT always on PATH as 'esptool.py' — that only holds inside the
    ESP-IDF PowerShell. A plain PowerShell will not have it. So try, in order:
    the PATH names, the current interpreter's module, then the IDF install's own
    python paired with its bundled esptool.py.

    Returns a command-list prefix, or None if esptool cannot be found at all.
    """
    global ESPTOOL_CMD, ESPTOOL_HOW
    if ESPTOOL_CMD is not None:
        return ESPTOOL_CMD

    def works(cmd):
        try:
            r = subprocess.run(cmd + ["version"], capture_output=True,
                               text=True, timeout=30)
            return r.returncode == 0
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            return False

    candidates = [
        (["esptool.py"], "esptool.py on PATH"),
        (["esptool"], "esptool on PATH"),
        ([sys.executable, "-m", "esptool"], "python -m esptool"),
    ]
    for idf in sorted(glob.glob(r"C:\Espressif\frameworks\esp-idf-*"), reverse=True):
        script = os.path.join(idf, "components", "esptool_py", "esptool", "esptool.py")
        if os.path.isfile(script):
            for py in sorted(glob.glob(r"C:\Espressif\python_env\*\Scripts\python.exe"),
                             reverse=True):
                candidates.append(([py, script], f"IDF bundled ({os.path.basename(idf)})"))
            candidates.append(([sys.executable, script], "IDF esptool.py + current python"))

    for cmd, how in candidates:
        if works(cmd):
            ESPTOOL_CMD, ESPTOOL_HOW = cmd, how
            return ESPTOOL_CMD
    return None


class EsptoolMissing(Exception):
    """esptool could not be located — an ENVIRONMENT problem, not a board fault."""


def _esptool(port, *args, timeout=60):
    """Run esptool, returning (returncode, combined output).

    Raises EsptoolMissing if esptool itself cannot be found, so the caller never
    mistakes a tooling problem for a hardware failure.
    """
    base = find_esptool()
    if base is None:
        raise EsptoolMissing()
    cmd = base + ["--port", port, *args]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "esptool timed out."


def check_bootloader(port):
    rc, out = _esptool(port, "chip_id")
    chip = re.search(r"Chip is (.+)", out)
    mac = re.search(r"MAC:\s*([0-9a-f:]{17})", out)
    crystal = re.search(r"Crystal is (\S+)", out)
    ok = rc == 0 and chip is not None
    detail = chip.group(1).strip() if chip else out.strip().splitlines()[-1] if out.strip() else "no response"
    return ok, detail, (mac.group(1) if mac else None), (crystal.group(1) if crystal else None)


def check_flash(port):
    rc, out = _esptool(port, "flash_id")
    size = re.search(r"Detected flash size:\s*(\S+)", out)
    manuf = re.search(r"Manufacturer:\s*(\S+)", out)
    if rc != 0 or not size:
        return False, "could not read flash id", None
    return True, f"{size.group(1)}" + (f", manufacturer {manuf.group(1)}" if manuf else ""), size.group(1)


def check_runtime(port, wait_s):
    """Listen for app output, then probe the csv_logger command listener."""
    try:
        ser = serial.Serial()
        ser.port = port
        ser.baudrate = BAUD
        ser.timeout = 0.5
        ser.dtr = False      # do NOT reset the board
        ser.rts = False
        ser.open()
    except Exception as e:
        return False, f"could not open port at {BAUD} ({e})", ""

    # Give the passive listen everything except a small fixed probe budget,
    # rather than a 60/40 split. The interesting late lines — the SPIFFS mount
    # banner and the blackhole-victim marker — land AFTER mesh_setup_init()
    # returns, and that call blocks for up to PHASE_STABILISE_S (60 s,
    # mesh_setup.c:196) when there is no mesh to join, which is exactly the
    # situation when you are checking one board on the desk. Under the old split
    # a --wait 60 listened for only 36 s and never reached them; now --wait 75
    # does. The default (10 s) is unchanged: 6 s passive, 4 s probe.
    probe_budget = min(4.0, wait_s * 0.4)
    listen_budget = max(wait_s - probe_budget, wait_s * 0.6)

    with ser:
        # 1) passive listen — a running app almost always chatters
        buf = ""
        t0 = time.time()
        while time.time() - t0 < listen_budget:
            d = ser.read(4096)
            if d:
                buf += d.decode("utf-8", "replace")

        # 2) active probe — LIST_FILES is answered by csv_logger's export task
        ser.reset_input_buffer()
        ser.write(b"LIST_FILES\n")
        ser.flush()
        t0 = time.time()
        reply = ""
        while time.time() - t0 < probe_budget:
            d = ser.read(4096)
            if d:
                reply += d.decode("utf-8", "replace")
            if "END_LIST" in reply:
                break

    combined = buf + reply
    if "FILE:" in reply or "END_LIST" in reply:
        return True, "app running and answering LIST_FILES", combined
    if re.search(r"^[IWE] \(\d+\)", buf, re.M) or "boot:" in buf or "rst:0x" in buf:
        return True, "app running (log output seen) but no LIST_FILES reply", combined
    if buf.strip():
        return True, "some serial output seen, but not recognisable app log", combined
    return False, f"silent for {wait_s}s — no app running (blank or crash-looping)", combined


# Which firmware variant is on the board, read from its own boot banner.
# The attack role is a COMPILE-TIME flag (-DACTIVE_ATTACK / -DBLACKHOLE_ROLE /
# -DWORMHOLE_END, see run.ps1), so nothing on the device reports it at runtime —
# the banner each variant prints at startup is the only self-declaration there
# is. check_bootloader() resets the chip via esptool just before this runs, so
# the banner is normally still in the captured output.
#
# Keep these strings in sync with the ESP_LOGI banners in root_main.c,
# victim_main.c, blackhole_victim.c and wormhole_victim.c.
# These four are printed from app_main(), so they appear in the first
# milliseconds of boot and are always inside the listen window.
FIRMWARE_SIGNATURES = [
    ("=== BLACKHOLE ATTACKER (relay) STARTING ===",
     "BLACKHOLE ATTACKER  (-Attack blackhole -BlackholeRole attacker)"),
    ("=== WORMHOLE NODE A (exit) STARTING ===",
     "WORMHOLE NODE A     (-Attack wormhole -WormholeEnd A)"),
    ("=== WORMHOLE NODE B (entry) STARTING ===",
     "WORMHOLE NODE B     (-Attack wormhole -WormholeEnd B)"),
    ("=== ROOT NODE STARTING ===",
     "ROOT                (-Role root)"),
]

# A blackhole VICTIM is built from the same victim_main.c as a plain child, so
# at boot BOTH print only "=== VICTIM NODE STARTING ===". The one line that
# separates them lives in probe_gen_task() (victim_main.c:147, inside
# #if defined(BLACKHOLE_VICTIM_TARGET)) and is printed only once the mesh is
# up — typically 10-30 s after reset, well past the default listen window.
#
# So the generic banner ALONE proves "a child", never "a plain child".
# Reporting PLAIN CHILD off it would tell you a blackhole victim was
# un-attacked firmware, which is exactly the mistake this check exists to catch.
CHILD_GENERIC_BANNER = "=== VICTIM NODE STARTING ==="
BLACKHOLE_VICTIM_MARKER = "Blackhole victim mode"


def identify_firmware(text, wait_s=None):
    """(variant, how_we_know) from captured boot output. Never guesses."""
    if not text:
        return None, "no output captured"

    for sig, label in FIRMWARE_SIGNATURES:
        if sig in text:
            return label, "boot banner"

    # Mesh is up and the probe task announced its target — now it is provable.
    if BLACKHOLE_VICTIM_MARKER in text:
        return ("BLACKHOLE VICTIM    (-Attack blackhole -BlackholeRole victim)",
                "probe-generator log line")

    if CHILD_GENERIC_BANNER in text:
        hint = ""
        if wait_s is not None and wait_s < 75:
            hint = f"  Re-run with --wait 75 (currently {wait_s:g})."
        return None, (
            "a CHILD — but PLAIN CHILD and BLACKHOLE VICTIM are built from the "
            "same firmware and are identical at boot. The line that separates "
            "them is in probe_gen_task(), which starts only after "
            "mesh_setup_init() returns — and that blocks up to 60s "
            "(PHASE_STABILISE_S) when there is no mesh to join." + hint)

    # Fallback: LIST_FILES lists arrivals.csv only on a root (csv_logger.c),
    # so it separates root from child even with no banner in the buffer.
    if "arrivals.csv" in text:
        return "ROOT                (-Role root)", "LIST_FILES reply"
    if "FILE:" in text and "telem.csv" in text:
        return None, ("a CHILD of some kind (LIST_FILES shows telem.csv only, "
                      "no arrivals.csv) — but the variant needs the boot "
                      "banner; power-cycle the board and re-run")
    return None, ("banner not in the captured window — the board booted a while "
                  "ago. Power-cycle it and re-run to catch the banner")


# csv_logger.c prints this at every boot:
#   "SPIFFS mounted. Total: %u KB  Used: %u KB"
# It is the single most useful number for predicting an export failure. SPIFFS
# read/write performance collapses as it fills: at 70% full the boards logged at
# 0.75 Hz with corrupt lines (esp32-issues I-017), and on 2026-07-26 three
# boards could no longer read their own telem.csv at all — EXPORT_LOGS announced
# the right size then returned 0 rows. Checking this BEFORE a run costs seconds;
# discovering it after costs the run.
SPIFFS_RE = re.compile(r"SPIFFS mounted\.\s*Total:\s*(\d+)\s*KB\s+Used:\s*(\d+)\s*KB")
SPIFFS_WARN_PCT = 50.0


def spiffs_usage(text):
    """(used_kb, total_kb, pct) from the boot banner, or None if not seen."""
    m = SPIFFS_RE.search(text or "")
    if not m:
        return None
    # Field order is Total then Used — csv_logger.c:79 prints
    # "SPIFFS mounted. Total: %u KB  Used: %u KB". Reading them the other way
    # round reports a nearly-empty board as nearly full.
    total, used = int(m.group(1)), int(m.group(2))
    if total <= 0:
        return None
    return used, total, used * 100.0 / total


def identify(mac):
    if not mac:
        return "unknown (MAC not read)"
    m = mac.lower()
    if m in KNOWN:
        return KNOWN[m]
    # try AP-side MAC (usually STA + 1 in the last octet)
    head, last = m.rsplit(":", 1)
    try:
        alt = f"{head}:{int(last, 16) - 1:02x}"
        if alt in KNOWN:
            return KNOWN[alt] + "  [AP-side MAC]"
    except ValueError:
        pass
    return "NOT in the known roster — a spare/new board"


def main():
    ap = argparse.ArgumentParser(description="Diagnose a suspect ESP32 board.")
    ap.add_argument("--port", help="e.g. COM28")
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("--wait", type=float, default=10.0,
                    help="seconds to spend on the runtime check (default 10)")
    args = ap.parse_args()

    if args.list or not args.port:
        print("Serial ports currently present:")
        found = list(list_ports.comports())
        if not found:
            print("  (none — check the USB cable; many are charge-only)")
        for p in sorted(found, key=lambda x: x.device):
            print(f"  {p.device:<8} {p.description}")
        if not args.port:
            print("\nRe-run with --port COMxx to diagnose one.")
        return 0

    port = args.port
    print(f"\n=== BOARD HEALTH CHECK — {port} ===\n")

    ok1, d1 = check_port(port)
    print(f"[1/4] Serial port ............ {_mark(ok1)}  ({d1})")
    if not ok1:
        print("\nVERDICT: the PC cannot see this port at all.")
        print("  -> try a different USB cable (charge-only cables are the #1 cause)")
        print("  -> plug directly into the laptop, not a hub")
        print("  -> check the CH340/CP210x driver is installed")
        return 1

    # Resolve esptool BEFORE judging anything. A missing esptool is an
    # environment problem; reporting it as a bootloader FAIL would wrongly
    # condemn a perfectly good board.
    if find_esptool() is None:
        print("[2/4] Bootloader ............. SKIPPED — esptool not found")
        print("\n" + "-" * 62)
        print("VERDICT: CANNOT JUDGE THIS BOARD — esptool is not available here.")
        print("  This says NOTHING about the board. Fix the environment:")
        print("    -> run from the 'ESP-IDF 5.x PowerShell' shortcut (Start menu), or")
        print("    -> pip install esptool     (then re-run; 'python -m esptool' is used)")
        print("-" * 62)
        return 2

    ok2, d2, mac, crystal = check_bootloader(port)
    print(f"[2/4] Bootloader ............. {_mark(ok2)}  ({d2})")
    if mac:
        print(f"      MAC {mac}  ->  {identify(mac)}")
    if crystal:
        print(f"      crystal {crystal}")
    if not ok2:
        print("\nVERDICT: port exists but the chip will not answer its bootloader.")
        print("  -> hold BOOT (IO0) while the tool says 'Connecting....', then release")
        print("  -> suspect the board, the USB-serial bridge, or power")
        print("  -> if another program holds the port (a monitor), close it and retry")
        return 1

    ok3, d3, size = check_flash(port)
    print(f"[3/4] Flash chip ............. {_mark(ok3)}  ({d3})")
    if ok3 and size and EXPECTED_FLASH.lower() not in size.lower():
        print(f"      WARNING: expected {EXPECTED_FLASH} for this project's partitions.csv")

    ok4, d4, runtime_text = check_runtime(port, args.wait)
    print(f"[4/4] Firmware runtime ....... {_mark(ok4)}  ({d4})")

    variant, how = identify_firmware(runtime_text, args.wait)
    if variant:
        print(f"      firmware: {variant}   [{how}]")
    else:
        print(f"      firmware: UNDETERMINED — {how}")

    usage = spiffs_usage(runtime_text)
    if usage:
        used, total, pct = usage
        flag = "  <-- TOO FULL" if pct >= SPIFFS_WARN_PCT else "  (healthy)"
        print(f"      SPIFFS:   {used} / {total} KB used ({pct:.0f}%){flag}")
        if pct >= SPIFFS_WARN_PCT:
            print("                A full SPIFFS makes the board unable to read")
            print("                its own telem.csv — EXPORT_LOGS then announces")
            print("                the right size and returns 0 rows. Clear it")
            print("                BEFORE the run: -Wipe -Flash (guaranteed), or")
            print("                export_logs.py --wipe (verify it acks).")
    else:
        # csv_logger_init() runs AFTER mesh_setup_init() (blackhole_victim.c:125
        # then :146, and the same order in victim_main.c / root_main.c), so the
        # mount line lands seconds-to-tens-of-seconds into boot — long after the
        # startup banner and well past the default listen window. Not a fault.
        print("      SPIFFS:   not reported — csv_logger_init() runs AFTER")
        print("                mesh_setup_init(), which blocks up to 60s "
              "(PHASE_STABILISE_S)")
        print("                when there is no mesh to join — so the mount "
              "line lands")
        if args.wait < 75:
            print(f"                ~60s after reset. Re-run with --wait 75 "
                  f"(currently {args.wait:g}).")
        else:
            print("                ~60s after reset, and it still did not "
                  "appear —")
            print("                the board may not be reaching "
                  "csv_logger_init() at all.")

    print("\n" + "-" * 62)
    if ok2 and ok3 and ok4:
        print("VERDICT: BOARD IS FINE — hardware good, firmware running.")
        print("  If it still misbehaves in a run, the problem is placement/radio,")
        print("  not the board. See the runbook troubleshooting table.")
    elif ok2 and ok3 and not ok4:
        print("VERDICT: HARDWARE IS FINE — no firmware running (blank or crash-looping).")
        print("  This board is USABLE. Flash it:")
        print("    .\\run.ps1 -Port %s -Role child -Topology linear -Wipe -Flash" % port)
    else:
        print("VERDICT: SUSPECT HARDWARE — bootloader or flash did not check out.")
        print("  Retry once with a different cable before condemning it.")
    print("-" * 62)
    return 0


if __name__ == "__main__":
    sys.exit(main())
