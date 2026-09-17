#!/usr/bin/env python3
"""
import_sdcard.py — File an SD card pulled from a node into exports/.

This is the no-laptop counterpart to export_logs.py. A board deployed somewhere
with only a wall charger or a powerbank cannot be exported over USB, so
csv_logger.c mirrors every telemetry row onto its SD card as it runs, into

    <card>/<attack>/<topology>/<location>/<role>_<node_id>_b<boot>_<kind>.csv

which lands under exports/<attack>/<topology>/<location>/<scenario>/ — the same
tree export_logs.py writes, except the card has no scenario level (it's a host-
side/ledger concept, like --repeat), so --scenario names it for the whole
import. You bring the card home, run this, and the CSVs land where
preprocess.py already looks.

The board supplies attack, topology, location, role, node id and boot count. It
cannot supply the remaining fields in the export filename/path: the repeat
number and scenario (both campaign-level decisions) and a wall-clock date (an
ESP32 with no RTC boots at 1970). So --repeat is required, --scenario defaults
to "none", and the date is taken at import time.

A single card commonly spans MULTIPLE repeats (b1..b13 across two experiment
runs, say) and one --repeat cannot cover the whole thing correctly. Each leaf
folder's runs.csv (written by csv_logger.c — boot,run,node_id,role,rows,
uptime_s,event,built) says how many rows each boot logged and whether it ended
cleanly, so --boots picks the boot numbers that belong to THIS repeat and
--include-aborted overrides the default skip of boots that never reached a
clean close. --files does the same selection one FILE at a time.

"built" is the build date+time of the firmware that logged a boot
(sd_status_build_stamp(); see sd_status.h for why a build stamp and not a
clock). It is the only calendar reference on a board that boots at 1970, and it
answers the question a pulled card otherwise cannot: is this capture from the
flash I am running now, or left over from a session I have forgotten about?
Every boot of one flash shares it, so pair it with the boot number for ordering
within a flash. --list-json reports it per file, which is what the wizards'
numbered picker shows in its leftmost column.

Naming is NOT reimplemented here — this calls _subdir_for() and _make_filename()
from export_logs.py, so a card import and a USB export produce byte-identical
filenames and the two can never drift apart.

Usage:
    python import_sdcard.py --card E:\\ --repeat 1
    python import_sdcard.py --card E:\\ --repeat 2 --boots 5,6,7 --dry-run
    python import_sdcard.py --card E:\\ --repeat 1 --list-json
    python import_sdcard.py --card E:\\ --repeat 1 --files "blackhole\\linear\\home\\victim_NODE_20500DE70C80_r1_b3_telem.csv"

NIS16 — CTTHES3
"""

import argparse
import csv
import json
import os
import re
import shutil
import sys
import time
import types

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _THIS_DIR)

try:
    import serial  # noqa: F401  (pyserial)
except ImportError:
    # export_logs.py sys.exit()s at import time when pyserial is missing, but
    # the two functions borrowed below are pure string manipulation and a card
    # import never opens a serial port. Stub the module so this runs in any
    # Python rather than only inside the ESP-IDF PowerShell.
    sys.modules["serial"] = types.ModuleType("serial")

# Naming is reused, never reimplemented: the filename convention living in
# exactly one place is what keeps a card import and a USB export identical.
import export_logs  # noqa: E402

# Card folder name -> the --attack CLI value export_logs.py would have been
# given. Inverts _subdir_for()'s "none means baseline" mapping so the attack
# field inside the filename matches a USB export of the same run.
_ATTACK_FROM_DIR = {
    "baseline": "none",
    "blackhole": "blackhole",
    "wormhole": "wormhole",
}

# Inverts _TOPOLOGY_DIR in export_logs.py — only "partial" differs from its
# folder name, but derive the whole map from there so it cannot drift.
_TOPOLOGY_FROM_DIR = {v: k for k, v in export_logs._TOPOLOGY_DIR.items()}

# <role>_<node_id>_r<run>_b<boot>_<kind>.csv, written by sd_csv_path() in
# csv_logger.c. The "_r<run>_" segment is OPTIONAL in this regex — a card
# written before the run-counter feature existed has bare "_b<boot>_" names
# with no run segment, and those must keep importing exactly as before.
_CARD_FILE = re.compile(
    r"^(?P<role>root|victim)_(?P<node>NODE_[0-9A-Fa-f]{12})"
    r"(?:_r(?P<run>\d+))?_b(?P<boot>\d+)_(?P<kind>telem|arrivals)\.csv$"
)


class _Args:
    """Duck-typed stand-in for export_logs.main()'s argparse namespace —
    _subdir_for() and _make_filename() read exactly these attributes."""

    def __init__(self, **kw):
        self.flat = False
        self.attack_dir = None
        self.label = None
        self.port = None
        self.scenario = "none"   # the SD card tree predates scenarios; host stamps it
        for k, v in kw.items():
            setattr(self, k, v)


def _manifest_built(row):
    """The "built" field of one runs.csv row — sd_status_build_stamp() as
    csv_logger.c recorded it ("YYYY-MM-DD HH:MM:SS"), or None.

    Two shapes have to work. A card whose runs.csv was CREATED by firmware
    carrying this feature has a "built" header column, and DictReader hands it
    over by name. A card whose manifest was started by OLDER firmware keeps its
    original 7-column header forever (the firmware only writes a header when the
    file is new), so newer boots append an 8th field that has no name to land
    under — DictReader collects those into row[None]. Reading it back
    positionally there is what stops a reused card from silently losing the
    stamp on every boot until it is reformatted."""
    built = (row.get("built") or "").strip()
    if not built:
        extra = row.get(None) or []
        if extra:
            built = str(extra[-1]).strip()
    # "unknown" is what the firmware writes when the app descriptor could not be
    # parsed; it carries no more information than a missing field, so flatten
    # the two into one "we don't know" for every reader downstream.
    if not built or built == "unknown":
        return None
    return built


def _read_manifest(leaf_dir):
    """Parses <leaf_dir>/runs.csv (written by csv_logger.c) into
    {boot_number: {"rows": int, "uptime_s": int, "clean": bool, "built": str|None}}.

    The manifest is append-only on the firmware side: a boot appends a
    "start" row (rows=0) when its telemetry mirror opens, then a "clean" row
    with the final row count from csv_logger_close() if it gets there. A boot
    with a "start" and no "clean" was aborted — power loss, a killed run —
    and that gap in the file IS the record; nothing here second-guesses it.

    "built" is the build date+time of the FIRMWARE that logged that boot (see
    sd_status_build_stamp()). It is the same for every boot of one flash, which
    is exactly what makes it useful: it separates "captured with the firmware I
    flashed today" from "left on this card by a flash weeks ago", which an
    RTC-less board can express no other way. None on older cards.

    Returns {} if runs.csv is absent or unreadable (older firmware predating
    the manifest, or a card the sweep already tidied down to nothing) — the
    caller treats an absent entry as "unknown", never as "aborted"; a card
    with no manifest at all must keep importing exactly as it always has."""
    path = os.path.join(leaf_dir, "runs.csv")
    manifest = {}
    if not os.path.isfile(path):
        return manifest
    try:
        with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
            for row in csv.DictReader(f):
                try:
                    boot = int(row["boot"])
                    rows = int(row["rows"])
                    uptime_s = int(row["uptime_s"])
                except (KeyError, TypeError, ValueError):
                    continue  # malformed line (e.g. a write torn by power loss) — skip it
                entry = manifest.setdefault(
                    boot, {"rows": 0, "uptime_s": 0, "clean": False, "built": None})
                # Either row of a boot carries the stamp and both say the same
                # thing (one flash cannot be relinked mid-run), so the first one
                # that has it wins and a torn/missing field never clears it.
                if entry["built"] is None:
                    entry["built"] = _manifest_built(row)
                if row.get("event") == "clean":
                    entry["rows"] = rows
                    entry["uptime_s"] = uptime_s
                    entry["clean"] = True
                elif not entry["clean"]:
                    entry["uptime_s"] = uptime_s
    except OSError:
        pass
    return manifest


def _scan_dir(folder, manifest):
    """Yield (src_path, match, manifest_entry) for every card file matching
    _CARD_FILE directly inside `folder` (non-recursive)."""
    for name in sorted(os.listdir(folder)):
        m = _CARD_FILE.match(name)
        if m:
            entry = manifest.get(int(m.group("boot"))) if manifest else None
            yield os.path.join(folder, name), m, entry


def _scan(card_root):
    """Yield (src_path, attack_dir, topo_dir, location, match, manifest_entry)
    for every card file sitting at the expected depth. Anything else on the
    card is ignored — status_*.txt reports, location.txt, runs.csv itself, and
    the empty folders of the 63-folder tree the firmware creates on every boot.

    Each leaf's _archive\\ subfolder is deliberately NOT read: it holds prior
    runs csv_logger.c already moved out of the way (sd_archive_prior_run_mirrors()
    at the next boot, or ARCHIVE_SD after a confirmed USB export), and importing
    them again mixed old captures into a new run's exports. Copy a file out of
    _archive\\ by hand if one is genuinely needed.

    manifest_entry is this file's boot's row from _read_manifest() (a dict
    with rows/uptime_s/clean), or None if the leaf has no manifest at all."""
    for attack_dir in sorted(_ATTACK_FROM_DIR):
        attack_path = os.path.join(card_root, attack_dir)
        if not os.path.isdir(attack_path):
            continue
        for topo_dir in sorted(_TOPOLOGY_FROM_DIR):
            topo_path = os.path.join(attack_path, topo_dir)
            if not os.path.isdir(topo_path):
                continue
            for location in export_logs.LOCATIONS:
                leaf = os.path.join(topo_path, location)
                if not os.path.isdir(leaf):
                    continue
                manifest = _read_manifest(leaf)
                for src_path, m, entry in _scan_dir(leaf, manifest):
                    yield src_path, attack_dir, topo_dir, location, m, entry


def _row_count(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return max(sum(1 for _ in f) - 1, 0)  # minus the header


def _already_imported(dest, rows):
    """Returns the matching filename if a capture with the same run identity
    (role, node, topology, attack, repeat, kind) AND the same row count
    already sits in the destination folder — i.e. this exact capture was
    already copied here. None otherwise.

    _make_filename() stamps the CURRENT time into every name, so the same
    card file imported twice produces two different paths and a plain
    os.path.exists check would never fire.

    Identity alone (ignoring only the timestamp) is not enough on an SD-card
    import, though: nothing in the export filename convention carries the
    SD card's boot number, so two DIFFERENT boots — real, distinct captures —
    can legitimately share every one of those fields (same node, same
    --repeat; --boots exists precisely to import several of them together).
    Row count is the disambiguator: an identity match with the SAME row
    count is the same physical capture re-imported (skip it); an identity
    match with a DIFFERENT row count is a different boot that happens to
    share a repeat number (let it through as an additional file —
    preprocess.py already concatenates every file in a leaf folder for one
    node, so this is more data for that repeat, not a corruption risk)."""
    folder, name = os.path.split(dest)
    if not os.path.isdir(folder):
        return None
    head, _date, _time, kind = name.rsplit("_", 3)
    for existing in sorted(os.listdir(folder)):
        if existing.startswith(head + "_") and existing.endswith("_" + kind):
            if _row_count(os.path.join(folder, existing)) == rows:
                return existing
    return None


def _load_roster(path):
    """Reads a run_wizard.ps1 preset (presets\\*.json) into
    {MAC-without-separators-uppercased: {"label": ..., "role": ...}}.

    Without this, an imported card file is named from what the CARD knows:
    role "victim" (the firmware's word for any non-root board) and label
    NODE_<MAC>. A USB export of the same board is named child_node2_... —
    so the same run ended up with two different naming shapes depending on
    how the data came off the board, and node2 was only identifiable by
    memorising its MAC.

    The preset already stores Label/Role/Mac per board, so pointing at it
    makes a card import produce byte-identical naming to a USB export of the
    same board:  child_node2_linear_blackhole_r2_<date>_<time>_telem.csv.

    Returns {} (silently falling back to card-supplied naming) if the file is
    missing or unparseable — a roster is an optional convenience, never a
    precondition for getting data off a card.
    """
    try:
        with open(path, "r", encoding="utf-8-sig") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        # stderr, not stdout: --list-json's whole output must stay parseable
        # JSON, and the wizards that drive it merge stderr into the transcript
        # anyway, so this stays just as visible as it was.
        print(f"WARNING: could not read roster {path}: {e}\n"
              f"         falling back to the card's own role/NODE_<MAC> naming.",
              file=sys.stderr)
        return {}

    roster = {}
    for board in cfg.get("boards") or []:
        mac = str(board.get("Mac") or "")
        key = re.sub(r"[^0-9A-Fa-f]", "", mac).upper()
        if len(key) != 12:
            continue
        roster[key] = {
            "label": str(board.get("Label") or "") or None,
            # Preset Role is already the export vocabulary (root/child); the
            # card only ever says root/victim.
            "role": str(board.get("Role") or "") or None,
        }
    return roster


def _make_unique_filename(dest_args, kind, used_this_run):
    """export_logs._make_filename() stamps only second-granularity wall-clock
    time. That was never a problem for a single USB export (one file per
    invocation), but --boots exists precisely so several boots of the same
    repeat get imported in one invocation — and generating their destination
    names back-to-back can land two calls in the same second, producing
    IDENTICAL paths. shutil.copy2() would then silently overwrite the first
    boot's data with the second's.

    _make_filename() itself is not touched (still the one place the naming
    convention lives) — this just refuses to reuse a name this run already
    claimed, sleeping the ~1s needed for the next call to land on a new
    timestamp. A real card import is a few files, seconds apart in practice;
    this only ever triggers on the fast, back-to-back multi-boot case."""
    dest = export_logs._make_filename(dest_args, kind)
    while dest in used_this_run:
        time.sleep(1)
        dest = export_logs._make_filename(dest_args, kind)
    used_this_run.add(dest)
    return dest


def _dest_args_for(m, attack_dir, topo_dir, location, roster, args):
    """The export_logs.py argument namespace that names ONE card file's
    destination.

    Shared by the copy loop and --list-json on purpose: the filename the picker
    shows an operator has to be the filename the copy actually writes, and the
    only way to guarantee that is for both to go through this one call."""
    # Card-supplied identity first; a --roster match upgrades it to the same
    # label/role a USB export of this board would have used.
    node_key = m.group("node").replace("NODE_", "").upper()
    known = roster.get(node_key) or {}
    return _Args(
        role=known.get("role") or m.group("role"),
        # sanitised to NODE-AABB.. by _make_filename when unmatched
        label=known.get("label") or m.group("node"),
        topology=_TOPOLOGY_FROM_DIR[topo_dir],
        attack=_ATTACK_FROM_DIR[attack_dir],
        attack_dir=attack_dir,       # keeps a baseline-flashed control victim
                                     # in the attack folder it was captured in
        location=location,
        repeat=args.repeat,
        outdir=args.outdir,
        scenario=args.scenario,
    )


def _describe(src, attack_dir, topo_dir, location, m, entry, roster, args):
    """One --list-json entry: everything a picker needs to show a file and hand
    it back for import.

    "built" is the headline field — the build date+time of the firmware that
    logged this boot (csv_logger.c's runs.csv "built" column). A board with no
    RTC cannot date its own captures, so this is what tells an operator whether
    a file on the card belongs to the flash they are running now or to a session
    they have since forgotten about. None on cards written before the stamp
    existed, which reads as "unknown", never as "old".

    "rel" is the identifier: pass it straight back in --files to import exactly
    this file."""
    rows = _row_count(src)
    dest = export_logs._make_filename(
        _dest_args_for(m, attack_dir, topo_dir, location, roster, args),
        m.group("kind"))
    return {
        "rel": os.path.relpath(src, args.card),
        "name": os.path.basename(src),
        "attack": attack_dir,
        "topology": topo_dir,
        "location": location,
        "role": m.group("role"),
        "node": m.group("node"),
        "boot": int(m.group("boot")),
        "run": int(m.group("run")) if m.group("run") else None,
        "kind": m.group("kind"),
        "rows": rows,
        # None = no manifest for this boot at all ("unknown"); False = the
        # manifest positively says it started and never closed cleanly.
        "clean": None if entry is None else bool(entry["clean"]),
        "built": (entry or {}).get("built"),
        # The name it was already imported under, if an identical capture (same
        # identity AND row count) is sitting in exports/ — so the picker can say
        # so before the operator picks it again.
        "already": _already_imported(dest, rows),
        "archived": os.path.basename(os.path.dirname(src)) == "_archive",
    }


def main():
    p = argparse.ArgumentParser(
        description="Copy a pulled SD card's CSVs into exports/.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--card", required=True,
                   help=r"Card root, e.g. E:\ — the folder holding baseline/, "
                        r"blackhole/, wormhole/.")
    p.add_argument("--repeat", required=True, type=int,
                   help="Repeat number for this run. The board cannot know it; "
                        "it must match the run_ledger.csv entry.")
    p.add_argument("--scenario", choices=export_logs.SCENARIOS, default="none",
                   help="Run scenario this card's capture used (run.ps1 -Scenario): "
                        "none | burst | highload | mobility | powercycle. The SD "
                        "card tree has no scenario level (host-side only, like "
                        "--repeat) — one value applies to every file this import "
                        "copies.")
    p.add_argument("--outdir", default=os.path.join(_THIS_DIR, "exports"),
                   help="Export root (default: the exports/ folder next to this "
                        "script — the same default export_logs.py uses).")
    p.add_argument("--boots", default=None,
                   help="Comma-separated boot numbers to import (e.g. 5,6,7). "
                        "A card commonly spans more than one experiment repeat "
                        "(b1..b13 across two runs) and --repeat is one value for "
                        "the whole invocation, so this is how you import just the "
                        "boots that belong to the repeat you're naming. Omit to "
                        "import every boot found (the old, whole-card behaviour).")
    p.add_argument("--files", default=None,
                   help="Comma-separated card-relative paths to import (exactly "
                        "as --list-json reports them in each entry's \"rel\"). "
                        "Where --boots selects whole boots, this selects "
                        "individual files, which is what the wizards' numbered "
                        "picker hands back. Omit to import everything found.")
    p.add_argument("--list-json", action="store_true",
                   help="Print one JSON array describing every importable file "
                        "on the card - rel path, boot/run, rows, clean/aborted, "
                        "the firmware build stamp, and whether an identical "
                        "capture is already in exports/ - then exit without "
                        "copying anything. This is what run_wizard.ps1 and "
                        "menu.ps1 build their numbered file picker from. stdout "
                        "is JSON and nothing else; warnings go to stderr.")
    p.add_argument("--include-aborted", action="store_true",
                   help="Also import boots whose runs.csv shows a 'start' with no "
                        "matching 'clean' (power loss, a killed run). Skipped by "
                        "default since that data is a partial, cut-off capture.")
    p.add_argument("--roster", default=None,
                   help="A run_wizard.ps1 preset (presets\\*.json) to take board "
                        "labels/roles from, matched by MAC. Without it a card "
                        "import is named from what the card knows (victim_NODE_"
                        "<MAC>_...); with it the file is named exactly as a USB "
                        "export of that board would be (child_node2_...), so one "
                        "run's files all look alike however they came off the board.")
    p.add_argument("--delete-source", action="store_true",
                   help="Delete each card file after its copy has been VERIFIED "
                        "(destination exists and has the same row count). Only "
                        "files this invocation actually copied are deleted - never "
                        "one that was skipped, filtered out, or already imported. "
                        "Ignored under --dry-run.")
    p.add_argument("--dry-run", action="store_true",
                   help="Show what would be copied and exit.")
    args = p.parse_args()

    if not os.path.isdir(args.card):
        return f"ERROR: --card path not found: {args.card}"

    wanted_boots = None
    if args.boots:
        try:
            wanted_boots = {int(b) for b in args.boots.split(",") if b.strip()}
        except ValueError:
            return f"ERROR: --boots must be comma-separated integers, got: {args.boots}"

    # Compared case- and separator-normalised: these come back from a picker in
    # PowerShell, and a card path spelled blackhole\linear\home\x.csv must match
    # the same file scanned as blackhole/linear/home/x.csv.
    wanted_files = None
    if args.files:
        wanted_files = {os.path.normcase(os.path.normpath(f.strip()))
                        for f in args.files.split(",") if f.strip()}
        if not wanted_files:
            return f"ERROR: --files was given but named nothing: {args.files}"

    found = list(_scan(args.card))
    roster = _load_roster(args.roster) if args.roster else {}

    # Listing runs before the "nothing found" error below: an empty card is a
    # legitimate answer to "what is on here?" ([] and exit 0), not a failure —
    # the caller wants to say "nothing to import" in its own words rather than
    # surface a traceback-shaped error for a card that is simply already clear.
    if args.list_json:
        print(json.dumps([
            _describe(src, attack_dir, topo_dir, location, m, entry, roster, args)
            for src, attack_dir, topo_dir, location, m, entry in found
        ]))
        return 0

    if not found:
        return (f"ERROR: no run CSVs found under {args.card}.\n"
                "  Expected <attack>/<topology>/<location>/<role>_NODE_..._b<n>_telem.csv\n"
                "  An empty 63-folder tree with no CSVs means the boards ran before\n"
                "  the SD mirror existed, or location.txt was missing/unrecognised —\n"
                "  check the status_NODE_*.txt report or LOCATION_MISSING.txt on the card.")

    copied = skipped = filtered_out = aborted_skipped = 0
    deleted = delete_failed = 0
    used_this_run = set()  # see _make_unique_filename() — guards against a
                            # same-second destination collision across boots
    for src, attack_dir, topo_dir, location, m, entry in found:
        boot = int(m.group("boot"))

        if wanted_boots is not None and boot not in wanted_boots:
            filtered_out += 1
            continue

        rel = os.path.relpath(src, args.card)

        # --files is the picker's counterpart to --boots: same "not for this
        # invocation" outcome, one file at a time instead of a whole boot.
        if wanted_files is not None and os.path.normcase(os.path.normpath(rel)) not in wanted_files:
            filtered_out += 1
            continue

        # run is None on a card written before the run-counter feature existed
        # (no "_r<N>_" segment in the filename) — shown only when present.
        run_tag = f"run {m.group('run')}, " if m.group("run") else ""

        # entry is None when the leaf has no runs.csv at all (older firmware,
        # or a manifest-less card) — "unknown", not "aborted", and imported as
        # before. entry["clean"] is False only when we POSITIVELY know this
        # boot's manifest shows a start with no matching clean.
        if entry is not None and not entry["clean"] and not args.include_aborted:
            print(f"  SKIP  {rel}\n"
                  f"        {run_tag}boot {boot} ABORTED (runs.csv: started, never "
                  f"closed cleanly) — pass --include-aborted to import it anyway")
            aborted_skipped += 1
            continue

        dest_args = _dest_args_for(m, attack_dir, topo_dir, location, roster, args)
        rows = _row_count(src)
        status = f", {run_tag.rstrip(', ')}" if run_tag else ""
        if entry is not None:
            status += (f", manifest: {entry['rows']} rows / {entry['uptime_s']}s, "
                       f"{'clean' if entry['clean'] else 'ABORTED'}")
            if entry["built"]:
                status += f", built {entry['built']}"

        dest = _make_unique_filename(dest_args, m.group("kind"), used_this_run)

        clash = _already_imported(dest, rows)
        if clash:
            print(f"  SKIP  {rel}\n        already imported as {clash}")
            skipped += 1
            continue

        print(f"  {'WOULD COPY' if args.dry_run else 'COPY'}  {rel}  "
              f"({rows} rows{status})\n        -> {os.path.relpath(dest, args.outdir)}")
        if not args.dry_run:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(src, dest)   # copy first, always: the card copy is only
                                      # released below, and only once verified
            copied += 1

            # --delete-source frees a reused card so last month's captures can't
            # be dragged into an exports folder again (the failure this whole
            # naming/repeat mess came from). Verified, not assumed: the
            # destination must exist and hold the same row count as the source
            # before the only other copy is destroyed. A failed verification
            # leaves the card file exactly where it was and says so.
            if args.delete_source:
                try:
                    if os.path.isfile(dest) and _row_count(dest) == rows:
                        os.remove(src)
                        deleted += 1
                    else:
                        delete_failed += 1
                        print(f"        KEPT on card: copy did not verify "
                              f"(expected {rows} rows)")
                except OSError as e:
                    delete_failed += 1
                    print(f"        KEPT on card: {e}")

    print()
    tail = []
    if filtered_out:
        which = "/".join(f for f, on in (("--boots", wanted_boots is not None),
                                         ("--files", wanted_files is not None)) if on)
        tail.append(f"{filtered_out} outside {which}")
    if aborted_skipped:
        tail.append(f"{aborted_skipped} aborted")
    if skipped:
        tail.append(f"{skipped} already imported")
    tail_str = (" (" + ", ".join(tail) + ")") if tail else ""
    if args.dry_run:
        print(f"Dry run: {len(found)} file(s) found{tail_str}.")
    else:
        print(f"Imported {copied} file(s) into {args.outdir}{tail_str}.")
        if args.delete_source:
            print(f"Removed {deleted} verified file(s) from the card"
                  + (f"; {delete_failed} kept (did not verify)." if delete_failed else "."))
        else:
            print("The card was not modified - erase it only after you have checked "
                  "the imported rows.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
