"""Real 802.11 MAC retry rate, per mesh link and per phase, from a sniffer capture.

WHY: the boards cannot report MAC retransmissions. ESP-IDF 5.3.5 and 5.5 only
offer esp_wifi_statis_dump(), which prints to the log and returns nothing, so
the CSV's retry_count is an application counter (D-15). But every 802.11 frame
that is a retransmission carries the Retry bit (frame control, flags & 0x08),
and the sniffer keeps the whole header. RetryRate here = frames with the Retry
bit / all unicast data frames the sniffer heard, per transmitter -> receiver.

PHASES come from the ROOT's run log (datasets/run_logs/...): the root's uptime
at each "Starting PHASE n" gives exact phase lengths. Placing them on the
laptop clock needs one anchor, and the root's own "@ HH:MM:SS PHT" banner is
NOT exact: the board restores its clock from the SD card at boot, so it runs
behind by however long flashing took (38.5 s on the sep. 27 18:35 run). So:
  - blackhole: the attack start is FITTED from the capture itself - the
    attacker's uplink frame rate drops for exactly the attack's length. The
    search starts no earlier than the transcript's "Start time:" plus the
    root's uptime at the attack (the root boots after the transcript starts).
  - otherwise: --attack-start HH:MM:SS (real laptop time), or --trust-stamp to
    accept the banner knowing it lags. No anchor -> the tool refuses.

Frames the sniffer never heard are unknowable; a link it hears poorly gives
few frames - read the frame counts, not only the %.

Usage:
  python tools/pcap_retry.py <capture.pcap> --run-log <root .log>
         [--attack-start HH:MM:SS] [--trust-stamp] [--no-csv]
  python tools/pcap_retry.py --all      # every capture under datasets/, paired
                                        # with its root log; what features.py runs
Writes <capture>_retry.csv (1-second windows; t_rel_attack_s has the same zero
as the analysis' t_anchor_s) and <capture>_retry.json (run identity, phase
times, capture span, pauses - or why the capture was refused).
"""
import argparse
import collections
import csv
import datetime as dt
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_pcap as cp  # noqa: E402
import name_stamp  # noqa: E402

DATASETS = os.path.normpath(os.path.join(HERE, "..", "datasets"))
PHT = dt.timezone(dt.timedelta(hours=8))
PHASE_NAMES = {0: "baseline", 1: "attack", 2: "attack", 3: "cooldown", 4: "terminate"}
FIT_EDGE_S = 30            # seconds either side of the attack used as "normal" rate
FIT_MAX_INSIDE_RATIO = 0.5  # attacker uplink must fall to <= half of normal
FIT_MIN_OUTSIDE_RATE = 0.5  # frames/s; below this there is nothing to fit on
# Transcript start -> root boot takes erase + build + flash; this caps the fit's search.
MAX_BOOT_DELAY_S = 600
# --all: a capture belongs to the root log whose transcript started closest to it.
PAIR_WINDOW_S = 20 * 60
# How long after a run starts its CSVs can still be pulled off the boards (SD cards
# and late children straggle - the sept 28 00:13 run's last child landed ~1 h later).
EXPORT_WINDOW_S = 12 * 3600

RE_START = re.compile(r"I \((\d+)\) ROOT_MAIN: \[CTRL\] Starting PHASE (\d)")
RE_TERM = re.compile(r"I \((\d+)\) ROOT_MAIN: .*PHASE 4\b")
RE_STAMP = re.compile(r"I \((\d+)\) ROOT_MAIN: .*PHASE (\d)\b.*@ (\d\d):(\d\d):(\d\d) PHT")
RE_NODE = re.compile(r"MESH_SETUP:\s+H\d\d\s+([0-9A-F]{2}(?::[0-9A-F]{2}){5})\s+([A-Z_]+)")
RE_CLOCK_OK = re.compile(r"board clock: .*\(real clock, from this laptop\)")
RE_TRANSCRIPT = re.compile(r"^Start time: (\d{14})", re.M)
RE_ROOT_CMD = re.compile(r"run\.ps1 [^\n]*-Role root[^\n]*")
RE_ANY_CMD = re.compile(r"run\.ps1 [^\n]*-Topology[^\n]*")
NOMINAL_RUN_S = 60 + 300 + 180 + 120  # a run can't end sooner than this after its log starts
IDENTITY_KEYS = ("attack", "topology", "location", "scenario")
# report() verdicts: a link is "worse/better" only past this many points of change,
# and only judged when both baseline and attack heard at least this many frames.
VERDICT_PTS = 5
MIN_JUDGE_FRAMES = 100

# report()'s console colours - the SAME hex palette as run_wizard.ps1's $script:RoleAnsi /
# Colorize-Role, so a board reads the same colour here as it does in the wizard's preset
# and board listings: root = gold, attacker (blackhole/wormhole) = pink, child = teal.
# UNKNOWN/OUTSIDE boards (heard on air but missing from the roster) are left plain - the
# wizard's own palette has no colour for "not sure what this is" either.
ROLE_COLOR = {"ROOT": "38;2;254;189;23", "CHILD": "38;2;27;192;186",
              "ATTACKER": "38;2;253;184;217"}  # #FEBD17 / #1BC0BA / #FDB8D9
_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def _enable_ansi():
    """True when stdout is a console that will render ANSI colours (turns on
    virtual-terminal processing on Windows; plain redirected output gets none).
    Same approach as tools/sniff.py's _enable_ansi()."""
    if not sys.stdout.isatty():
        return False
    if os.name == "nt":
        try:
            import ctypes
            k = ctypes.windll.kernel32
            h = k.GetStdHandle(-11)
            mode = ctypes.c_uint32()
            if not k.GetConsoleMode(h, ctypes.byref(mode)):
                return False
            return bool(k.SetConsoleMode(h, mode.value | 0x0004))
        except Exception:
            return False
    return True


ANSI = _enable_ansi()


def _role_code(role_name):
    """ANSI colour code for a report role string (ROOT/CHILD/BLACKHOLE/WORMHOLE_*/
    UNKNOWN/OUTSIDE), or None to leave it uncoloured."""
    if role_name in ROLE_COLOR:
        return ROLE_COLOR[role_name]
    if role_name.startswith("BLACKHOLE") or role_name.startswith("WORMHOLE"):
        return ROLE_COLOR["ATTACKER"]
    return None


def paint(text, code):
    """Wrap text in an ANSI colour code, or return it untouched off a console
    (or when there is no colour for this role)."""
    return "\x1b[%sm%s\x1b[0m" % (code, text) if ANSI and code else text


def vlen(s):
    """Length of s as it will actually appear on screen - ANSI escape bytes are
    invisible, so plain len() overcounts a coloured string."""
    return len(_ANSI_RE.sub("", s))


def ljust_visible(s, width):
    """s padded to width by VISIBLE length. str.ljust()/'%-*s' would count a
    colour-wrapped string's escape bytes as printable characters and under-pad it,
    misaligning every column after it."""
    return s + " " * max(0, width - vlen(s))


class Refuse(Exception):
    pass


def _cell_of(path, marker):
    """The <attack>/<topology>/<location>/<scenario> folders under `marker`, or ()."""
    parts = os.path.normpath(os.path.abspath(path)).split(os.sep)
    if marker not in parts:
        return ()
    return tuple(parts[parts.index(marker) + 1:-1])


def pcap_identity(pcap):
    """What the capture's OWN path and name say about its run, for pairing.
    Cell-filed captures live in PCAP/<atk>/<topo>/<loc>/<scen>/ and carry _r<N>_;
    a standalone/ capture says nothing, and is paired on time alone."""
    cell = _cell_of(pcap, "PCAP")
    if cell[:1] == ("standalone",):  # PCAP/standalone/ = filed under no run; time-only pairing
        cell = ()
    ident = dict(zip(IDENTITY_KEYS, cell))
    m = re.search(r"_r(\d+)_", os.path.basename(pcap))
    if m:
        ident["repeat"] = int(m.group(1))
    return ident


def _identity(path, text):
    """attack/topology/location/scenario from the run_logs folder (the analysis'
    own folder names), repeat from the root's run.ps1 command line."""
    ident = {}
    cell = _cell_of(path, "run_logs")
    if cell:
        ident["_cell"] = cell
        ident.update(zip(IDENTITY_KEYS, cell))
    cmd = RE_ROOT_CMD.search(text) or RE_ANY_CMD.search(text)
    if cmd:
        for key, flag in (("attack", "Attack"), ("topology", "Topology"),
                          ("location", "Location"), ("scenario", "Scenario"), ("repeat", "Repeat")):
            m = re.search(r"-%s (\S+)" % flag, cmd.group(0))
            if m:
                ident.setdefault(key, m.group(1))
    if "repeat" in ident:
        ident["repeat"] = int(ident["repeat"])
    return ident


def parse_root_log(path):
    with open(path, encoding="utf-8-sig", errors="replace") as f:
        text = f.read()
    starts = collections.defaultdict(list)
    for m in RE_START.finditer(text):
        starts[int(m.group(2))].append(int(m.group(1)))
    for m in RE_TERM.finditer(text):
        if int(m.group(1)) not in starts[4]:
            starts[4].append(int(m.group(1)))
    twice = [p for p, v in starts.items() if len(set(v)) > 1]
    if twice:
        raise Refuse("phase(s) %s started more than once - the root rebooted or two runs share "
                     "this log. Split the log to the one run the capture covers." % twice)
    # No phase lines at all: the console log lost the middle of the run (it happens -
    # the monitor can miss a stretch). Not fatal, the run's own exported CSVs hold the
    # same timings; analyze() falls back to phases_and_roles_from_exports().
    phases = {p: v[0] for p, v in starts.items()} if 0 in starts else None
    order = sorted(phases, key=phases.get) if phases else []
    if order != sorted(order):
        raise Refuse("phases out of order in the root log: %s" % order)
    stamp = None
    for m in RE_STAMP.finditer(text):
        stamp = (int(m.group(1)), int(m.group(3)), int(m.group(4)), int(m.group(5)))
        break
    roles = {}
    for m in RE_NODE.finditer(text):
        roles[m.group(1).lower()] = m.group(2)
    m = RE_TRANSCRIPT.search(text)
    started = (dt.datetime.strptime(m.group(1), "%Y%m%d%H%M%S").replace(tzinfo=PHT).timestamp()
               if m else None)
    return {"phases": phases, "stamp": stamp, "clock_ok": bool(RE_CLOCK_OK.search(text)),
            "roles": roles, "started": started, "identity": _identity(path, text)}


def _role_label(role):
    """CSV role -> the uppercase form the log's MESH_SETUP table uses."""
    role = str(role).strip().lower()
    return "CHILD" if role == "victim" else role.upper()


def export_cell_dirs(cell):
    """Where a cell's raw exports can be: the live folder, and any archive's copy (an
    archived run's exports are the only copy left). Never trimmed/ - that is a
    derived copy the analysis rebuilds, not the run's record."""
    return [d for d in [os.path.join(DATASETS, "exports", *cell)]
            + sorted(glob.glob(os.path.join(DATASETS, "archive", "*", "exports", *cell)))
            if os.path.isdir(d)]


def phases_and_roles_from_exports(log, run_log_path, sibling_logs=None, say=print):
    """Phase start uptimes (ms) + every node's role, read from the run's own
    EXPORTED CSVs instead of the console log's text.

    WHY: the console log can lose a stretch of the root's output (the sept 28
    00:13 run jumps from the flash straight to a snapshot 12 min in), and with it
    the 'Starting PHASE' lines. The root's telemetry CSV carries the same event
    in DATA - phase_id changes on its own 10 Hz row - so the timings survive. On
    the sep 27 18:35 run, where both exist, the two sources agree on the gaps
    between phases to within 40 ms (a constant ~600 ms offset that cancels, since
    the attack start is fitted from traffic and only the gaps are used).

    The exports are also the only place the ROLES are certain: that same sept 28
    log's topology table lists 3 of the 6 boards and no BLACKHOLE at all, which
    would leave the traffic fit with no attacker to look for. Every *_telem.csv
    states its own role.

    Refuses rather than guess: no cell folder, no/extra root export, a root that
    rebooted (uptime goes backwards), or a phase that starts twice.

    The export must be stamped after THIS run started and before the NEXT run of the
    same cell and repeat did. Without that upper bound the sep 26 23:39 capture read
    the 02:05 run's export - four runs here share blackhole/linear/home/stationary r1,
    and it only looked right because every run used the same 300/180/120 s phases.
    """
    cell = log["identity"].get("_cell")
    if not cell:
        raise Refuse("no 'Starting PHASE' lines in the run log, and it is not under "
                     "datasets/run_logs/<attack>/<topology>/<location>/<scenario>, so its "
                     "exported CSVs cannot be located. Pass --attack-start HH:MM:SS.")
    cell_dirs = export_cell_dirs(cell)
    if not cell_dirs:
        raise Refuse("no 'Starting PHASE' lines in the run log and no exports folder for this cell "
                     "(looked in exports/%s and archive/*/exports/%s)"
                     % ("/".join(cell), "/".join(cell)))
    if log["started"] is None:
        raise Refuse("no 'Starting PHASE' lines in the run log and no 'Start time:' transcript "
                     "header either, so its exports cannot be told from another run's. "
                     "Pass --attack-start HH:MM:SS.")
    rep = log["identity"].get("repeat")
    if sibling_logs is None:
        sibling_logs = _root_logs(DATASETS)
    here = os.path.normcase(os.path.abspath(run_log_path))
    next_run = min((p["started"] for path, p in sibling_logs.items()
                    if p["started"] is not None and p["started"] > log["started"]
                    and os.path.normcase(os.path.abspath(path)) != here
                    and same_identity(log["identity"], p.get("identity", {}))),
                   default=None)
    hi = log["started"] + EXPORT_WINDOW_S
    if next_run is not None:
        hi = min(hi, next_run)
    pattern = "*_r%s_*_telem.csv" % rep if rep is not None else "*_telem.csv"
    files = []
    for path in sorted(p for d in cell_dirs for p in glob.glob(os.path.join(d, pattern))):
        stamp = name_stamp.find(os.path.basename(path))
        if not stamp:
            continue
        exported = name_stamp.parse(stamp, path)[0].replace(tzinfo=PHT).timestamp()
        # A run's CSVs are pulled off the boards after it ends and before the next run of
        # the same cell + repeat starts; anything else belongs to a different run.
        if log["started"] <= exported <= hi:
            files.append(path)
    roots = [p for p in files if os.path.basename(p).startswith("root")]
    if not roots:
        raise Refuse("no 'Starting PHASE' lines in the run log, and no root *_telem.csv for r%s "
                     "exported between %s and %s (this run and the next of the same cell) in %s - "
                     "this run's own export is missing, so its phase times are unavailable."
                     % (rep, hms(log["started"]), hms(hi),
                        ", ".join(_stored_path(d) for d in cell_dirs)))
    if len(roots) > 1:
        raise Refuse("no 'Starting PHASE' lines in the run log, and %d root exports match r%s "
                     "(%s) - cannot tell which run the capture belongs to. Pass --attack-start."
                     % (len(roots), rep, ", ".join(os.path.basename(p) for p in roots)))

    rows = []
    with open(roots[0], newline="", encoding="utf-8-sig", errors="replace") as f:
        for r in csv.DictReader(f):
            try:
                rows.append((int(r["timestamp_us"]), int(r["phase_id"])))
            except (KeyError, TypeError, ValueError):
                continue
    if not rows:
        raise Refuse("the root export %s has no readable timestamp_us/phase_id rows."
                     % os.path.basename(roots[0]))
    if any(b[0] < a[0] for a, b in zip(rows, rows[1:])):
        raise Refuse("the root export %s runs backwards in time - the board rebooted mid-run, so "
                     "one phase timeline cannot be read from it. Pass --attack-start."
                     % os.path.basename(roots[0]))
    phases, blocks = {}, []
    for us, pid in rows:
        if not blocks or blocks[-1] != pid:
            blocks.append(pid)
            phases.setdefault(pid, round(us / 1000))
    repeated = [p for p in set(blocks) if blocks.count(p) > 1]
    if repeated:
        raise Refuse("phase(s) %s appear more than once in the root export %s (a reboot, or two "
                     "runs in one file) - cannot read one timeline. Pass --attack-start."
                     % (sorted(repeated), os.path.basename(roots[0])))
    phases.pop(255, None)  # stabilisation, not one of the run's phases

    roles = {}
    for path in files:
        with open(path, newline="", encoding="utf-8-sig", errors="replace") as f:
            row = next(csv.DictReader(f), None)
        mac = row and re.sub(r"[^0-9A-Fa-f]", "", str(row.get("node_id", "")).replace("NODE", ""))
        if row and mac and len(mac) == 12:
            roles[":".join(mac[i:i + 2] for i in range(0, 12, 2)).lower()] = _role_label(row["role"])
    say("Phases + roles read from the run's EXPORTED CSVs (the run log lost its 'Starting PHASE'"
        " lines): %s, %d board(s)" % (os.path.basename(roots[0]), len(roles)))
    return phases, roles, files


def wall_on_day(first_ts, h, mi, s):
    """HH:MM:SS PHT on whichever day puts it closest to the capture."""
    day = dt.datetime.fromtimestamp(first_ts, PHT).date()
    cands = [dt.datetime.combine(day + dt.timedelta(days=d), dt.time(h, mi, s), PHT).timestamp()
             for d in (-1, 0, 1)]
    return min(cands, key=lambda t: abs(t - first_ts))


def hms(t):
    return dt.datetime.fromtimestamp(t, PHT).strftime("%H:%M:%S")


def read_capture(path):
    with open(path, "rb") as f:
        data = f.read()
    pkts, _, _ = (cp.read_pcapng if data[:4] == b"\x0a\x0d\x0d\x0a" else cp.read_pcap)(data)
    return [p for p in pkts if p[0] is not None]


def data_frames(pkts, mesh_macs):
    """(ts, TA, RA, retry) for every unicast data frame a mesh node transmitted."""
    out = []
    for ts, lt, pkt in pkts:
        fr = cp.strip_link_header(lt, pkt)
        if fr is None or len(fr) < 16 or (fr[0] >> 2) & 3 != 2 or fr[4] & 1:
            continue
        ta = cp.mac(fr[10:16])
        if ta in mesh_macs:
            out.append((ts, ta, cp.mac(fr[4:10]), bool(fr[1] & 0x08)))
    return out


def fit_attack_start(frames, attacker_sta, attack_len, lo, hi):
    """Start second of the attack_len window where the attacker's uplink rate is lowest
    against the FIT_EDGE_S either side. First transmissions only (retries are noise).
    Returns (start, inside_rate, outside_rate) or None."""
    per_s = collections.Counter(int(ts) for ts, ta, _, retry in frames if ta == attacker_sta and not retry)
    if not per_s:
        return None
    t0, t1 = min(per_s), max(per_s)
    L, E = int(round(attack_len)), FIT_EDGE_S
    best = None
    for s in range(max(int(lo), t0 + E), min(int(hi), t1 - L - E) + 1):
        inside = sum(per_s.get(t, 0) for t in range(s, s + L)) / L
        outside = (sum(per_s.get(t, 0) for t in range(s - E, s))
                   + sum(per_s.get(t, 0) for t in range(s + L, s + L + E))) / (2 * E)
        if best is None or outside - inside > best[2] - best[1]:
            best = (s, inside, outside)
    if best is None or best[2] < FIT_MIN_OUTSIDE_RATE or best[1] > FIT_MAX_INSIDE_RATIO * best[2]:
        return None
    return best


def analyze(pcap, run_log, attack_start_hms=None, trust_stamp=False, pkts=None,
            sibling_logs=None, say=print):
    """Everything about one capture + its root log. Raises Refuse."""
    for p in (pcap, run_log):
        if not os.path.isfile(p):
            raise Refuse("file not found: %s" % p)
    pkts = pkts if pkts is not None else read_capture(pcap)
    if not pkts:
        raise Refuse("no timestamped packets in %s" % pcap)
    log = parse_root_log(run_log)
    ph, export_roles, export_files = log["phases"], {}, []
    phase_source = "root run log"
    if ph is None:
        ph, export_roles, export_files = phases_and_roles_from_exports(log, run_log, sibling_logs, say=say)
        phase_source = "the run's exported CSVs (run log lost its phase lines)"
    attack_id = 1 if 1 in ph else (2 if 2 in ph else None)
    if attack_id is None or 3 not in ph:
        raise Refuse("no attack phase (1/2) and cooldown (3) in %s - incomplete run." % phase_source)

    roster = dict(log["roles"])
    roster.update(export_roles)  # the exports state each board's own role; the log may not list it
    softap = {cp.mac_plus_one(m): m for m in roster}
    for b in cp.find_mesh(pkts)["bssids"]:
        roster.setdefault(cp.mac_minus_one(b), "?")
        softap.setdefault(b, cp.mac_minus_one(b))
    frames = data_frames(pkts, set(roster) | set(softap))
    first_ts, last_ts = pkts[0][0], pkts[-1][0]
    rel = {p: (u - ph[attack_id]) / 1000.0 for p, u in ph.items()}  # seconds from attack start
    attack_len = rel[3]

    stamp_attack = None
    if log["stamp"] and log["clock_ok"]:
        u, h, mi, s = log["stamp"]
        stamp_attack = wall_on_day(first_ts, h, mi, s) + (ph[attack_id] - u) / 1000.0

    if attack_start_hms:
        h, mi, s = (int(x) for x in attack_start_hms.split(":"))
        attack_start, how = wall_on_day(first_ts, h, mi, s), "given on the command line"
    else:
        attackers = [m for m, r in roster.items() if r == "BLACKHOLE"]
        # The root boots after the wizard's transcript starts, and a SET_TIME clock only
        # ever runs BEHIND real time, so both give a hard earliest attack start.
        floors = [t for t in (stamp_attack,
                              log["started"] + ph[attack_id] / 1000.0 if log["started"] else None)
                  if t is not None]
        fit = None
        if attack_id == 1 and len(attackers) == 1 and floors:
            lo = max(floors)
            say("Fit search: attack start between %s and %s" % (hms(lo), hms(lo + MAX_BOOT_DELAY_S)))
            fit = fit_attack_start(frames, attackers[0], attack_len, lo, lo + MAX_BOOT_DELAY_S)
        if fit:
            attack_start = float(fit[0])
            how = ("fitted: BLACKHOLE %s uplink %.1f -> %.1f frames/s for %d s"
                   % (attackers[0], fit[2], fit[1], round(attack_len)))
        elif stamp_attack and trust_stamp:
            attack_start = stamp_attack
            how = "root banner time (--trust-stamp; runs behind by the flash time, ~40 s)"
        else:
            raise Refuse("cannot place the phases on the laptop clock. %s Pass --attack-start "
                         "HH:MM:SS%s." % (
                             "No blackhole attack step found in the capture." if attack_id == 1
                             else "Only blackhole runs can be fitted from traffic.",
                             " or --trust-stamp" if stamp_attack else
                             " (the root banner time is missing or its clock was never set by SET_TIME)"))

    bounds = {PHASE_NAMES[p]: attack_start + rel[p] for p in ph}
    end = bounds.get("terminate", attack_start + attack_len + 120)
    segs = [("baseline", bounds["baseline"], bounds["attack"]),
            ("attack", bounds["attack"], bounds["cooldown"]),
            ("cooldown", bounds["cooldown"], end)]
    pauses = []
    side = os.path.splitext(pcap)[0] + ".json"
    if os.path.isfile(side):
        with open(side, encoding="utf-8") as f:
            for p in json.load(f).get("pauses", []):
                a = dt.datetime.fromisoformat(p["started"]).timestamp()
                pauses.append((a, a + float(p.get("seconds", 0))))
    return {"pcap": pcap, "run_log": run_log, "identity": log["identity"], "roster": roster,
            "softap": softap, "frames": frames, "first_ts": first_ts, "last_ts": last_ts,
            "attack_start": attack_start, "how": how, "stamp_attack": stamp_attack,
            "segs": segs, "run_end": end, "pauses": pauses, "phase_source": phase_source,
            "export_files": export_files, "export_cell": list(log["identity"].get("_cell", ()))}


def seg_of(res, ts):
    for name, a, z in res["segs"]:
        if a <= ts < z:
            return name
    return "pre" if ts < res["segs"][0][1] else "post"


def report(res):
    roster, softap = res["roster"], res["softap"]
    node_of = lambda m: softap.get(m, m)  # noqa: E731
    first_ts, last_ts = res["first_ts"], res["last_ts"]
    print("Capture: %s   %s-%s" % (os.path.basename(res["pcap"]), hms(first_ts), hms(last_ts)))
    print("Phase times from: %s" % res["phase_source"])
    print("Attack start: %s  (%s)" % (hms(res["attack_start"]), res["how"]))
    if res["stamp_attack"] is not None and not res["how"].startswith("given"):
        print("  root banner said %s -> root clock off by %+.1f s"
              % (hms(res["stamp_attack"]), res["attack_start"] - res["stamp_attack"]))
    for name, a, z in res["segs"]:
        cover = max(0.0, min(z, last_ts) - max(a, first_ts))
        note = "" if cover >= (z - a) - 1 else "   <- capture covers only %d s" % cover
        print("  %-8s %s-%s (%d s)%s" % (name, hms(a), hms(z), round(z - a), note))
    for a, z in res["pauses"]:
        print("  sniffer PAUSED %s for %.1f s - frames in that gap are missing" % (hms(a), z - a))

    tally = collections.defaultdict(lambda: [0, 0])
    for ts, ta, ra, retry in res["frames"]:
        seg = seg_of(res, ts)
        for key in ((seg, ta, ra), (seg, "*", "*")):
            tally[key][0] += 1
            tally[key][1] += retry
    names = [s[0] for s in res["segs"]]
    links = {(ta, ra) for (s, ta, ra) in tally if ta != "*"}
    volume = lambda k: sum(tally[(n,) + k][0] for n in names)  # noqa: E731

    # Each board's parent = where most of its uplink frames went; hop = steps to the root.
    # Only a label for reading the table - a board that re-parented still shows both links.
    parent_votes = collections.defaultdict(collections.Counter)
    for ta, ra in links:
        if ta in roster:
            parent_votes[ta][node_of(ra)] += volume((ta, ra))
    parent = {n: v.most_common(1)[0][0] for n, v in parent_votes.items()}

    def hop(n):
        steps = 0
        while roster.get(n) != "ROOT":
            n = parent.get(n)
            steps += 1
            if n is None or steps > len(roster):
                return None
        return steps

    role = lambda n: {"?": "UNKNOWN"}.get(roster.get(n, "OUTSIDE"), roster.get(n, "OUTSIDE"))  # noqa: E731
    who = lambda n: paint("%-9s %s" % (role(n), n), _role_code(role(n)))  # noqa: E731
    heard = {node_of(m) for link in links for m in link}

    print("\nWHAT THIS MEASURES")
    print("  A board that sends a frame and gets no ACK back sends it AGAIN with the Retry flag set.")
    print("  Retry rate = resent frames / all frames the sniffer heard on that link. Higher = the link")
    print("  is struggling (interference, weak signal, a receiver not answering).")

    print("\nBOARDS IN THIS RUN  (MAC = the board's station address, the node_id in its CSVs)")
    print("  %-4s %-9s %-17s  %s" % ("hop", "role", "MAC", "parent"))
    for n in sorted(roster, key=lambda n: (hop(n) is None, hop(n) or 0, n)):
        h = hop(n)
        note = ""
        if roster[n] == "BLACKHOLE":
            note = "   <- the attacker"
        elif roster[n] == "?":
            note = "   <- heard on air, but missing from the run log and exports"
        if n not in heard:
            note += "   (no frames heard from it)"
        role_field = paint("%-9s" % role(n), _role_code(role(n)))
        mac_field = paint(n, _role_code(role(n)))
        print("  %-4s %s %s  %s%s" % ("?" if h is None else h, role_field, mac_field,
                                     "-" if roster[n] == "ROOT" else parent.get(n, "?"), note))
    print("  (On air a board also transmits as MAC+1 - its access point for its own children.")
    print("   Those frames are counted under the board's own MAC above.)")

    def link_key(k):
        child = node_of(k[0] if k[0] in roster else k[1])  # the end farther from the root
        h = hop(child)
        return (h is None, h or 0, child, k[0] not in roster, -volume(k))

    shown = [k for k in sorted(links, key=link_key)
             if tally[("baseline",) + k][0] + tally[("attack",) + k][0] >= 20]
    print("\nRETRY RATE PER LINK  (one board sending to one neighbour; 'x% of N' = x% of N frames were resends)")
    print("  Verdicts compare attack to baseline: a change within +/-%d points counts as 'about the same';"
          % VERDICT_PTS)
    print("  under %d frames in either phase is too few to judge." % MIN_JUDGE_FRAMES)
    rate = lambda c: 100.0 * c[1] / c[0]  # noqa: E731
    verdicts = collections.defaultdict(list)
    for i, (ta, ra) in enumerate(shown, 1):
        up = ta in roster
        print("\n  %2d. %s  ->  %s" % (i, who(node_of(ta)), who(node_of(ra))))
        print("      %s" % ("uplink: a board sending to its parent (toward the root)" if up
                           else "downlink: a parent sending to its child (away from the root)"))
        print("      " + "   ".join("%s %s" % (n, "%.1f%% of %d" % (rate(tally[(n, ta, ra)]), tally[(n, ta, ra)][0])
                                                if tally[(n, ta, ra)][0] else "no frames") for n in names))
        b, a = tally[("baseline", ta, ra)], tally[("attack", ta, ra)]
        if min(b[0], a[0]) < MIN_JUDGE_FRAMES:
            verdict, kind = "too few frames to judge", "few"
        elif max(rate(b), rate(a)) >= 99.5:
            verdict = ("every frame heard was a resend - the sniffer is most likely missing this link's "
                       "first tries, so the % is not real; don't quote it")
            kind = "unreliable"
        else:
            d = rate(a) - rate(b)
            kind = "worse" if d >= VERDICT_PTS else "better" if d <= -VERDICT_PTS else "same"
            verdict = "%+.1f points -> %s" % (d, {
                "worse": "WORSE during the attack (more resends)",
                "better": "better during the attack (fewer resends)",
                "same": "about the same"}[kind])
        print("      attack vs baseline: %s" % verdict)
        verdicts[kind].append("%s -> %s" % (who(node_of(ta)), who(node_of(ra))))
    hidden = len(links) - len(shown)
    if hidden:
        print("\n  (%d more link(s) with under 20 frames in baseline + attack are not shown)" % hidden)

    # The same numbers side by side, one row per link (the original compact table).
    pct = lambda c: "%5.1f%% %5d" % (rate(c), c[0]) if c[0] else "     -     0"  # noqa: E731
    col = 66
    print("\nRESULTS TABLE  (same links, side by side: retry % and frames heard)")
    print("  %-*s" % (col, "transmitter -> receiver") + "".join("%-15s" % n for n in names) + "attack-baseline")
    for ta, ra in shown:
        b, a = tally[("baseline", ta, ra)], tally[("attack", ta, ra)]
        diff = "%+5.1f pts" % (rate(a) - rate(b)) if a[0] and b[0] else "   n/a"
        label = "%s -> %s (%s)" % (who(node_of(ta)), who(node_of(ra)), "up" if ta in roster else "down")
        print("  " + ljust_visible(label, col)
              + "".join("%-15s" % pct(tally[(n, ta, ra)]) for n in names) + diff)
    print("  %-*s" % (col, "ALL mesh links") + "".join("%-15s" % pct(tally[(n, "*", "*")]) for n in names))
    print("\n  How to read this table:")
    print("  - Each row is ONE radio link: transmitter -> receiver. 'up' = a board sending to its parent.")
    print("  - First number = share of the frames the sniffer heard that carried the Retry bit (had to be resent);")
    print("    second number = how many frames that is. A handful of frames means the % is not worth quoting.")
    print("  - attack-baseline = how much the link changed during the attack. No consistent rise = the paper's")
    print("    Table 3.4 prediction not observed (a blackhole still ACKs every frame, so the radio never resends).")
    print("  - The ALL row mixes links with different traffic volumes - compare link by link, not that row")
    print("    (a blackhole silencing a clean uplink raises it with no link getting worse).")

    judged = sum(len(verdicts[k]) for k in ("worse", "better", "same"))
    print("\nBOTTOM LINE")
    print("  Of %d link(s) with enough frames: %d worse, %d better, %d about the same during the attack."
          % (judged, len(verdicts["worse"]), len(verdicts["better"]), len(verdicts["same"])))
    for kind, title in (("worse", "Worse"), ("better", "Better"), ("unreliable", "Not usable (100% resends)")):
        if verdicts[kind]:
            print("  %s:" % title)
            for link in verdicts[kind]:
                print("    %s" % link)
    print("  The paper's Table 3.4 expects retries to RISE under attack. If most links are not worse,")
    print("  that prediction is not observed - a blackhole still ACKs every frame, so the radio")
    print("  below it has no reason to resend.")


def _stored_path(path):
    """Relative to datasets/ when inside it, so the .json survives a move to another laptop."""
    path = os.path.abspath(path)
    inside = os.path.normcase(path).startswith(os.path.normcase(DATASETS) + os.sep)
    return os.path.relpath(path, DATASETS).replace(os.sep, "/") if inside else path


def _resolve(stored):
    return stored if os.path.isabs(stored) else os.path.join(DATASETS, stored)


def outputs_for(pcap):
    stem = os.path.splitext(pcap)[0]
    return stem + "_retry.csv", stem + "_retry.json"


def write_outputs(res):
    csv_path, json_path = outputs_for(res["pcap"])
    roster, softap = res["roster"], res["softap"]
    node_of = lambda m: softap.get(m, m)  # noqa: E731
    zero = int(res["attack_start"])
    windows = collections.defaultdict(lambda: [0, 0])
    for ts, ta, ra, retry in res["frames"]:
        w = windows[(int(ts), ta, ra)]
        w[0] += 1
        w[1] += retry
    repeat = res["identity"].get("repeat", "")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["repeat", "second_epoch", "t_rel_attack_s", "segment", "ta", "ta_role", "ra", "ra_role",
                    "direction", "frames", "retries", "retry_rate"])
        for (sec, ta, ra), (n, r) in sorted(windows.items()):
            w.writerow([repeat, sec, sec - zero, seg_of(res, sec + 0.5), ta,
                        roster.get(node_of(ta), "OUTSIDE"), ra, roster.get(node_of(ra), "OUTSIDE"),
                        "up" if ta in roster else "down", n, r, round(r / n, 4)])
    meta = {"tool": "tools/pcap_retry.py", "capture": os.path.basename(res["pcap"]),
            "run_log": _stored_path(res["run_log"]),
            "identity": {k: v for k, v in res["identity"].items() if k != "_cell"},
            "alignment": res["how"], "phase_source": res["phase_source"],
            "attack_start_epoch": res["attack_start"], "zero_second_epoch": zero,
            "root_clock_behind_s": (None if res["stamp_attack"] is None
                                    else round(res["attack_start"] - res["stamp_attack"], 1)),
            "segments": {n: [a, z] for n, a, z in res["segs"]}, "run_end_epoch": res["run_end"],
            "capture_epoch": [res["first_ts"], res["last_ts"]],
            "pauses_epoch": [list(p) for p in res["pauses"]],
            "roster": res["roster"], "csv": os.path.basename(csv_path)}
    if res["export_files"]:  # phases came from the exports: the cache must notice when they change
        meta["export_cell"] = res["export_cell"]
        meta["export_dirs"] = [_stored_path(d) for d in export_cell_dirs(res["export_cell"])]
        meta["export_files"] = [_stored_path(p) for p in res["export_files"]]
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    return csv_path, json_path, meta


def _root_logs(root):
    """{path: parsed} for every run log under root. Logs without root phase lines
    (wizard text only) are kept with phases=None, so a refusal can say so."""
    out = {}
    for path in glob.glob(os.path.join(root, "**", "*.log"), recursive=True):
        try:
            out[path] = parse_root_log(path)
        except Refuse:  # corrupt (a phase starting twice); a log with NO phase lines parses fine
            with open(path, encoding="utf-8-sig", errors="replace") as f:
                text = f.read()
            m = RE_TRANSCRIPT.search(text)
            out[path] = {"phases": None, "identity": _identity(path, text), "unusable": True,
                         "started": m and dt.datetime.strptime(
                             m.group(1), "%Y%m%d%H%M%S").replace(tzinfo=PHT).timestamp()}
        except OSError:
            continue
    return out


def _exports_changed(meta, since):
    """True when a cached result that leaned on a cell's exports can no longer trust
    them: a file it read is gone or rewritten, or a file was added to / removed from
    the cell (folder mtime), or an archive copy of the cell appeared or went away.
    Without this, --all kept reporting a run as usable after its exports were moved
    (sep. 28: the r3 raw exports left the cell; a fresh read refused, the cache didn't)."""
    cell = meta.get("export_cell")
    if not cell:
        # Written before this check existed: an export-sourced result that never recorded
        # which exports it read can't be verified, so rebuild it once.
        return (not meta.get("refused")
                and meta.get("phase_source", "root run log") != "root run log")
    dirs_now = export_cell_dirs(cell)
    if sorted(_stored_path(d) for d in dirs_now) != sorted(meta.get("export_dirs", [])):
        return True
    if any(os.path.getmtime(d) > since for d in dirs_now):
        return True
    for stored in meta.get("export_files", []):
        path = _resolve(stored)
        if not os.path.isfile(path) or os.path.getmtime(path) > since:
            return True
    return False


def refresh_all(root=DATASETS, say=print):
    """Pair every capture under root with its root log, (re)build stale outputs.
    Returns the metadata of every capture that has usable retry data."""
    pcaps = sorted(glob.glob(os.path.join(root, "**", "*.pcap"), recursive=True)
                   + glob.glob(os.path.join(root, "**", "*.pcapng"), recursive=True))
    fixed = {p.replace("_fixed", "") for p in pcaps if "_fixed." in p}
    pcaps = [p for p in pcaps if p not in fixed]
    logs = None
    usable = []
    for pcap in pcaps:
        _, json_path = outputs_for(pcap)
        cached = None
        if os.path.isfile(json_path):
            with open(json_path, encoding="utf-8") as f:
                cached = json.load(f)
            log_path = cached.get("run_log") and _resolve(cached["run_log"])
            newest = [os.path.getmtime(pcap)]
            if cached.get("refused"):  # any new log might be the one it was missing
                logs = logs if logs is not None else _root_logs(root)
                newest += [os.path.getmtime(p) for p in logs]
            elif log_path and os.path.isfile(log_path):
                newest.append(os.path.getmtime(log_path))
            else:
                newest.append(float("inf"))  # its log is gone: rebuild
            built = os.path.getmtime(json_path)
            if built < max(newest) or _exports_changed(cached, built):
                cached = None
        if cached is None:
            logs = logs if logs is not None else _root_logs(root)
            cached = _build_one(pcap, json_path, logs)
        name = os.path.basename(pcap)
        if cached.get("refused"):
            say("  sniffer %s: no retry data - %s" % (name, cached["refused"]))
            continue
        i = cached["identity"]
        say("  sniffer %s: %s r%s, attack %s (%s%s)" % (
            name, "/".join(str(i.get(k, "?")) for k in IDENTITY_KEYS), i.get("repeat", "?"),
            hms(cached["attack_start_epoch"]), cached["alignment"].split(":")[0],
            "" if cached.get("phase_source", "root run log") == "root run log" else ", phases from exports"))
        cached["csv_path"] = outputs_for(pcap)[0]
        usable.append(cached)
    return usable


def same_identity(a, b):
    """True unless a key both sides know differs (case-insensitive)."""
    for key in IDENTITY_KEYS + ("repeat",):
        x, y = a.get(key), b.get(key)
        if x is not None and y is not None and str(x).strip().lower() != str(y).strip().lower():
            return False
    return True


def run_registry(metas, root=DATASETS):
    """Every run any log under root knows about, with the earliest time it can have
    ended and its usable capture (or None). A run logged on two laptops is one run.
    Built from ALL logs, so a run whose capture was refused still claims its own
    exports instead of letting them fall back to an older captured run."""
    by_log = {os.path.normcase(_resolve(m["run_log"])): m for m in metas if m.get("run_log")}
    entries = []
    for path, p in _root_logs(root).items():
        if p["started"] is None:
            continue
        end = p["started"] + (max(p["phases"].values()) / 1000.0 if p["phases"] else NOMINAL_RUN_S)
        entries.append({"identity": p["identity"], "started": p["started"], "earliest_end": end,
                        "capture": by_log.get(os.path.normcase(os.path.abspath(path)))})
    runs = []
    for e in sorted(entries, key=lambda e: e["started"]):
        for r in runs:
            if same_identity(r["identity"], e["identity"]) and e["started"] - r["started"] <= PAIR_WINDOW_S:
                r["earliest_end"] = max(r["earliest_end"], e["earliest_end"])
                r["capture"] = r["capture"] or e["capture"]
                break
        else:
            runs.append(dict(e))
    for r in runs:
        if r["capture"]:
            r["earliest_end"] = r["capture"]["run_end_epoch"]
    return runs


def _build_one(pcap, json_path, logs):
    def refuse(reason, run_log=None):
        meta = {"tool": "tools/pcap_retry.py", "capture": os.path.basename(pcap), "refused": reason,
                "run_log": run_log and _stored_path(run_log)}
        cell = run_log and logs.get(run_log, {}).get("identity", {}).get("_cell")
        if cell and not logs[run_log]["phases"]:  # refused for want of exports: re-check when they change
            meta["export_cell"] = list(cell)
            meta["export_dirs"] = [_stored_path(d) for d in export_cell_dirs(cell)]
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=1)
        return meta
    try:
        pkts = read_capture(pcap)
    except (ValueError, OSError) as ex:
        return refuse("unreadable capture (%s)" % ex)
    if not pkts:
        return refuse("no timestamped packets")
    first = pkts[0][0]
    near = sorted((abs(p["started"] - first), path) for path, p in logs.items()
                  if p["started"] is not None and abs(p["started"] - first) <= PAIR_WINDOW_S)
    if not near:
        return refuse("no run log started within %d min of this capture - copy the root's log "
                      "into datasets/run_logs" % (PAIR_WINDOW_S // 60))
    # A cell-filed capture (PCAP/<atk>/<topo>/<loc>/<scen>/..._r<N>_) names its own run, so it is
    # never paired with another cell's or repeat's log however close in time that log sits.
    want = pcap_identity(pcap)
    matched = [p for _, p in near if same_identity(want, logs[p].get("identity", {}))]
    if not matched:
        return refuse("no run log of this run (%s) within %d min; the nearest log is %s, which is a "
                      "different run" % ("/".join(str(want.get(k, "?")) for k in IDENTITY_KEYS),
                                         PAIR_WINDOW_S // 60, os.path.basename(near[0][1])),
                      near[0][1])
    # A log that still has its phase lines is the simplest source; one that lost them can
    # still work off the run's exported CSVs (phases_and_roles_from_exports).
    ordered = ([p for p in matched if logs[p]["phases"]]
               + [p for p in matched if not logs[p]["phases"] and not logs[p].get("unusable")]
               + [p for p in matched if logs[p].get("unusable")])
    first_reason = first_log = None
    for run_log in ordered:
        try:
            res = analyze(pcap, run_log, pkts=pkts, sibling_logs=logs, say=lambda *_: None)
        except Refuse as ex:
            if first_reason is None:
                first_reason, first_log = str(ex), run_log
            continue
        return write_outputs(res)[2]
    return refuse(first_reason, first_log)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Real 802.11 retry rate per link and phase from a sniffer pcap.")
    ap.add_argument("pcap", nargs="?")
    ap.add_argument("--run-log", help="the ROOT's run log for the same run")
    ap.add_argument("--attack-start", help="real laptop time HH:MM:SS the attack began (overrides the fit)")
    ap.add_argument("--trust-stamp", action="store_true",
                    help="use the root banner time even though it lags by the flash time")
    ap.add_argument("--no-csv", action="store_true")
    ap.add_argument("--all", action="store_true",
                    help="pair every capture under datasets/ with its root log and write its outputs")
    args = ap.parse_args()

    if args.all:
        usable = refresh_all()
        print("%d capture(s) with retry data." % len(usable))
        return 0
    if not args.pcap or not args.run_log:
        ap.error("give a capture and --run-log, or --all")
    try:
        res = analyze(args.pcap.strip().strip('"'), args.run_log, args.attack_start, args.trust_stamp)
    except Refuse as ex:
        print("REFUSED: %s" % ex)
        return 2
    report(res)
    if not args.no_csv:
        print("\nWrote %s" % write_outputs(res)[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
