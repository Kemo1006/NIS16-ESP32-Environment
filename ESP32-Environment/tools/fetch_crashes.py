#!/usr/bin/env python3
"""fetch_crashes.py — get a board's crash records off its SD card and decode them.

Since oct. 18 2026 the firmware keeps a crash's PC + backtrace and the last
[HEALTH] reading across the reboot (components/mesh_common/src/crash_record.c)
and writes ONE row per crash to  <attack>/<topology>/<location>/crashes_<node>.csv
on the SD card. A child on a powerbank has no laptop listening, so this file is
the only record of WHERE it crashed (checklist C12 / D9).

    python tools/fetch_crashes.py --port COM9 --leaf blackhole/tree/G402 --node NODE_F42DC973E618
    python tools/fetch_crashes.py --card E:\\                       (every crashes_*.csv on a pulled card)
    ... [--elf path\\to\\child_node.elf] [--out datasets/run_logs/<cell>]

Writes <out>/crashes_<node>.csv (a copy) and <out>/crashes_<node>.decoded.txt
(every PC turned into function + file:line with xtensa-esp32-elf-addr2line).
Without --elf the newest child_node.elf / root_node.elf under the build cache
is used and NAMED in the output - it must be the firmware the board ran.
Read-only on the board. Exit 0 = records found, 3 = none on the card.
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
sys.path.insert(0, HERE)


def _addr2line():
    exe = shutil.which("xtensa-esp32-elf-addr2line")
    if exe:
        return exe
    hits = sorted(glob.glob(r"C:\Espressif\tools\xtensa-esp-elf\*\xtensa-esp-elf\bin\xtensa-esp32-elf-addr2line.exe"))
    return hits[-1] if hits else None


def _guess_elf(node_role):
    pats = [r"C:\esp32b\*\*\build_*\child_node.elf", r"C:\Users\*\AppData\Local\esp32_builds\*\*\build_*\child_node.elf"]
    if node_role == "root":
        pats = [p.replace("child_node", "root_node") for p in pats]
    hits = [h for p in pats for h in glob.glob(p)]
    return max(hits, key=os.path.getmtime) if hits else None


ELF_ARCHIVE = os.path.join(os.environ.get("LOCALAPPDATA", ""), "NIS16", "elf_archive")


def _elf_for_sha(sha, node_role):
    """The archived .elf whose SHA-256 starts with `sha` (crash row column
    elf_sha, oct. 20 2026 firmware; run.ps1 archives every build), or None."""
    if not sha or sha == "-" or not os.path.isdir(ELF_ARCHIVE):
        return None
    proj = "root_node" if node_role == "root" else "child_node"
    hits = sorted(glob.glob(os.path.join(ELF_ARCHIVE, f"{sha.lower()}*_{proj}.elf"))) or         sorted(glob.glob(os.path.join(ELF_ARCHIVE, f"{sha.lower()}*.elf")))
    return hits[0] if hits else None


def decode(rows, elf, tool, node_role="child"):
    """[(row dict, [decoded lines], elf used)]. A row that names its build
    (elf_sha) is decoded against THAT archived .elf; a guessed .elf is only a
    fallback and is named in the output."""
    out = []
    for r in rows:
        pcs = [p for p in ([r.get("pc", "")] + r.get("backtrace", "").split()) if re.fullmatch(r"0x[0-9a-fA-F]{8}", p or "")]
        pcs = list(dict.fromkeys(pcs))
        lines = []
        use = _elf_for_sha(r.get("elf_sha"), node_role) or elf
        if use and tool and pcs and pcs != ["0x00000000"]:
            p = subprocess.run([tool, "-pfiaC", "-e", use] + pcs, capture_output=True, text=True, errors="replace")
            lines = [l for l in p.stdout.splitlines() if l.strip()]
        out.append((r, lines, use))
    return out


def _parse(text):
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines:
        return []
    head = lines[0].split(",")
    return [dict(zip(head, l.split(","))) for l in lines[1:]]


def save(node, text, out_dir, elf, tool):
    os.makedirs(out_dir, exist_ok=True)
    csv_path = os.path.join(out_dir, f"crashes_{node}.csv")
    with open(csv_path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text if text.endswith("\n") else text + "\n")
    rows = _parse(text)
    dec = decode(rows, elf, tool)
    txt = [f"crash records of {node} (from its SD card)", f"default elf (rows without elf_sha): {elf or 'NONE - pass --elf'}", ""]
    for r, lines, use in dec:
        sha = r.get("elf_sha") or "-"
        exact = use is not None and use != elf
        txt.append(f"boot {r.get('boot')} started after {r.get('reset_reason')}: exception {r.get('exception')} on core {r.get('core')}, pc {r.get('pc')}")
        txt.append(f"  build elf_sha {sha}: decoded with {use or 'NOTHING'}"
                   + ("" if exact else "  (NOT proven to be the build that crashed - addresses may be wrong)"))
        txt.append(f"  last [HEALTH] before it (uptime {r.get('health_uptime_s')} s): heap {r.get('heap')} B, lowest {r.get('min_heap')} B, "
                   f"largest block {r.get('big_block')} B, tightest stack {r.get('tightest_task')} = {r.get('tightest_stack_b')} B")
        txt += [f"    {l}" for l in lines] or ["    (no PCs to decode - the crash was not captured, e.g. a brownout)"]
        txt.append("")
    dec_path = os.path.join(out_dir, f"crashes_{node}.decoded.txt")
    with open(dec_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(txt))
    print("\n".join(txt))
    print(f"CRASHES: {node} {len(rows)} record(s) -> {csv_path}")
    return len(rows)


def from_port(port, leaves, node):
    import export_logs
    ser = export_logs._open_port(port)
    try:
        for leaf in leaves:
            rel = f"{leaf.strip('/')}/crashes_{node}.csv"
            rows, err, _ = export_logs._capture_with_retries(ser, f"EXPORT_SD_PATH={rel}")
            if rows and not err:
                return leaf, "\n".join(rows)
    finally:
        try:
            ser.close()
        except Exception:
            pass
    return None, None


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description="Fetch + decode a board's crashes_<node>.csv from its SD card.")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--port")
    src.add_argument("--card")
    ap.add_argument("--leaf", action="append", default=[], help="attack/topology/location folder(s) to look in (--port)")
    ap.add_argument("--node", help="NODE_<12 hex> (--port)")
    ap.add_argument("--role", default="child", choices=["child", "root"])
    ap.add_argument("--elf", default=None)
    ap.add_argument("--out", default=None, help="folder for the copy + decoded text (default: datasets/run_logs/<leaf>/crashes)")
    a = ap.parse_args()
    tool = _addr2line()
    elf = a.elf or _guess_elf(a.role)
    found = 0
    if a.card:
        for p in glob.glob(os.path.join(a.card, "*", "*", "*", "crashes_*.csv")):
            leaf = os.path.relpath(os.path.dirname(p), a.card).replace("\\", "/")
            node = os.path.basename(p)[len("crashes_"):-4]
            out = a.out or os.path.join(BASE, "datasets", "run_logs", *leaf.split("/"), "crashes")
            found += save(node, open(p, encoding="utf-8", errors="replace").read(), out, elf, tool)
    else:
        if not a.node or not a.leaf:
            print("ERROR: --port needs --node and at least one --leaf", file=sys.stderr)
            return 2
        node = a.node if a.node.startswith("NODE_") else "NODE_" + re.sub(r"[^0-9A-Fa-f]", "", a.node).upper()
        leaf, text = from_port(a.port, a.leaf, node)
        if text:
            out = a.out or os.path.join(BASE, "datasets", "run_logs", *leaf.strip("/").split("/"), "crashes")
            found += save(node, text, out, elf, tool)
    if not found:
        print("CRASHES: none on this card (no crash since the crash record firmware, oct. 18 2026)")
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
