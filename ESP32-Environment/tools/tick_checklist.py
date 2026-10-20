#!/usr/bin/env python3
"""
tick_checklist.py - mark ONE row of docs/deviations-limitations/THESIS-UPDATE-CHECKLIST.md
done (oct. 20 2026, user: "how to tick it - is it possible to put it in the GUI also?").

    python tools/tick_checklist.py D2 --note "superseded by the oct. 19 7:45 PM recapture, all 8 boards, verified #65"
    python tools/tick_checklist.py D2 --show          (print the row, change nothing)

The row's status cell (⬜ / 🟨) becomes "✅ (<date>)" and "**done: <note>**" is appended to
its 'Why' column - the same shape as the rows ticked by hand (D1). Exactly one row is
touched; a row that is already ✅, or that is not found, is refused (exit 2). The GUI's
Verify page (RUN STATUS card) calls this for a "newer capture exists - tick Dn" reason.
Exit 0 = ticked, 2 = refused.
"""
import argparse
import os
import re
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKLIST = os.path.join(os.path.dirname(HERE), "docs", "deviations-limitations", "THESIS-UPDATE-CHECKLIST.md")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description="Tick one row of the thesis update checklist.")
    ap.add_argument("row", help="row id, e.g. D2, C19, A33")
    ap.add_argument("--note", default="", help="why it is done (evidence) - appended to the row")
    ap.add_argument("--show", action="store_true", help="print the row only")
    ap.add_argument("--file", default=CHECKLIST)
    a = ap.parse_args()
    rid = a.row.strip().upper()
    with open(a.file, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    hits = [i for i, ln in enumerate(lines) if re.match(rf"\|\s*{re.escape(rid)}\s*\|", ln)]
    if len(hits) != 1:
        print(f"TICK: REFUSED - {len(hits)} row(s) named {rid} in the checklist (need exactly 1)")
        return 2
    i = hits[0]
    cells = lines[i].split("|")          # ['', ' D2 ', ' ⬜ ', what, why, source, '']
    if a.show:
        print(lines[i])
        return 0
    if len(cells) < 7:
        print(f"TICK: REFUSED - row {rid} does not have the 5 checklist columns")
        return 2
    status = cells[2].strip()
    if status.startswith("✅"):
        print(f"TICK: REFUSED - {rid} is already done: {status}")
        return 2
    if not (status.startswith("⬜") or status.startswith("🟨")):
        print(f"TICK: REFUSED - {rid} has status '{status}' (only open ⬜ / 🟨 rows are ticked)")
        return 2
    today = date.today()
    cells[2] = f" ✅ ({today:%b}. {today.day}, {today.year}) ".lower()
    note = " ".join(a.note.split())
    if note:
        cells[4] = cells[4].rstrip() + f" - **done: {note}** "
    lines[i] = "|".join(cells)
    with open(a.file, "w", encoding="utf-8", newline="") as fh:
        fh.write("\n".join(lines))
    print(f"TICK: OK - {rid} marked done" + (f" ({note})" if note else ""))
    print(lines[i])
    return 0


if __name__ == "__main__":
    sys.exit(main())
