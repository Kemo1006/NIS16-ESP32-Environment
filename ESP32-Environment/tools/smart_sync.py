#!/usr/bin/env python3
"""Smart GitHub sync - the brain behind run_gui.ps1's GitHub sync page (oct. 18, 2026).

    python tools/smart_sync.py status --json            plan everything, change nothing
    python tools/smart_sync.py apply --plan plan.json   do exactly the ticked items
    python tools/smart_sync.py update-repo [--dry-run]  bring THIS folder up to GitHub safely

Built on tools/push_data.py (same private clone, same "never code" guard, same
byte-exact verify), and adds what went wrong in practice:

  * STALE ANALYSIS never goes up. An analysis cell is current only when its
    feature_table.csv's source_file list covers every *_telem.csv of that run's
    exports folder (content, not file times - git rewrites times on pull).
    A stale or missing analysis is reported as "analyse first", not pushed.
  * Analysis is derived data, so it never makes KEEP-BOTH conflict copies:
    a current analysis replaces a stale one on GitHub; two current analyses of
    the same data are equivalent and the one on GitHub stays.
  * A cell's analysis never goes up without the data it was made from: pushing
    an analysis cell pulls that cell's pending capture files into the push.
  * DUPLICATES are caught before they reach GitHub: byte-identical to a file
    GitHub has under another path, or the same board + kind + row count already
    in that run folder under another name (preset naming vs card naming).
  * Deleted-on-GitHub files are never re-uploaded (restore is the way back).
  * Pull never stages anything in your repo's index (that is how raw captures
    once rode along in a code commit). update-repo makes the folder consistent.
  * update-repo never leaves a half-done merge: every file in the way is backed
    up first (%LOCALAPPDATA%\\NIS16\\sync_backup\\<time>\\), code you changed is
    3-way merged with GitHub's change (blocked, untouched, if they conflict),
    data conflicts resolve by rule, and any unexpected failure rolls back.
"""

import argparse
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import push_data as ps  # noqa: E402

BASE = ps.BASE
AREAS = {"exports": ps.EXPORTS, "analysis": ps.ANALYSIS, "logs": ps.LOGS, "presets": ps.PRESETS}
DATA_ROOTS = (ps.EXPORTS, ps.ANALYSIS, ps.LOGS, ps.PRESETS, ps.CONFLICTS, ps.ARCHIVE, "datasets", "archive", "sync_test")
HOME = Path(os.environ.get("LOCALAPPDATA") or str(Path.home() / ".cache")) / "NIS16"
STATE = HOME / "sync_state.json"
ROW_TOL = 2


def sha_blob(data):
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


# LINE ENDINGS (found oct. 18, 2026 - a root cause of the sync mess): exports and
# run logs are byte-exact (.gitattributes -text), but analysis tables and presets
# are TEXT, and a laptop with core.autocrlf=true commits them LF while the
# working copy (and push_data.py's raw-bytes push) is CRLF. Every file a normal
# commit touched then looked "different" to the data sync -> KEEP-BOTH copies,
# re-pushes, pull refusals. One canonical form for those text files: LF.
canon = ps.canon       # one rule, shared with the CLI's push_data.py


# SPEED (oct. 18, 2026 - a check took 152 s and made the GUI lag): every git
# question used to start its own process (~0.1 s each on Windows + antivirus,
# ~1150 of them). Now: ONE long-lived `git cat-file --batch` per repo for blob
# reads, one `git log --raw` per area for history, batched ls-tree /
# hash-object for the folder preview, and a cache on disk of everything derived
# from a file (hash, feature-table sources, board fingerprint) keyed by
# (size, mtime_ns) - a file that did not change is never read again.
CACHE_FILE = HOME / "sync_cache.json"
_CACHE = None


def cache():
    global _CACHE
    if _CACHE is None:
        try:
            _CACHE = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
            if _CACHE.get("v") != 1:
                raise ValueError
        except (OSError, ValueError):
            _CACHE = {"v": 1}
    return _CACHE


def save_cache():
    if _CACHE is None:
        return
    try:
        HOME.mkdir(parents=True, exist_ok=True)
        tmp = CACHE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(_CACHE), encoding="utf-8")
        os.replace(tmp, CACHE_FILE)
    except OSError:
        pass


def cached(kind, path, fn):
    """fn() for this file, remembered until its size or modified time changes."""
    try:
        st = os.stat(path)
    except OSError:
        return fn()
    box = cache().setdefault(kind, {})
    key = str(path)
    ent = box.get(key)
    if ent and ent[0] == st.st_size and ent[1] == st.st_mtime_ns:
        return ent[2]
    val = fn()
    box[key] = [st.st_size, st.st_mtime_ns, val]
    return val


class Cat:
    """One `git cat-file --batch` process: blob bytes by sha, no process per read."""

    def __init__(self, cwd):
        self.p = subprocess.Popen(["git", "cat-file", "--batch"], cwd=str(cwd),
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.memo = {}

    def get(self, sha):
        if sha in self.memo:
            return self.memo[sha]
        self.p.stdin.write((sha + "\n").encode())
        self.p.stdin.flush()
        hdr = self.p.stdout.readline().split()
        if len(hdr) < 3 or hdr[1] == b"missing":
            data = None
        else:
            data = self.p.stdout.read(int(hdr[2]))
            self.p.stdout.read(1)
        if data is not None and len(data) < 4_000_000:
            self.memo[sha] = data
        return data

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()


def same_as_remote(ctx, area, rel, data, rsha):
    """True when GitHub's blob is the same file once line endings are made canonical."""
    if area not in (ps.ANALYSIS, ps.PRESETS) or rsha is None:
        return False
    blob = ctx.cat.get(rsha)
    return blob is not None and canon(area, rel, blob) == data


def history(ctx, area):
    """{rel: every blob sha GitHub ever had at that path} - one git log for the whole area."""
    p = ps.git(["log", "--no-abbrev", "--no-renames", "--format=", "--raw", "HEAD", "--", ctx.prefix + area],
               ctx.sync, cfg=("core.quotepath=off",))
    res = {}
    for line in ps.text(p).splitlines():
        if not line.startswith(":"):
            continue
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) >= 4:
            res.setdefault(path[len(ctx.prefix):], set()).add(parts[3])
    return res


def scan_github(ctx):
    """Everything the plan needs from GitHub in TWO git calls (ls-tree + one log):
    rhash {area: {rel: sha}}, hist {area: {rel: {every sha}}}, deleted {area: {rel: (commit, when, subject)}},
    archived (names, ledger rows) - same rules as push_data's per-area helpers."""
    areas = list(AREAS.values())
    rhash = {a: {} for a in areas}
    arch_names, arch_rows = set(), set()
    p = ps.git(["ls-tree", "-r", "-z", "HEAD", "--"] + [ctx.prefix + a for a in areas + [ps.ARCHIVE]], ctx.sync,
               cfg=("core.quotepath=off",))
    for ent in ps.nul_list(p):
        meta, _, path = ent.partition("\t")
        rel, sha = path[len(ctx.prefix):], meta.split()[2]
        if rel.startswith(ps.ARCHIVE + "/"):
            name = rel.rsplit("/", 1)[-1]
            if name == "run_ledger.csv":
                blob = ctx.cat.get(sha) or b""
                arch_rows.update(ps.split_ledger(blob)[0][1:])
            elif name.lower().endswith(".csv"):
                arch_names.add(name)
            continue
        for a in areas:
            if rel.startswith(a + "/"):
                rhash[a][rel] = sha
                break
    arch_names -= ps.LEDGERS
    hist = {a: {} for a in areas}
    deleted = {a: {} for a in areas}
    # --full-history: every side of every merge (a merged teammate push is history too).
    # --no-renames on purpose: a RENAMED file counts as deleted at its old path, so a
    # laptop still holding the old name never re-uploads it (the oct. 7 presets mess).
    p = ps.git(["log", "--full-history", "--no-abbrev", "--no-renames", "--raw", "--date=format:%b %d %Y %H:%M",
                "--format=%x01%H%x09%ad%x09%ct%x09%an%x09%s", "HEAD", "--"] + [ctx.prefix + a for a in areas],
               ctx.sync, cfg=("core.quotepath=off",))
    cur, who = None, None
    ups = {}
    for line in ps.text(p).splitlines():
        if line.startswith("\x01"):
            f = line[1:].split("\t", 4)
            cur, who = (f[0], f[1], f[4] if len(f) > 4 else ""), (int(f[2]), f[3])
            continue
        if not line.startswith(":"):
            continue
        meta, _, path = line.partition("\t")
        parts = meta.split()
        rel = path[len(ctx.prefix):]
        area = next((a for a in areas if rel.startswith(a + "/")), None)
        if area is None or len(parts) < 5:
            continue
        hist[area].setdefault(rel, set()).add(parts[3])
        if parts[4][:1] in ("A", "M") and who and parts[3] == rhash[area].get(rel):
            if rel not in ups or who[0] < ups[rel][0]:   # the EARLIEST commit that brought today's version
                ups[rel] = who
        if parts[4].startswith("D") and cur and rel not in deleted[area] and rel not in rhash[area]:
            name = rel.rsplit("/", 1)[-1]
            if name in ps.LEDGERS or (area == ps.EXPORTS and name in arch_names):
                continue
            if ps.is_area_payload(area, rel) and not ps.in_archive(rel):
                deleted[area][rel] = cur
    ctx.ups = ups
    return rhash, hist, deleted, (arch_names, arch_rows)


def local_listing():
    """{area: [rel]} of this laptop's data - two git calls instead of one per area
    (exports/presets honour .gitignore; analysis/logs do not, as in push_data.local_files)."""
    res = {a: [] for a in AREAS.values()}
    for areas, std in (([ps.EXPORTS, ps.PRESETS], True), ([ps.ANALYSIS, ps.LOGS], False)):
        cmd = ["ls-files", "-z", "--cached", "--others"] + (["--exclude-standard"] if std else []) + ["--"] + areas
        for rel in set(ps.nul_list(ps.git(cmd, BASE))):
            a = next((x for x in areas if rel.startswith(x + "/")), None)
            if a and ps.is_area_payload(a, rel) and not ps.in_archive(rel) and (BASE / rel).is_file():
                res[a].append(rel)
    return {a: sorted(v) for a, v in res.items()}


def local_deletions():
    """{area: {rel: canonical sha of the deleted version}} - data files this repo has
    COMMITTED but that are gone from this laptop's folder (deleted or moved by hand, a
    wrong import cleaned up, an old run replaced). oct. 20 2026: before, Pull saw such a
    file only as 'a teammate's file you don't have' and brought it back - the deleted
    run reappeared in its run folder next to the right one (verification #48, #68)."""
    res = {a: {} for a in AREAS.values()}
    dels = [r for r in ps.nul_list(ps.git(["ls-files", "-z", "-d", "--"] + list(AREAS.values()), BASE, check=False))
            if not (BASE / r).exists()]
    for i in range(0, len(dels), 100):
        chunk = dels[i:i + 100]
        p = ps.git(["ls-tree", "-r", "-z", "HEAD", "--"] + chunk, BASE, check=False)
        for rec in ps.nul_list(p):
            try:
                meta, rel = rec.split("\t", 1)
                sha = meta.split()[2]
            except (ValueError, IndexError):
                continue
            area = next((x for x in AREAS.values() if rel.startswith(x + "/")), None)
            if not area or not ps.is_area_payload(area, rel) or ps.in_archive(rel):
                continue
            try:
                data = ps.git(["cat-file", "blob", sha], BASE).stdout
                res[area][rel] = sha_blob(canon(area, rel, data))
            except ps.SyncError:
                continue
    return res


def local_sha(area, rel):
    p = BASE / rel
    return cached("sha", p, lambda: sha_blob(canon(area, rel, p.read_bytes())))


def g(args, cwd=None, check=True, stdin=None, cfg=()):
    """git in YOUR repo with YOUR settings (autocrlf etc. untouched, unlike ps.git)."""
    cmd = ["git", "-c", "core.quotepath=off"]
    for c in cfg:
        cmd += ["-c", c]
    p = subprocess.run(cmd + list(args), cwd=str(cwd or BASE), capture_output=True,
                       input=stdin if isinstance(stdin, (bytes, type(None))) else stdin.encode("utf-8"))
    if check and p.returncode != 0:
        raise ps.SyncError("git {} failed:\n{}".format(" ".join(args), p.stderr.decode("utf-8", "replace").strip()))
    return p


def out(p):
    return p.stdout.decode("utf-8", "replace")


def log(msg):
    print(msg, flush=True)


# ------------------------------------------------------------- run cells ---

def cell_of(rel):
    """'attack/topology/location/scenario' a data file belongs to ('' if none)."""
    parts = rel.split("/")
    for root in (ps.EXPORTS, ps.ANALYSIS, ps.LOGS):
        n = len(root.split("/"))
        if rel.startswith(root + "/"):
            inner = parts[n:-1]
            if "eda_output" in inner:
                inner = inner[:inner.index("eda_output")]
            return "/".join(x for x in inner if x not in ("trimmed",))
    return ""


def read_sources(ft):
    """source_file basenames in a feature_table.csv; None = no table; 'nocol' = old table."""
    if not ft.is_file():
        return None
    val = cached("src", ft, lambda: _read_sources(ft))
    return set(val) if isinstance(val, list) else val


def _read_sources(ft):
    # only the one column, plain csv.reader (DictReader builds a dict per row -
    # these tables run to tens of MB)
    try:
        with open(ft, newline="", encoding="utf-8-sig") as fh:
            r = csv.reader(fh)
            head = next(r, None)
            if not head or "source_file" not in head:
                return "nocol"
            i = head.index("source_file")
            seen = set()
            for row in r:
                if len(row) > i and row[i]:
                    seen.add(row[i])
            return sorted({os.path.basename(x) for x in seen})
    except (OSError, csv.Error, UnicodeDecodeError):
        return "nocol"


def telem_names(root, cell):
    d = root / ps.EXPORTS / cell
    if not d.is_dir():
        return set()
    return {f.name for f in d.iterdir() if f.is_file() and f.name.endswith("_telem.csv")}


def freshness(root, cell, extra=()):
    """fresh / stale / missing / unknown / noexports for one analysis cell under `root`."""
    tel = telem_names(root, cell) | set(extra)
    src = read_sources(root / ps.ANALYSIS / cell / "feature_table.csv")
    if not tel:
        return "noexports" if src is None else "orphan"
    if src is None:
        return "missing"
    if src == "nocol":
        return "unknown"
    return "fresh" if tel <= src else "stale"


def fingerprint(path):
    """(mac, kind, rows) of a capture CSV from its own rows; cached on disk by (size, mtime)."""
    if not os.path.isfile(path):
        return None
    v = cached("fp", path, lambda: _fingerprint(path))
    return tuple(v) if v else None


def _fingerprint(path):
    mac, n = "", 0
    try:
        with open(path, "rb") as fh:
            fh.readline()
            first = fh.readline()
            if first:
                n = 1 + sum(1 for _ in fh)
        m = re.search(rb"NODE_([0-9A-Fa-f]{12})", first or b"")
        mac = m.group(1).decode().lower() if m else ""
    except OSError:
        return None
    kind = "telem" if path.name.endswith("_telem.csv") else "arrivals" if path.name.endswith("_arrivals.csv") else ""
    return [mac, kind, n]


def same_capture(a, b):
    return bool(a and b and a[0] and a[1] and a[0] == b[0] and a[1] == b[1] and abs(a[2] - b[2]) <= ROW_TOL)


# --------------------------------------------------------------- context ---

def make_ctx(branch=None):
    ns = argparse.Namespace(yes=True, branch=branch, remote="origin", sync_dir=None, action="push")
    ctx = ps.Ctx(ns)
    marker = ctx.sync / ".git" / ps.MARKER
    if marker.exists():
        # an existing private clone: skip push_data's ls-remote (a network round trip
        # that only matters before the first clone) and re-declare the sparse
        # folders only when the list changed
        ps.git(["remote", "set-url", "origin", ctx.url], ctx.sync)
        want = "\n".join(ctx.prefix + a for a in (ps.EXPORTS, ps.TEST_AREA, ps.PRESETS, ps.ANALYSIS, ps.LOGS, ps.CONFLICTS))
        mark = ctx.sync / ".git" / "nis16-sparse"
        if not mark.exists() or mark.read_text(encoding="utf-8") != want:
            ps.apply_sparse(ctx)
            mark.write_text(want, encoding="utf-8")
    else:
        ps.ensure_clone(ctx)
    # the two network fetches (private clone + your folder's origin/<branch>) run side by side
    box = {}
    th = threading.Thread(target=lambda: box.update(r=g(["fetch", "--quiet", "origin", ctx.branch], ctx.root, check=False)))
    th.start()
    ps.refresh(ctx)
    th.join()
    ctx.prefetch = box.get("r")
    ctx.rroot = ctx.sync / ctx.prefix.rstrip("/") if ctx.prefix else ctx.sync
    ctx.cat = Cat(ctx.sync)
    return ctx


def remote_hashes(ctx, area):
    """{rel: blob sha} for the area on GitHub (one ls-tree, no blob reads)."""
    p = ps.git(["ls-tree", "-r", "-z", "HEAD", "--", ctx.prefix + area], ctx.sync)
    res = {}
    for ent in ps.nul_list(p):
        meta, _, path = ent.partition("\t")
        res[path[len(ctx.prefix):]] = meta.split()[2]
    return res


# ---------------------------------------------------------------- health ---

def repo_health(ctx):
    root = ctx.root
    gitdir = Path(out(g(["rev-parse", "--absolute-git-dir"], root)).strip())
    h = {"branch": ctx.branch, "computer": ctx.computer, "url": ctx.url, "blocking": [], "warnings": [],
         "ahead": 0, "behind": 0, "codeDirty": [], "dataDirty": 0, "stashes": 0, "fetched": True}
    # make_ctx already fetched (in parallel) - use that once; a later call (after a push) fetches again
    fetch = getattr(ctx, "prefetch", None) or g(["fetch", "--quiet", "origin", ctx.branch], root, check=False)
    ctx.prefetch = None
    if fetch.returncode != 0:
        h["fetched"] = False
        h["warnings"].append("Could not reach GitHub to compare your folder (offline?) - "
                             + fetch.stderr.decode("utf-8", "replace").strip()[:160])
    if (gitdir / "MERGE_HEAD").exists():
        h["blocking"].append("An unfinished MERGE is in progress in your folder - finish it or press 'Abort unfinished merge'.")
    if (gitdir / "rebase-merge").exists() or (gitdir / "rebase-apply").exists():
        h["blocking"].append("An unfinished REBASE is in progress - run 'git rebase --abort' (or finish it) first.")
    if (gitdir / "CHERRY_PICK_HEAD").exists():
        h["blocking"].append("An unfinished cherry-pick is in progress - 'git cherry-pick --abort' first.")
    um = [x for x in out(g(["diff", "--name-only", "--diff-filter=U"], root, check=False)).splitlines() if x]
    if um:
        h["blocking"].append("{} file(s) still have merge conflicts: {}".format(len(um), ", ".join(um[:4])))
    lr = g(["rev-list", "--left-right", "--count", "HEAD...origin/" + ctx.branch], root, check=False)
    if lr.returncode == 0:
        a, b = out(lr).split()
        h["ahead"], h["behind"] = int(a), int(b)
    h["stashes"] = len([x for x in out(g(["stash", "list"], root, check=False)).splitlines() if x])
    ctx.porc = porcelain(root)
    for path, st in ctx.porc:
        if is_data_path(ctx, path):
            h["dataDirty"] += 1
        else:
            h["codeDirty"].append({"path": path, "status": st})
    if h["ahead"]:
        h["warnings"].append("Your folder has {} commit(s) GitHub does not have yet - push your code (git push) "
                             "when it is ready; data sync never sends code.".format(h["ahead"]))
    if h["stashes"]:
        h["warnings"].append("{} old stash(es) in this repo - 'git stash list' to check nothing is forgotten there.".format(h["stashes"]))
    return h


def porcelain(root):
    """[(path, XY)] of changed + untracked files (not ignored), repo-root relative."""
    p = g(["status", "--porcelain=v1", "-z", "-uall", "--no-renames"], root, check=False)
    res = []
    for ent in [x for x in out(p).split("\0") if x]:
        res.append((ent[3:], ent[:2]))
    return res


def is_data_path(ctx, path):
    rel = path[len(ctx.prefix):] if path.startswith(ctx.prefix) else None
    return rel is not None and any(rel == r or rel.startswith(r + "/") for r in DATA_ROOTS)


# ------------------------------------------------------------- push plan ---

def same_remote_cached(ctx, area, rel, sha, rsha):
    """same_as_remote, remembered per (your hash, GitHub's hash) pair."""
    if area not in (ps.ANALYSIS, ps.PRESETS) or rsha is None:
        return False
    box = cache().setdefault("eq", {})
    key = sha + ":" + rsha
    if key not in box:
        box[key] = same_as_remote(ctx, area, rel, canon(area, rel, (BASE / rel).read_bytes()), rsha)
    return box[key]


def push_plan(ctx, area, lhash, rhash, hist, archived, deleted, rfp_cache):
    """Items for one area: what would go up, and what is held back (with why)."""
    items = []
    r_by_sha = {}
    for rel, sha in rhash.items():
        r_by_sha.setdefault(sha, rel)
    for rel, sha in lhash.items():
        name = rel.rsplit("/", 1)[-1]
        it = {"area": area_key(area), "rel": rel, "cell": cell_of(rel), "size": 0}
        p = BASE / rel
        rsha = rhash.get(rel)
        if rsha == sha or same_remote_cached(ctx, area, rel, sha, rsha):
            continue                                     # identical on GitHub
        data = canon(area, rel, p.read_bytes())          # only files that really differ are read
        it["size"] = len(data)
        repo_path = ctx.prefix + rel
        seen = hist.get(rel, ())
        if name in ps.LEDGERS:
            remote = ctx.cat.get(rsha) if rsha else None
            merged = ps.merge_ledger(remote, data, archived[1])
            if merged == b"":
                continue
            if merged is None:
                items.append(dict(it, kind="conflict", act="push", why="ledger headers differ - yours kept beside it",
                                  dest=ps.conflict_path(ctx, rel, data) or ""))
            else:
                items.append(dict(it, kind="ledger", act="push", why="run registry - your rows are merged in, none removed",
                                  dest=repo_path))
            continue
        if rsha is None:
            if area == ps.EXPORTS and name in archived[0]:
                items.append(dict(it, kind="archived", act="skip", why="a teammate moved this run to archive/ on GitHub"))
            elif rel in deleted and sha in seen:
                c = deleted[rel]
                items.append(dict(it, kind="deleted", act="skip",
                                  why="deleted from GitHub ({}, '{}') - not re-uploaded; use Restore if that was a mistake".format(c[1], c[2][:50])))
            elif sha in r_by_sha:
                items.append(dict(it, kind="duplicate", act="skip",
                                  why="GitHub already has this exact file as " + r_by_sha[sha]))
            else:
                dup = content_twin(ctx, rel, p, rhash, rfp_cache) if area == ps.EXPORTS else None
                if dup:
                    items.append(dict(it, kind="duplicate", act="skip",
                                      why="same board, same run, same rows already on GitHub as " + dup.rsplit("/", 1)[-1]))
                else:
                    items.append(dict(it, kind="new", act="push", why="not on GitHub yet", dest=repo_path))
            continue
        if sha in seen:
            items.append(dict(it, kind="older", act="skip", why="GitHub has a NEWER version of this file"))
            continue
        if area == ps.ANALYSIS:
            items.append(dict(it, kind="update", act="push", why="", dest=repo_path))   # judged per cell below
            continue
        cp = ps.conflict_path(ctx, rel, data)
        if cp is None:
            continue
        items.append(dict(it, kind="conflict", act="push", dest=cp,
                          why="same name, different bytes on GitHub - BOTH kept, yours under " + cp[len(ctx.prefix):]))
    return items


def content_twin(ctx, rel, path, rhash, cache):
    """A file in the SAME run folder on GitHub holding the same capture under another name."""
    folder = rel.rsplit("/", 1)[0]
    me = fingerprint(path)
    if not me or not me[0]:
        return None
    if folder not in cache:
        cache[folder] = [(r, fingerprint(ctx.rroot / r)) for r in rhash if r.rsplit("/", 1)[0] == folder]
    for r, fp in cache[folder]:
        if same_capture(me, fp):
            return r
    return None


def judge_analysis(ctx, items, pending_exports):
    """Per analysis cell: push only a CURRENT analysis, and only where GitHub's isn't."""
    cells = {}
    for it in items:
        if it["area"] == "analysis":
            cells.setdefault(it["cell"], []).append(it)
    verdicts = {}
    for cell, its in cells.items():
        mine = freshness(BASE, cell)
        theirs = freshness(ctx.rroot, cell, extra=pending_exports.get(cell, ()))
        verdicts[cell] = (mine, theirs)
        for it in its:
            if mine not in ("fresh", "unknown"):
                it.update(act="skip", kind="stale", why="your analysis is {} - it does not cover every capture of this run; "
                          "re-analyse first".format("missing" if mine == "missing" else "STALE"))
            elif it["kind"] == "update" and theirs == "fresh":
                it.update(act="skip", kind="equivalent",
                          why="GitHub already has a current analysis of the same data (re-renders differ by a few bytes)")
            elif it["kind"] == "update":
                it.update(why="replaces GitHub's {} analysis with your current one".format(theirs))
            elif it["kind"] == "new":
                it.update(why="current analysis, not on GitHub yet")
    return verdicts


# ------------------------------------------------------------- pull plan ---

_CAPTURE_KEY = re.compile(r"^(root|child|victim)_(.+?)_[a-z_]+?_[a-z]+_r(\d+)_.*_(telem|arrivals)\.csv$")


def _same_board_capture(dst):
    """Name of a local file in dst's folder that is the SAME board + repeat + kind
    (another capture of it), or None."""
    m = _CAPTURE_KEY.match(dst.name)
    if not m or not dst.parent.is_dir():
        return None
    key = (m.group(1), m.group(2), m.group(3), m.group(4))
    for f in dst.parent.iterdir():
        if f.is_file() and f.name != dst.name:
            k = _CAPTURE_KEY.match(f.name)
            if k and (k.group(1), k.group(2), k.group(3), k.group(4)) == key:
                return f.name
    return None


def pull_plan(ctx, area, rhash, local_hash, local_archived, rdeleted_mine):
    items = []
    l_by_sha = {}
    for rel, sha in local_hash.items():
        l_by_sha.setdefault(sha, rel)
    for rel, sha in rhash.items():
        if not ps.is_area_payload(area, rel) or ps.in_archive(rel):
            continue
        name = rel.rsplit("/", 1)[-1]
        it = {"area": area_key(area), "rel": rel, "cell": cell_of(rel)}
        dst = BASE / rel
        lsha = local_hash.get(rel)
        if lsha == sha or (lsha and same_remote_cached(ctx, area, rel, lsha, sha)):
            continue
        if not dst.exists():
            if rdeleted_mine and rel in rdeleted_mine:
                items.append(dict(it, kind="deletedhere", act="skip",
                                  why="you DELETED this on this laptop - not pulled back. To delete it on GitHub "
                                      "too, tick it under Send ('DELETE ON GITHUB'); to get it back: git checkout -- <file>"))
            elif name in local_archived:
                items.append(dict(it, kind="archived", act="skip", why="you archived this locally"))
            elif sha in l_by_sha:
                items.append(dict(it, kind="duplicate", act="skip", why="you already have this exact file as " + l_by_sha[sha]))
            else:
                twin = None
                if area == ps.EXPORTS:
                    fp = fingerprint(ctx.rroot / rel)
                    folder = dst.parent
                    if folder.is_dir():
                        for f in folder.iterdir():
                            if f.is_file() and f.suffix == ".csv" and same_capture(fp, fingerprint(f)):
                                twin = f.name
                                break
                same_board = _same_board_capture(dst) if area == ps.EXPORTS else None
                if twin:
                    items.append(dict(it, kind="duplicate", act="skip", why="you have the same capture as " + twin))
                elif same_board:
                    # oct. 19 2026: never put a SECOND file of one board + repeat into a
                    # run folder - the analysis would read both (two runs mixed)
                    items.append(dict(it, kind="duplicate", act="skip",
                                      why="you already have this board's capture for this run ({}) - pulling it "
                                          "would put two runs in one folder; archive yours first if GitHub's is the "
                                          "right one".format(same_board)))
                else:
                    items.append(dict(it, kind="new", act="pull", why="a teammate's file you don't have"))
            continue
        if name in ps.LEDGERS:
            r_lines = ps.split_ledger((ctx.rroot / rel).read_bytes())[0]
            l_lines = ps.split_ledger(dst.read_bytes())[0]
            if r_lines[:1] == l_lines[:1] and {x for x in l_lines if x.strip()} <= set(r_lines):
                items.append(dict(it, kind="ledger", act="pull", why="gains teammates' rows, none of yours removed"))
            continue
        if area == ps.ANALYSIS:
            items.append(dict(it, kind="update", act="pull", why=""))      # judged per cell
            continue
        items.append(dict(it, kind="differ", act="skip", why="your copy differs - yours is kept (it goes up as a KEEP-BOTH copy)"))
    return items


def judge_pull_analysis(ctx, items, incoming_exports):
    cells = {}
    for it in items:
        if it["area"] == "analysis" and it["act"] == "pull":
            cells.setdefault(it["cell"], []).append(it)
    for cell, its in cells.items():
        mine = freshness(BASE, cell, extra=incoming_exports.get(cell, ()))
        theirs = freshness(ctx.rroot, cell)
        # GitHub's analysis must match the data you will have after this pull
        have = telem_names(BASE, cell) | set(incoming_exports.get(cell, ()))
        src = read_sources(ctx.rroot / ps.ANALYSIS / cell / "feature_table.csv")
        covers = isinstance(src, set) and have and have <= src
        for it in its:
            if not covers and theirs != "unknown":
                it.update(act="skip", kind="stale", why="GitHub's analysis does not cover the captures you have - analyse here instead")
            elif it["kind"] == "update" and mine == "fresh":
                it.update(act="skip", kind="equivalent", why="your analysis is already current for this data")
            elif it["kind"] == "update":
                it.update(kind="replace", why="replaces your {} analysis (yours is backed up first)".format(mine))
            else:
                it.update(why="current analysis from a teammate")


def area_key(area):
    return {v: k for k, v in AREAS.items()}[area]


# ---------------------------------------------------------------- status ---

def build_status(ctx):
    health = repo_health(ctx)
    push, pull, cells = [], [], {}
    rh, hist, deleted, archived = scan_github(ctx)
    lh = {}
    for area, rels in local_listing().items():
        lh[area] = {}
        for rel in rels:
            try:
                lh[area][rel] = local_sha(area, rel)
            except OSError:
                pass
    rfp = {}
    for key, area in AREAS.items():
        push += push_plan(ctx, area, lh[area], rh[area], hist[area], archived, deleted[area], rfp)
    pending = {}
    for it in push:
        if it["area"] == "exports" and it["act"] == "push" and it["rel"].endswith("_telem.csv"):
            pending.setdefault(it["cell"], set()).add(it["rel"].rsplit("/", 1)[-1])
    judge_analysis(ctx, push, pending)

    local_archived = set()
    if (BASE / ps.ARCHIVE).is_dir():
        for _, _, files in os.walk(BASE / ps.ARCHIVE):
            local_archived.update(files)
    if (BASE / ps.LOGS / "_archive").is_dir():
        for _, _, files in os.walk(BASE / ps.LOGS / "_archive"):
            local_archived.update(files)
    # oct. 19 2026: tools/archive_replaced.py (re-capture auto-archive) and Collect's
    # wrong-piece moves go to ESP32-Environment/archive/, NOT datasets/archive/. This
    # folder was not looked at, so a sync pulled the archived 7:21 PM capture back into
    # the run folder next to its 10:11 PM replacement (and the analysis read both).
    if (BASE / "archive").is_dir():
        for _, _, files in os.walk(BASE / "archive"):
            local_archived.update(files)
    dels = local_deletions()
    for key, area in AREAS.items():
        pull += pull_plan(ctx, area, rh[area], lh[area], local_archived, dels[area])
    # oct. 20 2026: a file deleted here that GitHub still has -> an explicit DELETE item,
    # NEVER ticked by default. Only offered when GitHub holds exactly the version you
    # deleted; if a teammate changed it since, it is held back as a conflict.
    for key, area in AREAS.items():
        for rel, dsha in sorted(dels[area].items()):
            rsha = rh[area].get(rel)
            if rsha is None:
                continue
            it = {"area": key, "rel": rel, "cell": cell_of(rel), "size": 0, "dest": ctx.prefix + rel}
            if rsha == dsha or same_remote_cached(ctx, area, rel, dsha, rsha):
                push.append(dict(it, kind="delete", act="push", tick=False,
                                 why="you deleted this on this laptop; GitHub still has it - tick to delete it on "
                                     "GitHub too (a normal commit: it stays in GitHub's history, Restore brings it back)"))
            else:
                push.append(dict(it, kind="deleteconflict", act="skip",
                                 why="you deleted it here, but a teammate CHANGED it on GitHub since - not deleted "
                                     "there; decide with the team (git checkout -- <file> restores your copy)"))
    incoming = {}
    for it in pull:
        if it["area"] == "exports" and it["act"] == "pull" and it["rel"].endswith("_telem.csv"):
            incoming.setdefault(it["cell"], set()).add(it["rel"].rsplit("/", 1)[-1])
    judge_pull_analysis(ctx, pull, incoming)

    # copies of files a teammate deleted on GitHub (only byte-identical ones are offered)
    gone = []
    for key, area in AREAS.items():
        for rel in lh[area]:
            if rel in deleted[area] and rel not in rh[area]:
                if lh[area][rel] in hist[area].get(rel, ()):
                    c = deleted[area][rel]
                    gone.append({"area": key, "rel": rel, "cell": cell_of(rel), "kind": "gone", "act": "remove",
                                 "why": "deleted on GitHub {} ('{}') - your copy is identical to GitHub's history, so removing it is undoable".format(c[1], c[2][:60])})

    # one row per run: data + analysis, here and on GitHub
    names = set()
    for area in (ps.EXPORTS, ps.ANALYSIS):
        for rel in list(lh[area]) + list(rh[area]):
            c = cell_of(rel)
            if c.count("/") >= 2:
                names.add(c)
    for c in sorted(names):
        lt, rt = telem_names(BASE, c), telem_names(ctx.rroot, c)
        has_root_l = any(n.startswith("root") for n in lt)
        cells[c] = {"cell": c, "localBoards": len(lt), "githubBoards": len(rt),
                    "onlyHere": len(lt - rt), "onlyGithub": len(rt - lt),
                    "localAnalysis": freshness(BASE, c), "githubAnalysis": freshness(ctx.rroot, c),
                    "rootHere": has_root_l or not lt}
    ups = getattr(ctx, "ups", None) or ps.upload_times(ctx, ps.EXPORTS)
    for it in pull:
        if it["rel"] in ups:
            it["when"], it["who"] = ups[it["rel"]]
    for it in push:
        if it["act"] == "push" and it["area"] == "exports" and it["kind"] != "delete":
            ca = freshness(BASE, it["cell"])
            if ca != "fresh":
                it["needsAnalysis"] = ca
    update = plan_update(ctx) if health["fetched"] else {"behind": 0, "obstacles": [], "canUpdate": False, "why": "offline"}
    save_cache()
    state = {}
    try:
        state = json.loads(STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    return {"health": health, "push": push, "pull": pull, "gone": gone, "cells": list(cells.values()),
            "update": update, "last": state.get(ctx.branch), "generated": int(time.time())}


# ------------------------------------------------------------------ apply ---

def apply(ctx, plan):
    """plan = {push: [rel], pull: [rel], remove: [rel], update: bool, allowCodeMerge: bool}"""
    report = {"pushed": 0, "pulled": 0, "removed": 0, "skipped": [], "updated": None, "backup": ""}
    want_push, want_pull = set(plan.get("push") or []), set(plan.get("pull") or [])
    want_rm = set(plan.get("remove") or [])
    if want_push:
        report["pushed"] = do_push(ctx, want_push, report)
    if want_pull or want_rm:
        st = build_status(ctx)
        pulls = [it for it in st["pull"] if it["rel"] in want_pull]
        for rel in want_pull - {it["rel"] for it in pulls if it["act"] == "pull"}:
            report["skipped"].append({"rel": rel, "why": "no longer needed / not safe any more (GitHub changed) - re-check"})
        report["pulled"] = do_pull(ctx, [it for it in pulls if it["act"] == "pull"], report)
        rm = [it["rel"] for it in st["gone"] if it["rel"] in want_rm]
        report["removed"] = remove_local(rm, report)
    if plan.get("update"):
        report["updated"] = update_repo(ctx, allow_code_merge=bool(plan.get("allowCodeMerge", True)), dry=False)
    record(ctx, report)
    return report


def do_push(ctx, wanted, report):
    for attempt in range(1, ps.MAX_ATTEMPTS + 1):
        if attempt > 1:
            ps.refresh(ctx)
        st = build_status(ctx)
        items = [it for it in st["push"] if it["rel"] in wanted]
        go = [it for it in items if it["act"] == "push"]
        # an analysis cell never goes up without the captures it was made from
        cells = {it["cell"] for it in go if it["area"] == "analysis"}
        extra = [it for it in st["push"] if it["act"] == "push" and it["area"] == "exports"
                 and it["kind"] != "delete" and it["cell"] in cells and it["rel"] not in wanted]
        if extra:
            log("  + {} capture file(s) added so the analysis travels with its data".format(len(extra)))
            go += extra
        if attempt == 1:
            for it in items:
                if it["act"] != "push":
                    report["skipped"].append({"rel": it["rel"], "why": it["why"]})
                    log("  held back: {}  - {}".format(it["rel"], it["why"]))
        if not go:
            log("  Nothing to push - GitHub already has it.")
            return 0
        writes, removes = [], []
        for it in [x for x in go if x["kind"] == "delete"]:
            removes.append(it["dest"])
        go_w = [x for x in go if x["kind"] != "delete"]
        for it in go_w:
            rel = it["rel"]
            area = AREAS[it["area"]]
            data = canon(area, rel, (BASE / rel).read_bytes())
            if it["kind"] == "ledger":
                remote = (ps.git(["cat-file", "blob", "HEAD:" + ctx.prefix + rel], ctx.sync, check=False).stdout or None)
                data = ps.merge_ledger(remote, data, ps.archived_on_github(ctx)[1]) or data
            writes.append((it["kind"], rel, it["dest"], data, area))
        for _, _, dest, data, _ in writes:
            dst = ctx.sync / dest
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
        if writes:
            ps.git(["add", "-f", "--pathspec-from-file=-", "--pathspec-file-nul"], ctx.sync,
                   stdin="\0".join(w[2] for w in writes))
        if removes:
            ps.git(["rm", "-q", "--cached", "--ignore-unmatch", "--pathspec-from-file=-", "--pathspec-file-nul"],
                   ctx.sync, stdin="\0".join(removes))
            for dpath in removes:
                try:
                    (ctx.sync / dpath).unlink()
                except OSError:
                    pass
        check_staged(ctx)
        counts = {}
        for it in go:
            counts[it["area"]] = counts.get(it["area"], 0) + 1
        msg = "Data: {} file(s) ({}) from {} [smart sync]".format(
            len(writes), ", ".join("{} {}".format(v, k) for k, v in sorted(counts.items())), ctx.computer)
        if removes:
            msg += " - {} deleted on request: {}".format(
                len(removes), ", ".join(r.rsplit("/", 1)[-1] for r in removes[:5]) + (" ..." if len(removes) > 5 else ""))
        ps.git(["commit", "-q", "-m", msg], ctx.sync, cfg=ctx.ident)
        for dpath in removes:
            if ps.git(["cat-file", "-e", "HEAD:" + dpath], ctx.sync, check=False).returncode == 0:
                ps.refresh(ctx)
                raise ps.SyncError("VERIFY FAILED - {} is still in the commit. Nothing was pushed.".format(dpath))
        for kind, rel, dest, data, area in writes:
            blob = ps.git(["cat-file", "blob", "HEAD:" + dest], ctx.sync).stdout
            if blob != data or (kind != "ledger" and data != canon(area, rel, (BASE / rel).read_bytes())):
                ps.refresh(ctx)
                raise ps.SyncError("VERIFY FAILED for {} - committed bytes differ from your file. Nothing was pushed.".format(rel))
        if ps.push_head(ctx):
            log("  Pushed {} file(s), byte-for-byte verified ({}){}.".format(
                len(writes), ctx.branch, "; deleted on GitHub: {}".format(len(removes)) if removes else ""))
            for dpath in removes:
                log("  DELETED ON GITHUB (recoverable from history): " + dpath[len(ctx.prefix):])
            return len(writes) + len(removes)
        log("  A teammate pushed at the same moment - redoing on top of theirs ({}/{})".format(attempt, ps.MAX_ATTEMPTS))
        time.sleep(1.5)
    raise ps.SyncError("GitHub kept changing during {} attempts - try again in a minute.".format(ps.MAX_ATTEMPTS))


def check_staged(ctx):
    toks = ps.nul_list(ps.git(["diff", "--cached", "--name-status", "-z", "--no-renames"], ctx.sync))
    bad = []
    for status, path in zip(toks[0::2], toks[1::2]):
        rel = path[len(ctx.prefix):]
        ok = status in ("A", "M", "D") and (
            any(rel.startswith(a + "/") and ps.is_area_payload(a, rel) for a in AREAS.values())
            or (rel.startswith(ps.CONFLICTS + "/") and rel.lower().endswith((".csv", ".png", ".json", ".md", ".log"))))
        if not ok:
            bad.append("{} {}".format(status, path))
    if bad:
        ps.git(["reset", "-q", "--hard"], ctx.sync)
        raise ps.SyncError("REFUSED - the commit would include something that is not data:\n  " + "\n  ".join(bad))
    if not toks:
        raise ps.SyncError("git staged nothing - nothing was pushed.")


def backup_dir():
    d = HOME / "sync_backup" / datetime.now().strftime("%Y%m%d_%H%M%S")
    d.mkdir(parents=True, exist_ok=True)
    return d


def do_pull(ctx, items, report):
    n, bk = 0, None
    order = {"exports": 0, "presets": 1, "logs": 2, "analysis": 3}
    for it in sorted(items, key=lambda x: order[x["area"]]):
        rel = it["rel"]
        src, dst = ctx.rroot / rel, BASE / rel
        data = src.read_bytes()
        dst.parent.mkdir(parents=True, exist_ok=True)
        if it["kind"] == "new":
            try:
                with open(dst, "xb") as f:
                    f.write(data)
            except FileExistsError:
                report["skipped"].append({"rel": rel, "why": "appeared on this laptop meanwhile - kept yours"})
                continue
        else:                                            # ledger / replace: back up yours, then swap atomically
            if bk is None:
                bk = backup_dir()
                report["backup"] = str(bk)
            b = bk / rel
            b.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dst, b)
            tmp = dst.with_name(dst.name + ".sync-tmp")
            tmp.write_bytes(data)
            os.replace(tmp, dst)
        if dst.read_bytes() != data:
            raise ps.SyncError("VERIFY FAILED copying " + rel)
        n += 1
    log("  Pulled {} file(s){}.".format(n, " (replaced files backed up in {})".format(bk) if bk else ""))
    return n


def remove_local(rels, report):
    if not rels:
        return 0
    bk = backup_dir()
    report["backup"] = report["backup"] or str(bk)
    for rel in rels:
        b = bk / rel
        b.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(BASE / rel), str(b))
        ps.prune_empty_dirs(rel)
    log("  Moved {} copy(ies) of GitHub-deleted files to {} (undo = copy back).".format(len(rels), bk))
    return len(rels)


def record(ctx, report):
    try:
        HOME.mkdir(parents=True, exist_ok=True)
        st = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {}
    except (OSError, ValueError):
        st = {}
    st[ctx.branch] = {"when": int(time.time()), "pushed": report["pushed"], "pulled": report["pulled"],
                      "updated": bool(report.get("updated") and report["updated"].get("ok"))}
    try:
        STATE.write_text(json.dumps(st), encoding="utf-8")
    except OSError:
        pass


# ------------------------------------------------------------ update-repo ---

def wt_blob(root, path):
    """Blob sha of the working file AS GIT WOULD STORE IT (your eol filters applied)."""
    p = g(["hash-object", "--path=" + path, "--", path], root, check=False)
    return out(p).strip() if p.returncode == 0 else None


def tree_map(root, rev):
    """{path: blob sha} of a whole commit - one call."""
    res = {}
    for ent in [x for x in out(g(["ls-tree", "-r", "-z", rev], root, check=False)).split("\0") if x]:
        meta, _, path = ent.partition("\t")
        res[path] = meta.split()[2]
    return res


def work_blobs(root, paths):
    """{path: blob sha of the working file as git would store it} - one call for all."""
    if not paths:
        return {}
    p = g(["hash-object", "--stdin-paths"], root, check=False, stdin="\n".join(paths) + "\n")
    shas = out(p).split()
    return dict(zip(paths, shas)) if p.returncode == 0 and len(shas) == len(paths) else {x: wt_blob(root, x) for x in paths}


def rev_blob(root, rev, path):
    p = g(["rev-parse", "-q", "--verify", "{}:{}".format(rev, path)], root, check=False)
    return out(p).strip() if p.returncode == 0 else None


def cat(root, sha):
    return g(["cat-file", "blob", sha], root).stdout


def plan_update(ctx):
    """What 'Update my folder' would do - read-only."""
    root, up = ctx.root, "origin/" + ctx.branch
    res = {"behind": 0, "ahead": 0, "obstacles": [], "canUpdate": True, "why": "", "mergeConflicts": []}
    lr = g(["rev-list", "--left-right", "--count", "HEAD..." + up], root, check=False)
    if lr.returncode != 0:
        return dict(res, canUpdate=False, why="branch not on GitHub")
    res["ahead"], res["behind"] = [int(x) for x in out(lr).split()]
    if not res["behind"]:
        return res
    mb = out(g(["merge-base", "HEAD", up], root)).strip()
    incoming = set(x for x in out(g(["diff", "--name-only", "-z", "--no-renames", mb, up], root)).split("\0") if x)
    dirty = {p: s for p, s in (getattr(ctx, "porc", None) or porcelain(root))}
    head_t, up_t = tree_map(root, "HEAD"), tree_map(root, up)
    # untracked + IGNORED files git would overwrite silently (not in status): checked too
    ign = {p for p in incoming if p not in dirty and p not in head_t and (root / p).is_file()}
    paths = sorted((set(dirty) & incoming) | ign)
    mine_t = work_blobs(root, [p for p in paths if (root / p).is_file()])
    for path in paths:
        theirs = up_t.get(path)
        mine_exists = path in mine_t
        mine = mine_t.get(path)
        base = head_t.get(path)
        ob = {"path": path, "status": dirty.get(path, "!!"), "data": is_data_path(ctx, path), "tracked": base is not None}
        if mine == theirs:
            ob.update(how="same", text="identical to GitHub's copy - nothing lost")
        elif ob["data"]:
            rel = path[len(ctx.prefix):]
            if rel.startswith(ps.ANALYSIS + "/"):
                ob.update(how="data", text="analysis - GitHub's copy is taken, yours backed up (re-analyse if needed)")
            else:
                ob.update(how="keepmine", text="data - your version is kept on top (backed up too)")
        elif not mine_exists:
            ob.update(how="keepmine", text="you deleted it, GitHub changed it - your delete is kept")
        elif base and theirs:
            ok, _ = three_way(root, path, base, theirs)
            ob.update(how="merge" if ok else "conflict",
                      text="your change and GitHub's merge cleanly - both kept" if ok
                      else "you and GitHub changed the SAME lines - needs a person (commit or undo yours first)")
        else:
            ob.update(how="conflict", text="a new file on both sides with different content - needs a person")
        res["obstacles"].append(ob)
    if res["ahead"]:
        # files both sides committed -> where a real merge could conflict
        mine_c = set(x for x in out(g(["diff", "--name-only", "-z", "--no-renames", mb, "HEAD"], root)).split("\0") if x)
        res["mergeConflicts"] = sorted(mine_c & incoming)
        # predict the merge for real (git >= 2.38; older git keeps the both-sides list above)
        mt = g(["merge-tree", "--write-tree", "--name-only", "--no-messages", "HEAD", up], root, check=False)
        if mt.returncode in (0, 1):
            clash = [x for x in out(mt).splitlines()[1:] if x.strip()]
            res["mergeConflicts"] = clash
            code = [x for x in clash if not is_data_path(ctx, x)]
            if code:
                res.update(canUpdate=False, why="your commits and GitHub's change the same code lines: " + ", ".join(code[:4])
                           + " - merge by hand (git pull), then sync again")
            elif clash:
                res["why"] = "{} data file(s) changed on both sides - resolved by rule (ledger rows merged, yours backed up)".format(len(clash))
    if any(o["how"] == "conflict" for o in res["obstacles"]):
        res.update(canUpdate=False, why="code conflict - see the list")
    return res


def three_way(root, path, base_sha, theirs_sha):
    """(clean?, merged bytes) of base -> mine (working file) + base -> theirs, eol-normalised."""
    mine_sha = out(g(["hash-object", "-w", "--path=" + path, "--", path], root)).strip()
    d = Path(os.environ.get("TEMP", "/tmp")) / "nis16_merge"
    d.mkdir(parents=True, exist_ok=True)
    fs = []
    for tag_, sha in (("mine", mine_sha), ("base", base_sha), ("theirs", theirs_sha)):
        f = d / tag_
        f.write_bytes(cat(root, sha))
        fs.append(str(f))
    p = subprocess.run(["git", "merge-file", "-p", "--quiet"] + fs, capture_output=True)
    return p.returncode == 0, p.stdout


def smudge(root, path, data):
    """Normalised bytes -> what checkout would write for `path` (your eol settings)."""
    sha = out(g(["hash-object", "-w", "--no-filters", "--stdin"], root, stdin=data)).strip()
    return g(["cat-file", "--filters", "--path=" + path, sha], root).stdout


def update_repo(ctx, allow_code_merge=True, dry=False):
    root, up = ctx.root, "origin/" + ctx.branch
    h = repo_health(ctx)
    if h["blocking"]:
        return {"ok": False, "why": " ".join(h["blocking"])}
    plan = plan_update(ctx)
    if not plan["behind"]:
        log("  Your folder already has everything GitHub has.")
        return {"ok": True, "why": "up to date", "changed": 0}
    if not plan["canUpdate"]:
        return {"ok": False, "why": plan["why"], "obstacles": plan["obstacles"]}
    if any(o["how"] == "merge" for o in plan["obstacles"]) and not allow_code_merge:
        return {"ok": False, "why": "code you changed is also changed on GitHub (merge not allowed)"}
    if dry:
        return {"ok": True, "dry": True, "plan": plan}

    bk = backup_dir()
    saved = []          # (path, bytes or None) - your working copies, for restore
    later = []          # (path, bytes) to write back after the update
    to_head = []        # tracked files to step back to HEAD's version - one checkout for all
    try:
        for ob in plan["obstacles"]:
            path = ob["path"]
            f = root / path
            if ob["how"] == "same" and ob["status"] == "!!":
                continue    # ignored + identical to GitHub's: git overwrites it with the same bytes
            mine = f.read_bytes() if f.is_file() else None
            if mine is not None:
                b = bk / path
                b.parent.mkdir(parents=True, exist_ok=True)
                b.write_bytes(mine)
            saved.append((path, mine))
            if ob["how"] == "merge":
                ok, merged = three_way(root, path, rev_blob(root, "HEAD", path), rev_blob(root, up, path))
                if not ok:
                    raise ps.SyncError("merge of {} is no longer clean".format(path))
                later.append((path, smudge(root, path, merged)))
            elif ob["how"] == "keepmine":
                later.append((path, mine))
            # step the file out of the way: back to HEAD's version (or gone if untracked)
            if ob.get("tracked"):
                to_head.append(path)
            elif f.exists():
                f.unlink()
        if to_head:
            g(["checkout", "HEAD", "--pathspec-from-file=-", "--pathspec-file-nul"], root, stdin="\0".join(to_head))
        log("  Backed up {} file(s) in the way -> {}".format(len(saved), bk))
        if plan["ahead"]:
            m = g(["merge", "--no-edit", up], root, check=False, cfg=ctx.ident)
            if m.returncode != 0:
                resolve_merge(ctx, bk)
        else:
            g(["merge", "--ff-only", up], root)
        for path, data in later:
            if data is None:
                p = root / path
                if p.exists():
                    p.unlink()
            else:
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_bytes(data)
        log("  Folder updated: +{} commit(s) from GitHub. Nothing lost - backup in {}".format(plan["behind"], bk))
        return {"ok": True, "changed": plan["behind"], "backup": str(bk), "kept": [p for p, _ in later]}
    except Exception as e:
        rollback(root, saved)
        return {"ok": False, "why": "rolled back - nothing changed: {}".format(e), "backup": str(bk)}


def resolve_merge(ctx, bk):
    """Data conflicts resolve by rule; ANY code conflict aborts the whole merge."""
    root = ctx.root
    um = [x for x in out(g(["diff", "--name-only", "-z", "--diff-filter=U"], root)).split("\0") if x]
    code = [p for p in um if not is_data_path(ctx, p)]
    if code:
        g(["merge", "--abort"], root, check=False)
        raise ps.SyncError("your commits and GitHub's change the same code: " + ", ".join(code[:5])
                           + " - merge it by hand (nothing was changed)")
    for path in um:
        rel = path[len(ctx.prefix):]
        name = rel.rsplit("/", 1)[-1]
        ours = g(["show", ":2:" + path], root, check=False).stdout
        if ours:
            b = bk / "merge_ours" / path
            b.parent.mkdir(parents=True, exist_ok=True)
            b.write_bytes(ours)
        if name in ps.LEDGERS:
            theirs = g(["show", ":3:" + path], root, check=False).stdout
            merged = ps.merge_ledger(theirs or None, ours or b"", set()) if ours else theirs
            (root / path).write_bytes(merged if merged not in (None, b"") else (theirs or ours))
        else:
            g(["checkout", "--theirs", "--", path], root, check=False)
            if not (root / path).exists() and ours:
                (root / path).write_bytes(ours)
        g(["add", "--", path], root)
    g(["commit", "--no-edit", "-q"], root, cfg=ctx.ident)
    log("  Merged: {} data conflict(s) resolved by rule (yours backed up in {}).".format(len(um), bk / "merge_ours"))


def rollback(root, saved):
    gitdir = Path(out(g(["rev-parse", "--absolute-git-dir"], root)).strip())
    if (gitdir / "MERGE_HEAD").exists():
        g(["merge", "--abort"], root, check=False)
    for path, data in saved:
        f = root / path
        if data is None:
            continue
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(data)


def abort_merge(ctx):
    root = ctx.root
    gitdir = Path(out(g(["rev-parse", "--absolute-git-dir"], root)).strip())
    if not (gitdir / "MERGE_HEAD").exists():
        log("  No unfinished merge.")
        return 0
    bk = backup_dir()
    for path, _ in porcelain(root):
        f = root / path
        if f.is_file():
            b = bk / path
            b.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, b)
    g(["merge", "--abort"], root)
    log("  Unfinished merge aborted - your folder is back to your last commit (your edits are kept; copies in {}).".format(bk))
    return 0


# ------------------------------------------------------------------- main ---

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["status", "apply", "update-repo", "abort-merge"])
    ap.add_argument("--json", action="store_true", help="status: print JSON only")
    ap.add_argument("--out", help="status: write the JSON to this file instead of stdout")
    ap.add_argument("--plan", help="apply: JSON file {push:[rel], pull:[rel], remove:[rel], update:bool}")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--branch", default=None)
    args = ap.parse_args()
    try:
        ctx = make_ctx(args.branch)
        if args.action == "status":
            st = build_status(ctx)
            txt = json.dumps(st)
            if args.out:
                Path(args.out).write_text(txt, encoding="utf-8")
            if args.json and not args.out:
                print(txt)
            elif not args.json:
                print("push {} / held {} / pull {} / behind {}".format(
                    sum(1 for i in st["push"] if i["act"] == "push"), sum(1 for i in st["push"] if i["act"] != "push"),
                    sum(1 for i in st["pull"] if i["act"] == "pull"), st["update"]["behind"]))
            return 0
        if args.action == "apply":
            plan = json.loads(Path(args.plan).read_text(encoding="utf-8-sig"))
            log("Smart sync on branch {} as {}".format(ctx.branch, ctx.computer))
            rep = apply(ctx, plan)
            log("RESULT " + json.dumps(rep))
            return 0 if not rep.get("updated") or rep["updated"].get("ok") else 2
        if args.action == "update-repo":
            r = update_repo(ctx, dry=args.dry_run)
            log("RESULT " + json.dumps(r, default=str))
            return 0 if r.get("ok") else 2
        if args.action == "abort-merge":
            return abort_merge(ctx)
    except ps.SyncError as e:
        log("\nERROR: {}".format(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
