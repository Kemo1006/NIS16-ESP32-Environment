"""
serial_guard.py — keep the CP210x driver's receive buffer from ever filling up.

WHY (oct. 7, 2026): the laptop's blue screens (bugcheck 0xB8, every dump
bucketed 0xB8_silabser!unknown_function at silabser+0xa821) are a bug in the
Silicon Labs CP210x driver, silabser.sys 11.3.0.176. Disassembling that offset
shows WHEN it fires: inside its read-complete callback (DISPATCH_LEVEL, called
from a USB DPC), once the bytes waiting in its receive buffer reach ~81 % of the
buffer size, it calls WdfIoTargetStop() to throttle the board — which Microsoft
documents as PASSIVE_LEVEL-only for a continuous-reader pipe. It waits inside the
DPC, and Windows bugchecks.

So the trigger is simply "a port is open and nobody has read it for a while".
pyserial asks the driver for a 4096-byte buffer, which crosses the 81 % mark
after ~3.3 KB — about 0.29 s of a board logging at 115200 baud, or ~36 ms of the
sniffer at 921600. A time.sleep() with a port open, a retry pause, or a stalled
consumer (Wireshark's live pipe) is enough.

Two rules, both applied by every script that opens a board's port:
  1. grow_rx_queue() right after open(): the driver honours a bigger buffer
     (its resize path only ever grows, no cap), which pushes the trip point from
     seconds to minutes.
  2. discard_for() instead of time.sleep() while a port is open: keep READING
     (and throwing away) what arrives, so the buffer never builds up at all.

esptool / idf.py monitor are Espressif's code and still use 4096; they read
continuously, so they are much less exposed, but not immune.
"""

import sys
import time

RX_QUEUE_BYTES = 1 << 20          # 1 MiB: trips only after ~74 s unread at 115200
TX_QUEUE_BYTES = 4096             # what pyserial already uses; writes are tiny


def grow_rx_queue(ser, size=RX_QUEUE_BYTES):
    """Ask the driver for a `size`-byte receive buffer. Call right after open().

    Returns True when the driver accepted it. On failure it warns and carries on
    with the small default buffer — the port still works; it is just less
    protected, so the warning says so instead of failing an export over it.
    pyserial's own set_buffer_size() ignores SetupComm's result, which is why
    this calls it directly.
    """
    if sys.platform != "win32":
        return True
    try:
        from serial import win32
        ok = bool(win32.SetupComm(ser._port_handle, size, TX_QUEUE_BYTES))
    except Exception:
        ok = False
    if not ok:
        print(f"WARNING: {getattr(ser, 'port', '?')}: driver refused a {size}-byte receive "
              "buffer - pausing reads on this port can still blue-screen the laptop.",
              file=sys.stderr)
    return ok


def discard_for(ser, seconds):
    """Wait `seconds` while still reading — and discarding — everything that arrives.

    Use this wherever a port is open and the code would otherwise time.sleep().
    It polls in_waiting rather than changing ser.timeout, because every timeout
    change makes pyserial re-apply the whole port configuration.
    """
    deadline = time.monotonic() + seconds
    while True:
        n = ser.in_waiting
        if n:
            ser.read(n)
        left = deadline - time.monotonic()
        if left <= 0:
            return
        if not n:
            time.sleep(min(0.01, left))
