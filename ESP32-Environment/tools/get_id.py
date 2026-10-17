"""
get_id.py - which board is on this port, WITHOUT resetting it (oct. 17 2026).

esptool read_mac (tools/Get-EspMac.ps1) pulls EN low, so the board REBOOTS -
fine for a board that was just plugged in, fatal for one in the middle of a
run. This asks the running firmware instead: the port is opened with DTR/RTS
deasserted (export_logs.py's rule, so nothing resets), the GET_ID command is
sent, and the reply "ID:NODE_<12 hex>" is the same eFuse MAC read_mac prints.

Prints the MAC (aa:bb:cc:dd:ee:ff) and exits 0, or exits 3 when the board did
not answer (firmware older than GET_ID, still booting, or blank) - the caller
then decides whether a resetting read_mac is acceptable.

    python get_id.py --port COM7 [--timeout 2]
"""

import argparse
import re
import sys
import time

import serial

import serial_guard

ID_RE = re.compile(rb"ID:NODE_([0-9A-Fa-f]{12})")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--port", required=True)
    p.add_argument("--timeout", type=float, default=2.0)
    a = p.parse_args()

    ser = serial.Serial()
    ser.port = a.port
    ser.baudrate = 115200
    ser.timeout = 0.05
    ser.dtr = False
    ser.rts = False
    try:
        ser.open()
    except serial.SerialException as e:
        print(f"could not open {a.port}: {e}", file=sys.stderr)
        return 2
    try:
        serial_guard.grow_rx_queue(ser)
        ser.write(b"\r\nGET_ID\r\n")
        buf = b""
        end = time.monotonic() + a.timeout
        while time.monotonic() < end:          # read non-stop: never leave bytes waiting
            buf += ser.read(4096)
            m = ID_RE.search(buf)
            if m:
                h = m.group(1).decode().lower()
                print(":".join(h[i:i + 2] for i in range(0, 12, 2)))
                return 0
            if len(buf) > 65536:
                buf = buf[-256:]
    finally:
        ser.close()
    print(f"no GET_ID answer from {a.port}", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
