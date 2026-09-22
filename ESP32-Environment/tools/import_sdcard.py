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

TWO SOURCES, ONE PIPELINE
-------------------------
The card can be read either way, and everything after the read is shared:

    --card E:\\      the card is OUT of the board, in a reader on this laptop
    --port COM7      the card is STILL IN the board; it is read over USB using
                     the firmware's LIST_SD / EXPORT_SD_PATH commands

--port exists because pulling a card to see what is on it is the step that
loses cards, bends holders, and reboots a board mid-campaign. Both modes produce
the same --list-json shape, the same filenames and the same exports/ layout, so
the wizard's file picker is one piece of code that does not care which was used.

The two are not quite equals in one respect, and the difference is deliberate.
Over USB a file's row count comes from the leaf's runs.csv manifest rather than
from counting the file, because counting means streaming every byte off a 4 MHz
SPI card before the operator sees a single line (see sd_list_card() in
csv_logger.c). A file whose manifest is missing reports rows as None —
"unknown", never 0. The true count is learned when the file is actually
imported, and a disagreement with the manifest is reported, since that is the
signature of a capture cut short.

Usage:
    python import_sdcard.py --card E:\\ --repeat 1
    python import_sdcard.py --card E:\\ --repeat 2 --boots 5,6,7 --dry-run
    python import_sdcard.py --card E:\\ --repeat 1 --list-json
    python import_sdcard.py --card E:\\ --repeat 1 --files "blackhole\\linear\\home\\victim_NODE_20500DE70C80_r1_b3_telem.csv"
    python import_sdcard.py --port COM7 --repeat 1 --list-json
    python import_sdcard.py --port COM7 --repeat 1 --files "blackhole/linear/home/victim_NODE_20500DE70C80_r1_b3_telem.csv"

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
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
            return _parse_manifest_lines(f)
    except OSError:
        return {}


def _parse_manifest_lines(lines):
    """The parsing half of _read_manifest(), over any iterable of runs.csv text
    lines. Split out so the --port path can feed it the manifest the firmware
    streamed over USB (SDMAN: lines from LIST_SD) and get an identical result —
    one parser, so the two sources can never disagree about what 'aborted'
    means."""
    manifest = {}
    for row in csv.DictReader(lines):
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


# ── Card sources ────────────────────────────────────────────────────────────
# Everything below the source is shared: the same filtering, the same naming,
# the same duplicate rules, the same output. A source only has to answer three
# questions — what is on the card, how many rows is this file, and give me its
# contents — so adding a third way to reach a card later stays cheap.

class _MountedCard:
    """--card: the card is in a reader on this laptop."""

    kind = "card"

    def __init__(self, root):
        self.root = root
        self.label = root
        self.can_delete = True

    def entries(self):
        for src, attack_dir, topo_dir, location, m, entry in _scan(self.root):
            yield os.path.relpath(src, self.root), attack_dir, topo_dir, location, m, entry

    def _abs(self, rel):
        return os.path.join(self.root, rel)

    def rows(self, rel, entry):
        return _row_count(self._abs(rel))

    def size(self, rel):
        try:
            return os.path.getsize(self._abs(rel))
        except OSError:
            return -1

    def live(self, rel):
        # A card in a reader has no board writing to it, by definition.
        return False

    def copy_to(self, rel, dest):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(self._abs(rel), dest)
        return _row_count(dest)

    def delete(self, rel):
        os.remove(self._abs(rel))

    def close(self):
        pass


class _BoardCard:
    """--port: the card is still in the board, read over USB serial.

    One serial connection is held open for the whole invocation: LIST_SD once,
    then one EXPORT_SD_PATH per file the caller actually wants. The port is
    opened exactly the way export_logs.py opens it (DTR/RTS deasserted) so
    connecting does not reset the board and kill its export task."""

    def __init__(self, port):
        self.port = port
        self.label = f"{port} (card in the board)"
        self.can_delete = False   # DELETE_SD_PATH removes FOLDERS, not files
        self._ser = export_logs._open_port(port)
        self._files = {}      # rel -> size in bytes
        self._live = set()    # rel paths the board still has OPEN right now
        self._manifests = {}  # leaf_rel -> parsed manifest
        self._scan_board()

    def _scan_board(self):
        """Issue LIST_SD and parse the SDLIST_BEGIN/SDLEAF/SDMAN/SDFILE frame."""
        export_logs._drain(self._ser)
        export_logs._send_command(self._ser, "LIST_SD")
        deadline = time.time() + _BOARD_LIST_TIMEOUT_S
        started = False
        leaf = None
        man_lines = {}
        while time.time() < deadline:
            raw = self._ser.readline()
            if not raw:
                continue
            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            if line.startswith("ERROR:"):
                raise RuntimeError(f"board refused LIST_SD: {line}")
            if line == "SDLIST_BEGIN":
                started = True
                continue
            if line == "SDLIST_END":
                break
            if not started:
                continue  # boot chatter before the frame opened
            deadline = time.time() + _BOARD_LIST_TIMEOUT_S  # progress — extend
            if line.startswith("SDLEAF:"):
                leaf = line[len("SDLEAF:"):].strip()
                man_lines.setdefault(leaf, [])
            elif line.startswith("SDMAN:") and leaf:
                man_lines[leaf].append(line[len("SDMAN:"):])
            elif line.startswith("SDFILE:") and leaf:
                # SDFILE:<name>|<bytes>|<live>   (live added sep. 22, 2026)
                # Older firmware sends only <name>|<bytes>, and older still just
                # <name>. Parse from the RIGHT so a filename containing "|" can
                # never eat the numeric fields, and default live to 0 = unknown
                # rather than guessing a run is in progress.
                body = line[len("SDFILE:"):]
                parts = body.split("|")
                name, size, live = body, "-1", "0"
                if len(parts) >= 3:
                    name, size, live = "|".join(parts[:-2]), parts[-2], parts[-1]
                elif len(parts) == 2:
                    name, size = parts[0], parts[1]
                try:
                    size_i = int(size)
                except ValueError:
                    size_i = -1
                rel = f"{leaf}/{name}"
                self._files[rel] = size_i
                if live.strip() == "1":
                    self._live.add(rel)
        else:
            raise RuntimeError(
                "board never finished LIST_SD (no SDLIST_END). Old firmware "
                "without LIST_SD, or idf.py monitor still holding the port?")
        if not started:
            raise RuntimeError(
                "board did not answer LIST_SD. Reflash it — this needs the "
                "firmware that added LIST_SD/EXPORT_SD_PATH.")
        for leaf_rel, lines in man_lines.items():
            self._manifests[leaf_rel] = _parse_manifest_lines(lines)

    def entries(self):
        for rel in sorted(self._files):
            leaf_rel, _, name = rel.rpartition("/")
            m = _CARD_FILE.match(name)
            if not m:
                continue
            parts = leaf_rel.split("/")
            if len(parts) != 3:
                continue
            attack_dir, topo_dir, location = parts
            if attack_dir not in _ATTACK_FROM_DIR or topo_dir not in _TOPOLOGY_FROM_DIR:
                continue
            manifest = self._manifests.get(leaf_rel) or {}
            entry = manifest.get(int(m.group("boot"))) if manifest else None
            yield rel, attack_dir, topo_dir, location, m, entry

    def rows(self, rel, entry):
        """Manifest rows, or None for "unknown" — see the module docstring for
        why this does not count the file. None for an ABORTED boot too: its
        manifest never received a final count, so 0 there would be a lie.

        None for an ARRIVALS file as well, whatever the manifest holds.
        runs.csv's "rows" column is the TELEMETRY count for that boot
        (csv_logger_close() reports s_total_rows); a root's arrivals.csv shares
        the boot, and therefore the manifest row, while counting a completely
        different thing. Handing that number back would print a telemetry count
        beside an arrivals file in the picker, and — worse — give
        _already_imported() a disambiguator that can never match the file's real
        count, so re-importing a root over USB copied a duplicate every time
        instead of skipping it. "Unknown" is the honest answer, and it makes
        _already_imported() fall back to its identity-only match, which does
        catch the duplicate. The mounted-card path is unaffected: it counts the
        file itself. The same telem/arrivals conflation is guarded at the
        manifest-mismatch check in the import loop — keep the two in step."""
        if entry is None or not entry["clean"]:
            return None
        m = _CARD_FILE.match(os.path.basename(rel))
        if m and m.group("kind") != "telem":
            return None
        return entry["rows"]

    def size(self, rel):
        return self._files.get(rel, -1)

    def live(self, rel):
        """True if the board still has this file OPEN — a run in progress.
        See sd_is_live_mirror() in csv_logger.c for why this is not the same
        thing as "aborted", even though runs.csv cannot tell them apart."""
        return rel in self._live

    def copy_to(self, rel, dest):
        rows, err, _tries = export_logs._capture_with_retries(
            self._ser, f"EXPORT_SD_PATH={rel}")
        if err:
            raise RuntimeError(err)
        if not rows:
            raise RuntimeError("board streamed no rows")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        export_logs._save(rows, dest)
        return _row_count(dest)

    def delete(self, rel):
        raise RuntimeError(
            "--delete-source is not available over --port: the firmware's "
            "DELETE_SD_PATH removes whole folders, never single files. Pull the "
            "card, or use the wizard's 'delete a folder from the card' option.")

    def close(self):
        try:
            self._ser.close()
        except Exception:
            pass


# LIST_SD walks up to 48 leaf folders and reads a manifest in each, so the
# first line can be slow to arrive; the timeout restarts on every line received.
_BOARD_LIST_TIMEOUT_S = 30


def _already_imported(dest, rows):   # noqa: D401 — docstring below is the spec
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
    node, so this is more data for that repeat, not a corruption risk).

    rows may be None when the row count is not known yet — the --port path,
    where counting a file would mean streaming it off the card first (see the
    module docstring). The disambiguator is then unavailable, so this falls back
    to an IDENTITY-only match and the caller is told it is a likely, not
    certain, duplicate. Erring toward "you have probably already got this"
    matches the mounted-card behaviour for the operator, and the file is still
    importable by naming it explicitly in --files."""
    folder, name = os.path.split(dest)
    if not os.path.isdir(folder):
        return None
    head, _date, _time, kind = name.rsplit("_", 3)
    for existing in sorted(os.listdir(folder)):
        if existing.startswith(head + "_") and existing.endswith("_" + kind):
            if rows is None:
                return existing
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


def _describe(source, rel, attack_dir, topo_dir, location, m, entry, roster, args):
    """One --list-json entry: everything a picker needs to show a file and hand
    it back for import.

    "built" is the headline field — the build date+time of the firmware that
    logged this boot (csv_logger.c's runs.csv "built" column). A board with no
    RTC cannot date its own captures, so this is what tells an operator whether
    a file on the card belongs to the flash they are running now or to a session
    they have since forgotten about. None on cards written before the stamp
    existed, which reads as "unknown", never as "old".

    "rel" is the identifier: pass it straight back in --files to import exactly
    this file.

    "rows" is None when the source cannot answer cheaply (the --port path — see
    the module docstring). A picker must render that as "unknown", never as 0:
    0 rows is a real and meaningful state on this project (it is what a
    reset-interrupted capture used to look like before the fsync fix in
    csv_logger.c) and the two must not be confused.

    "bytes" is -1 when unknown. It is the --port path's stand-in for a row
    count: it always comes back, and a file whose size is plainly too small is
    the same warning sign a row count would have been."""
    rows = source.rows(rel, entry)
    size = source.size(rel) if hasattr(source, "size") else -1
    dest = export_logs._make_filename(
        _dest_args_for(m, attack_dir, topo_dir, location, roster, args),
        m.group("kind"))
    return {
        "rel": rel,
        "name": os.path.basename(rel),
        "attack": attack_dir,
        "topology": topo_dir,
        "location": location,
        "role": m.group("role"),
        "node": m.group("node"),
        "boot": int(m.group("boot")),
        "run": int(m.group("run")) if m.group("run") else None,
        "kind": m.group("kind"),
        "rows": rows,
        "bytes": size,
        # True = the board is writing to this file RIGHT NOW (run in progress).
        # Distinct from clean=False, which cannot tell "still going" from "died".
        "live": source.live(rel) if hasattr(source, "live") else False,
        # Where this listing came from, so a picker can label itself and can
        # explain WHY rows may be unknown without guessing.
        "source": getattr(source, "kind", "card"),
        # None = no manifest for this boot at all ("unknown"); False = the
        # manifest positively says it started and never closed cleanly.
        "clean": None if entry is None else bool(entry["clean"]),
        "built": (entry or {}).get("built"),
        # The name it was already imported under, if an identical capture (same
        # identity AND row count) is sitting in exports/ — so the picker can say
        # so before the operator picks it again.
        "already": _already_imported(dest, rows),
        "archived": os.path.basename(os.path.dirname(rel)) == "_archive",
    }


def main():
    p = argparse.ArgumentParser(
        description="Copy a pulled SD card's CSVs into exports/.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--card", default=None,
                     help=r"Card root, e.g. E:\ — the folder holding baseline/, "
                          r"blackhole/, wormhole/. Use this when the card has "
                          r"been pulled and put in a reader.")
    src.add_argument("--port", default=None,
                     help="Serial port of a RUNNING board, e.g. COM7 — read its "
                          "SD card over USB instead, leaving the card in place. "
                          "Needs firmware with LIST_SD/EXPORT_SD_PATH. Close "
                          "idf.py monitor first; the port can only be held once.")
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

    if args.card and not os.path.isdir(args.card):
        return f"ERROR: --card path not found: {args.card}"
    if args.port and args.delete_source:
        return ("ERROR: --delete-source cannot be used with --port. The "
                "firmware can only delete whole card FOLDERS (DELETE_SD_PATH), "
                "never single files, so there is no safe per-file removal over "
                "USB. Pull the card if you need to free it.")

    try:
        source = _MountedCard(args.card) if args.card else _BoardCard(args.port)
    except Exception as e:                       # serial, or a board that can't list
        return f"ERROR: could not read the card: {e}"

    try:
        return _run(source, args)
    finally:
        source.close()


def _parsed_boots(args):
    """A set of boot numbers, None for "every boot", or an ERROR string."""
    if not args.boots:
        return None
    try:
        return {int(b) for b in args.boots.split(",") if b.strip()}
    except ValueError:
        return f"ERROR: --boots must be comma-separated integers, got: {args.boots}"


def _parsed_files(args):
    """A set of normalised card-relative paths, None for "every file", or an
    ERROR string.

    Compared case- and separator-normalised: these come back from a picker in
    PowerShell, and a card path spelled blackhole\\linear\\home\\x.csv must match
    the same file listed as blackhole/linear/home/x.csv — which is exactly what
    the --port path reports, since the firmware speaks in forward slashes."""
    if not args.files:
        return None
    wanted = {os.path.normcase(os.path.normpath(f.strip()))
              for f in args.files.split(",") if f.strip()}
    if not wanted:
        return f"ERROR: --files was given but named nothing: {args.files}"
    return wanted


def _run(source, args):
    """Everything from here down is source-agnostic — see the module docstring.
    Split out of main() only so the caller can guarantee source.close()."""
    wanted_boots = _parsed_boots(args)
    wanted_files = _parsed_files(args)
    if isinstance(wanted_boots, str):
        return wanted_boots
    if isinstance(wanted_files, str):
        return wanted_files

    found = list(source.entries())
    roster = _load_roster(args.roster) if args.roster else {}

    # Listing runs before the "nothing found" error below: an empty card is a
    # legitimate answer to "what is on here?" ([] and exit 0), not a failure —
    # the caller wants to say "nothing to import" in its own words rather than
    # surface a traceback-shaped error for a card that is simply already clear.
    if args.list_json:
        print(json.dumps([
            _describe(source, rel, attack_dir, topo_dir, location, m, entry, roster, args)
            for rel, attack_dir, topo_dir, location, m, entry in found
        ]))
        return 0

    if not found:
        return (f"ERROR: no run CSVs found under {args.card}.\n"
                "  Expected <attack>/<topology>/<location>/<role>_NODE_..._b<n>_telem.csv\n"
                "  An empty 63-folder tree with no CSVs means the boards ran before\n"
                "  the SD mirror existed, or location.txt was missing/unrecognised —\n"
                "  check the status_NODE_*.txt report or LOCATION_MISSING.txt on the card.")

    copied = skipped = filtered_out = aborted_skipped = failed = live_skipped = 0
    deleted = delete_failed = 0
    used_this_run = set()  # see _make_unique_filename() — guards against a
                            # same-second destination collision across boots
    for rel, attack_dir, topo_dir, location, m, entry in found:
        boot = int(m.group("boot"))

        if wanted_boots is not None and boot not in wanted_boots:
            filtered_out += 1
            continue

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
        # A file the board still has OPEN is NOT aborted — the run simply has not
        # finished. Importing it now yields a truncated capture that looks like a
        # real one, so this is refused outright rather than hidden behind
        # --include-aborted, which exists for genuinely dead runs — a different
        # thing. Let the run reach TERMINATE, then export.
        if hasattr(source, "live") and source.live(rel):
            print(f"  SKIP  {rel}")
            print(f"        {run_tag}boot {boot} is STILL BEING WRITTEN"
                  f" - this board is mid-run.")
            print( "        Let it reach TERMINATE (or reset it), then export."
                   " Importing now captures a partial run that looks complete.")
            live_skipped += 1
            continue

        if entry is not None and not entry["clean"] and not args.include_aborted:
            print(f"  SKIP  {rel}\n"
                  f"        {run_tag}boot {boot} ABORTED (runs.csv: started, never "
                  f"closed cleanly) — pass --include-aborted to import it anyway")
            aborted_skipped += 1
            continue

        dest_args = _dest_args_for(m, attack_dir, topo_dir, location, roster, args)
        # None over --port (see the module docstring): reported as "?" rather
        # than 0, because 0 rows is a real state on this project and the two
        # must never look the same in the operator's output.
        rows = source.rows(rel, entry)
        rows_txt = "?" if rows is None else str(rows)
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
              f"({rows_txt} rows{status})\n        -> {os.path.relpath(dest, args.outdir)}")
        if not args.dry_run:
            # copy_to() copies a mounted card's file, or streams it off the
            # board over USB — either way the source is untouched and only
            # released below, and only once verified.
            try:
                written = source.copy_to(rel, dest)
            except Exception as e:
                failed += 1
                print(f"        FAILED: {e}")
                continue
            copied += 1

            # Over --port the MANIFEST's row count was all we had until now;
            # this is the first moment the real one is known. A mismatch means
            # the file on the card disagrees with what the firmware recorded for
            # that boot — a capture cut short, or a manifest written for a file
            # that kept growing. Worth saying out loud: it is the same shape as
            # the zero-rows failure the fsync fix in csv_logger.c addresses.
            # ONLY meaningful for telemetry: runs.csv's "rows" column is the
            # TELEMETRY row count for that boot (csv_logger_close() reports
            # s_total_rows). A root's arrivals.csv shares the same boot and so
            # the same manifest row, but counts a completely different thing —
            # comparing the two would fire a bogus "mismatch" on every single
            # root export and teach the operator to ignore a real warning.
            is_telem = m.group("kind") == "telem"
            if is_telem and rows is not None and written != rows:
                print(f"        NOTE: got {written} rows, manifest said {rows}")
            elif is_telem and rows is None:
                print(f"        {written} rows (no manifest to compare against)")

            # --delete-source frees a reused card so last month's captures can't
            # be dragged into an exports folder again (the failure this whole
            # naming/repeat mess came from). Verified, not assumed: the
            # destination must exist and hold the same row count as the source
            # before the only other copy is destroyed. A failed verification
            # leaves the card file exactly where it was and says so.
            if args.delete_source:
                try:
                    if os.path.isfile(dest) and written > 0 and (
                            rows is None or written == rows):
                        source.delete(rel)
                        deleted += 1
                    else:
                        delete_failed += 1
                        print(f"        KEPT on card: copy did not verify "
                              f"(expected {rows_txt} rows, got {written})")
                except OSError as e:
                    delete_failed += 1
                    print(f"        KEPT on card: {e}")

    print()
    tail = []
    if filtered_out:
        which = "/".join(f for f, on in (("--boots", wanted_boots is not None),
                                         ("--files", wanted_files is not None)) if on)
        tail.append(f"{filtered_out} outside {which}")
    if live_skipped:
        tail.append(f"{live_skipped} STILL RUNNING")
    if aborted_skipped:
        tail.append(f"{aborted_skipped} aborted")
    if skipped:
        tail.append(f"{skipped} already imported")
    if failed:
        tail.append(f"{failed} FAILED")
    tail_str = (" (" + ", ".join(tail) + ")") if tail else ""
    if args.dry_run:
        print(f"Dry run: {len(found)} file(s) found{tail_str}.")
    else:
        print(f"Imported {copied} file(s) from {source.label} "
              f"into {args.outdir}{tail_str}.")
        if args.delete_source:
            print(f"Removed {deleted} verified file(s) from the card"
                  + (f"; {delete_failed} kept (did not verify)." if delete_failed else "."))
        else:
            print("The card was not modified - erase it only after you have checked "
                  "the imported rows.")
    if failed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
