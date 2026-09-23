"""Check (and repair) a sniffer capture from the Mac's Wireless Diagnostics Sniffer.

Answers, without Wireshark: did the capture record anything, did it hear OUR
mesh, did it hear mesh DATA frames (not just beacons), and how long did it run.

Wireshark's "The capture file appears to have been cut short in the middle of
a packet" means only the LAST record is incomplete (file opened/copied before
the Sniffer finished writing, or capture stopped abruptly). Every packet before
it is fine. This tool writes <name>_fixed.<ext> with that partial tail dropped,
so Wireshark opens it cleanly.

Mesh nodes: ESP-WIFI-MESH beacons carry a HIDDEN (empty) SSID - "ESPM_xxxxxx"
only shows up in the child's own log - and the mesh IE is scrambled, so the
beacon body can't identify the mesh. What does: an ESP32's softAP MAC is its
STA MAC + 1. So a node = a hidden-SSID beacon sender whose MAC - 1 ALSO
transmits in the capture. Verified on the sep. 23 2026 blackhole/linear M1
capture: picked exactly the 4 boards, and none of the neighbours' hidden APs.
Beacons that DO say ESPM_* still count; --mac adds any board by hand.

Stdlib only. Handles pcap (usec/nsec, either byte order) and pcapng; link
types radiotap (127), raw 802.11 (105), Prism (119), AVS (163).

Usage: python tools/check_pcap.py <capture.pcap|.pcapng> [--no-fix] [--mac aa:bb:..]
"""
import argparse
import os
import struct
import sys

LT_80211, LT_PRISM, LT_RADIOTAP, LT_AVS = 105, 119, 127, 163


def strip_link_header(linktype, pkt):
    """Return the raw 802.11 frame, or None if the link type is unsupported."""
    if linktype == LT_80211:
        return pkt
    if linktype == LT_RADIOTAP and len(pkt) >= 4:
        return pkt[struct.unpack_from("<H", pkt, 2)[0]:]
    if linktype == LT_PRISM and len(pkt) >= 8:
        return pkt[struct.unpack_from("<I", pkt, 4)[0]:]
    if linktype == LT_AVS and len(pkt) >= 8:
        return pkt[struct.unpack_from(">I", pkt, 4)[0]:]
    return None


def read_pcap(data):
    """Yield (ts_seconds, linktype, packet); return (good_end_offset, truncated)."""
    magic = data[:4]
    if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
        e = "<"
    elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
        e = ">"
    else:
        raise ValueError("not a pcap file")
    nsec = magic in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
    linktype = struct.unpack_from(e + "I", data, 20)[0] & 0x0FFFFFFF
    off, pkts = 24, []
    while off + 16 <= len(data):
        ts_s, ts_f, incl, _orig = struct.unpack_from(e + "IIII", data, off)
        if off + 16 + incl > len(data):
            break
        pkts.append((ts_s + ts_f / (1e9 if nsec else 1e6), linktype,
                     data[off + 16: off + 16 + incl]))
        off += 16 + incl
    return pkts, off, off != len(data)


def read_pcapng(data):
    pkts, off, e = [], 0, "<"
    ifaces = []  # (linktype, ts_divisor) per interface in the current section
    while off + 12 <= len(data):
        btype = struct.unpack_from(e + "I", data, off)[0]
        if btype == 0x0A0D0D0A:  # section header: byte order lives here
            e = "<" if data[off + 8: off + 12] == b"\x4d\x3c\x2b\x1a" else ">"
            ifaces = []
        blen = struct.unpack_from(e + "I", data, off + 4)[0]
        if blen < 12 or off + blen > len(data):
            break
        body = data[off + 8: off + blen - 4]
        if btype == 1:  # interface description
            linktype = struct.unpack_from(e + "H", body, 0)[0]
            div, o = 1e6, 8
            while o + 4 <= len(body):  # options: look for if_tsresol (9)
                code, olen = struct.unpack_from(e + "HH", body, o)
                if code == 0:
                    break
                if code == 9 and olen >= 1:
                    r = body[o + 4]
                    div = float(2 ** (r & 0x7F)) if r & 0x80 else 10.0 ** r
                o += 4 + ((olen + 3) & ~3)
            ifaces.append((linktype, div))
        elif btype == 6 and len(body) >= 20:  # enhanced packet
            iid, hi, lo, cap = struct.unpack_from(e + "IIII", body, 0)
            lt, div = ifaces[iid] if iid < len(ifaces) else (LT_RADIOTAP, 1e6)
            pkts.append((((hi << 32) | lo) / div, lt, body[20: 20 + cap]))
        elif btype == 3 and len(body) >= 4:  # simple packet (iface 0, no ts)
            lt = ifaces[0][0] if ifaces else LT_RADIOTAP
            pkts.append((None, lt, body[4:]))
        off += blen
    return pkts, off, off != len(data)


def mac(b):
    return ":".join("%02x" % x for x in b)


def mac_plus_one(m):
    n = (int(m.replace(":", ""), 16) + 1) & 0xFFFFFFFFFFFF
    return ":".join("%02x" % ((n >> s) & 0xFF) for s in range(40, -8, -8))


def mac_minus_one(m):
    n = (int(m.replace(":", ""), 16) - 1) & 0xFFFFFFFFFFFF
    return ":".join("%02x" % ((n >> s) & 0xFF) for s in range(40, -8, -8))


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Check/repair a Mac sniffer capture.")
    ap.add_argument("file")
    ap.add_argument("--no-fix", action="store_true", help="don't write a _fixed copy")
    ap.add_argument("--mac", action="append", default=[],
                    help="add a board by its STA MAC (repeatable) if auto-detect misses it")
    args = ap.parse_args()

    path = args.file.strip().strip('"')
    if not os.path.isfile(path):
        print("FILE NOT FOUND: %s" % path)
        return 2
    with open(path, "rb") as f:
        data = f.read()
    print("File: %s  (%d bytes)" % (path, len(data)))
    if len(data) == 0:
        print("RESULT: FAIL - the file is EMPTY (0 bytes). The Sniffer recorded nothing,")
        print("  or you grabbed it before it was written. Wait ~10 s after Stop, re-check /var/tmp.")
        return 1

    try:
        if data[:4] == b"\x0a\x0d\x0d\x0a":
            fmt, (pkts, good_end, truncated) = "pcapng", read_pcapng(data)
        else:
            fmt, (pkts, good_end, truncated) = "pcap", read_pcap(data)
    except (ValueError, struct.error) as ex:
        print("RESULT: FAIL - not a readable pcap/pcapng file (%s)." % ex)
        print("  A .wcap from older macOS: open it in Wireshark once and 'Save As' .pcapng.")
        return 1

    print("Format: %s   packets: %d" % (fmt, len(pkts)))
    if truncated:
        print("TRUNCATED: the last %d byte(s) are a partial packet - this is what Wireshark's"
              % (len(data) - good_end))
        print("  'cut short in the middle of a packet' warning means. Everything before it is intact.")

    ts = [t for t, _, _ in pkts if t is not None]
    if len(ts) >= 2:
        span = max(ts) - min(ts)
        print("Capture span: %d min %02d s  (a full run is ~11 min + flashing time)"
              % (span // 60, span % 60))

    mesh_bssids, hidden, senders = set(), set(), set()
    types = {0: 0, 1: 0, 2: 0}
    unsupported = 0
    frames = []
    for _, lt, pkt in pkts:
        fr = strip_link_header(lt, pkt)
        if fr is None:
            unsupported += 1
            continue
        if len(fr) < 10:
            continue
        ftype, sub = (fr[0] >> 2) & 3, (fr[0] >> 4) & 0xF
        types[ftype] = types.get(ftype, 0) + 1
        frames.append((ftype, fr))
        if ftype in (0, 2) and len(fr) >= 16:
            senders.add(mac(fr[10:16]))
        if ftype == 0 and sub == 8 and len(fr) >= 38 and fr[36] == 0:  # beacon SSID IE
            ssid = fr[38: 38 + fr[37]]
            if not ssid.strip(b"\x00"):
                hidden.add(mac(fr[16:22]))
            elif ssid.startswith(b"ESPM_"):
                mesh_bssids.add(mac(fr[16:22]))

    mesh_bssids |= {b for b in hidden if mac_minus_one(b) in senders}
    for m in args.mac:  # a board's STA MAC (what the wizard's Identify prints)
        mesh_bssids.add(mac_plus_one(m.lower().replace("-", ":")))
    mesh_macs = set(mesh_bssids) | {mac_minus_one(m) for m in mesh_bssids}
    mesh_mgmt = mesh_data = 0
    per_node = {}
    for ftype, fr in frames:
        addrs = {mac(fr[4:10])}
        if len(fr) >= 16:
            addrs.add(mac(fr[10:16]))
            if ftype == 2 and mac(fr[10:16]) in mesh_macs:
                per_node[mac(fr[10:16])] = per_node.get(mac(fr[10:16]), 0) + 1
        if addrs & mesh_macs:
            if ftype == 2:
                mesh_data += 1
            elif ftype == 0:
                mesh_mgmt += 1

    print("Frame types: management %d, control %d, data %d%s"
          % (types[0], types[1], types[2],
             ("   (%d with unsupported link type)" % unsupported) if unsupported else ""))
    print("Mesh nodes heard: %d" % len(mesh_bssids))
    for b in sorted(mesh_bssids):
        sta = mac_minus_one(b)
        print("   STA %s / softAP %s   data frames sent: %d"
              % (sta, b, per_node.get(sta, 0) + per_node.get(b, 0)))
    print("Mesh frames: %d management, %d DATA" % (mesh_mgmt, mesh_data))

    if not args.no_fix and truncated and pkts:
        stem, ext = os.path.splitext(path)
        out = stem + "_fixed" + (ext or ".pcap")
        with open(out, "wb") as f:
            f.write(data[:good_end])
        print("Wrote repaired copy (partial last packet dropped): %s" % out)

    print("")
    if not pkts:
        print("RESULT: FAIL - no complete packets. Sniffer ran but captured nothing.")
        return 1
    if not mesh_bssids:
        print("RESULT: HALF - the Mac captured Wi-Fi, but NOT our mesh. Wrong channel (must be 11),")
        print("  too far from the boards, or the boards weren't running during the capture.")
        return 1
    if mesh_data == 0:
        print("RESULT: BEACONS ONLY - the Mac hears the mesh but no data frames between boards.")
        print("  Most likely the boards ran OLD firmware at 40 MHz (log: 'channel 11, 40D'), which")
        print("  a 20 MHz Mac can't decode. Reflash with MESH_FORCE_HT20=1 (boot log must say")
        print("  'RF width ... STA 20 MHz, AP 20 MHz'), and capture during baseline/attack phases.")
        return 1
    print("RESULT: PASS - mesh beacons AND %d mesh data frames captured." % mesh_data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
