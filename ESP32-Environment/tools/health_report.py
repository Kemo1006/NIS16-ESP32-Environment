#!/usr/bin/env python3
"""health_report.py — what a board's [HEALTH] lines say before it crashed.

Reads a crash-watch / monitor log (datasets/run_logs/.../<board>_<port>_serial_*.log)
for the "[HEALTH]" lines the firmware prints every 30 s
(components/mesh_common/src/health_log.c) and shows:
  * free heap over time, its lowest point, and whether it was falling
  * per task, the least stack it ever had left (the tightest one first)
  * any LOW HEAP / LOW STACK warning, and the crash lines found in the same log
so a crash (checklist C12 / D9) can be told apart: slow leak, stack running out,
or a sudden bug with healthy memory (then the backtrace points at the line).

    python tools/health_report.py datasets/run_logs/blackhole/tree/G402/stationary/node4_COM11_serial_*.log
"""
import glob
import re
import sys

RX = re.compile(r"\[HEALTH\] up=(\d+)s heap=(\d+) min=(\d+) big=(\d+) \| stack free\(B\):(.*)$")
CRASH = re.compile(r"Guru Meditation|abort\(\) was called|Backtrace:|Brownout|Task watchdog|Interrupt wdt|stack overflow|CORRUPT HEAP|assert failed|rst:0x", re.I)


def report(path):
    rows, tasks, warns, crashes = [], {}, [], []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = re.sub(r"\x1b\[[0-9;]*m", "", line).rstrip()
        m = RX.search(line)
        if m:
            up, heap, low, big = (int(m.group(i)) for i in range(1, 5))
            rows.append((up, heap, low, big))
            for name, val in re.findall(r"(\w+)=(\d+)", m.group(5)):
                tasks[name] = min(tasks.get(name, 10 ** 9), int(val))
        elif "[HEALTH] LOW" in line:
            warns.append(line.split("[HEALTH]", 1)[1].strip())
        elif CRASH.search(line):
            crashes.append(line.strip()[:160])
    print(f"== {path}")
    if not rows:
        print("   no [HEALTH] lines (firmware from before oct. 18 2026, or the log is empty)")
    else:
        first, last = rows[0], rows[-1]
        trend = last[1] - first[1]
        print(f"   {len(rows)} health line(s), uptime {first[0]}-{last[0]} s")
        print(f"   free heap: {first[1]:,} -> {last[1]:,} B ({'+' if trend >= 0 else ''}{trend:,});  lowest ever {min(r[2] for r in rows):,} B;  "
              f"largest block at the end {last[3]:,} B")
        if len(rows) >= 4 and all(rows[i + 1][1] <= rows[i][1] for i in range(len(rows) - 4, len(rows) - 1)):
            print("   ! the free heap kept FALLING over the last readings - a leak is likely")
        tight = sorted(tasks.items(), key=lambda kv: kv[1])
        print("   least stack left per task (B): " + ", ".join(f"{k}={v}" for k, v in tight))
    for w in warns:
        print(f"   WARNING: {w}")
    print(f"   crash lines in this log: {len(crashes)}")
    for c in crashes[:8]:
        print(f"     {c}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    paths = [p for a in sys.argv[1:] for p in (glob.glob(a) or [a])]
    for p in paths:
        report(p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
