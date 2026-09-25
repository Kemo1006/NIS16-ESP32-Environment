"""
preprocess.py — NIS16 Milestone 6: Cross-Layer Data Preprocessing Pipeline

Converts raw per-node CSV telemetry logs (1 Hz samples) into a clean,
windowed, analyzable DataFrame.

Implements thesis Section 4.2.4.1 "Preprocessing" and Table 4.10
"Window Aggregation":
  - Per-node timestamp re-basing (each node's clock starts at 0)
  - Missing-sample handling (interpolate / forward-fill / discard, per the
    rules in Section 4.2.4.1 "Handling Missing Values")
  - Cumulative-counter → per-window delta conversion (Equation 4.1)
  - 5-second non-overlapping window aggregation (Table 4.10)
  - Modal phase-label assignment per window (ground truth for downstream
    clustering — Milestone 8 onward)
  - Window-completeness threshold: discard any window with < 4 of the
    expected 5 one-second samples (Section 4.2.4.1, point 4)

This module is deliberately decoupled from real hardware: it operates on
any folder of CSVs matching the schema written by csv_logger.c, so it can
be developed and unit-tested against synthetic data (see generate_fake_data.py)
while Milestone 1 hardware bring-up is still in progress.

Scope note: this script produces the *windowed aggregate* table (raw
per-window statistics — means, deltas, event counts). The 16 named
features from Table 4.11 (ForwardingRatio, RetryRate, PDR, etc.) are
Milestone 7's responsibility and are computed from this table's output,
not inside it. Keeping the boundary here matches how the two milestones
are scored separately on the CTTHES2 milestones form.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
from dataclasses import dataclass, field

# Windows consoles default to a codepage (e.g. cp1252) that can't encode the
# box-drawing characters (─) used in the printed quality report below.
# Reconfigure to UTF-8 so this script's own diagnostic output never crashes
# the run after the real work (the output CSV) is already written.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
import pandas as pd

# ─────────────────────────────────────────────────────────────────────────
# Constants — kept here rather than scattered through the code so any
# future window-length sensitivity analysis (CTTHES3) only touches one
# place.
# ─────────────────────────────────────────────────────────────────────────

# Analysis grid rate, in Hz. The firmware already captures at 10 Hz
# (SAMPLING_INTERVAL_MS 100U); this is the rate we ANALYSE at. Was 1 Hz, which
# threw 9 of every 10 captured samples away (thesis-deviate D-1). Raised to 10 Hz
# on 2026-09-16 so a 1-second window still carries 10 samples — MORE statistical
# support per window than the old 5-second/1 Hz window's 5. See D-9.
# To revert to the paper's literal configuration: GRID_HZ=1, WINDOW_SECONDS=5,
# MIN_VALID_SAMPLES=4. Nothing else needs touching.
GRID_HZ = 10

WINDOW_SECONDS = 1                  # Table 4.10 (was 5 — see D-9)
EXPECTED_SAMPLES_PER_WINDOW = GRID_HZ * WINDOW_SECONDS
MIN_VALID_SAMPLES = 8               # Section 4.2.4.1 point 4 — keeps that rule's
                                    # 80% completeness ratio (was 4 of 5)
MAX_INTERP_GAP_SAMPLES = 2          # "gap of 1-2 consecutive missing samples".
                                    # Deliberately left in SAMPLES, not seconds:
                                    # at 10 Hz this interpolates at most 0.2 s,
                                    # i.e. strictly LESS synthetic data than the
                                    # 2 s it covered at 1 Hz.
# Phase-0 is overloaded THREE ways by the firmware (see DATASET-AUDIT-2026-09-18
# finding A1 #6): a genuine baseline phase, the root's PHASE_STABILISE_S window,
# and "this node has not heard any phase broadcast yet" — phase_listener.c:35
# initialises s_phase_id/s_gt_label to BASELINE. A node powered up before the
# root therefore logs phase 0 / gt_label 0 while probing a mesh that has no root
# in it, and those windows are indistinguishable from real baseline.
#
# assign_segments() separates them using the ONE cross-node reference that needs
# no shared clock: each node's own FIRST EXIT from phase 0, which is a mesh
# broadcast every node receives. Working backwards from it, the last
# PHASE_BASELINE_S of phase 0 is the real baseline; anything earlier is
# pre_baseline and is EXCLUDED from the labelled dataset (window_label = NaN).
# Must match PHASE_BASELINE_S in components/mesh_common/include/mesh_config.h.
# Firmware wrote "victim" for every plain child until 2026-09-23, when it
# became "child" -- a child is only a VICTIM if the attacker sits between it and
# the root, which is a property of the RUN, not of the build (see
# analysis/exposure.py). Captures from before that flash say "victim" and will
# forever, so both spellings are folded to one canonical value here, at the ONE
# place node_role is produced.
#
# Canonical is "child". Leaving it as "victim" would have made the firmware
# change cosmetic; picking "child" means features.py's role gates must test
# "child" too -- they do. Anything not listed passes through untouched, so
# blackhole / wormhole_a / wormhole_b / root are unaffected.
ROLE_ALIASES = {"victim": "child"}


def _canonical_role(role):
    """One spelling per role, across every firmware generation."""
    if role is None:
        return role
    return ROLE_ALIASES.get(str(role).strip().lower(), role)


PHASE_BASELINE_S = 300

# F1 (firmware, 2026-09-20): from this capture onward the board RECORDS the
# "not heard a phase broadcast yet" state instead of logging it as phase 0.
# Must match PHASE_ID_UNSET / GT_LABEL_UNSET in mesh_config.h.
#
# Handling it is not optional once the firmware emits it: 255 is non-zero, so
# the phase-exit anchor below would treat the node's very FIRST window as its
# exit from phase 0 and shift every t_anchor_s by the whole pre-root period.
# The result would look plausible and be wrong. Both schemas therefore run
# through the same rules, with 255 mapped to pre_baseline explicitly.
PHASE_ID_UNSET = 255
# The phases a run's schedule actually broadcasts (baseline, blackhole,
# wormhole, cooldown). A telemetry file with no row in any of them never heard
# the root - see _has_experiment_rows().
EXPERIMENT_PHASE_IDS = (0, 1, 2, 3)
GT_LABEL_UNSET = 255

SEGMENT_PRE_BASELINE = "pre_baseline"
SEGMENT_BASELINE = "baseline"
SEGMENT_ATTACK = "attack"
SEGMENT_COOLDOWN = "cooldown"
SEGMENT_REBROADCAST = "baseline_rebroadcast"   # phase 0 seen again after an exit
SEGMENT_NO_PHASE = "no_phase_seen"             # node never left phase 0 at all

# Segments that carry a usable ground-truth label. Everything else gets
# window_label = NaN so it can never enter a benign or attack population.
LABELLED_SEGMENTS = (SEGMENT_BASELINE, SEGMENT_ATTACK, SEGMENT_COOLDOWN)

# rssi_dbm == 0 is the firmware's uninitialised placeholder, not a reading:
# esp_wifi_sta_get_rssi() leaves the 0 initialiser when the node has no parent
# link, and it is 0 on every root row. Audit finding A1 #7 measured it on
# exactly 1 of 146,310 joined non-root rows, i.e. it is never a real value.
RSSI_PLACEHOLDER = 0

EPSILON = 1e-6                      # Equation 4.2 divide-by-zero guard
MAX_SESSION_SECONDS = 24 * 3600    # 86400 — captures run for minutes, so a
                                   # per-node relative time beyond a full day
                                   # means a corrupt timestamp_us (esp_timer
                                   # glitch), not real data. See _fill_node_gaps.
# HARD CEILING on the dense 1 Hz reindex grid, in rows. This is a safety
# tripwire, not a tuning knob: the sole place this pipeline can allocate an
# unbounded array is the per-node reindex in _fill_node_gaps, and a corrupt
# timestamp once made it try to allocate ~30 GiB and freeze the machine. Legit
# per-node grids are <= (MAX_SESSION_SECONDS * GRID_HZ) + 1 rows (864,001 at
# 10 Hz), so this ceiling is never hit by real data; if it ever would be, we
# refuse to densify instead of risking the host's memory. Must stay ABOVE that
# bound or the tripwire fires on legitimate captures. 5M int64 rows is ~40 MB.
MAX_GRID_ROWS = 5_000_000

# Columns that are CUMULATIVE counters (monotonically increasing on the
# node) — these get delta-converted per window (Equation 4.1).
# Columns NOT in this set are treated as CONTINUOUS metrics (mean/var/min/max).
#
# NOTE: this is a tuple, not a set. Iteration order over a Python set is
# not guaranteed stable across runs/processes, and the thesis requires
# "pipeline is deterministic — same inputs always produce the same
# output" (Milestone 6 criteria). Using sets here silently violated that
# by reordering output columns between runs even though row values were
# identical. Membership tests (`col in CUMULATIVE_COLUMNS`) work fine on
# a tuple, so nothing else needs to change.
CUMULATIVE_COLUMNS = (
    "retry_count",
    "tx_count",
    "probes_count",
    "probes_received",
    # F3 (telemetry schema v2). Absent from every capture up to and including
    # 2026-09-18; every loop over this tuple skips columns the file does not
    # have, so listing them here is a no-op on v1 data and picks them up
    # automatically on v2. features.compute_forwarding_features() already
    # prefers recv_count_delta/forward_count_delta when they exist.
    "recv_count",
    "forward_count",
    "drop_count",
)

# Columns that are CONTINUOUS metrics — aggregated as mean/var/min/max
# per window rather than delta'd. Same ordering note as above.
CONTINUOUS_COLUMNS = (
    "rssi_dbm",
)

# Columns carried through as metadata / identity — not aggregated
# numerically, just used for grouping or taken as the first value in
# the window. Tuple for the same determinism reason as above.
IDENTITY_COLUMNS = (
    "node_id", "role", "layer", "parent_mac",
)

# Schema columns the firmware always writes as integers. A non-numeric value
# in any of these means the row is contaminated (see _coerce_and_drop_malformed)
# and must be dropped before any numeric step. node_id/role/parent_mac are
# genuinely textual, so they're deliberately excluded here.
NUMERIC_COLUMNS = (
    "timestamp_us", "layer", "rssi_dbm",
    "retry_count", "tx_count", "probes_count",
    "phase_id", "gt_label",
    # F3 schema v2 — skipped when absent (see the loop at _coerce_and_drop_
    # malformed), so v1 captures are unaffected.
    "recv_count", "forward_count", "drop_count",
)


@dataclass
class PreprocessReport:
    """
    Quality-tracking record. Thesis Section 4.2.4.1 explicitly requires
    that "the fraction of discarded windows is reported as a dataset
    quality metric" — this dataclass is that report.
    """
    files_loaded: int = 0
    files_skipped: list[str] = field(default_factory=list)
    unimported_card_files: list[str] = field(default_factory=list)
    duplicates_archived: list[str] = field(default_factory=list)
    # Telemetry files with no row in any experiment phase - see
    # _has_experiment_rows(). Skipped, never loaded as a node of the run.
    files_no_experiment: list[str] = field(default_factory=list)
    # Nodes whose phase 0 was SHORTER than PHASE_BASELINE_S — see the block in
    # the segment assignment for why that silently corrupts the benign class.
    short_baseline: list[str] = field(default_factory=list)
    rows_dropped_malformed: int = 0
    rows_dropped_downsampled: int = 0
    rows_dropped_corrupt_timestamp: int = 0
    raw_rows_total: int = 0
    windows_total: int = 0
    windows_discarded_incomplete: int = 0
    windows_discarded_gap: int = 0
    windows_kept: int = 0
    per_node_window_counts: dict[str, int] = field(default_factory=dict)
    rssi_placeholders_blanked: int = 0
    segment_counts: dict[str, int] = field(default_factory=dict)
    nodes_without_phase_exit: list[str] = field(default_factory=list)

    def discard_fraction(self) -> float:
        if self.windows_total == 0:
            return 0.0
        discarded = self.windows_discarded_incomplete + self.windows_discarded_gap
        return discarded / self.windows_total

    def summary(self) -> str:
        lines = [
            "── Preprocessing Quality Report ──────────────────────────",
            f"  Files loaded:               {self.files_loaded}",
            f"  Files skipped (bad/empty):  {len(self.files_skipped)}",
            f"  Rows dropped (contaminated):{self.rows_dropped_malformed}",
            f"  Rows dropped (corrupt ts):  {self.rows_dropped_corrupt_timestamp}",
            f"  Rows downsampled to {GRID_HZ}Hz grid: {self.rows_dropped_downsampled} "
            f"(expected — see current SAMPLING_INTERVAL_MS in thesis-deviate.md)",
            f"  Raw rows ingested:          {self.raw_rows_total}",
            f"  Windows formed:             {self.windows_total}",
            f"  Windows discarded (<4 smp): {self.windows_discarded_incomplete}",
            f"  Windows discarded (gap>2s): {self.windows_discarded_gap}",
            f"  Windows kept:               {self.windows_kept}",
            f"  Discard fraction:           {self.discard_fraction():.1%}",
            f"  RSSI placeholders blanked:  {self.rssi_placeholders_blanked} "
            f"(rssi_dbm == 0 -> missing; audit A1 #7)",
        ]
        if self.segment_counts:
            lines.append("  Windows per segment (pre_baseline is EXCLUDED, "
                         "window_label = NaN):")
            for seg in (SEGMENT_PRE_BASELINE, SEGMENT_BASELINE, SEGMENT_ATTACK,
                        SEGMENT_COOLDOWN, SEGMENT_REBROADCAST, SEGMENT_NO_PHASE):
                if seg in self.segment_counts:
                    excl = "" if seg in LABELLED_SEGMENTS else "   [excluded]"
                    lines.append(f"    {seg:<22} {self.segment_counts[seg]}{excl}")
        if self.nodes_without_phase_exit:
            lines.append(f"  [WARN] {len(self.nodes_without_phase_exit)} node(s) never "
                         f"left phase 0 — no baseline can be attributed to them:")
            for n in self.nodes_without_phase_exit:
                lines.append(f"    {n}")
        if self.files_skipped:
            lines.append(f"  Skipped files: {self.files_skipped}")
        if self.files_no_experiment:
            lines.append(f"  SKIPPED - NO EXPERIMENT DATA (only phase {PHASE_ID_UNSET}, the root's "
                         f"schedule never reached them): {len(self.files_no_experiment)}")
            for name in self.files_no_experiment:
                lines.append(f"    {name}")
            lines.append("    -> these hold only pre-run rows: that boot never heard the root's schedule. "
                         "Usually a different boot than the run itself - look in the card's _archive "
                         "folder for the real run file before re-capturing anything.")
        if self.unimported_card_files:
            lines.append(f"  REFUSED (raw SD-card files, never imported): "
                          f"{len(self.unimported_card_files)}")
            for name in self.unimported_card_files:
                lines.append(f"    {name}")
            lines.append("    -> run tools\\import_sdcard.py --card <drive> --repeat <N> "
                          "instead of copying off the card by hand.")
        if self.short_baseline:
            lines.append(
                f"  !! BASELINE SHORTER THAN EXPECTED on {len(self.short_baseline)} node(s). "
                f"PHASE_BASELINE_S here is {PHASE_BASELINE_S}s; if the firmware was built "
                f"with -DPHASE_BASELINE_S=<less>, the 'baseline' slice reaches past the real "
                f"start and mesh-formation noise is being labelled benign. Make the two agree.")
            for name in self.short_baseline:
                lines.append(f"    {name}")
        if self.duplicates_archived:
            lines.append(f"  Duplicate captures archived: {len(self.duplicates_archived)} "
                          f"(older re-run of the same board+repeat -- see _archive/)")
            for name in self.duplicates_archived:
                lines.append(f"    {name}")
        lines.append("  Per-node window counts:")
        for node, count in sorted(self.per_node_window_counts.items()):
            lines.append(f"    {node}: {count}")
        lines.append("───────────────────────────────────────────────────────────")
        return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────
# Step 1 — Load raw CSVs
# ─────────────────────────────────────────────────────────────────────────

_REPEAT_RE = re.compile(r"_r(\d+)_\d{8}_\d{6}_(?:telem|arrivals)\.csv$")


def _repeat_from_filename(source_file: str):
    """Pull the M4 repeat number out of an export filename, or NaN.

    An analysis folder deliberately holds all three repeats at once (the M4
    matrix counts them by the _r1_/_r2_/_r3_ tag), and this loader globs the
    whole folder — so every window from r1, r2 and r3 lands in one table with
    no way to tell them apart. That is fine for M8 separability, which pools
    benign vs attack windows regardless of run, but it makes per-repeat
    variance impossible to recover downstream: a reader can always pool, but
    cannot un-pool.

    Carrying the repeat as its own column costs nothing and keeps the dataset
    usable for reproducibility questions ("does the signature hold across
    runs?") that the pooled table cannot answer. NaN for any file that does
    not follow the export naming convention.
    """
    m = _REPEAT_RE.search(source_file or "")
    return int(m.group(1)) if m else np.nan


KNOWN_ATTACKS = ("baseline", "blackhole", "wormhole")
KNOWN_TOPOLOGIES = ("linear", "star", "tree", "partial_mesh")


def _run_context_from_path(input_dir: str) -> dict:
    """Derive attack / topology / location / scenario from the export path.

    Same argument as _repeat_from_filename above, one level up: the export tree
    encodes which cell of the M4 matrix a capture belongs to
    (<attack>/<topology>/<location>/[<scenario>/]), but none of it survived into
    the tables — so once runs were pooled into combined_all.csv, rows from two
    different locations, or a `mobility` run and a `none` run at the same cell,
    became indistinguishable. A reader can always pool, but cannot un-pool.

    Carrying these as columns makes every row self-describing and lets
    combine_all.py stop re-deriving them from paths it may not have.

    Anchored on the LAST path segment that names a known attack, so it still
    resolves correctly under archive/<date>/exports/... . 'trimmed' and
    '_archive' are stripped first — they are derived-output folders, not part
    of the cell identity. Returns None for every field when the path is not an
    export tree at all (e.g. synthetic fixtures from generate_fake_data.py), so
    unknown provenance is never labelled as if it were known.

    Scenario defaults to 'stationary' rather than NaN because the export
    convention is that the no-variation scenario (run.ps1 -Scenario none) gets
    NO folder — absence of the segment IS that scenario, not missing
    information. The dataset names it 'stationary' (thesis-deviate D-10); the
    folders/filenames/run.ps1 keep 'none'.
    Location falls back to 'unrecorded', matching combine_all.py's own name for
    pre-location captures.
    """
    ctx = {"attack": None, "topology": None, "location": None, "scenario": None}
    if not input_dir:
        return ctx
    try:
        parts = [p for p in os.path.normpath(os.path.abspath(input_dir)).split(os.sep) if p]
    except (TypeError, ValueError):
        return ctx

    parts = [p for p in parts if p not in ("trimmed", "_archive")]

    idx = None
    for i, p in enumerate(parts):
        if p in KNOWN_ATTACKS:
            idx = i
    if idx is None:
        return ctx

    tail = parts[idx:]
    ctx["attack"] = tail[0]
    ctx["topology"] = tail[1] if len(tail) > 1 and tail[1] in KNOWN_TOPOLOGIES else None
    ctx["location"] = tail[2] if len(tail) > 2 else "unrecorded"
    scn = tail[3] if len(tail) > 3 else "none"
    # A stray ".../none/" folder (a since-fixed bug) means the same thing.
    ctx["scenario"] = "stationary" if scn == "none" else scn
    return ctx


# Matches export_logs.py / import_sdcard.py's filename shape, e.g.
# root_node1_linear_blackhole_r1_20260914_204207_telem.csv — same pattern
# trim_run.py's _warn_on_duplicate_captures uses, kept in sync deliberately.
_CAPTURE_RE = re.compile(
    r"^(?P<role>root|child|victim)_(?P<label>[^_]+)_(?P<topology>[^_]+)_"
    r"(?P<attack>[^_]+)_r(?P<repeat>\d+)_(?P<date>\d{8})_(?P<time>\d{6})_"
    r"(?P<kind>telem|arrivals)\.csv$"
)


def _has_experiment_rows(path: str):
    """True if the file holds at least one row from an experiment phase,
    False if it holds none, None if that cannot be told (unreadable, or no
    phase_id column - e.g. a synthetic fixture).

    A boot that never hears the root's schedule logs only phase 255 ("no
    broadcast heard yet"). On sep. 24, 2026 five of the G402 children's imported
    files were exactly that - and they were NOT the run itself: the root's
    arrivals prove all six children ran the whole experiment, so these were
    other (later) boots, and the run's own files sit in each card's _archive\
    folder, which the importer skips. Such a file cannot yield one labelled
    window, yet it used to load as a node of the run - and, being the NEWER
    capture, it made _archive_duplicate_captures() move the node's complete
    capture aside.
    Reads only the phase_id column; stops at the first experiment row."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            header = f.readline().strip().split(",")
            if "phase_id" not in header:
                return None
            idx = header.index("phase_id")
            wanted = {str(p) for p in EXPERIMENT_PHASE_IDS}
            for line in f:
                fields = line.split(",")
                if idx < len(fields) and fields[idx].strip() in wanted:
                    return True
        return False
    except OSError:
        return None


def _archive_duplicate_captures(input_dir: str) -> list[str]:
    """
    Auto-archives the OLDER file(s) when two+ captures share the same board,
    repeat and kind (telem/arrivals) in one folder — e.g. a repeat that had to
    be re-run after a bad attempt (MAC mismatch, wrong wipe, whatever), leaving
    both the failed export and the good one sitting side by side.

    Exports are timestamped, so re-running an already-captured cell never
    overwrites — it ADDS a second file. Nothing downstream used to notice:
    this loader globs the whole folder, so every duplicate got counted (and
    analyzed, and fed into verify_attack.py) right alongside the real run,
    silently diluting/contaminating the dataset. Newest file (by the embedded
    date_time, which sorts lexicographically) is kept in place; everything
    older for that same key is moved into <input_dir>/_archive/ — never
    deleted, matching this project's archive-not-delete convention elsewhere
    (trim_run.py, ARCHIVE-RUNBOOK.md, csv_logger.c's SD-card archive sweep).

    Runs once per load_raw_telemetry() call, before the glob that actually
    loads files, so an archived duplicate is invisible to THIS run but still
    sitting in _archive/ if anyone needs to go back and look at it.

    Returns the list of archived filenames (for PreprocessReport).
    """
    try:
        names = os.listdir(input_dir)
    except OSError:
        return []

    groups: dict[tuple, list[str]] = {}
    for name in names:
        m = _CAPTURE_RE.match(name)
        if not m:
            continue
        g = m.groupdict()
        key = (g["role"], g["label"], g["topology"], g["attack"], g["repeat"], g["kind"])
        groups.setdefault(key, []).append(name)

    archived = []
    for names_for_key in groups.values():
        if len(names_for_key) < 2:
            continue
        # date+time are both fixed-width digit strings, so lexicographic sort
        # is chronological — newest last. A capture with NO experiment data
        # never outranks one that has it, however new: "newest wins" alone
        # archived node8's only complete G402 capture (949 s, every phase) in
        # favour of a 161 s phase-255-only file from a later session.
        # Unknown (None) ranks as data, so fixtures keep the old behaviour.
        ordered = sorted(
            names_for_key,
            key=lambda n: (_has_experiment_rows(os.path.join(input_dir, n)) is not False, n))
        keep, stale = ordered[-1], ordered[:-1]
        # The kept file is only the newest by DATA, not by time, when a newer one
        # had no experiment rows. That older file may belong to a DIFFERENT
        # session than the rest of the folder (node8's 13:41 file sat beside a
        # 14:4x run) - say so, because nothing here can prove which run it is.
        newest = sorted(names_for_key)[-1]
        if keep != newest:
            print(f"  [WARN] {keep} was KEPT over the newer {newest} because the newer one has "
                  f"no experiment data. Confirm {keep} belongs to THIS run (compare seq_num "
                  f"with the root's arrivals) - it may be from an earlier session.",
                  file=sys.stderr)
        archive_dir = os.path.join(input_dir, "_archive")
        for name in stale:
            os.makedirs(archive_dir, exist_ok=True)
            src = os.path.join(input_dir, name)
            dst = os.path.join(archive_dir, name)
            try:
                if os.path.exists(dst):
                    # Already archived by a previous run of this function
                    # (e.g. M7 re-invoking M6's loader) — nothing to do.
                    continue
                os.replace(src, dst)
                archived.append(name)
                print(f"  [INFO] Archived duplicate capture (superseded by {keep}): {name}",
                      file=sys.stderr)
            except OSError as e:
                print(f"  [WARN] Could not archive duplicate {name}: {e}", file=sys.stderr)

    return archived


# The RAW on-card filename csv_logger.c's sd_csv_path() writes, e.g.
# victim_NODE_20500DE70C80_r21_b22_telem.csv — mirrors import_sdcard.py's
# _CARD_FILE. The "_b<boot>_" segment is the giveaway: a real export is
# named _r<repeat>_<date>_<time>_<kind>.csv and never carries a boot number.
_RAW_CARD_RE = re.compile(
    r"^(?:root|victim)_NODE_[0-9A-Fa-f]{12}(?:_r\d+)?_b\d+_(?:telem|arrivals)\.csv$"
)


def _reject_unimported_card_files(files: list[str], report: PreprocessReport) -> list[str]:
    """Drops raw SD-card CSVs that were copied into an exports folder by hand
    instead of being imported with tools/import_sdcard.py.

    A card mirrors the same <attack>/<topology>/<location>/ tree the exports
    folder uses, so dragging a card's folder over the exports folder MERGES
    raw captures straight into a leaf — and they still end in _telem.csv, so
    this loader used to glob them in as if they were real exports.

    That is not a cosmetic naming problem. The r<N> in a card filename is the
    board's OWN on-device run counter (how many times that board logged to
    that card), not the campaign repeat: a root exported at r2 sat in one
    folder beside a card-copied attacker at r21 and victim at r26, from three
    unrelated sessions, and the pooled feature table reported a confident
    BLACKHOLE CONFIRMED built from captures that were never part of the same
    run. import_sdcard.py exists precisely to restamp those files with ONE
    campaign --repeat; bypassing it is what breaks the invariant.

    Refuses only this one unambiguous shape rather than everything that fails
    _CAPTURE_RE — synthetic fixtures (generate_fake_data.py writes
    NODE_ROOT01_RUN_001_telem.csv) are not canonical either and must keep
    loading.
    """
    kept = []
    for fp in files:
        name = os.path.basename(fp)
        if _RAW_CARD_RE.match(name):
            report.unimported_card_files.append(name)
            print(f"  [REFUSED] {name}: raw SD-card file, never imported. Its r-number is "
                  f"that board's on-device run counter, NOT a campaign repeat - loading it "
                  f"would pool an unrelated run. Import it with "
                  f"tools/import_sdcard.py --card <drive> --repeat <N>, or move it out of "
                  f"this folder.", file=sys.stderr)
            continue
        kept.append(fp)
    return kept


def load_raw_telemetry(input_dir: str, report: PreprocessReport) -> pd.DataFrame:
    """
    Load every *_telem.csv file in input_dir into one long DataFrame.

    Each row is one 1 Hz telemetry sample from one node. Probe-arrival
    files (*_arrivals.csv, root-only) are intentionally NOT loaded here —
    PDR computation (Milestone 7) joins them separately on
    (src_node_id, seq_num), per the thesis's "Implementation note" under
    the Feature Engineering milestone.
    """
    report.duplicates_archived.extend(_archive_duplicate_captures(input_dir))

    pattern = os.path.join(input_dir, "*_telem.csv")
    files = sorted(glob.glob(pattern))
    files = _reject_unimported_card_files(files, report)

    if not files:
        raise FileNotFoundError(
            f"No *_telem.csv files found in {input_dir!r}. "
            f"Expected files like NODE_AABBCC..._RUN_001_telem.csv "
            f"(see csv_logger.c naming convention)."
        )

    frames = []
    for fp in files:
        try:
            df = pd.read_csv(fp)
        except (pd.errors.EmptyDataError, pd.errors.ParserError) as e:
            report.files_skipped.append(os.path.basename(fp))
            print(f"  [WARN] Skipping unreadable file {fp}: {e}", file=sys.stderr)
            continue

        if df.empty:
            report.files_skipped.append(os.path.basename(fp))
            print(f"  [WARN] Skipping empty file {fp}", file=sys.stderr)
            continue

        required_cols = {
            "timestamp_us", "node_id", "role", "layer", "parent_mac",
            "rssi_dbm", "retry_count", "tx_count", "probes_count",
            "phase_id", "gt_label",
        }
        missing = required_cols - set(df.columns)
        if missing:
            report.files_skipped.append(os.path.basename(fp))
            print(
                f"  [WARN] Skipping {fp}: missing columns {missing}",
                file=sys.stderr,
            )
            continue

        # Numeric first: one UART-contaminated row types the column as text.
        phases = pd.to_numeric(df["phase_id"], errors="coerce")
        if phases.notna().any() and not phases.isin(EXPERIMENT_PHASE_IDS).any():
            report.files_no_experiment.append(os.path.basename(fp))
            print(f"  [SKIPPED] {os.path.basename(fp)}: NO EXPERIMENT DATA - only phase "
                  f"{PHASE_ID_UNSET} rows (the board stopped logging before the root's "
                  f"schedule reached it). Not loaded as a node of this run.", file=sys.stderr)
            continue

        df["_source_file"] = os.path.basename(fp)
        frames.append(df)
        report.files_loaded += 1

    if not frames:
        raise ValueError(
            "All discovered files were skipped (empty/unreadable/malformed). "
            "Nothing to preprocess."
        )

    raw = pd.concat(frames, ignore_index=True)
    raw = _coerce_and_drop_malformed(raw, report)
    report.raw_rows_total = len(raw)
    return raw


def _coerce_and_drop_malformed(
    raw: pd.DataFrame, report: PreprocessReport
) -> pd.DataFrame:
    """
    Force the schema's numeric columns to numbers and drop any row where one
    failed to parse.

    Such rows are contamination, not real samples: an ESP-IDF log line printed
    asynchronously over the same UART (a mesh ``<assoc>``/``[SCAN]`` event, etc.)
    gets interleaved into the CSV during serial export, so the row's fields shift
    and a numeric column ends up holding a text token like ``" channel:11"`` or
    ``" MAP:0"``. Even one such value makes pandas type the whole column as
    ``object``, which then blows up interpolation downstream (``TypeError: Series
    cannot interpolate with object dtype``). The firmware always writes every
    numeric field as an integer, so a non-numeric value there means the row isn't
    a genuine 1 Hz sample — dropping it keeps a single stray log line from
    aborting the entire run, consistent with this pipeline's skip-bad-input,
    report-the-count philosophy.

    Clean data is unaffected: with no non-numeric tokens nothing is dropped and
    the already-integer columns coerce back to the same dtype, so output stays
    byte-identical (the determinism criterion).

    The drop count (and, on request, the affected filenames) is recorded on
    `report` rather than raised as a `warnings.warn()` — this can legitimately
    fire on every real capture (any stray async log line interleaved over the
    shared UART during export), so it belongs in the one-line quality summary
    every run already prints, not as a console warning per run.
    """
    coerced = raw.copy()
    bad_mask = pd.Series(False, index=coerced.index)
    for col in NUMERIC_COLUMNS:
        if col not in coerced.columns:
            continue
        as_num = pd.to_numeric(coerced[col], errors="coerce")
        # Flag only values that were present but un-parseable (a genuinely
        # empty cell stays NaN and is handled later as a normal missing sample).
        bad_mask |= as_num.isna() & coerced[col].notna()
        coerced[col] = as_num

    n_bad = int(bad_mask.sum())
    if n_bad:
        report.rows_dropped_malformed += n_bad
        coerced = coerced.loc[~bad_mask].reset_index(drop=True)

    # rssi_dbm == 0 is the "no parent link" placeholder, not a measurement
    # (audit A1 #7). Left in, it is averaged into RSSI_mean and compared against
    # a per-layer baseline median that is itself 0, manufacturing an
    # RSSI_Hop_Diff of exactly 0. Blank it so the normal missing-value path
    # handles it and it can never masquerade as a -0 dBm reading.
    if "rssi_dbm" in coerced.columns:
        placeholder = coerced["rssi_dbm"] == RSSI_PLACEHOLDER
        n_placeholder = int(placeholder.sum())
        if n_placeholder:
            report.rssi_placeholders_blanked += n_placeholder
            coerced.loc[placeholder, "rssi_dbm"] = np.nan

    return coerced


# ─────────────────────────────────────────────────────────────────────────
# Step 2 — Per-node timestamp re-basing
# ─────────────────────────────────────────────────────────────────────────

def rebase_timestamps(raw: pd.DataFrame) -> pd.DataFrame:
    """
    "Per-node timestamp re-basing (each node's clock starts at 0)."

    timestamp_us comes from esp_timer_get_time() on each board, which
    starts counting from that board's own boot, not a shared wall clock.
    We convert to seconds and subtract each node's own first sample so
    every node's timeline starts at t=0, then window on that relative
    time. This sidesteps needing real cross-node clock alignment (the
    thesis notes phase-broadcast markers are used for that offline step,
    which is a separate, optional refinement layered on top of this if
    multi-node drift turns out to matter empirically).
    """
    df = raw.copy()
    df["timestamp_s"] = df["timestamp_us"] / 1_000_000.0
    df = df.sort_values(["node_id", "timestamp_s"]).reset_index(drop=True)

    node_start = df.groupby("node_id")["timestamp_s"].transform("min")
    df["t_rel"] = df["timestamp_s"] - node_start

    return df


# ─────────────────────────────────────────────────────────────────────────
# Step 3 — Missing-sample handling (per-node, before windowing)
# ─────────────────────────────────────────────────────────────────────────

def _fill_node_gaps(node_df: pd.DataFrame, report: PreprocessReport) -> pd.DataFrame:
    """
    Apply the thesis's missing-value rules to one (node, run) timeline,
    operating on a synthetic GRID_HZ grid built from t_rel, indexed in ticks of
    1/GRID_HZ seconds. The firmware captures at 10 Hz (SAMPLING_INTERVAL_MS
    100U); with GRID_HZ=10 the grid now matches that rate instead of discarding
    9 of every 10 samples (see thesis-deviate.md D-1 and D-9). A raw rate faster
    than GRID_HZ is still downsampled to the grid, not resampled to match it.

    Continuous metrics (rssi_dbm): linear interpolation for gaps of
    1-2 consecutive missing samples; longer gaps are left as NaN (the
    window-level discard logic in build_windows() handles those).

    Cumulative counters: forward-fill for gaps <= 2s (counter assumed
    unchanged — Section 4.2.4.1 point 2); longer gaps left as NaN, also
    handled by window-level discard.

    Note: this must be called per (node_id, run) pair, not just per
    node_id — a node's t_rel resets to 0 at the start of every run, so
    grouping by node_id alone across multiple concatenated runs would
    produce duplicate t_rel values and corrupt the reindex below. The
    caller (handle_missing_values) enforces this grouping.
    """
    import warnings
    node_df = node_df.copy()
    # Grid index is in TICKS of 1/GRID_HZ seconds, not whole seconds.
    t_int = (node_df["t_rel"] * GRID_HZ).round().astype(int)

    # Guard against a corrupt timestamp. A single garbage timestamp_us value
    # (e.g. 4.0e15 µs seen from an esp_timer glitch) survives numeric coercion
    # but makes t_int.max() astronomical, so the RangeIndex/reindex below tries
    # to allocate tens of GiB and aborts the run (numpy _ArrayMemoryError). Real
    # captures span minutes; drop any sample whose relative time exceeds
    # MAX_SESSION_SECONDS before the grid is built. Anchored on min(), which is a
    # legitimate small value (the outlier is a large positive, unsigned micros).
    span_ok = (t_int - t_int.min()) <= MAX_SESSION_SECONDS * GRID_HZ
    if not span_ok.all():
        n_bad = int((~span_ok).sum())
        node_id_val = node_df["node_id"].iloc[0] if "node_id" in node_df.columns else "?"
        report.rows_dropped_corrupt_timestamp += n_bad
        warnings.warn(
            f"[preprocess] {node_id_val}: dropped {n_bad} sample(s) with a corrupt "
            f"timestamp_us (relative time > {MAX_SESSION_SECONDS}s — esp_timer glitch). "
            f"This should never happen on real data — investigate the source file."
        )
        node_df = node_df.loc[span_ok]
        t_int = t_int.loc[span_ok]

    if t_int.duplicated().any():
        # Two or more raw samples can round to the same integer second —
        # expected whenever the firmware's raw sampling rate is faster than
        # the 1 Hz analysis grid (current rate: see SAMPLING_INTERVAL_MS /
        # thesis-deviate.md), plus ordinary esp_timer jitter on top. Keep the
        # row closest to its integer second, discard the rest. This preserves
        # the 1 Hz grid Table 4.10 windows are defined on. Expected to fire on
        # every real capture at rates > 1 Hz, so it's tallied on `report` and
        # shown once in the quality summary rather than warned per node/file.
        node_df["_t_int"] = t_int
        node_df["_t_frac_err"] = (node_df["t_rel"] - t_int).abs()
        node_df = (
            node_df
            .sort_values(["_t_int", "_t_frac_err"])
            .drop_duplicates(subset="_t_int", keep="first")
            .sort_values("_t_int")
        )
        n_dropped = len(t_int) - len(node_df)
        report.rows_dropped_downsampled += n_dropped
        t_int = node_df["_t_int"]
        node_df = node_df.drop(columns=["_t_int", "_t_frac_err"])

    # Build the dense 1 Hz grid — but never allocate an absurd one. The outlier
    # drop above already bounds the span to MAX_SESSION_SECONDS, so this ceiling
    # is a belt-and-suspenders tripwire: even if some future/edge path let a huge
    # span through, we refuse to densify (which is what tried to grab ~30 GiB and
    # froze the laptop) and fall back to the observed timestamps only, so the
    # allocation can never exceed the number of real samples.
    grid_rows = int(t_int.max()) - int(t_int.min()) + 1
    if grid_rows > MAX_GRID_ROWS:
        node_id_val = node_df["node_id"].iloc[0] if "node_id" in node_df.columns else "?"
        warnings.warn(
            f"[preprocess] {node_id_val}: dense {GRID_HZ} Hz grid would be {grid_rows:,} "
            f"rows (> MAX_GRID_ROWS={MAX_GRID_ROWS:,}) — corrupt timestamps. "
            f"Refusing to densify; using observed timestamps only, no gap-fill."
        )
        full_index = pd.Index(sorted(t_int.unique()))
    else:
        full_index = pd.RangeIndex(t_int.min(), t_int.max() + 1)

    grid = node_df.set_index(t_int).reindex(full_index)

    for col in CONTINUOUS_COLUMNS:
        if col in grid.columns:
            grid[col] = grid[col].interpolate(
                method="linear", limit=MAX_INTERP_GAP_SAMPLES, limit_area="inside"
            )

    for col in CUMULATIVE_COLUMNS:
        if col in grid.columns:
            grid[col] = grid[col].ffill(limit=MAX_INTERP_GAP_SAMPLES)

    for col in IDENTITY_COLUMNS:
        if col in grid.columns:
            grid[col] = grid[col].ffill().bfill()

    if "phase_id" in grid.columns:
        grid["phase_id"] = grid["phase_id"].ffill().bfill()
    if "gt_label" in grid.columns:
        grid["gt_label"] = grid["gt_label"].ffill().bfill()

    grid["t_rel"] = grid.index.astype(float) / GRID_HZ
    grid["_was_missing"] = node_df.set_index(t_int).reindex(full_index)[
        "timestamp_us"
    ].isna()

    return grid.reset_index(drop=True)


def handle_missing_values(df: pd.DataFrame, report: PreprocessReport) -> pd.DataFrame:
    """
    Apply _fill_node_gaps() independently per (node_id, run).

    Grouping must include the source file (one file = one run for one
    node) rather than node_id alone, because t_rel resets to 0 at the
    start of every run — two runs from the same node concatenated
    together would otherwise collide on relative timestamp.
    """
    filled = []
    for (node_id, source_file), group in df.groupby(["node_id", "_source_file"]):
        filled.append(_fill_node_gaps(group, report))
    return pd.concat(filled, ignore_index=True)


# ─────────────────────────────────────────────────────────────────────────
# Step 4 — Window aggregation (Table 4.10)
# ─────────────────────────────────────────────────────────────────────────

def _layer_to_hop(layer):
    """ESP-WIFI-MESH `layer` -> hop count from the root.

    WHY THIS EXISTS (adviser feedback, sep. 21, 2026): panel members read the
    column name `layer` as an OSI layer. It is not — ESP-WIFI-MESH's `layer` is
    a node's depth in the mesh TREE, and the mesh runs below IP entirely. `hop`
    is the standard networking word for that and carries no OSI baggage, so the
    analysis and the paper lead with it. `layer` is kept alongside it as the raw
    value the firmware reported, so nothing loses traceability.

    ⚠️ THE OFF-BY-ONE IS THE WHOLE POINT, don't "simplify" this away:
    Espressif numbers the ROOT as layer 1 (mesh_setup.c, "center(L1)"), so a
    direct child of the root is layer 2 — but it is **1 hop** from the root, and
    the root is **0 hops** from itself. A straight rename of the column, keeping
    the values, would have every hop count off by one and would read as "the
    root is 1 hop from itself", which is wrong and a panel would catch it.

    layer == -1 is the firmware's "no parent right now" sentinel, NOT a real
    depth — it must become NaN, never -2.
    """
    val = pd.to_numeric(layer, errors="coerce")
    if pd.isna(val) or val < 1:
        return np.nan
    return val - 1


def _modal_label(series: pd.Series):
    """
    Modal phase-label assignment per window. pandas mode() can return
    multiple values on a tie; we take the first (earliest-occurring in
    sort order) deterministically so the pipeline stays reproducible,
    per the thesis's "Pipeline is deterministic" criterion.
    """
    series = series.dropna()
    if series.empty:
        return np.nan
    modes = series.mode()
    return modes.iloc[0]


def build_windows(
    df: pd.DataFrame,
    report: PreprocessReport,
    run_context: dict | None = None,
) -> pd.DataFrame:
    """
    Aggregate the gap-filled grid samples into non-overlapping WINDOW_SECONDS
    windows per node, applying Table 4.10's aggregation rules:

      Continuous metrics    → mean, variance, min, max per window
      Cumulative counters   → delta per window (Equation 4.1)
      Event counts          → total events per window
      Phase label           → modal value per window

    Windows with fewer than MIN_VALID_SAMPLES valid (non-imputed-beyond-gap)
    samples are discarded, per Section 4.2.4.1 point 4.
    """
    run_context = run_context or {}
    df = df.copy()
    df["window_idx"] = (df["t_rel"] // WINDOW_SECONDS).astype(int)
    df["window_start"] = df["window_idx"] * WINDOW_SECONDS

    rows = []

    for (node_id, source_file, window_idx), wdf in df.groupby(
        ["node_id", "_source_file", "window_idx"]
    ):
        report.windows_total += 1

        n_present = (~wdf["_was_missing"]).sum()
        n_total = len(wdf)

        # Discard rule: fewer than MIN_VALID_SAMPLES actually-observed
        # samples (out of the expected EXPECTED_SAMPLES_PER_WINDOW).
        if n_present < MIN_VALID_SAMPLES:
            report.windows_discarded_incomplete += 1
            continue

        # Discard rule: any single gap inside this window longer than
        # MAX_INTERP_GAP_SAMPLES consecutive missing samples invalidates
        # the whole window (can't reliably interpolate/ffill across it).
        missing_flags = wdf.sort_values("t_rel")["_was_missing"].to_numpy()
        max_run = _max_consecutive_true(missing_flags)
        if max_run > MAX_INTERP_GAP_SAMPLES:
            report.windows_discarded_gap += 1
            continue

        row = {
            "window_start": wdf["window_start"].iloc[0],
            "node_id": node_id,
            "source_file": source_file,
            "attack": run_context.get("attack"),
            "topology": run_context.get("topology"),
            "location": run_context.get("location"),
            "scenario": run_context.get("scenario"),
            "run_repeat": _repeat_from_filename(source_file),
            "node_role": _canonical_role(
                wdf["role"].mode().iloc[0] if not wdf["role"].mode().empty
                else wdf["role"].iloc[0]),
            "layer": wdf["layer"].mode().iloc[0] if "layer" in wdf and not wdf["layer"].mode().empty else np.nan,
            "hop": _layer_to_hop(
                wdf["layer"].mode().iloc[0]
                if "layer" in wdf and not wdf["layer"].mode().empty else np.nan),
            "parent_mac": wdf["parent_mac"].iloc[-1] if "parent_mac" in wdf else None,
            "n_samples_present": int(n_present),
            "n_samples_expected": EXPECTED_SAMPLES_PER_WINDOW,
        }

        # Continuous metrics: mean / var / min / max
        for col in CONTINUOUS_COLUMNS:
            if col not in wdf.columns:
                continue
            vals = wdf[col].dropna()
            row[f"{col}_mean"] = vals.mean() if len(vals) else np.nan
            row[f"{col}_var"] = vals.var(ddof=0) if len(vals) > 1 else 0.0
            row[f"{col}_min"] = vals.min() if len(vals) else np.nan
            row[f"{col}_max"] = vals.max() if len(vals) else np.nan

        # Cumulative counters: delta = last - first valid value in window
        # (Equation 4.1). If the window also includes one sample from
        # just before window start due to ffill carry-in, that's fine —
        # we delta strictly within this window's own valid samples.
        wdf_sorted = wdf.sort_values("t_rel")
        for col in CUMULATIVE_COLUMNS:
            if col not in wdf_sorted.columns:
                continue
            vals = wdf_sorted[col].dropna()
            if len(vals) >= 2:
                delta = vals.iloc[-1] - vals.iloc[0]
                # Counters are monotonic; a negative delta means a
                # device reboot occurred mid-window (counter reset).
                # Flag rather than silently emit a negative value.
                row[f"{col}_delta"] = max(delta, 0)
                row[f"{col}_reset_detected"] = delta < 0
            elif len(vals) == 1:
                row[f"{col}_delta"] = 0
                row[f"{col}_reset_detected"] = False
            else:
                row[f"{col}_delta"] = np.nan
                row[f"{col}_reset_detected"] = False

            # The counter's ABSOLUTE value at each window edge, not just the
            # delta. PDR joins the root's arrivals log on probe sequence number
            # (the boards share no clock, so a time-keyed join is impossible);
            # reconstructing which sequence numbers a window covers needs the
            # true counter values here. See features.compute_pdr_features.
            row[f"{col}_first"] = vals.iloc[0] if len(vals) else np.nan
            row[f"{col}_last"] = vals.iloc[-1] if len(vals) else np.nan

        # Event counts: total events in window. layer_change_count and
        # parent_switch counts are derived in Milestone 7 from the raw
        # layer/parent_mac sequence; this pipeline carries the raw
        # per-sample layer/parent sequence forward implicitly via the
        # underlying long-format table, so M7 can recompute event counts
        # without needing them duplicated here.

        row["window_label"] = _modal_label(wdf["gt_label"])
        row["window_phase_id"] = _modal_label(wdf["phase_id"])

        rows.append(row)

    report.windows_kept = len(rows)

    windowed = pd.DataFrame(rows)
    if not windowed.empty:
        for node_id, count in windowed["node_id"].value_counts().items():
            report.per_node_window_counts[str(node_id)] = int(count)

    return windowed


def assign_segments(
    windowed: pd.DataFrame, report: PreprocessReport
) -> pd.DataFrame:
    """
    Separate the three meanings of phase 0 and void the label on the two that
    are not a baseline. Implements audit fix C6 (DATASET-AUDIT-2026-09-18,
    finding A1 #6); see the PHASE_BASELINE_S comment block at the top of this
    module for why phase 0 is ambiguous in the first place.

    ANCHOR. Each node's own FIRST EXIT from phase 0 — the window where
    window_phase_id first becomes non-zero. That transition is driven by a mesh
    broadcast from the root, so every node observes the same event, which makes
    it the one cross-node reference point that needs no shared clock (the boards
    never synchronise theirs). Times are expressed relative to it as
    ``t_anchor_s``, which is negative before the exit and zero at it.

    RULES, per node:
      phase 0, t_anchor_s <  -PHASE_BASELINE_S  -> pre_baseline  (EXCLUDED)
      phase 0, -PHASE_BASELINE_S <= t < 0       -> baseline
      phase 1 or 2                              -> attack
      phase 3                                   -> cooldown
      phase 0, t_anchor_s >= 0                  -> baseline_rebroadcast (EXCLUDED)
      never exits phase 0                       -> no_phase_seen        (EXCLUDED)

    Excluded segments keep every measured value — nothing is deleted — but get
    ``window_label = NaN`` so they cannot be counted into the benign class or
    the attack class by anything downstream. That is the whole point: a node
    probing a mesh the root has not joined yet is not "normal operation", and
    pooling it into the reference distribution is what made the 3-sigma
    verification arithmetically unable to detect even a perfect attack.

    WHY THE ANCHOR MUST BE THE PHASE EXIT, not the root's boot or its first
    logged arrival. On the 2026-09-18 G402 capture the attacker flushes its
    queued relay backlog the instant the root appears — 117 forwarded in a
    window where it received 6, ForwardingRatio 19.5 — and that single window
    carries most of the baseline variance. It sits at t_anchor_s = -361, i.e.
    61 s before the real baseline opens, so this rule excludes it; a cutoff
    anchored on the root's boot would keep it and ForwardingRatio would still
    fail (measured z = -2.78). Verified on that capture.
    """
    if windowed.empty:
        return windowed

    out = windowed.copy()
    out["t_anchor_s"] = np.nan
    out["segment"] = SEGMENT_NO_PHASE

    phase = pd.to_numeric(out["window_phase_id"], errors="coerce")

    # PHASE_ID_UNSET is "no broadcast heard yet" — the same condition phase 0
    # used to hide, now stated by the firmware. It is emphatically NOT a phase
    # exit, so it is excluded from the anchor test below and mapped straight to
    # pre_baseline. On v1 captures this mask is simply all-False and every rule
    # behaves exactly as before, which is what keeps the two schemas comparable.
    is_unset = phase.eq(PHASE_ID_UNSET)

    for (node_id, source_file), idx in out.groupby(
        ["node_id", "source_file"], sort=False
    ).groups.items():
        rows = out.loc[idx]
        exited = (phase.loc[idx].ne(0) & phase.loc[idx].notna()
                  & ~is_unset.loc[idx])
        if not exited.any():
            report.nodes_without_phase_exit.append(f"{node_id} ({source_file})")
            continue

        anchor = rows.loc[exited, "window_start"].min()
        t = rows["window_start"] - anchor
        out.loc[idx, "t_anchor_s"] = t

        p = phase.loc[idx]
        seg = pd.Series(SEGMENT_NO_PHASE, index=idx, dtype=object)
        seg[p.isin([1, 2])] = SEGMENT_ATTACK
        seg[p == 3] = SEGMENT_COOLDOWN
        is_zero = p == 0
        seg[is_zero & (t >= 0)] = SEGMENT_REBROADCAST
        seg[is_zero & (t < 0)] = SEGMENT_BASELINE
        seg[is_zero & (t < -PHASE_BASELINE_S)] = SEGMENT_PRE_BASELINE

        # THE SCHEDULE IS DEFINED IN TWO PLACES AND NOTHING CHECKED THEY AGREE.
        #
        # PHASE_BASELINE_S above must equal the firmware's PHASE_BASELINE_S
        # (mesh_config.h), which is overridable at build time with
        # `idf.py -DPHASE_BASELINE_S=180`. Build shorter than the host assumes
        # and this slice reaches PAST the start of the real baseline, pulling
        # mesh-formation noise into the benign class -- silently, and in the
        # direction that looks like clean data rather than an error.
        #
        # The capture itself knows the answer, so measure it: how much phase-0
        # actually preceded the exit. Shorter than we assumed is the dangerous
        # direction and is reported per node; LONGER is normal and expected,
        # because the `jitter` scenario extends phase 0 on purpose.
        zero_span = -t[is_zero].min() if is_zero.any() else 0.0
        if zero_span and zero_span < PHASE_BASELINE_S:
            report.short_baseline.append(
                f"{node_id} ({source_file}): phase 0 ran {zero_span:.0f}s but "
                f"PHASE_BASELINE_S is {PHASE_BASELINE_S}s")
        # Applied LAST so it wins outright: an explicitly-unset phase is never
        # baseline, whatever t_anchor_s says about it.
        seg[is_unset.loc[idx]] = SEGMENT_PRE_BASELINE
        out.loc[idx, "segment"] = seg

    # Void the label everywhere the segment is not a real experimental phase.
    unlabelled = ~out["segment"].isin(LABELLED_SEGMENTS)
    out.loc[unlabelled, "window_label"] = np.nan

    # Belt and braces: GT_LABEL_UNSET must never survive as a class value, even
    # if some future segment rule accidentally admits it. 255 entering a label
    # column is the single most expensive failure this module can produce — it
    # is numerically valid, sorts as "the biggest class", and nothing
    # downstream would question it.
    out.loc[pd.to_numeric(out["window_label"], errors="coerce")
            .eq(GT_LABEL_UNSET), "window_label"] = np.nan

    report.segment_counts = out["segment"].value_counts().to_dict()
    return out


def _max_consecutive_true(flags: np.ndarray) -> int:
    """Length of the longest run of True values in a boolean array."""
    if flags.size == 0:
        return 0
    max_run = run = 0
    for f in flags:
        run = run + 1 if f else 0
        max_run = max(max_run, run)
    return max_run


# ─────────────────────────────────────────────────────────────────────────
# Step 5 — Orchestration
# ─────────────────────────────────────────────────────────────────────────

def run_pipeline(
    input_dir: str,
) -> tuple[pd.DataFrame, PreprocessReport, pd.DataFrame]:
    """
    Full pipeline entry point. Accepts a folder of raw *_telem.csv files,
    returns (windowed_dataframe, quality_report, gap_filled_long_df).

    The third return value is the gap-filled long-format table (one row
    per node per second, post missing-value-handling, pre-windowing).
    Milestone 6 itself only needs the first two — the windowed output is
    the M6 deliverable. The long-format table exists for Milestone 7,
    which needs the raw per-sample (layer, parent_mac) SEQUENCE to detect
    transitions (ParentSwitchRate, HopChangeCount, HopStabilityDuration)
    — information that is necessarily lost once samples are collapsed to
    one modal value per 5-second window. Returning it here avoids
    re-running steps 1-3 a second time inside the M7 module.
    """
    report = PreprocessReport()

    raw = load_raw_telemetry(input_dir, report)
    rebased = rebase_timestamps(raw)
    filled = handle_missing_values(rebased, report)
    windowed = build_windows(filled, report, _run_context_from_path(input_dir))
    windowed = assign_segments(windowed, report)

    return windowed, report, filled


# ─────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────

def _write_column_legend(columns, data_path: str):
    """Writes <data>_legend.csv beside the output: what every column means.

    A failure here must never cost the data file already written, so it is
    reported and swallowed rather than raised.
    """
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import column_legend
        print(f"Wrote column legend to: "
              f"{column_legend.write_legend(columns, data_path)}")
    except Exception as exc:  # noqa: BLE001 — legend is a convenience
        print(f"  (column legend not written: {exc})")


def main():
    parser = argparse.ArgumentParser(
        description="NIS16 Milestone 6 — Cross-Layer Data Preprocessing Pipeline"
    )
    parser.add_argument(
        "input_dir",
        help="Folder containing raw *_telem.csv files (one or more experiment runs)",
    )
    parser.add_argument(
        "-o", "--output",
        default="windowed_dataset.csv",
        help="Output path for the windowed CSV (default: windowed_dataset.csv)",
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="Print the quality report to stdout after running",
    )
    args = parser.parse_args()

    print(f"Loading raw telemetry from: {args.input_dir}")
    windowed, report, _ = run_pipeline(args.input_dir)

    windowed.to_csv(args.output, index=False)
    print(f"Wrote {len(windowed)} windowed rows to: {args.output}")
    _write_column_legend(windowed.columns, args.output)

    if args.report or True:  # always show report — it's cheap and useful
        print()
        print(report.summary())


if __name__ == "__main__":
    main()
