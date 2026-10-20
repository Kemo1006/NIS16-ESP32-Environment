#!/usr/bin/env python3
"""collect_run.py — pull ONE run's telemetry off every plugged-in child's SD card.

After a capture the children usually still sit on their USB cables. Instead of
importing them one by one (oct. 18 2026: seven boards by hand, and a card whose
location.txt was wrong filed one under G402), this reads each port in turn,
picks the file of THIS run and files it under the run's own folder:

    python tools/collect_run.py --ports COM10,COM11,COM9 --attack wormhole \
        --topology linear --location DLSU_Library --scenario highload --repeat 1 \
        --since "2026-10-18 14:40" [--roster presets/Cal/x.json] [--skip-mac b0cbd8f33218] [--dry-run]
    (scan, copies nothing:  --dry-run --plan-json plan.json ; copy exactly what was ticked:  --pick "COM10=<rel>;COM11=<rel>")

Per board it takes THE clean telemetry file of this attack + topology + location
started at/after --since - and refuses when there are two (a card has no scenario
folder, so it cannot tell a stationary run from a burst one). A file recorded under
another LOCATION is taken only with --allow-other-location (a location.txt left on
the last site) and is then filed under --location. A
board whose file is already in exports (same MAC, same rows) is skipped.

The copy itself is tools/import_sdcard.py --port (unchanged), one port at a
time: never two serial reads at once (the CP210x blue-screen history). Then
run_summary.py prints the run's health card.

Lines for the GUI:  COLLECT: <port> <mac> OK|SKIP|FAIL <text>
                    COLLECT_SUMMARY: ok=<n> skip=<n> fail=<n>
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    import root_match              # verification #60: is a child's file from the root's run?
except Exception:                  # pandas missing etc. - collect still works, unchecked
    root_match = None
BASE = os.path.dirname(HERE)
EXPORTS = os.path.join(BASE, "datasets", "exports")
TOPO_DIR = {"partial": "partial_mesh"}


def _py():
    return sys.executable or "python"


def _say(port, mac, state, text):
    print(f"COLLECT: {port} {mac or '-'} {state} {text}", flush=True)


def _list(src_args, repeat, scenario, roster):
    a = [_py(), os.path.join(HERE, "import_sdcard.py")] + src_args + ["--repeat", str(repeat), "--scenario", scenario, "--list-json"]
    if roster:
        a += ["--roster", roster]
    p = subprocess.run(a, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=HERE)
    line = next((l for l in reversed(p.stdout.splitlines()) if l.lstrip().startswith("[")), None)
    if p.returncode != 0 or line is None:
        err = (p.stderr.strip().splitlines() or p.stdout.strip().splitlines() or ["no answer"])[-1]
        raise RuntimeError(err)
    return json.loads(line)


# oct. 18 2026 (user: "Collect says FAILED on some nodes, but each node has good
# data"): a scan found 4 FAILs and none was the data - a port held by the GUI, a
# card that had not mounted yet, a board that did not answer in time, and a board
# whose only pieces were reset-ended. The transient ones are retried, and every
# failure says WHAT it is and what to do.
LIST_TRIES = (0, 3, 8)       # seconds to wait before attempt 1, 2, 3
TRANSIENT = ("never finished LIST_SD", "did not answer LIST_SD", "SD_NO_CARD", "Access is denied",
             "PermissionError", "could not open port", "timed out", "timeout", "no answer")


def _explain(err):
    """(kind, text) for a card-listing failure - kind: BUSY | NO_CARD | NO_ANSWER | OTHER."""
    e = str(err)
    if "Access is denied" in e or "PermissionError" in e or "could not open port" in e:
        return "BUSY", ("the PORT IS IN USE by another program (the GUI's Live run monitor / crash watch, a serial "
                        "monitor, a second GUI) - the card was never read. Close that, then Retry failed")
    if "SD_NO_CARD" in e:
        return "NO_CARD", ("the board says its SD card is NOT MOUNTED right now (just reset, or the card is loose) - "
                           "the data is still on the card. Press the card in, unplug + replug the board, then Retry failed")
    if "never finished LIST_SD" in e or "did not answer LIST_SD" in e or "no answer" in e or "timed out" in e.lower():
        return "NO_ANSWER", ("the board did not answer in time (still booting, busy, or the ROOT / a board on old "
                             "firmware) - nothing is wrong with its data. Unplug + replug it, then Retry failed")
    return "OTHER", e


def _list_retry(src_args, repeat, scenario, roster, label):
    """_list with up to 3 tries for the transient failures (a board that was just
    plugged in reboots and mounts its card a few seconds later)."""
    last = None
    for i, wait in enumerate(LIST_TRIES):
        if wait:
            print(f"   retry {i + 1}/{len(LIST_TRIES)} of {label} in {wait} s ({_explain(last)[0].lower()})", flush=True)
            time.sleep(wait)
        try:
            return _list(src_args, repeat, scenario, roster)
        except Exception as e:
            last = e
            if not any(t.lower() in str(e).lower() for t in TRANSIENT):
                break
    raise last


class _Tee:
    def __init__(self, *streams):
        self.streams = streams

    def write(self, text):
        for st in self.streams:
            try:
                st.write(text)
            except Exception:
                pass

    def flush(self):
        for st in self.streams:
            try:
                st.flush()
            except Exception:
                pass


def _tee_log(folder, head):
    """Everything this run prints also goes to <run_logs cell>/<head>_<stamp>.log -
    a failed board can be looked at after the GUI window is closed."""
    try:
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f"{head}_{dt.datetime.now():%b%d_%I%M%S%p}.log".lower())
        fh = open(path, "w", encoding="utf-8")
        fh.write(f"collect_run.py {' '.join(sys.argv[1:])}\n")
        sys.stdout = _Tee(sys.stdout, fh)
        print(f"(log: {path})", flush=True)
    except OSError:
        pass


def _when(text):
    try:
        return dt.datetime.strptime(str(text)[:19], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


CRASH_ENDS = ("PANIC", "INT_WDT", "TASK_WDT", "WDT")
MIN_PIECE_B = 80_000         # ~1,000 rows = ~100 s: smaller is a boot fragment, not a run


def _crashed_leaves(files, attack_dir, topology, since=None):
    """The card folders where this board CRASHED in this attack + topology (ended_by),
    in THIS run's time window - an older run's crash is not looked up again."""
    return sorted({f"{f.get('attack')}/{f.get('topology')}/{f.get('location')}" for f in files
                   if f.get("kind") == "telem" and f.get("filed_under") == attack_dir and f.get("topology") == topology
                   and str(f.get("ended_by") or "").upper() in CRASH_ENDS
                   and not (since and _when(f.get("started")) and _when(f.get("started")) < since)})


# ---- "does the data look good?" (oct. 19 2026) --------------------------------------
# User: "make Collect allow the datasets that look good". The card's own labels
# (clean / aborted, size, start time) do not say whether a file HOLDS the run: B7:68's
# piece picked by size + time held only 319 s of stabilise. So every file is checked
# by its CONTENT after the copy (into a temp folder first): rows per phase, with the
# root-restart rule of run_summary.py / preprocess.py. The pieces are tried NEWEST BOOT
# FIRST and the first one holding a baseline wins - NOT the one with the most data:
# B7:68's card held two pieces with a full baseline (b19 = the 9:40 PM root attempt,
# 53 s of attack; b114 = the 9:55 PM run, 29 s), and "most data" took the wrong run.
# A root session that reached Phase 0 is a run; the newest one is the run being
# collected (a stopped attempt is always older). A piece without a usable baseline is
# never filed - it is reported, the card is not touched.
HZ = 10                      # telemetry rows per second
FULL = {0: 270 * HZ, "attack": 120 * HZ, 3: 90 * HZ}   # >= 90 % baseline, 2/3 attack, 3/4 cooldown
MIN_BASELINE_ROWS = 60 * HZ  # under 60 s of baseline the 3-sigma test has nothing to compare with
MAX_TRIES = 4                # pieces copied per board at most
# oct. 19 2026 (verification #60): FE90's newest run left only stabilise pieces, so
# "newest piece that holds a baseline" walked back to a COMPLETE file of the attempt an
# hour earlier and filed it next to the new root. Pieces of one run start within minutes
# of each other (a reboot keeps the run's start); a piece this much older than the newest
# one is ANOTHER run and is never a fallback.
RUN_GAP_MIN = 15


def _coverage(path):
    import run_summary
    b = run_summary.read_board(path)
    ph = b["phases"]
    return {"stab": ph.get(255, 0), "base": ph.get(0, 0), "attack": ph.get(1, 0) + ph.get(2, 0), "cool": ph.get(3, 0),
            "old": b.get("old_rows", 0)}


def _cov_text(c):
    return (f"baseline {c['base'] // HZ} s, attack {c['attack'] // HZ} s, cooldown {c['cool'] // HZ} s"
            + (f", stabilise {c['stab'] // HZ} s" if c["stab"] else ""))


def _grade(c):
    """FULL | PARTIAL | SHORT_BASELINE | NO_RUN"""
    if c["base"] >= FULL[0] and c["attack"] >= FULL["attack"] and c["cool"] >= FULL[3]:
        return "FULL"
    if c["base"] >= FULL[0] and c["attack"] > 0:
        return "PARTIAL"
    if c["base"] >= MIN_BASELINE_ROWS:
        return "SHORT_BASELINE"
    return "NO_RUN"


def _score(c):
    return c["base"] + c["attack"] + c["cool"]


def _boot(f):
    try:
        return int(f.get("boot") or -1)
    except (TypeError, ValueError):
        return -1


def _alternatives(files, chosen, want_atk, topology, location, since, allow_other):
    """Other telemetry pieces of this run on the card, newest boot first."""
    out = []
    for f in files:
        if f.get("kind") != "telem" or f.get("rel") == chosen.get("rel") or f.get("live"):
            continue
        if not (f.get("filed_under") == want_atk and f.get("topology") == topology):
            continue
        if f.get("location") != location and not allow_other:
            continue
        st = _when(f.get("started"))
        if since and st and st < since:
            continue
        if _size(f) < MIN_PIECE_B:
            continue
        out.append(f)
    return sorted(out, key=_boot, reverse=True)


def _import_one(src_args, f, a, outdir):
    """Copy ONE card file into outdir with import_sdcard.py; (path or None, stdout)."""
    imp = [_py(), os.path.join(HERE, "import_sdcard.py")] + src_args + [
        "--repeat", str(a.repeat), "--scenario", a.scenario, "--files", f["rel"], "--outdir", outdir]
    if f.get("clean") is not True:
        imp.append("--include-aborted")
    if f.get("location") != a.location:
        imp += ["--file-location", a.location]
    if a.roster:
        imp += ["--roster", a.roster]
    # oct. 19 2026: the card read's PROGRESS lines (export_logs.py, when the GUI set
    # NIS16_PROGRESS=1) go straight through to our stderr, live, so the GUI's bar
    # moves INSIDE a board; everything else is collected as before
    err = []
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as fo:
        p = subprocess.Popen(imp, stdout=fo, stderr=subprocess.PIPE, text=True, encoding="utf-8",
                             errors="replace", cwd=HERE)
        for line in p.stderr:
            if line.startswith("PROGRESS:"):
                sys.stderr.write(line)
                sys.stderr.flush()
            else:
                err.append(line)
        p.wait()
        fo.seek(0)
        out = fo.read()
    hits = glob.glob(os.path.join(outdir, "**", "*_telem.csv"), recursive=True) if p.returncode == 0 else []
    return (max(hits, key=os.path.getmtime) if hits else None), out + ("".join(err) if p.returncode else "")


def _fetch_crashes(kind, s, leaves, node, run_logs):
    """tools/fetch_crashes.py for one board: copy + decode crashes_<node>.csv (oct. 18 2026)."""
    a = [_py(), os.path.join(HERE, "fetch_crashes.py")] + (["--port", s] if kind == "port" else ["--card", s])
    for lf in leaves:
        a += ["--leaf", lf]
    a += ["--node", node, "--out", run_logs]
    p = subprocess.run(a, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=HERE)
    for line in p.stdout.splitlines():
        if line.strip():
            print("   " + line, flush=True)


def _file_node(path):
    """node_id of a telemetry file's first data row (12 hex, upper) or ''."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            head = fh.readline().strip().split(",")
            first = fh.readline().strip().split(",")
        i = head.index("node_id")
        return re.sub(r"[^0-9A-F]", "", first[i].upper())[-12:]
    except (OSError, ValueError, IndexError):
        return ""


_STAMP = re.compile(r"(?i)_(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)(\d{1,2})_(\d{2})(\d{2})(am|pm)")
_MON = {m: i for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}


def _root_export_time(roots):
    """When this run folder's root was exported (its arrivals file name stamp), or None.
    oct. 20 2026: a child's file that STARTED after that cannot belong to this run - the
    attacker sends no probes, so root_match cannot test it (verification #65: 1C38's
    highload file was filed into burst)."""
    best = None
    for r in roots or []:
        m = _STAMP.search(os.path.basename(r))
        if not m:
            continue
        h = int(m.group(3)) % 12 + (12 if m.group(5).lower() == "pm" else 0)
        y = dt.datetime.fromtimestamp(os.path.getmtime(r)).year
        try:
            t = dt.datetime(y, _MON[m.group(1).lower()[:3]], int(m.group(2)), h, int(m.group(4)))
        except ValueError:
            continue
        best = t if best is None or t > best else best
    return best


def _rows_in(path):
    with open(path, "rb") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def _already(dest_dir, mac, rows, size):
    """An export of THIS card file is already in the run folder: same board and
    the same rows - or, over USB where the card does not report rows, about the
    same size (the GUI Data page's rule). Same board alone is not enough: repeat
    r1 and r2 of a run share the folder."""
    for f in glob.glob(os.path.join(dest_dir, f"*{mac.upper()}*_telem.csv")):
        try:
            if rows is not None:
                if abs(_rows_in(f) - int(rows)) <= 2:
                    return os.path.basename(f)
            elif size and size > 0:
                if abs(os.path.getsize(f) - size) <= 0.03 * size:
                    return os.path.basename(f)
        except OSError:
            continue
    return None


def _size(f):
    """A piece's size for comparing pieces of one run: bytes, else rows x ~80 B."""
    b = f.get("bytes")
    if b is not None and int(b) >= 0:
        return int(b)
    return int(f.get("rows") or 0) * 80


def pick(files, attack, topology, location, since, skip_macs, allow_other_location=False, scenario=None):
    """(file, note) - this run's telemetry on one card - or (None, why).

    Safety net (oct. 18 2026): a card has NO scenario folder (only
    attack/topology/location), so a card holding two runs of the same attack +
    topology (a stationary and a burst one, two days at two sites) is ambiguous.
    Never guess: exactly ONE clean candidate in the window, or nothing. A file
    recorded under ANOTHER location is only taken with allow_other_location (a
    card whose location.txt was left on the last site) - else it is another run."""
    want_atk = "baseline" if attack in ("none", "baseline") else attack
    telem = [f for f in files if f.get("kind") == "telem"]
    if not telem:
        return None, "no telemetry file on this card"
    mac = str(telem[0].get("node", "")).replace("NODE_", "").lower()
    if mac in skip_macs:
        return None, "the root (exported over USB) - skipped"
    cand, other, elsewhere = [], [], []
    for f in telem:
        if f.get("live"):
            other.append("one file is STILL BEING WRITTEN (run not ended)")
            continue
        started = _when(f.get("started"))
        if since and started and started < since:
            continue
        if not (f.get("filed_under") == want_atk and f.get("topology") == topology):
            other.append(f"{f.get('filed_under')}/{f.get('topology')}/{f.get('location')} (another run)")
            continue
        if f.get("location") != location and not allow_other_location:
            elsewhere.append(f"{f.get('location')} ran {f.get('started') or '?'}")
            continue
        cand.append(f)
    # oct. 20 2026: a card of the oct. 20 firmware records each run's SCENARIO. When any
    # piece recorded THIS run's scenario, a piece with another or no scenario (older
    # firmware = an older run) is not this run - it was taken instead of the real one
    # when it was the bigger piece (ED80 / 2805, wormhole/star/G402/highload).
    if scenario and any(str(f.get("scenario") or "") == scenario for f in cand):
        cand = [f for f in cand if str(f.get("scenario") or "") == scenario]
    clean = [f for f in cand if f.get("clean") is not False]
    aborted = [f for f in cand if f.get("clean") is False]
    crash = [f for f in aborted if str(f.get("ended_by") or "").upper() not in ("", "POWERON")]
    if not clean and crash:
        # oct. 18 2026: no clean file, but the board CRASHED mid-run - its biggest
        # piece holds most of the run (baseline included); take it and say so
        best = max(crash, key=_size)
        return best, (f"the board CRASHED during the run ({best.get('ended_by')}) - took its biggest piece; "
                      f"its data stops at the crash ({len(cand)} piece(s) on the card)")
    if not clean and aborted:
        # oct. 18 2026 (B7:68, the victim that went OFFLINE mid-attack): a board
        # that was RESET during the run (power dip on its powerbank, brownout, a
        # crash older firmware could not name) never closes its file cleanly -
        # but the file holds the run up to the reset. Take the LATEST piece among
        # the big ones (>= half the biggest): an earlier, stopped attempt in the
        # same window is older, and a tiny post-reset tail is smaller. Too small
        # to be a run = still FAIL. run_summary.py then shows what it covers.
        biggest = max(aborted, key=_size)
        if _size(biggest) >= MIN_PIECE_B:
            big = [f for f in aborted if _size(f) >= 0.5 * _size(biggest)]
            best = max(big, key=lambda f: str(f.get("started") or ""))
            ended = str(best.get("ended_by") or "").upper() or "an unknown reset (power cut / unplugged)"
            note = (f"PARTIAL: the board was RESET during the run (ended by {ended}) - took its run piece "
                    f"({_size(best):,} B, ran {best.get('started') or '?'}; {len(aborted)} piece(s) on the card). "
                    f"Its data stops at the reset - check the run summary")
            if best.get("root_lost"):
                # oct. 20 2026 firmware: not a reset - it lost the root and closed the file itself
                note = (f"PARTIAL: the board LOST THE ROOT during the run and closed its file safely after the "
                        f"planned run - took it ({_size(best):,} B, ran {best.get('started') or '?'}). Rows after "
                        f"the loss carry the last phase it heard - check the run summary / root log")
            if best.get("location") != location:
                note += f"; card recorded {best.get('location')}, filed under {location}"
            return best, note
    if not clean:
        why = "no clean file of this run in the time window"
        if cand:
            why += f" ({len(cand)} aborted piece(s) - import those from the Data page, 'show aborted')"
        if elsewhere:
            why += (f" - this attack + topology was recorded at ANOTHER location ({'; '.join(elsewhere)}); "
                    f"tick 'cards may have recorded the wrong location' only if this run really was at {location}")
        elif other and not cand:
            why += " - found only: " + "; ".join(sorted(set(other)))
        return None, why
    if len(clean) > 1:
        when = "; ".join(f"{f.get('location')} ran {f.get('started') or '?'}" for f in sorted(clean, key=lambda f: str(f.get("started") or "")))
        return None, (f"{len(clean)} runs of this attack + topology in the time window ({when}) - the card cannot "
                      f"say which scenario each was. Narrow the time window, or pick the file in Data > Import")
    best = clean[0]
    # oct. 19 2026 (verification #60, FE90): a NEWER run on the card that left only
    # reset-ended pieces makes the one clean file look unique - but it is the older run.
    st_best = _when(best.get("started"))
    newer = [x for x in aborted if st_best and _when(x.get("started"))
             and _when(x.get("started")) > st_best + dt.timedelta(minutes=RUN_GAP_MIN)]
    if newer:
        last = max(newer, key=lambda x: str(x.get("started") or ""))
        return None, (f"the only complete file ran {best.get('started')}, but a NEWER run is on the card (ran "
                      f"{last.get('started')}, {len(newer)} piece(s), none complete) - the complete file is "
                      f"probably an EARLIER attempt. Narrow the time window to the newer run, or pick the file "
                      f"in Data > Import")
    # oct. 18 2026 (F4:18): a board that CRASHED mid-run and rebooted closes only its
    # post-crash TAIL cleanly (cooldown, no baseline); the run itself is in the bigger,
    # crash-ended piece. A clean file under half the size of a crash-ended piece of the
    # same run is that tail - take the big piece instead and say why.
    big = max(crash, key=_size) if crash else None
    if big is not None and _size(best) < 0.5 * _size(big):
        note = (f"the board CRASHED during the run ({big.get('ended_by')}) - took the crash-ended piece "
                f"({_size(big):,} B) over the clean post-crash tail ({_size(best):,} B); its data stops at the crash")
        if big.get("location") != location:
            note += f"; card recorded {big.get('location')}, filed under {location}"
        return big, note
    note = "" if best.get("location") == location else f"card recorded {best.get('location')}, filed under {location}"
    return best, note


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description="Collect one run's telemetry from every plugged-in child's SD card.")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--ports", help="COM10,COM11,... (cards still in the boards)")
    src.add_argument("--cards", help="card folders (pulled cards in readers) - also for testing")
    ap.add_argument("--attack", required=True)
    ap.add_argument("--topology", required=True)
    ap.add_argument("--location", required=True)
    ap.add_argument("--scenario", default="stationary")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--since", default=None, help="'YYYY-MM-DD HH:MM' - ignore files started before this")
    ap.add_argument("--allow-other-location", action="store_true",
                    help="also take a file the card recorded under another location (location.txt left on the last site)")
    ap.add_argument("--pick", default=None,
                    help="'COM10=<rel>;COM11=<rel>' - copy EXACTLY these files (what a scan showed and the user ticked)")
    ap.add_argument("--plan-json", default=None, help="write the per-board plan here (with --dry-run = a scan)")
    ap.add_argument("--roster", default=None)
    ap.add_argument("--skip-mac", default="", help="MACs to leave alone (the root), comma separated")
    ap.add_argument("--outdir", default=EXPORTS)
    ap.add_argument("--expect-mac", default="",
                    help="'COM10=aa:bb:..;COM11=...' - each board's REAL MAC (the GUI reads it from the port): "
                         "a card whose files belong to another board (SD card swapped) is refused, never filed")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    topology = TOPO_DIR.get(a.topology, a.topology)
    attack_dir = "baseline" if a.attack in ("none", "baseline") else a.attack
    since = dt.datetime.strptime(a.since, "%Y-%m-%d %H:%M") if a.since else None
    skip = {re.sub(r"[^0-9a-f]", "", m.lower()) for m in a.skip_mac.split(",") if m.strip()}
    expect = {}
    for part in (a.expect_mac or "").split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            expect[k.strip().upper()] = re.sub(r"[^0-9A-F]", "", v.upper())[-12:]
    picks = {}
    for part in (a.pick or "").split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            picks[k.strip().upper()] = v.strip()
    dest_dir = os.path.join(a.outdir, attack_dir, topology, a.location, a.scenario)
    _tee_log(os.path.join(BASE, "datasets", "run_logs", attack_dir, topology, a.location, a.scenario),
             "collect-scan" if a.dry_run else "collect")
    sources = ([("port", p.strip()) for p in a.ports.split(",") if p.strip()] if a.ports
               else [("card", c.strip()) for c in a.cards.split(";") if c.strip()])
    plan_rows = []
    retry = []                 # ports worth a "Retry failed" (not a data problem)
    ok = skipn = fail = 0
    for kind, s in sources:
        src_args = ["--port", s] if kind == "port" else ["--card", s]
        label = s if kind == "port" else os.path.basename(os.path.normpath(s)) or s
        print(f"\n-- {label}: reading the card ...", flush=True)
        row = {"port": label, "mac": "", "state": "", "why": "", "rel": "", "name": "", "started": "", "rows": None, "cell": ""}
        plan_rows.append(row)
        try:
            files = _list_retry(src_args, a.repeat, a.scenario, a.roster, label)
        except Exception as e:                       # one bad board never stops the rest
            kind_, text = _explain(e)
            _say(label, "", "FAIL", f"{kind_}: {text}")
            row.update(state="FAIL", why=f"{kind_}: {text}", kind=kind_, detail=str(e))
            fail += 1
            retry.append(label)
            continue
        mac = str((files[0] if files else {}).get("node", "")).replace("NODE_", "")
        row["mac"] = mac
        # oct. 20 2026: the card must belong to the board it sits in - else one board's data
        # would be filed under another board's identity (a swapped SD card)
        real = expect.get(label.upper())
        card = re.sub(r"[^0-9A-F]", "", mac.upper())[-12:]
        if real and card and real != card:
            why = (f"this card's files belong to board {card[-4:]}, but the board on {label} is {real[-4:]} - "
                   f"was the SD card swapped? Nothing filed (it would land under the wrong board)")
            _say(label, mac, "FAIL", why)
            row.update(state="FAIL", why=why, kind="IDENTITY")
            fail += 1
            continue
        if picks:
            want = picks.get(label.upper())
            if not want:
                _say(label, mac, "SKIP", "not ticked")
                row.update(state="SKIP", why="not ticked")
                skipn += 1
                continue
            f = next((x for x in files if str(x.get("rel", "")).replace(chr(92), "/").lower() == want.replace(chr(92), "/").lower()), None)
            note = "" if not f or f.get("location") == a.location else f"card recorded {f.get('location')}, filed under {a.location}"
            if f is None:
                _say(label, mac, "FAIL", f"the ticked file is no longer on the card: {want}")
                row.update(state="FAIL", why="the ticked file is no longer on the card")
                fail += 1
                continue
        else:
            f, note = pick(files, a.attack, topology, a.location, since, skip, a.allow_other_location, a.scenario)
        if f is not None:
            row.update(rel=f.get("rel", ""), name=f.get("name", ""), started=str(f.get("started") or ""), rows=f.get("rows"),
                       cell=f"{f.get('filed_under')}/{f.get('topology')}/{f.get('location')}/{f.get('scenario') or '? (older card)'}")
        if f is None:
            state = "SKIP" if ("root" in note or "no telemetry" in note) else "FAIL"
            _say(label, mac, state, note)
            row.update(state=state, why=note)
            skipn += state == "SKIP"
            fail += state == "FAIL"
            continue
        have = _already(dest_dir, mac, f.get("rows"), f.get("bytes"))
        if have:
            _say(label, mac, "SKIP", f"already in the run folder as {have}")
            row.update(state="SKIP", why=f"already imported as {have}")
            skipn += 1
            continue
        row.update(state="OK", why=note)
        if a.dry_run and a.plan_json:           # a scan: nothing is copied, no second card read
            _say(label, mac, "OK", f"would copy {f.get('name')} ({f.get('rows') or '?'} rows, ran {f.get('started')})" + (f" - {note}" if note else ""))
            ok += 1
            continue
        if a.dry_run:                            # a CLI dry run: say what would be copied
            _say(label, mac, "OK", f"would copy {f.get('name')} ({f.get('rows') or '?'} rows, ran {f.get('started')})"
                 + (f" - {note}" if note else ""))
            ok += 1
            continue
        # copy into a temp folder, look INSIDE, keep only a piece that holds the run
        want_atk = "baseline" if a.attack in ("none", "baseline") else a.attack
        tmp = tempfile.mkdtemp(prefix="collect_")
        tried, best = [], None
        try:
            alts = _alternatives(files, f, want_atk, topology, a.location, since, a.allow_other_location)
            # newest boot first; the picked file leads only when nothing newer is on the card
            order = sorted([f] + alts, key=_boot, reverse=True)
            starts = [_when(x.get("started")) for x in order if _when(x.get("started"))]
            newest = max(starts) if starts else None
            older = [x for x in order if newest and _when(x.get("started"))
                     and _when(x.get("started")) < newest - dt.timedelta(minutes=RUN_GAP_MIN)]
            for x in older:
                tried.append(f"{x.get('name')} (ran {x.get('started')}): NOT tried - an earlier run than the "
                             f"newest one on this card (ran {newest:%H:%M})")
            order = [x for x in order if x not in older]
            # the root of this run already exported? then every piece must match it
            roots = root_match.find_arrivals(dest_dir) if root_match else []
            root_at = _root_export_time(roots)
            mismatch = None                  # a piece that holds a baseline but does NOT match the root
            for cand in order[:MAX_TRIES]:
                sub = os.path.join(tmp, str(len(tried)))
                path, out = _import_one(src_args, cand, a, sub)
                if not path:
                    tried.append(f"{cand.get('name')}: copy failed ({(out.strip().splitlines() or ['?'])[-1][:80]})")
                    continue
                rec = cand.get("scenario")
                if rec and rec != a.scenario:
                    tried.append(f"{cand.get('name')}: the card recorded scenario {rec}, not {a.scenario} - another run")
                    print(f"   {cand.get('name')}: recorded as {rec}, not {a.scenario} - refused", flush=True)
                    continue
                node = _file_node(path)
                if node and card and node != card:
                    tried.append(f"{cand.get('name')}: holds board {node[-4:]}'s data, not {card[-4:]}'s - refused")
                    print(f"   {cand.get('name')}: its rows belong to board {node[-4:]} - refused", flush=True)
                    continue
                st_ = _when(cand.get("started"))
                if root_at and st_ and st_ > root_at + dt.timedelta(minutes=2):
                    tried.append(f"{cand.get('name')} (ran {cand.get('started')}): started AFTER this run's root was "
                                 f"exported ({root_at:%H:%M}) - a later run, not this one")
                    print(f"   {cand.get('name')}: started {st_:%H:%M}, after the root of this run was exported "
                          f"({root_at:%H:%M}) - a LATER run, refused", flush=True)
                    mismatch = mismatch or (cand, None, path, "LATER", {"pct": 1.0})
                    continue
                c = _coverage(path)
                g = _grade(c)
                tried.append(f"{cand.get('name')} ({'clean' if cand.get('clean') else 'ended by ' + str(cand.get('ended_by') or 'a reset')}): {_cov_text(c)} -> {g}")
                print(f"   checked {cand.get('name')}: {_cov_text(c)} -> {g}", flush=True)
                if g != "NO_RUN" and roots:
                    rm = root_match.check(path, dest_dir)
                    if rm["verdict"] == "MISMATCH":
                        tried[-1] += f" - does NOT match the root ({100 * rm['pct']:.1f} % of probes in another phase)"
                        print(f"   {cand.get('name')} does NOT match the root's run: {rm['why']}", flush=True)
                        mismatch = mismatch or (cand, c, path, g, rm)
                        continue
                if g != "NO_RUN":
                    best = (cand, c, path, g)        # the newest session that holds a baseline
                    break
                if best is None:
                    best = (cand, c, path, g)
            if (best is None or best[3] == "NO_RUN") and mismatch:
                # nothing that matches the root: never file it silently - report it, file nothing
                why = ("the only piece(s) with a baseline do NOT match the root's run - nothing filed (another "
                       "run, or the board's phase labels were out of sync). Pieces checked: " + "; ".join(tried)
                       + ". If you are sure, pick the file in Data > Import and footnote it")
                _say(label, mac, "FAIL", why)
                row.update(state="FAIL", why=why)
                fail += 1
                continue
            if best is None or best[3] == "NO_RUN":
                why = "no piece on the card holds this run's baseline - nothing filed. Pieces checked: " + "; ".join(tried)
                _say(label, mac, "FAIL", why)
                row.update(state="FAIL", why=why)
                fail += 1
                continue
            cand, c, path, g = best
            os.makedirs(dest_dir, exist_ok=True)
            dest = os.path.join(dest_dir, os.path.basename(path))
            if os.path.exists(dest):
                dest = dest[:-len("_telem.csv")] + f"_{dt.datetime.now():%H%M%S}_telem.csv"
            shutil.move(path, dest)
            if not os.path.isfile(dest) or _rows_in(dest) <= 0:
                why = f"the copy did not verify ({os.path.basename(dest)} missing or empty after filing)"
                _say(label, mac, "FAIL", why)
                row.update(state="FAIL", why=why)
                fail += 1
                continue
            print(f"COLLECT_FILE: {os.path.abspath(dest)}|{_rows_in(dest)}", flush=True)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        verdict = {"FULL": "", "PARTIAL": "PARTIAL - ", "SHORT_BASELINE": "SHORT BASELINE - "}[g]
        if cand is not f:
            note = (f"took the NEWEST piece that holds a baseline ({cand.get('name')}, boot {_boot(cand)}), "
                    f"not {f.get('name')}" + (f"; {note}" if note else ""))
        text = (f"{verdict}{cand.get('name')} -> {os.path.basename(dest)}: {_cov_text(c)}" + (f" - {note}" if note else ""))
        _say(label, mac, "OK", text)
        row.update(state="OK", why=text, rel=cand.get("rel", ""), name=cand.get("name", ""))
        ok += 1
        # the board crashed in this run: its card also holds WHERE (crash_record.c,
        # firmware since oct. 18 2026) - fetch + decode it next to the run's logs
        crashed = _crashed_leaves(files, attack_dir, topology, since)
        if crashed and not a.dry_run:
            node = str(f.get("node") or "")
            _fetch_crashes(kind, s, crashed, node,
                           os.path.join(BASE, "datasets", "run_logs", attack_dir, topology, a.location, a.scenario, "crashes"))
    print(f"\nCOLLECT_SUMMARY: ok={ok} skip={skipn} fail={fail}", flush=True)
    if retry:
        print(f"COLLECT_RETRY: {','.join(retry)}", flush=True)
    if a.plan_json:
        with open(a.plan_json, "w", encoding="utf-8") as fh:
            json.dump(plan_rows, fh, indent=1, default=str)
    if not a.dry_run and os.path.isdir(dest_dir):
        print("", flush=True)
        subprocess.run([_py(), os.path.join(HERE, "run_summary.py"), dest_dir], cwd=HERE)
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main())
