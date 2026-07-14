#!/usr/bin/env python3
"""
validate_integrity.py — Independent integrity check for exported telemetry CSVs.

NIS16 — CTTHES2 Milestone 5 — Integrity Validation half (extraction half is
export_logs.py). Runs entirely against files already in tools/exports/ (or any
directory passed in) — no hardware required.

Checks per file (see m5_extraction/README.md for the spec this implements):
  1. Schema width   — telem.csv header is exactly the 11 csv_logger.c columns,
                       arrivals.csv exactly the 14; every data row has the same
                       field count as its header (no truncated/garbled rows).
  2. Phase coverage  — per phase_id row counts vs the Table 4.1 phase durations
                       at the 1 Hz sampling rate, generous tolerance (this flags
                       truncation, not exact counts — see PHASE_NOMINAL_S).
  3. Monotonicity    — timestamp_us never goes backwards within a file.
  4. Manifest/SHA-256 — every file gets a locked checksum in manifest.json; a
                       changed hash on a re-run means the file was altered or a
                       re-pull was not byte-identical.

Usage
-----
    cd tools
    python validate_integrity.py                  # validates ./exports (recursive)
    python validate_integrity.py exports/blackhole
    python validate_integrity.py --strict          # WARNings also fail (exit 1)
    python validate_integrity.py --relock          # accept changed hashes as new baseline

Exit code: 0 if no FAILs (WARNs allowed unless --strict), 1 otherwise.
"""

import argparse
import hashlib
import json
import os
import re
import sys

TELEM_HEADER = [
    "timestamp_us", "node_id", "role", "layer", "parent_mac",
    "rssi_dbm", "retry_count", "tx_count", "probes_count",
    "phase_id", "gt_label",
]
ARRIVALS_HEADER = TELEM_HEADER[:9] + ["phase_id", "gt_label", "src_mac", "seq_num", "latency_us"]
# probes_count is named probes_received in arrivals.csv (same position/meaning)
ARRIVALS_HEADER[8] = "probes_received"

EXPECTED_HEADERS = {"telem": TELEM_HEADER, "arrivals": ARRIVALS_HEADER}

# Table 4.1 phase durations (seconds) — fixed by the proposal, independent of
# sampling rate. Phase 0 (baseline) legitimately runs high: telemetry sampling
# starts at boot, before the first phase broadcast arrives, so the "baseline"
# bucket absorbs the unlogged 60 s stabilisation window too (observed ~358 rows
# vs the 300 s * 1 Hz spec on a real capture) — hence the wide tolerance below.
PHASE_DURATION_S = {0: 300, 1: 180, 2: 180, 3: 120}

# mesh_config.h SAMPLING_INTERVAL_MS. Raised 1000ms -> 50ms on 2026-07-12 (see
# thesis-deviate.md) so a run exceeds 10,000 rows; captures made before that date
# were at 1 Hz. Override with --sample-interval-ms when validating older data.
DEFAULT_SAMPLE_INTERVAL_MS = 50
PHASE_NAMES = {0: "baseline", 1: "blackhole", 2: "wormhole", 3: "cooldown", 4: "terminate"}
ATTACK_TO_PHASE = {"blackhole": 1, "wormhole": 2}

UNDER_TOLERANCE = 0.5   # < 50% of nominal duration's rows -> suspected truncation
OVER_TOLERANCE = 2.0    # > 200% of nominal -> suspiciously stuck/duplicated
# arrivals.csv aggregates probe arrivals from ALL victims in the mesh (root
# receives ~1 row/sec PER victim, not one total), so its row count legitimately
# scales with node count. Only the under-tolerance (truncation) check applies.

# Attacker firmware self-identifies with a distinct role string instead of
# "victim" (blackhole_victim.c / wormhole_victim.c) — both are legitimate
# identities for a board the filename tags with role=victim.
VICTIM_ROLE_ALIASES = {"victim", "blackhole", "wormhole_a", "wormhole_b"}

FILENAME_RE = re.compile(
    r"^(?P<role>root|victim)_(?P<port>[^_]+)_(?P<topology>[^_]+)_(?P<attack>[^_]+)"
    r"_r(?P<repeat>\d+)_(?P<date>\d{8})_(?P<time>\d{6})_(?P<kind>telem|arrivals)\.csv$"
)


class FileReport:
    def __init__(self, path):
        self.path = path
        self.fails = []
        self.warns = []

    def fail(self, msg):
        self.fails.append(msg)

    def warn(self, msg):
        self.warns.append(msg)

    @property
    def status(self):
        if self.fails:
            return "FAIL"
        if self.warns:
            return "WARN"
        return "PASS"


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _find_csvs(root):
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            if name.endswith("_telem.csv") or name.endswith("_arrivals.csv"):
                yield os.path.join(dirpath, name)


def _check_schema_and_monotonicity(path, kind, report):
    """Returns (rows, phase_counts) where rows excludes the header."""
    with open(path, "r", encoding="utf-8", newline="") as f:
        lines = [line.rstrip("\n").rstrip("\r") for line in f]

    if not lines or lines[0] == "":
        report.fail("file is empty (no header)")
        return [], {}

    header = lines[0].split(",")
    expected = EXPECTED_HEADERS[kind]
    if header != expected:
        report.fail(
            f"schema mismatch: expected {len(expected)} cols {expected}, "
            f"got {len(header)} cols {header}"
        )

    data_lines = [l for l in lines[1:] if l != ""]
    if not data_lines:
        report.fail("no data rows (header only)")
        return [], {}

    ts_idx = header.index("timestamp_us") if "timestamp_us" in header else 0
    phase_idx = header.index("phase_id") if "phase_id" in header else None

    rows = []
    prev_ts = None
    bad_width_rows = 0
    phase_counts = {}
    for lineno, line in enumerate(data_lines, start=2):
        fields = line.split(",")
        if len(fields) != len(header):
            bad_width_rows += 1
            continue
        rows.append(fields)

        try:
            ts = int(fields[ts_idx])
        except ValueError:
            report.fail(f"row {lineno}: non-numeric timestamp_us {fields[ts_idx]!r}")
            continue
        if prev_ts is not None and ts < prev_ts:
            report.fail(f"row {lineno}: timestamp regression ({ts} < previous {prev_ts})")
        prev_ts = ts

        if phase_idx is not None:
            try:
                phase = int(fields[phase_idx])
            except ValueError:
                phase = None
            if phase is not None:
                phase_counts[phase] = phase_counts.get(phase, 0) + 1

    if bad_width_rows:
        report.fail(
            f"{bad_width_rows} row(s) have a field count that doesn't match the "
            f"header ({len(header)} cols) — truncated/garbled data"
        )

    return rows, phase_counts


def _check_phase_coverage(phase_counts, attack, kind, sample_interval_ms, report):
    attack_phase = ATTACK_TO_PHASE.get(attack)
    # arrivals.csv aggregates ~1 row/sec PER VICTIM (root receives from every
    # node), so its counts legitimately exceed the single-node nominal — only
    # check for truncation (too few), never "too many".
    check_upper_bound = kind != "arrivals"
    rate_hz = 1000.0 / sample_interval_ms

    for phase_id, duration_s in PHASE_DURATION_S.items():
        nominal = duration_s * rate_hz
        is_attack_phase = phase_id in ATTACK_TO_PHASE.values()
        if is_attack_phase and phase_id != attack_phase:
            # Not this run's attack phase: rows should be ~0 (baseline-only or a
            # different attack). A meaningful count here means phase-id bleed.
            count = phase_counts.get(phase_id, 0)
            if count > 0:
                report.warn(
                    f"phase {phase_id} ({PHASE_NAMES[phase_id]}) has {count} rows "
                    f"but filename attack='{attack}' — unexpected phase bleed"
                )
            continue

        count = phase_counts.get(phase_id, 0)
        if count == 0:
            report.warn(
                f"phase {phase_id} ({PHASE_NAMES[phase_id]}) has 0 rows — "
                f"expected ~{nominal:.0f} (missing phase, possible truncation)"
            )
            continue

        ratio = count / nominal
        if ratio < UNDER_TOLERANCE:
            report.warn(
                f"phase {phase_id} ({PHASE_NAMES[phase_id]}) has {count} rows, "
                f"expected ~{nominal:.0f} at {rate_hz:.1f} Hz (ratio {ratio:.2f} < "
                f"{UNDER_TOLERANCE}) — possible truncation"
            )
        elif check_upper_bound and ratio > OVER_TOLERANCE:
            report.warn(
                f"phase {phase_id} ({PHASE_NAMES[phase_id]}) has {count} rows, "
                f"expected ~{nominal:.0f} at {rate_hz:.1f} Hz (ratio {ratio:.2f} > "
                f"{OVER_TOLERANCE}) — possible stuck/duplicated sampling"
            )


def _check_role_consistency(rows, header, meta, report):
    if not rows or "role" not in header:
        return
    role_idx = header.index("role")
    csv_role = rows[0][role_idx]
    filename_role = meta["role"] if meta else None
    if not filename_role:
        return
    if filename_role == "victim":
        ok = csv_role in VICTIM_ROLE_ALIASES
    else:
        ok = csv_role == filename_role
    if not ok:
        report.warn(
            f"role in CSV ('{csv_role}') doesn't match role in filename "
            f"('{filename_role}')"
        )


def _load_manifest(manifest_path):
    if os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def _save_manifest(manifest_path, manifest):
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")


def _check_manifest(rel_path, digest, size, row_count, manifest, relock, report):
    entry = manifest.get(rel_path)
    if entry is None:
        manifest[rel_path] = {
            "sha256": digest, "size_bytes": size, "row_count": row_count,
        }
        return
    if entry["sha256"] != digest:
        if relock:
            report.warn("hash changed since last validation — accepted (--relock)")
            manifest[rel_path] = {
                "sha256": digest, "size_bytes": size, "row_count": row_count,
            }
        else:
            report.fail(
                f"hash mismatch vs manifest: file changed since last validated "
                f"(was {entry['sha256'][:12]}…, now {digest[:12]}…) — re-run with "
                f"--relock if this change was intentional"
            )
    else:
        manifest[rel_path]["row_count"] = row_count  # keep in sync, hash unchanged


def validate(target_dir, manifest_path, relock, sample_interval_ms):
    reports = []
    manifest = _load_manifest(manifest_path)

    for path in _find_csvs(target_dir):
        report = FileReport(path)
        name = os.path.basename(path)
        kind = "telem" if name.endswith("_telem.csv") else "arrivals"
        meta_match = FILENAME_RE.match(name)
        meta = meta_match.groupdict() if meta_match else None
        if meta is None:
            report.warn("filename doesn't match the export_logs.py naming convention")

        rows, phase_counts = _check_schema_and_monotonicity(path, kind, report)
        if rows:
            _check_role_consistency(rows, EXPECTED_HEADERS[kind], meta, report)
            if meta:
                _check_phase_coverage(phase_counts, meta["attack"], kind, sample_interval_ms, report)

        digest = _sha256(path)
        size = os.path.getsize(path)
        rel_path = os.path.relpath(path, target_dir).replace(os.sep, "/")
        _check_manifest(rel_path, digest, size, len(rows), manifest, relock, report)

        reports.append(report)

    _save_manifest(manifest_path, manifest)
    return reports


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("directory", nargs="?", default="exports",
                    help="Directory of exported CSVs to validate (recursive). Default: exports")
    p.add_argument("--manifest", default=None,
                    help="Manifest JSON path. Default: <directory>/manifest.json")
    p.add_argument("--strict", action="store_true",
                    help="Treat WARNings as failures too (nonzero exit).")
    p.add_argument("--relock", action="store_true",
                    help="Accept a changed hash as the new locked baseline instead of failing.")
    p.add_argument("--sample-interval-ms", type=float, default=DEFAULT_SAMPLE_INTERVAL_MS,
                    help=f"mesh_config.h SAMPLING_INTERVAL_MS at capture time (default: "
                         f"{DEFAULT_SAMPLE_INTERVAL_MS}, the current firmware value). Use "
                         f"1000 for captures made before the 2026-07-12 rate change.")
    args = p.parse_args()

    if not os.path.isdir(args.directory):
        print(f"ERROR: no such directory: {args.directory}", file=sys.stderr)
        return 1

    manifest_path = args.manifest or os.path.join(args.directory, "manifest.json")
    reports = validate(args.directory, manifest_path, args.relock, args.sample_interval_ms)

    if not reports:
        print(f"No *_telem.csv / *_arrivals.csv files found under {args.directory}")
        return 1

    counts = {"PASS": 0, "WARN": 0, "FAIL": 0}
    for r in reports:
        counts[r.status] += 1
        print(f"[{r.status}] {os.path.relpath(r.path, args.directory)}")
        for msg in r.fails:
            print(f"    FAIL: {msg}")
        for msg in r.warns:
            print(f"    WARN: {msg}")

    print(
        f"\n{len(reports)} file(s) — {counts['PASS']} PASS, {counts['WARN']} WARN, "
        f"{counts['FAIL']} FAIL. Manifest: {manifest_path}"
    )

    any_fail = counts["FAIL"] > 0 or (args.strict and counts["WARN"] > 0)
    return 1 if any_fail else 0


if __name__ == "__main__":
    sys.exit(main())
