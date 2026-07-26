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
  4. Label integrity — gt_label matches the Table 4.1 phase->label map on every
                       row (the ground-truth column M8 separates on); a mismatch
                       is a mislabel or a field-shifted row the width check missed.
  5. Manifest/SHA-256 — every file gets a locked checksum in manifest.json; a
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

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))

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

# mesh_config.h SAMPLING_INTERVAL_MS. Timeline of the firmware value:
#   pre-2026-07-12 : 1000ms (1 Hz)  -> validate with --sample-interval-ms 1000
#   2026-07-12     :   50ms (20 Hz) -> validate with --sample-interval-ms 50
#   2026-07-25     :  200ms (5 Hz)  -> the one baseline/linear capture made that day
#   2026-07-25     :  100ms (10 Hz) -> the default below (campaign rate)
# Captures are NOT self-describing: the rate is not stored in the CSV, so you
# must pass the rate that was in the firmware AT CAPTURE TIME when validating
# anything older than the current default, or phase-coverage checks will be
# judged against the wrong expected row counts.
DEFAULT_SAMPLE_INTERVAL_MS = 100
PHASE_NAMES = {0: "baseline", 1: "blackhole", 2: "wormhole", 3: "cooldown", 4: "terminate"}
ATTACK_TO_PHASE = {"blackhole": 1, "wormhole": 2}

UNDER_TOLERANCE = 0.5   # < 50% of nominal duration's rows -> suspected truncation
OVER_TOLERANCE = 2.0    # > 200% of nominal -> suspiciously stuck/duplicated
# For *_arrivals.csv only: probes still reaching the root DURING the attack
# window, as a fraction of that same run's baseline arrival rate. Some leakage is
# normal (packets already queued when the phase flips); more than this means the
# drop never really took hold and the run does not show the attack.
# Applies to DROP-signature attacks only — see ATTACK_SIGNATURE.
ATTACK_LEAK_TOLERANCE = 0.5

# What the attack does to the root's arrivals log — the two are opposites, and a
# check written for one declares a perfect capture of the other broken:
#   drop      blackhole  probes STOP arriving (0 rows during the window)
#   duplicate wormhole   probes arrive TWICE (Node B's are replayed out of the
#                        UART tunnel, so arrivals go ABOVE baseline)
ATTACK_SIGNATURE = {"blackhole": "drop", "wormhole": "duplicate"}

# gt_label ground-truth encoding: every node in a run carries the SAME per-phase
# label (verified uniform across root / attacker / control-victim / wormhole
# endpoints in tools/exports/). The label is the attack active during that phase,
# NOT whether this particular board is the attacker — baseline & cooldown are
# benign (0), the two attack phases carry their attack code. M8's baseline-vs-
# attack separation depends on this column being correct, so validate it.
PHASE_TO_LABEL = {0: 0, 1: 1, 2: 2, 3: 0, 4: 0}
# Fraction of correctly-sized rows whose gt_label may disagree with the phase→
# label map before it's treated as a real mislabel (not a 1-row phase boundary).
LABEL_MISMATCH_FAIL_FRACTION = 0.01
# arrivals.csv aggregates probe arrivals from ALL victims in the mesh (root
# receives ~1 row/sec PER victim, not one total), so its row count legitimately
# scales with node count AND with how often the victims probe. Neither is known
# here, so it gets its own check entirely — see _check_arrivals_coverage.

# Attacker firmware self-identifies with a distinct role string instead of
# "victim" (blackhole_victim.c / wormhole_victim.c) — both are legitimate
# identities for a board the filename tags with role=victim.
VICTIM_ROLE_ALIASES = {"victim", "blackhole", "wormhole_a", "wormhole_b"}

# export_logs.py names files "<role>_..." where --role is root | child | victim
# (default: child). The regex MUST list all three — an earlier version only
# accepted root|victim, so every child_*.csv failed to parse and silently
# skipped its phase-coverage and role checks. Keep this in sync with the
# --role choices in export_logs.py.
FILENAME_RE = re.compile(
    r"^(?P<role>root|victim|child)_(?P<port>[^_]+)_(?P<topology>[^_]+)_(?P<attack>[^_]+)"
    r"_r(?P<repeat>\d+)_(?P<date>\d{8})_(?P<time>\d{6})_(?P<kind>telem|arrivals)\.csv$"
)


class FileReport:
    def __init__(self, path):
        self.path = path
        self.fails = []
        self.warns = []
        self.infos = []

    def fail(self, msg):
        self.fails.append(msg)

    def warn(self, msg):
        self.warns.append(msg)

    def info(self, msg):
        """A measurement worth printing that is NOT a problem. Never affects
        status — used by the arrivals check to report the probe rate it found
        instead of warning about a count it has no nominal for."""
        self.infos.append(msg)

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


def _phase_stats(rows, header):
    """Per-phase count / span / rate / src_macs, plus the (src_mac, seq_num)
    multiset needed to spot the wormhole's duplicate deliveries."""
    ts_idx = header.index("timestamp_us")
    ph_idx = header.index("phase_id")
    mac_idx = header.index("src_mac") if "src_mac" in header else None
    seq_idx = header.index("seq_num") if "seq_num" in header else None

    stats = {}
    for fields in rows:
        try:
            phase = int(fields[ph_idx])
            ts = int(fields[ts_idx])
        except (ValueError, IndexError):
            continue
        st = stats.setdefault(phase, {"count": 0, "lo": ts, "hi": ts,
                                      "macs": set(), "pairs": {}})
        st["count"] += 1
        st["lo"] = min(st["lo"], ts)
        st["hi"] = max(st["hi"], ts)
        if mac_idx is not None and mac_idx < len(fields):
            mac = fields[mac_idx]
            st["macs"].add(mac)
            if seq_idx is not None and seq_idx < len(fields):
                key = (mac, fields[seq_idx])
                st["pairs"][key] = st["pairs"].get(key, 0) + 1
    for st in stats.values():
        st["span_s"] = (st["hi"] - st["lo"]) / 1e6
        st["rate_hz"] = st["count"] / st["span_s"] if st["span_s"] > 0 else 0.0
        # A probe the root logged more than once = the same (src_mac, seq_num)
        # delivered twice: once over the mesh, once out of the wormhole tunnel.
        st["dup_rows"] = sum(n - 1 for n in st["pairs"].values() if n > 1)
        st["dup_macs"] = sorted({mac for (mac, _), n in st["pairs"].items() if n > 1})
    return stats


def _check_attack_phase(phase_id, st, count, base, base_rate, attack, report):
    """Did the attack actually happen? Judged by ITS OWN signature."""
    name = PHASE_NAMES[phase_id]

    if ATTACK_SIGNATURE.get(attack) == "duplicate":
        # Wormhole: Node B's probes are tunnelled over UART and replayed, so the
        # root logs the same (src_mac, seq_num) twice. Volume alone proves
        # nothing — a wormhole that delivers ONE copy is indistinguishable from
        # no attack at all, so test the duplicates, not the rate.
        if count == 0:
            report.warn(
                f"phase {phase_id} ({name}) has 0 probe arrivals — a wormhole "
                f"duplicates traffic, it does not stop it; the mesh was down or "
                f"the capture is truncated"
            )
            return
        dup = st["dup_rows"]
        rate_txt = (f"{count} probes at {st['rate_hz']:.2f}/s = "
                    f"{st['rate_hz'] / base_rate:.0%} of baseline" if base_rate
                    else f"{count} probes")
        if dup == 0:
            report.warn(
                f"phase {phase_id} ({name}): {rate_txt}, but NOT ONE probe "
                f"arrived twice — "
                f"the tunnel delivered nothing. Check the UART wire "
                f"(uart_link_test) and that Node A's probes_count is climbing"
            )
            return
        uniq = len(st["pairs"])
        report.info(
            f"phase {phase_id} ({name}): {rate_txt}; {dup} of them are DUPLICATE "
            f"deliveries of {uniq} unique probes (x{count / uniq:.2f}) from "
            f"{', '.join(st['dup_macs'])} — the expected wormhole signature"
        )
        if base["dup_rows"]:
            report.warn(
                f"phase 0 (baseline) already had {base['dup_rows']} duplicate "
                f"probe arrival(s) before the tunnel opened — the duplication in "
                f"phase {phase_id} is not attributable to the wormhole alone"
            )
        return

    # Blackhole (default): the attack means probes STOP reaching the root.
    if count == 0:
        report.info(
            f"phase {phase_id} ({name}): 0 probes reached the root — total drop, "
            f"the expected attack signature (baseline was {base_rate:.2f}/s)"
        )
        return
    leak = st["rate_hz"] / base_rate if base_rate else 0.0
    msg = (f"phase {phase_id} ({name}): {count} probes still reached the root at "
           f"{st['rate_hz']:.2f}/s = {leak:.0%} of baseline")
    if leak > ATTACK_LEAK_TOLERANCE:
        report.warn(msg + " — the attack did not take effect; check the "
                          "attacker's tx_count is flat across this phase")
    else:
        report.info(msg + " (partial drop)")


def _check_arrivals_coverage(rows, header, attack, report):
    """Phase coverage for *_arrivals.csv, which is an EVENT LOG — not a sampler.

    telem.csv is written by a periodic sampler, so "rows vs duration x rate" is a
    sound truncation test. arrivals.csv holds one row per probe that actually
    REACHED the root, arriving at whatever rate the victims probe (~1 Hz each,
    so ~4 Hz for a four-victim mesh) — a rate this script cannot know in advance.
    Scoring it against the 10 Hz telemetry rate flagged every healthy capture at
    ratio ~0.4, and reported the attack phase's 0 rows as "missing phase,
    possible truncation" when that zero IS the result the run exists to produce
    (Milestone 2: "zero forwarded probes reach the root during the attack
    window"). Three WARNs on a perfect capture, every repeat. See 2026-07-26.md.

    So: measure the probe rate per phase and report it, and test for truncation
    against the file's OWN baseline rate rather than a fixed nominal.
    """
    attack_phase = ATTACK_TO_PHASE.get(attack)
    stats = _phase_stats(rows, header)

    base = stats.get(0)
    if not base or not base["count"]:
        report.warn(
            "phase 0 (baseline) has 0 probe arrivals — the root logged no probes "
            "before the attack window, so there is no reference rate. Capture is "
            "truncated or no victim was probing."
        )
        return
    base_rate = base["rate_hz"]
    report.info(
        f"phase 0 (baseline): {base['count']} probes from {len(base['macs'])} "
        f"victim(s) over {base['span_s']:.0f}s = {base_rate:.2f}/s (reference rate)"
    )

    for phase_id in sorted(PHASE_DURATION_S):
        if phase_id == 0:
            continue
        st = stats.get(phase_id)
        count = st["count"] if st else 0
        is_attack_phase = phase_id in ATTACK_TO_PHASE.values()

        # Some other attack's phase: any rows here mean phase-id bleed. Unchanged.
        if is_attack_phase and phase_id != attack_phase:
            if count > 0:
                report.warn(
                    f"phase {phase_id} ({PHASE_NAMES[phase_id]}) has {count} rows "
                    f"but filename attack='{attack}' — unexpected phase bleed"
                )
            continue

        if is_attack_phase:
            # THE measurement of the run — and the two attacks look OPPOSITE here,
            # so the test has to know which one it is looking at. A blackhole
            # DROPS (arrivals fall to zero); a wormhole DUPLICATES (arrivals rise
            # above baseline as Node B's probes land twice). Scoring the wormhole
            # with the blackhole's rule called a textbook capture a failure:
            # linear/wormhole/r1 warned "125% of baseline — the attack did not
            # take effect" when that 125% WAS the tunnel working. See 2026-07-26.md.
            _check_attack_phase(phase_id, st, count, base, base_rate, attack, report)
            continue

        # Benign phase (cooldown): probes should flow again at ~the baseline rate.
        if count == 0:
            report.warn(
                f"phase {phase_id} ({PHASE_NAMES[phase_id]}) has 0 probe arrivals — "
                f"expected traffic to resume at ~{base_rate:.2f}/s (missing phase, "
                f"possible truncation)"
            )
            continue
        ratio = st["rate_hz"] / base_rate if base_rate else 0.0
        line = (f"phase {phase_id} ({PHASE_NAMES[phase_id]}): {count} probes from "
                f"{len(st['macs'])} victim(s) over {st['span_s']:.0f}s = "
                f"{st['rate_hz']:.2f}/s ({ratio:.0%} of baseline)")
        if ratio < UNDER_TOLERANCE:
            report.warn(line + " — rate collapsed vs this run's own baseline, "
                               "possible truncation")
        elif st["macs"] < base["macs"]:
            report.warn(
                line + f" — victim(s) {sorted(base['macs'] - st['macs'])} probed "
                f"during baseline but never returned after the attack"
            )
        else:
            report.info(line)


def _check_phase_coverage(phase_counts, attack, kind, sample_interval_ms, report):
    attack_phase = ATTACK_TO_PHASE.get(attack)
    check_upper_bound = True
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
    # "child" and "victim" are the same board position (export_logs.py keeps
    # "victim" as an alias for "child"); both can carry any non-root node_role.
    if filename_role in ("victim", "child"):
        ok = csv_role in VICTIM_ROLE_ALIASES
    else:
        ok = csv_role == filename_role
    if not ok:
        report.warn(
            f"role in CSV ('{csv_role}') doesn't match role in filename "
            f"('{filename_role}')"
        )


def _check_label_integrity(rows, header, report):
    """gt_label must equal PHASE_TO_LABEL[phase_id] on every row.

    This is the M5 "label" validator: the ground-truth column M8 trains its
    baseline-vs-attack separation on. A row whose gt_label disagrees with its
    phase is either a mislabel (firmware/labeling bug) or a field-shifted row
    that still happens to have the right column count, so the width check missed
    it. Only correctly-sized rows reach here (schema check filters the rest)."""
    if not rows:
        return
    if "gt_label" not in header or "phase_id" not in header:
        return  # schema check already FAILs on a missing column
    label_idx = header.index("gt_label")
    phase_idx = header.index("phase_id")

    mismatches = 0
    unknown_phase = 0
    examples = []
    for fields in rows:
        try:
            phase = int(fields[phase_idx])
            label = int(fields[label_idx])
        except (ValueError, IndexError):
            mismatches += 1
            continue
        expected = PHASE_TO_LABEL.get(phase)
        if expected is None:
            unknown_phase += 1
            continue
        if label != expected:
            mismatches += 1
            if len(examples) < 3:
                examples.append(f"phase {phase}->gt_label {label} (expected {expected})")

    if unknown_phase:
        report.warn(
            f"{unknown_phase} row(s) have a phase_id outside the Table 4.1 set "
            f"{sorted(PHASE_TO_LABEL)} — gt_label can't be checked for those"
        )

    if mismatches:
        frac = mismatches / len(rows)
        detail = "; ".join(examples)
        msg = (
            f"{mismatches}/{len(rows)} row(s) ({frac:.1%}) have gt_label "
            f"inconsistent with phase_id [{detail}] — mislabel or field shift"
        )
        if frac > LABEL_MISMATCH_FAIL_FRACTION:
            report.fail(msg)
        else:
            report.warn(msg)


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
            _check_label_integrity(rows, EXPECTED_HEADERS[kind], report)
            if meta:
                if kind == "arrivals":
                    _check_arrivals_coverage(rows, EXPECTED_HEADERS[kind],
                                             meta["attack"], report)
                else:
                    _check_phase_coverage(phase_counts, meta["attack"], kind,
                                          sample_interval_ms, report)

        digest = _sha256(path)
        size = os.path.getsize(path)
        rel_path = os.path.relpath(path, target_dir).replace(os.sep, "/")
        _check_manifest(rel_path, digest, size, len(rows), manifest, relock, report)

        reports.append(report)

    _save_manifest(manifest_path, manifest)
    return reports


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    # Default resolves RELATIVE TO THIS SCRIPT, not the shell's CWD — a bare
    # "exports" validates whatever stray folder happens to sit in the directory
    # you ran from (usually nothing, so it reports 0 files and looks like a pass).
    p.add_argument("directory", nargs="?",
                    default=os.path.join(_THIS_DIR, "exports"),
                    help="Directory of exported CSVs to validate (recursive). "
                         "Default: the exports/ folder next to this script.")
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
        for msg in r.infos:
            print(f"    info: {msg}")

    print(
        f"\n{len(reports)} file(s) — {counts['PASS']} PASS, {counts['WARN']} WARN, "
        f"{counts['FAIL']} FAIL. Manifest: {manifest_path}"
    )

    any_fail = counts["FAIL"] > 0 or (args.strict and counts["WARN"] > 0)
    return 1 if any_fail else 0


if __name__ == "__main__":
    sys.exit(main())
