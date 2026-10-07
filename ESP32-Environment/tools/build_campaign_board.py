#!/usr/bin/env python3
"""build_campaign_board.py - rebuild the campaign dashboard page from the folders.

Runs inventory_cells.py's campaign status (the same numbers as the wizard's
Campaign board) and fills tools/campaign_board_template.html with it, so the
shared "Mesh Campaign Board" page can be refreshed from any laptop:

    python tools/build_campaign_board.py               # -> datasets/campaign_board.html
    python tools/build_campaign_board.py --out my.html

Then ask Claude to republish that file to the board's existing link.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_THIS_DIR)
TEMPLATE = os.path.join(_THIS_DIR, "campaign_board_template.html")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=os.path.join(_REPO, "datasets", "campaign_board.html"))
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        status = os.path.join(tmp, "campaign_status.json")
        subprocess.run([sys.executable, os.path.join(_THIS_DIR, "inventory_cells.py"),
                        "--json", status, "--live-only"], check=True)
        with open(status, encoding="utf-8") as fh:
            data = json.load(fh)

    for x in data["slots"]:
        x.pop("slot", None)
    for se in data["sessions"]:
        se["runs"] = [{k: r[k] for k in ("attack", "scenario", "kind", "state", "why")}
                      for r in se["runs"]]
    payload = json.dumps(data, separators=(",", ":")).replace("</", r"<\/")
    with open(TEMPLATE, encoding="utf-8") as fh:
        page = fh.read().replace("__DATA__", payload)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(page)
    print(f"  campaign board -> {args.out}  ({data['total']['done']}/{data['total']['planned']} runs done)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
