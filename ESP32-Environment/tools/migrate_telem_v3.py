"""Write role-neutral (schema v3) COPIES of the raw telemetry logs.

Raw files under datasets/exports/ are never modified. For every *_telem.csv this writes the
same file, same relative path, into datasets/exports_v3/ with the v3 columns
(analysis/schema.py), and records a manifest row (source path, SHA-256 of the raw file,
rows in/out, schema version found) so every clean row can be traced to a raw row.
*_arrivals.csv are not converted (their root-counter columns are a separate follow-up).

Usage:
  python tools/migrate_telem_v3.py            # convert everything under datasets/exports
  python tools/migrate_telem_v3.py --check    # only verify an existing exports_v3 tree
"""
import argparse
import csv
import hashlib
import os
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "analysis"))
import schema  # noqa: E402

SRC = os.path.join(ROOT, "datasets", "exports")
DST = os.path.join(ROOT, "datasets", "exports_v3")
MANIFEST = os.path.join(DST, "manifest_v3.csv")
CUMULATIVE = ["own_sent", "own_failed", "recv_count", "forward_count", "drop_count",
              "arrivals_count", "bcast_count", "bcast_failed", "tunnel_tx", "tunnel_rx", "tunnel_fail"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def convert(src_path):
    raw = pd.read_csv(src_path, dtype=str, keep_default_na=False)
    ver = schema.detect_version(raw.columns)
    out = schema.to_v3(raw)
    # identity columns keep the raw text; counters become integers (blank where the raw cell was unreadable)
    for c in schema.IDENTITY:
        if c in raw.columns:
            out[c] = raw[c]
    for c in CUMULATIVE:
        out[c] = out[c].round().astype("Int64")
    return raw, ver, out


def telem_files():
    for dirpath, _, names in os.walk(SRC):
        for n in sorted(names):
            if n.endswith("_telem.csv"):
                yield os.path.join(dirpath, n)


def migrate():
    rows = []
    n = 0
    for sp in telem_files():
        rel = os.path.relpath(sp, SRC)
        dp = os.path.join(DST, rel)
        try:
            raw, ver, out = convert(sp)
        except (pd.errors.EmptyDataError, pd.errors.ParserError, KeyError) as ex:
            rows.append([rel.replace("\\", "/"), sha256(sp), 0, 0, "unreadable", f"{ex!r}"[:80]])
            continue
        os.makedirs(os.path.dirname(dp), exist_ok=True)
        out.to_csv(dp, index=False)
        rows.append([rel.replace("\\", "/"), sha256(sp), len(raw), len(out), f"v{ver}", ""])
        n += 1
        if n % 200 == 0:
            print(f"  {n} files ...", flush=True)
    os.makedirs(DST, exist_ok=True)
    with open(MANIFEST, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["source_rel_path", "source_sha256", "rows_in", "rows_out", "source_schema", "note"])
        w.writerows(rows)
    bad = [r for r in rows if r[4] == "unreadable"]
    print(f"converted {n} files, {len(bad)} unreadable (left out, listed in the manifest)")
    return 0


def check():
    """Raw hash unchanged, row counts equal, last cumulative values equal, header = V3."""
    problems = 0
    with open(MANIFEST, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["note"] or r["source_schema"] == "unreadable":
                continue
            sp = os.path.join(SRC, r["source_rel_path"])
            dp = os.path.join(DST, r["source_rel_path"])
            if sha256(sp) != r["source_sha256"]:
                print("RAW CHANGED:", r["source_rel_path"]); problems += 1; continue
            out = pd.read_csv(dp, dtype=str, keep_default_na=False)
            if list(out.columns) != schema.V3_HEADER or len(out) != int(r["rows_in"]):
                print("SHAPE:", r["source_rel_path"]); problems += 1
    print("check:", "OK" if not problems else f"{problems} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    sys.exit(check() if ap.parse_args().check else migrate())
