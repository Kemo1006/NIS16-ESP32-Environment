#!/usr/bin/env python3
"""Push capture CSVs, analysis output, run logs or saved presets to GitHub - data only, never code.

    python tools/push_data.py push                     raw capture CSVs under tools/exports/
    python tools/push_data.py push --area analysis     analysis + EDA output (feature_table,
                                                       windowed_dataset, eda_output/ plots)
    python tools/push_data.py push --area logs         saved run logs (.log) under run_logs/
    python tools/push_data.py push --area presets      your saved presets under presets/<you>/
    python tools/push_data.py pull                     fetch teammates' CSVs - never touches code
    python tools/push_data.py pull --area analysis     fetch teammates' analysis + EDA output
    python tools/push_data.py pull --area logs         fetch teammates' run logs
    python tools/push_data.py pull --area presets      fetch teammates' presets - never touches code
    python tools/push_data.py delete --area <area>     pick files to remove from GitHub (+ this laptop)
    python tools/push_data.py restore --area <area>    bring deleted files back from GitHub's history

A delete is an ordinary commit, so git history keeps every deleted file and
`restore` can always undo it. Only files GitHub has can be deleted here, which
is what keeps that promise. A teammate's next pull/push offers to remove their
copies of files deleted on GitHub (never automatic), and push never re-uploads
a file that was deleted on GitHub - restore it instead.

The branch is whichever one YOUR repo is checked out on (--branch overrides).
It used to be hardcoded, which quietly sent data to one branch while the code
that produced it sat on another.
    python tools/push_data.py test                     3 throwaway animal CSVs under sync_test/
    python tools/push_data.py test-cleanup             remove sync_test/ from GitHub and here

--area applies to push/pull only (default: exports); test/test-cleanup always use sync_test/.

All git work happens in a private partial clone under %LOCALAPPDATA%\\nis16-data-sync,
so your own folder is never stashed, checked out, merged or rebased (a
`git pull --autostash` on a folder with uncommitted code is what broke on
sep. 17, 2026). Each attempt rebuilds the data commit on top of the latest
GitHub state, so two people pushing different nodes never lose each other's files:

  * a file GitHub doesn't have yet            -> added
  * run_ledger.csv / test_ledger.csv           -> rows merged, both sides kept
  * same file, identical bytes                 -> skipped
  * your copy is an OLDER version on GitHub    -> skipped (not a conflict)
  * same name, different bytes                 -> BOTH kept; yours goes to
                                                  sync_conflicts/<computer>/...
  * already moved to archive/ on GitHub        -> not re-pushed into the live tree
  * inside an archive/ or _archive/ folder     -> never pushed; superseded capture
"""

import argparse
import hashlib
import os
import random
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
MARKER = "nis16-data-sync"
LEDGERS = {"run_ledger.csv", "test_ledger.csv"}
EXPORTS = "tools/exports"
TEST_AREA = "sync_test"
PRESETS = "presets"
ANALYSIS = "analysis"
# run_wizard.ps1's console transcripts, filed run_logs/<attack>/<topology>/<location>/<scenario>/.
# run_logs/_archive/ is the wizard's "Archive it" - in_archive() keeps it local.
LOGS = "run_logs"
CONFLICTS = "sync_conflicts"
MAX_ATTEMPTS = 5
# str.endswith() takes a tuple, so an area may accept several file types.
# ANALYSIS deliberately does NOT list .py/.txt: analysis/ holds the pipeline's
# own source (preprocess.py, eda.py, requirements.txt) right beside its output,
# and this tool must never move code. See is_area_payload() for the second half
# of that guard.
AREA_EXT = {
    EXPORTS: (".csv",),
    TEST_AREA: (".csv",),
    PRESETS: (".json",),
    ANALYSIS: (".csv", ".png", ".json", ".md"),
    LOGS: (".log",),
}
# Folders that mean "superseded capture, not live data". .gitignore already covers
# these, but a file committed before that rule existed stays --cached and would
# still be pushed into the live tree, so the sync path re-checks them by name.
ARCHIVE_DIRS = {"archive", "_archive"}
ANIMALS = ["Dog", "Cat", "Horse", "Cow", "Goat", "Sheep", "Pig", "Chicken", "Duck",
           "Rabbit", "Carabao", "Tarsier", "Eagle", "Turtle", "Monkey", "Deer"]


class SyncError(Exception):
    pass


def git(args, cwd, check=True, stdin=None, cfg=()):
    # autocrlf off everywhere: pushed bytes, verified bytes and locally staged
    # bytes must be identical or the byte-exact checks below mean nothing.
    cmd = ["git", "-c", "core.autocrlf=false", "-c", "core.safecrlf=false"]
    for c in cfg:
        cmd += ["-c", c]
    p = subprocess.run(cmd + list(args), cwd=str(cwd), capture_output=True,
                       input=stdin.encode("utf-8") if stdin is not None else None)
    if check and p.returncode != 0:
        raise SyncError("git {} failed:\n{}".format(
            " ".join(args), p.stderr.decode("utf-8", "replace").strip()))
    return p


def text(p):
    return p.stdout.decode("utf-8", "replace")


def nul_list(p):
    return [x for x in text(p).split("\0") if x]


def ask(question, yes):
    if yes:
        print(question + " y (--yes)")
        return True
    try:
        return input(question + " [y/N] > ").strip().lower() in ("y", "yes")
    except EOFError:
        return False


def rows(data):
    return max(len(data.splitlines()) - 1, 0)


def _fmt_size(n):
    if n >= 1024 * 1024:
        return "{:.1f} MB".format(n / (1024 * 1024))
    if n >= 1024:
        return "{:.0f} KB".format(n / 1024)
    return "{} B".format(n)


def tag(s):
    return re.sub(r"[^A-Za-z0-9-]", "-", s or "unknown").strip("-") or "unknown"


def current_branch():
    """The branch YOUR repo is checked out on, or None if there isn't one.

    Returns None on a detached HEAD, where `rev-parse --abbrev-ref HEAD` says
    the literal string "HEAD" -- which is not a branch and must never be pushed
    to as if it were.
    """
    p = git(["rev-parse", "--abbrev-ref", "HEAD"], BASE, check=False)
    if p.returncode != 0:
        return None
    name = text(p).strip()
    return None if name in ("", "HEAD") else name


class Ctx:
    def __init__(self, args):
        self.yes = args.yes
        # Follow the branch the operator is actually working on.
        #
        # This used to default to a fixed "Unified". That silently sent capture
        # data to one branch while the code that produced it lived on another,
        # so a teammate who checked out the working branch got the firmware but
        # not the CSVs, and the push output said "branch Unified" in a line that
        # is easy to read past. Data belongs beside the code that made it.
        #
        # An explicit --branch still wins, for the case where you really do mean
        # somewhere else.
        self.branch = args.branch or current_branch()
        self.branch_explicit = bool(args.branch)
        if not self.branch:
            raise SyncError(
                "Could not tell which branch to sync with: this repo is on a detached "
                "HEAD (no branch checked out).\n"
                "Check out a branch first (git switch <branch>), or say explicitly:\n"
                "  python tools/push_data.py {} --branch <branch>".format(
                    getattr(args, "action", "push")))
        self.root = Path(text(git(["rev-parse", "--show-toplevel"], BASE)).strip())
        self.prefix = text(git(["rev-parse", "--show-prefix"], BASE)).strip()
        self.url = text(git(["remote", "get-url", args.remote], BASE)).strip()
        name = text(git(["config", "user.name"], BASE, check=False)).strip()
        email = text(git(["config", "user.email"], BASE, check=False)).strip()
        if not name or not email:
            raise SyncError("git user.name / user.email are not set - run:\n"
                            "  git config --global user.name \"Your Name\"\n"
                            "  git config --global user.email you@example.com")
        self.ident = ("user.name=" + name, "user.email=" + email)
        self.computer = tag(os.environ.get("COMPUTERNAME")) + "_" + tag(os.environ.get("USERNAME"))
        if args.sync_dir:
            self.sync = Path(args.sync_dir)
        else:
            home = os.environ.get("LOCALAPPDATA") or str(Path.home() / ".cache")
            h = hashlib.sha1("{}|{}|{}".format(
                self.url, self.root, self.branch).encode()).hexdigest()[:10]
            self.sync = Path(home) / MARKER / h


# ------------------------------------------------------------ private clone ---

def require_remote_branch(ctx):
    """Check the branch exists on the remote before anything tries to clone it.

    ensure_clone() clones with --branch <name>; if the branch is local-only that
    fails with git's bare "Remote branch not found in upstream origin", which
    reads like the remote is broken rather than like "push your branch first".
    """
    p = git(["ls-remote", "--heads", ctx.url, ctx.branch], BASE, check=False)
    if p.returncode != 0 or text(p).strip():
        return
    if ctx.branch_explicit:
        # They named it, so don't lecture them about the branch they are on.
        raise SyncError(
            "Branch '{0}' does not exist on the remote, so there is nothing to sync "
            "data against.\n"
            "Check the name, or drop --branch to use the branch this repo is on "
            "({1}).".format(ctx.branch, current_branch() or "none - detached HEAD"))
    raise SyncError(
        "This repo is on branch '{0}', but that branch is not on the remote yet, so "
        "there is nothing to sync data against.\n"
        "Push the branch itself first:\n"
        "  git push -u origin {0}\n"
        "or sync the data somewhere that already exists:\n"
        "  python tools/push_data.py push --branch <existing-branch>".format(ctx.branch))


def ensure_clone(ctx):
    require_remote_branch(ctx)
    marker = ctx.sync / ".git" / MARKER
    if ctx.sync.exists():
        if not marker.exists():
            raise SyncError("{} exists but was not made by this tool - refusing to touch it.\n"
                            "Move it somewhere else and run again.".format(ctx.sync))
        git(["remote", "set-url", "origin", ctx.url], ctx.sync)
        apply_sparse(ctx)
        return
    ctx.sync.parent.mkdir(parents=True, exist_ok=True)
    print("  First run on this computer: making a small private copy of the repo (data folders only)...")
    git(["clone", "--quiet", "--filter=blob:none", "--no-checkout", "--single-branch",
         "--branch", ctx.branch, ctx.url, str(ctx.sync)], ctx.sync.parent)
    marker.write_text("created by tools/push_data.py - safe to delete\n")
    apply_sparse(ctx)


def apply_sparse(ctx):
    """(Re)declare which folders the private clone checks out.

    Called on EVERY run, not just at clone time: a clone made before a new area
    existed would otherwise never check that folder out, and the area would look
    permanently empty on the one machine that had synced before. `sparse-checkout
    set` is idempotent, so re-running it costs nothing.
    """
    git(["sparse-checkout", "set", "--cone",
         ctx.prefix + EXPORTS, ctx.prefix + TEST_AREA, ctx.prefix + PRESETS,
         ctx.prefix + ANALYSIS, ctx.prefix + LOGS, ctx.prefix + CONFLICTS], ctx.sync)


def refresh(ctx):
    git(["fetch", "--quiet", "origin",
         "+refs/heads/{0}:refs/remotes/origin/{0}".format(ctx.branch)], ctx.sync)
    git(["reset", "--hard", "--quiet", "origin/" + ctx.branch], ctx.sync)
    git(["clean", "-fdq"], ctx.sync)


def remote_tree(ctx, sub):
    return nul_list(git(["ls-tree", "-r", "-z", "--name-only", "HEAD", "--", ctx.prefix + sub], ctx.sync))


def push_head(ctx):
    p = git(["push", "--porcelain", "origin", "HEAD:refs/heads/" + ctx.branch], ctx.sync, check=False)
    if p.returncode == 0:
        return True
    msg = text(p) + p.stderr.decode("utf-8", "replace")
    if re.search(r"rejected|non-fast-forward|fetch first|stale info|cannot lock ref", msg):
        return False
    raise SyncError("git push failed (login / network / permission - not a teammate race):\n" + msg.strip())


def commit_checked(ctx, allowed, message, area, allow_delete=False):
    p = git(["diff", "--cached", "--name-status", "-z", "--no-renames"], ctx.sync)
    toks = nul_list(p)
    bad = []
    for status, path in zip(toks[0::2], toks[1::2]):
        ok_status = status in ("A", "M") or (allow_delete and status == "D")
        rel = path[len(ctx.prefix):]
        # sync_conflicts/ mirrors an area's files under a different root, so it
        # is checked on extension only -- the cell-depth rule below belongs to
        # analysis/ paths, and a conflict copy is not one.
        ok_ext = (is_area_payload(area, rel) if rel.startswith(area + "/")
                  else rel.lower().endswith(AREA_EXT[area]))
        ok_path = any(path.startswith(ctx.prefix + a + "/") for a in allowed) and ok_ext
        if not (ok_status and ok_path):
            bad.append("{} {}".format(status, path))
    if bad:
        git(["reset", "-q"], ctx.sync)
        raise SyncError("REFUSED - the commit would include something that is not capture data:\n  "
                        + "\n  ".join(bad) + "\nNothing was pushed.")
    if not toks:
        return False
    git(["commit", "-q", "-m", message], ctx.sync, cfg=ctx.ident)
    return True


# ----------------------------------------------------------------- planning ---

def is_area_payload(area, rel):
    """Is `rel` a RESULT file this area should sync, rather than code?

    Extension alone is enough for exports/presets, whose folders hold nothing
    else. analysis/ is different: the pipeline's source lives at its top level
    (eda.py, preprocess.py, analysis_README.md, requirements.txt) while results
    live under analysis/<attack>/<topology>/<location>/. Syncing on extension
    alone would push analysis_README.md and ANALYSIS-Commands.md as if they were
    data, and this tool's entire promise is that it never moves code.

    So analysis payload must additionally sit at cell depth -- at least
    analysis/<attack>/<topology>/<location>/<file>. Anything shallower is
    refused no matter what it is called.
    """
    if not rel.lower().endswith(AREA_EXT[area]):
        return False
    if rel.startswith(ANALYSIS + "/"):
        return len(rel.split("/")) >= 5
    return True


def local_files(area, ext=None):
    cmd = ["ls-files", "-z", "--cached", "--others"]
    if area not in (ANALYSIS, LOGS):
        cmd.append("--exclude-standard")
    # LOGS: same reasoning as below. The repo-root .gitignore ignores *.log, so
    # run logs never ride along in a code commit, but they are still team data.
    # in_archive() keeps run_logs/_archive/ from going up.
    # ANALYSIS is listed WITHOUT --exclude-standard on purpose. Its three
    # outputs -- feature_table.csv, windowed_dataset.csv and eda_output/ -- are
    # all in .gitignore (lines 64-66), because they are regenerated by
    # run.ps1 -Analyze and have no business in a CODE commit. But "don't commit
    # it with the source" and "don't share it with the team" are different
    # decisions, and a teammate who cannot rebuild your EDA plots locally still
    # needs to see them. This tool pushes into its own private clone, never into
    # your repo's index, so honouring .gitignore here would block the one thing
    # the area exists to do while protecting nothing.
    #
    # is_area_payload() is what keeps that safe: extension whitelist plus a
    # cell-depth rule, so the pipeline's own .py/.txt at analysis/ top level can
    # never ride along.
    p = git(cmd + ["--", area], BASE)
    return sorted(r for r in set(nul_list(p))
                  if is_area_payload(area, r) and (BASE / r).is_file())


def in_archive(rel):
    return any(part in ARCHIVE_DIRS for part in rel.split("/")[:-1])


def split_ledger(data):
    t = data.decode("utf-8")
    return t.splitlines(), ("\r\n" if "\r\n" in t else "\n")


def merge_ledger(remote, local, archived_rows):
    """None = headers differ (keep both files); b"" = nothing to add; else merged bytes."""
    l_lines, l_nl = split_ledger(local)
    if remote is None:
        keep = l_lines[:1] + [x for x in l_lines[1:] if x.strip() and x not in archived_rows]
        if keep == [x for x in l_lines if x.strip()]:
            return local
        return (l_nl.join(keep) + l_nl).encode("utf-8")
    r_lines, r_nl = split_ledger(remote)
    if r_lines[:1] != l_lines[:1]:
        return None
    have = set(r_lines)
    add = []
    for x in l_lines[1:]:
        if x.strip() and x not in have and x not in archived_rows:
            have.add(x)
            add.append(x)
    if not add:
        return b""
    return (r_nl.join(r_lines + add) + r_nl).encode("utf-8")


def archived_on_github(ctx):
    names = remote_tree(ctx, "archive")
    files = {n.rsplit("/", 1)[-1] for n in names if n.lower().endswith(".csv")} - LEDGERS
    ledger_rows = set()
    for n in names:
        if n.rsplit("/", 1)[-1] == "run_ledger.csv":
            blob = git(["cat-file", "blob", "HEAD:" + n], ctx.sync).stdout
            ledger_rows.update(split_ledger(blob)[0][1:])
    return files, ledger_rows


def older_version_on_github(ctx, repo_path, data):
    blob = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
    p = git(["log", "--no-abbrev", "--format=", "--raw", "HEAD", "--", repo_path], ctx.sync)
    return any(line.split()[3] == blob for line in text(p).splitlines() if line.startswith(":"))


def conflict_path(ctx, rel, data):
    stem, ext = os.path.splitext("{}/{}/{}".format(CONFLICTS, ctx.computer, rel))
    for i in range(1, 100):
        cand = ctx.prefix + stem + ("" if i == 1 else "_{}".format(i)) + ext
        p = ctx.sync / cand
        if not p.exists():
            return cand
        if p.read_bytes() == data:
            return None
    raise SyncError("too many conflict copies of " + rel)


def build_plan(ctx, area):
    archived_files, archived_rows = archived_on_github(ctx) if area == EXPORTS else (set(), set())
    deleted = deleted_on_github(ctx, area)
    writes, notes = [], {"same": 0, "older": [], "archived": [], "in_archive": [], "deleted": []}
    # One listing, then blob reads only for paths that are genuinely tracked.
    tracked = set(remote_tree(ctx, area))
    for rel in local_files(area, AREA_EXT[area]):
        if in_archive(rel):
            notes["in_archive"].append(rel)
            continue
        data = (BASE / rel).read_bytes()
        repo_path = ctx.prefix + rel
        name = rel.rsplit("/", 1)[-1]
        remote = (git(["cat-file", "blob", "HEAD:" + repo_path], ctx.sync).stdout
                  if repo_path in tracked else None)

        if name in LEDGERS:
            merged = merge_ledger(remote, data, archived_rows)
            if merged == b"":
                notes["same"] += 1
            elif merged is not None:
                writes.append(("ledger", rel, repo_path, merged))
                continue
            else:
                cpath = conflict_path(ctx, rel, data)
                if cpath:
                    writes.append(("conflict", rel, cpath, data))
            continue

        if remote is None:
            if name in archived_files:
                notes["archived"].append(rel)
            elif rel in deleted and older_version_on_github(ctx, repo_path, data):
                # Someone deleted exactly this file on GitHub. Pushing it as "new"
                # would silently undo their delete; restore is the explicit way back.
                notes["deleted"].append(rel)
            else:
                writes.append(("new", rel, repo_path, data))
        elif remote == data:
            notes["same"] += 1
        elif older_version_on_github(ctx, repo_path, data):
            notes["older"].append(rel)
        else:
            cpath = conflict_path(ctx, rel, data)
            if cpath is None:
                notes["same"] += 1
            else:
                writes.append(("conflict", rel, cpath, data))
    return writes, notes


def print_plan(writes, notes, area=EXPORTS):
    print("")
    labels = {"new": "NEW", "ledger": "LEDGER (rows merged)", "conflict": "KEEP BOTH (name clash)"}
    for kind in ("new", "ledger", "conflict"):
        items = [w for w in writes if w[0] == kind]
        if not items:
            continue
        print("  {} - {} file(s):".format(labels[kind], len(items)))
        for _, rel, repo_path, data in items:
            extra = "" if kind != "conflict" else "   -> saved as " + repo_path
            # Row counts only mean something for text. A PNG "has" as many
            # rows as it happens to contain 0x0A bytes, which is noise dressed
            # up as a measurement - show its size instead.
            measure = ("{} rows".format(rows(data)) if rel.lower().endswith((".csv", ".md", ".json"))
                       else _fmt_size(len(data)))
            print("    {}  ({}){}".format(rel, measure, extra))
    if notes["same"]:
        print("  already on GitHub, identical: {} file(s)".format(notes["same"]))
    if notes["older"]:
        print("  skipped - GitHub already has a NEWER version: {} file(s)".format(len(notes["older"])))
        for rel in notes["older"]:
            print("    " + rel)
    if notes["archived"]:
        print("  skipped - a teammate already moved these to archive/ on GitHub: {} file(s)".format(len(notes["archived"])))
        for rel in notes["archived"]:
            print("    " + rel)
    if notes["deleted"]:
        print("  skipped - DELETED from GitHub (by you or a teammate), not re-pushed: {} file(s)".format(
            len(notes["deleted"])))
        for rel in notes["deleted"]:
            print("    " + rel)
        print("    If that delete was a mistake, use 'restore' (wizard: Data sync -> Restore deleted data).")
    if notes["in_archive"] and area == LOGS:
        # Listed by count only: archiving a log is the operator saying "not this one".
        print("  skipped - archived run logs (run_logs\\_archive\\), kept local: {} file(s)".format(
            len(notes["in_archive"])))
    elif notes["in_archive"]:
        print("  skipped - superseded captures sitting in an archive folder, not live "
              "data: {} file(s)".format(len(notes["in_archive"])))
        for rel in notes["in_archive"]:
            print("    " + rel)
        print("    To share these anyway, move them under archive\\<date>_<label>\\exports\\ "
              "at the\n    repo root and commit them normally - this tool only syncs live captures.")


# ------------------------------------------------------------------ syncing ---

def sync_push(ctx, area):
    """Returns True if the push succeeded or there was nothing new, False if cancelled."""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        refresh(ctx)
        writes, notes = build_plan(ctx, area)
        if attempt == 1:
            print_plan(writes, notes, area)
        if not writes:
            print("\n  Nothing new to push - GitHub already has all of your {} data.".format(area))
            return True
        if attempt == 1 and not ask("\nPush {} file(s) to GitHub branch '{}'?".format(len(writes), ctx.branch), ctx.yes):
            print("  Cancelled - nothing was pushed.")
            return False

        for _, _, repo_path, data in writes:
            dst = ctx.sync / repo_path
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
        git(["add", "-f", "--pathspec-from-file=-", "--pathspec-file-nul"], ctx.sync,
            stdin="\0".join(w[2] for w in writes))
        if not commit_checked(ctx, [area, CONFLICTS],
                              "Data: {} {} file(s) from {}".format(len(writes), area, ctx.computer),
                              area):
            raise SyncError("planned {} file(s) but git staged nothing - nothing was pushed.".format(len(writes)))

        for kind, rel, repo_path, data in writes:
            blob = git(["cat-file", "blob", "HEAD:" + repo_path], ctx.sync).stdout
            if blob != data or (kind != "ledger" and data != (BASE / rel).read_bytes()):
                raise SyncError("VERIFY FAILED for {} - committed bytes differ from your file. "
                                "Nothing was pushed.".format(rel))

        if push_head(ctx):
            print("\n  Pushed {} file(s) to GitHub ({}), byte-for-byte verified.".format(len(writes), ctx.branch))
            return True
        print("  A teammate pushed first - redoing on top of their data ({}/{})...".format(attempt, MAX_ATTEMPTS))
        time.sleep(1)
    raise SyncError("GitHub kept changing during {} attempts - try again in a minute.".format(MAX_ATTEMPTS))


def stage_locally(rels):
    """A later normal `git pull` refuses to overwrite untracked files even when
    they are identical, so mark files that now match GitHub as staged here."""
    if not rels:
        return
    p = git(["add", "--pathspec-from-file=-", "--pathspec-file-nul"], BASE, check=False, stdin="\0".join(rels))
    if p.returncode == 0:
        print("  Staged {} data file(s) in your repo that now match GitHub, so a later "
              "'git pull' won't refuse to overwrite them.".format(len(rels)))
    else:
        print("  WARNING: couldn't stage the data files in your repo ({}).\n"
              "  A later 'git pull' may say they 'would be overwritten' - they're identical, "
              "so moving them aside and pulling is safe.".format(p.stderr.decode("utf-8", "replace").strip()))


def pull_back(ctx, area, yes):
    local_archived, archived_rows = set(), set()
    if area == EXPORTS and (BASE / "archive").is_dir():
        for folder, _, files in os.walk(BASE / "archive"):
            local_archived.update(files)
            if "run_ledger.csv" in files:
                archived_rows.update(split_ledger((Path(folder) / "run_ledger.csv").read_bytes())[0][1:])
        archived_rows.discard("")
    # A log this operator archived must not come back into the live list just
    # because the pushed copy is still on GitHub.
    if area == LOGS and (BASE / LOGS / "_archive").is_dir():
        for _, _, files in os.walk(BASE / LOGS / "_archive"):
            local_archived.update(files)

    incoming, ledgers, skipped_archived, matching, differ = [], [], 0, [], []
    skipped_nested = 0
    for repo_path in remote_tree(ctx, area):
        rel = repo_path[len(ctx.prefix):]
        if not is_area_payload(area, rel):
            continue
        # A teammate on an older copy of this tool could have pushed their local
        # archive folder into the live tree; don't seed it back into ours.
        if in_archive(rel):
            skipped_nested += 1
            continue
        name = rel.rsplit("/", 1)[-1]
        src, dst = ctx.sync / repo_path, BASE / rel
        if not dst.exists():
            if name in local_archived:
                skipped_archived += 1
            else:
                incoming.append(rel)
            continue
        remote, local = src.read_bytes(), dst.read_bytes()
        if remote == local:
            matching.append(rel)
        elif name in LEDGERS:
            r_lines, l_lines = split_ledger(remote)[0], split_ledger(local)[0]
            if archived_rows & set(r_lines[1:]):
                print("  ({} on GitHub still lists runs you archived - not copied)".format(rel))
                differ.append(rel)
            elif r_lines[:1] == l_lines[:1] and {x for x in l_lines if x.strip()} <= set(r_lines):
                ledgers.append(rel)
            else:
                differ.append(rel)
        else:
            differ.append(rel)

    if skipped_archived:
        print("  ({} teammate file(s) not copied - you already have them under archive\\)".format(skipped_archived))
    if skipped_nested:
        print("  ({} file(s) on GitHub sit in an archive folder - superseded, not copied)".format(skipped_nested))
    if incoming or ledgers:
        print("\n  Teammates' data on GitHub that you don't have yet:")
        for rel in incoming:
            print("    NEW     " + rel)
        for rel in ledgers:
            print("    LEDGER  {} (gains their rows, none of yours removed)".format(rel))
        if ask("Copy these into your folder? Existing capture files are never overwritten.", yes):
            for rel in incoming:
                dst = BASE / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                with open(dst, "xb") as f:
                    f.write((ctx.sync / (ctx.prefix + rel)).read_bytes())
            for rel in ledgers:
                tmp = BASE / (rel + ".sync-tmp")
                tmp.write_bytes((ctx.sync / (ctx.prefix + rel)).read_bytes())
                os.replace(tmp, BASE / rel)
            print("  Copied {} file(s).".format(len(incoming) + len(ledgers)))
            matching += incoming + ledgers
    else:
        print("  You already have all of your teammates' {} data.".format(area))
    # Not for analysis: those paths are .gitignore'd in the user's own repo on
    # purpose (rebuildable output), and staging them would slip derived files
    # into the code commits that rule exists to keep them out of. The reason
    # stage_locally() exists -- git refusing to overwrite untracked files on
    # pull -- does not apply to ignored ones, which checkout replaces freely.
    # LOGS: same - *.log is ignored by the repo-root .gitignore.
    if area not in (ANALYSIS, LOGS):
        stage_locally(matching)

    if differ:
        blocking = set(nul_list(git(["diff", "--name-only", "-z", "--relative", "HEAD", "--", area], BASE, check=False)))
        blocking |= set(nul_list(git(["ls-files", "-z", "-o", "--exclude-standard", "--", area], BASE)))
        differ = [r for r in differ if r in blocking]
    if differ:
        print("\n  HEADS UP - your copy of these differs from GitHub's, so a normal 'git pull' will")
        print("  refuse until you move yours aside (anything unique of yours is already on GitHub,")
        print("  under {}/{}/ for data files):".format(CONFLICTS, ctx.computer))
        for rel in differ:
            print("    " + rel)

    offer_local_removal(ctx, area, deleted_on_github(ctx, area))


# --------------------------------------------------------- delete / restore ---

def remote_payload(ctx, area):
    """The area's live data files on GitHub right now (repo-relative, sorted)."""
    out = []
    for repo_path in remote_tree(ctx, area):
        rel = repo_path[len(ctx.prefix):]
        if is_area_payload(area, rel) and not in_archive(rel):
            out.append(rel)
    return sorted(out)


def deleted_on_github(ctx, area):
    """{rel: (commit, when, subject)} for data files GitHub once had in `area` and no longer does.

    Newest deletion wins, so that commit's parent holds the last version. Ledgers
    are left out (rows only ever merge in), and so are captures that moved to
    archive/ - archiving is not deleting.
    """
    p = git(["log", "--diff-filter=D", "--name-only", "--date=format:%b %d %Y %H:%M",
             "--format=%x01%H%x09%ad%x09%s", "HEAD", "--", ctx.prefix + area],
            ctx.sync, cfg=("core.quotepath=off",))
    live = set(remote_tree(ctx, area))
    archived = archived_on_github(ctx)[0] if area == EXPORTS else set()
    out, cur = {}, None
    for line in text(p).splitlines():
        if line.startswith("\x01"):
            cur = tuple(line[1:].split("\t", 2))
            continue
        path = line.strip()
        if not path or cur is None or path in live:
            continue
        rel = path[len(ctx.prefix):]
        name = rel.rsplit("/", 1)[-1]
        if rel in out or name in LEDGERS or name in archived:
            continue
        if is_area_payload(area, rel) and not in_archive(rel):
            out[rel] = cur
    return out


def parse_picks(raw, n):
    """'1,3-5' / 'all' -> sorted 0-based indexes, or None if it doesn't parse."""
    raw = raw.strip().lower().replace(" ", "")
    if raw in ("a", "all"):
        return list(range(n))
    out = set()
    for part in raw.split(","):
        m = re.fullmatch(r"(\d+)(?:-(\d+))?", part)
        if not m:
            return None
        a, b = int(m.group(1)), int(m.group(2) or m.group(1))
        if a < 1 or b > n or a > b:
            return None
        out.update(range(a - 1, b))
    return sorted(out) or None


def prompt_picks(question, n, enter_means_all=False):
    """Indexes the operator typed; [] = cancelled (Enter, n, or end of input)."""
    while True:
        try:
            raw = input(question).strip().lower()
        except EOFError:
            return []
        if not raw:
            return list(range(n)) if enter_means_all else []
        if raw in ("n", "no", "q"):
            return []
        idx = parse_picks(raw, n)
        if idx is not None:
            return idx
        print("  Type numbers like 1 or 2,4-6, or 'all'.")


def narrow(rels, verb):
    """Show `rels` numbered; all of them by default, or just the ones typed."""
    print("")
    for i, rel in enumerate(rels, 1):
        print("    [{}] {}".format(i, rel))
    idx = prompt_picks("\n  {} ALL {} file(s) above? Enter = all, numbers = only those (e.g. 1,4-6), "
                       "'n' cancels > ".format(verb, len(rels)), len(rels), enter_means_all=True)
    return [rels[i] for i in idx]


def pick_by_folder(rels, verb):
    folders = []
    for rel in rels:
        f = rel.rsplit("/", 1)[0]
        if f not in folders:
            folders.append(f)
    print("\n  On GitHub now:")
    for i, f in enumerate(folders, 1):
        print("    [{}] {}/  ({} file(s))".format(i, f, sum(1 for r in rels if r.rsplit("/", 1)[0] == f)))
    idx = prompt_picks("\n  Which folder(s) to {} from? e.g. 1 or 2,4-5, 'all' - Enter cancels > ".format(
        verb.lower()), len(folders))
    if not idx:
        return []
    keep = {folders[i] for i in idx}
    return narrow([r for r in rels if r.rsplit("/", 1)[0] in keep], verb)


def prune_empty_dirs(rel):
    """Remove folders a local delete left empty, up to (never including) the repo folder."""
    d = (BASE / rel).parent
    while d != BASE and BASE in d.parents:
        try:
            d.rmdir()
        except OSError:
            break
        d = d.parent


def remove_local(rels):
    for rel in rels:
        (BASE / rel).unlink()
        prune_empty_dirs(rel)
    # Undo stage_locally()'s earlier `git add` too, or git status keeps listing a
    # staged file that no longer exists. Paths not in the index are ignored.
    for i in range(0, len(rels), 100):
        git(["rm", "-q", "--cached", "--ignore-unmatch", "--"] + rels[i:i + 100], BASE, check=False)
    print("  Deleted {} file(s) from this laptop.".format(len(rels)))


def offer_local_removal(ctx, area, deleted, picked=None):
    """Offer to delete this laptop's copies of files deleted on GitHub.

    Only copies whose bytes match a version GitHub still has in its history are
    offered, so every local delete here can be undone with restore. A copy that
    differs is yours alone and is always kept. Never automatic, even with --yes.
    """
    pool = picked if picked is not None else [r for r in local_files(area, AREA_EXT[area]) if r in deleted]
    safe, unique = [], []
    for rel in pool:
        p = BASE / rel
        if not p.is_file():
            continue
        (safe if older_version_on_github(ctx, ctx.prefix + rel, p.read_bytes()) else unique).append(rel)
    if safe:
        print("\n  Deleted from GitHub, but this laptop still has a copy:")
        for rel in safe:
            print("    " + rel)
        if ask("Delete these copies from this laptop too? (restore can bring them back)", False):
            remove_local(safe)
        else:
            print("  Kept. Push will not re-upload them.")
    if unique:
        print("\n  KEPT on this laptop - your copy differs from every version on GitHub, so deleting it")
        print("  could not be undone. Delete by hand if you are sure:")
        for rel in unique:
            print("    " + rel)


def delete_on_github(ctx, area):
    refresh(ctx)
    cands = [r for r in remote_payload(ctx, area) if r.rsplit("/", 1)[-1] not in LEDGERS]
    if not cands:
        print("\n  GitHub has no {} files to delete.".format(area))
        return
    picked = pick_by_folder(cands, "Delete")
    if not picked:
        print("  Cancelled - nothing was deleted.")
        return
    print("\n  {} file(s) will be removed from GitHub branch '{}'. They stay in GitHub's history:".format(
        len(picked), ctx.branch))
    print("  'restore' (wizard: Data sync -> Restore deleted data) brings them back any time.")
    try:
        ans = input("  Type DELETE to confirm > ").strip()
    except EOFError:
        ans = ""
    if ans != "DELETE":
        print("  Cancelled - nothing was deleted.")
        return

    for attempt in range(1, MAX_ATTEMPTS + 1):
        if attempt > 1:
            refresh(ctx)
        live = set(remote_tree(ctx, area))
        todo = [ctx.prefix + r for r in picked if ctx.prefix + r in live]
        if not todo:
            print("  Already gone from GitHub - nothing to delete there.")
            break
        for i in range(0, len(todo), 100):
            git(["rm", "-q", "--"] + todo[i:i + 100], ctx.sync)
        commit_checked(ctx, [area], "Data: delete {} {} file(s) from {}".format(len(todo), area, ctx.computer),
                       area, allow_delete=True)
        if push_head(ctx):
            print("\n  Deleted {} file(s) from GitHub ({}).".format(len(todo), ctx.branch))
            break
        print("  A teammate pushed first - redoing on top of their data ({}/{})...".format(attempt, MAX_ATTEMPTS))
        time.sleep(1)
    else:
        raise SyncError("GitHub kept changing during {} attempts - nothing was deleted.".format(MAX_ATTEMPTS))
    offer_local_removal(ctx, area, None, picked=picked)


def restore_from_github(ctx, area):
    refresh(ctx)
    deleted = deleted_on_github(ctx, area)
    if not deleted:
        print("\n  Nothing to restore - GitHub has no deleted {} files.".format(area))
        return
    by_commit = {}   # one entry per deleting commit; dicts keep log order = newest first
    for rel, info in deleted.items():
        by_commit.setdefault(info, []).append(rel)
    events = list(by_commit.items())
    print("\n  Deleted from GitHub (newest first):")
    for i, ((_, when, subject), rels) in enumerate(events, 1):
        print("    [{}] {}  {}  - {} file(s)".format(i, when, subject, len(rels)))
        for f in sorted({r.rsplit("/", 1)[0] for r in rels}):
            print("          {}/".format(f))
    idx = prompt_picks("\n  Restore which delete(s)? e.g. 1 or 1,3, 'all' - Enter cancels > ", len(events))
    if not idx:
        print("  Cancelled - nothing was restored.")
        return
    picked = narrow(sorted(r for i in idx for r in events[i][1]), "Restore")
    if not picked:
        print("  Cancelled - nothing was restored.")
        return

    for attempt in range(1, MAX_ATTEMPTS + 1):
        if attempt > 1:
            refresh(ctx)
            deleted = deleted_on_github(ctx, area)
        live = set(remote_tree(ctx, area))
        writes = []
        for rel in picked:
            path = ctx.prefix + rel
            if path in live or rel not in deleted:
                continue
            data = git(["cat-file", "blob", "{}^:{}".format(deleted[rel][0], path)], ctx.sync).stdout
            dst = ctx.sync / path
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
            writes.append(path)
        if not writes:
            print("  Already back on GitHub - nothing to restore there.")
            break
        git(["add", "-f", "--pathspec-from-file=-", "--pathspec-file-nul"], ctx.sync, stdin="\0".join(writes))
        commit_checked(ctx, [area], "Data: restore {} {} file(s) from {}".format(len(writes), area, ctx.computer),
                       area)
        if push_head(ctx):
            print("\n  Restored {} file(s) on GitHub ({}).".format(len(writes), ctx.branch))
            break
        print("  A teammate pushed first - redoing on top of their data ({}/{})...".format(attempt, MAX_ATTEMPTS))
        time.sleep(1)
    else:
        raise SyncError("GitHub kept changing during {} attempts - nothing was restored.".format(MAX_ATTEMPTS))

    copied, differ = [], []
    live = set(remote_tree(ctx, area))
    for rel in picked:
        path = ctx.prefix + rel
        if path not in live:
            continue
        data = git(["cat-file", "blob", "HEAD:" + path], ctx.sync).stdout
        dst = BASE / rel
        if dst.exists():
            if dst.read_bytes() != data:
                differ.append(rel)
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        with open(dst, "xb") as f:
            f.write(data)
        copied.append(rel)
    if copied:
        print("  Put {} file(s) back on this laptop.".format(len(copied)))
    for rel in differ:
        print("  KEPT your different local copy of " + rel)
    if area not in (ANALYSIS, LOGS):
        stage_locally(copied)


# -------------------------------------------------------------------- tests ---

def make_test_files(ctx):
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    folder = BASE / TEST_AREA / ctx.computer / stamp
    folder.mkdir(parents=True)
    rng = random.Random()
    for i in (1, 2, 3):
        lines = ["Animal,Sex"] + ["{},{}".format(rng.choice(ANIMALS), rng.choice(["Female", "Male"]))
                                  for _ in range(10)]
        (folder / "animals_{}.csv".format(i)).write_bytes(("\n".join(lines) + "\n").encode())
    ledger = BASE / TEST_AREA / "test_ledger.csv"
    if not ledger.exists():
        ledger.write_bytes(b"recorded_at,computer,folder\n")
    with open(ledger, "ab") as f:
        f.write("{},{},{}\n".format(datetime.now().isoformat(timespec="seconds"), ctx.computer, stamp).encode())
    print("  Made 3 test CSVs (10 rows each, Animal + Sex) in {}".format(folder))
    print("  and added one row to {}".format(ledger))


def test_report(ctx):
    per_computer = {}
    for repo_path in remote_tree(ctx, TEST_AREA):
        parts = repo_path[len(ctx.prefix) + len(TEST_AREA) + 1:].split("/")
        if len(parts) == 3:
            per_computer.setdefault(parts[0], set()).add(parts[1])
    ledger = ctx.sync / (ctx.prefix + TEST_AREA + "/test_ledger.csv")
    print("\n  === What GitHub has in sync_test/ right now ===")
    for comp, runs in sorted(per_computer.items()):
        print("    {}  - {} test run(s), {} CSV(s)".format(comp, len(runs), len(runs) * 3))
    if ledger.exists():
        print("  test_ledger.csv rows:")
        for line in split_ledger(ledger.read_bytes())[0][1:]:
            print("    " + line)
    if len(per_computer) < 2:
        print("\n  To prove two people don't overwrite each other: run this same test on a SECOND")
        print("  laptop without pulling first, then run it here again - both computers should be listed.")
    else:
        print("\n  PASS: {} computers' data are all on GitHub side by side.".format(len(per_computer)))


def test_cleanup(ctx):
    for attempt in range(1, MAX_ATTEMPTS + 1):
        refresh(ctx)
        tracked = remote_tree(ctx, TEST_AREA)
        if not tracked:
            print("  GitHub has no sync_test/ files.")
            break
        if attempt == 1 and not ask("Delete all {} sync_test/ file(s) from GitHub (every computer's)?".format(len(tracked)), ctx.yes):
            print("  Cancelled.")
            return
        git(["rm", "-r", "-q", "--", ctx.prefix + TEST_AREA], ctx.sync)
        commit_checked(ctx, [TEST_AREA], "Data: remove sync test files", TEST_AREA, allow_delete=True)
        if push_head(ctx):
            print("  Removed sync_test/ from GitHub.")
            break
        print("  A teammate pushed first - redoing ({}/{})...".format(attempt, MAX_ATTEMPTS))
    else:
        raise SyncError("GitHub kept changing during {} attempts - try again in a minute.".format(MAX_ATTEMPTS))

    local = BASE / TEST_AREA
    if local.is_dir() and ask("Also delete your local {} folder?".format(local), ctx.yes):
        shutil.rmtree(local)
        git(["rm", "-r", "-q", "--cached", "--ignore-unmatch", "--", TEST_AREA], BASE, check=False)
        print("  Deleted " + str(local))


# --------------------------------------------------------------------- main ---

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["push", "pull", "delete", "restore", "test", "test-cleanup"])
    ap.add_argument("--area", choices=["exports", "presets", "analysis", "logs"], default="exports",
                     help="what push/pull syncs: capture CSVs under tools/exports (default), "
                          "your saved presets under presets/<you>/, analysis + EDA output "
                          "under analysis/<attack>/<topology>/<location>/ (.csv/.png/.json/.md "
                          "only -- never the pipeline's own .py), or run_wizard.ps1's saved "
                          "run logs (.log) under run_logs/. Ignored by test/test-cleanup.")
    ap.add_argument("--yes", action="store_true", help="answer yes to every prompt")
    ap.add_argument("--no-pull-back", action="store_true", help="don't offer teammates' files afterwards")
    ap.add_argument("--branch", default=None,
                     help="branch to sync data on. Default: whatever branch YOUR repo is "
                          "currently on, so data follows the code you are working on. Pass "
                          "this only to push somewhere other than your current branch.")
    ap.add_argument("--remote", default="origin", help="remote in YOUR repo whose URL is used")
    ap.add_argument("--sync-dir", help="private clone location (default under %%LOCALAPPDATA%%)")
    args = ap.parse_args()

    try:
        ctx = Ctx(args)
        print("Data sync: {} -> {} (branch {})".format(ctx.computer, ctx.url, ctx.branch))
        print("Your own folder's code, staged changes and stashes are never touched.")
        ensure_clone(ctx)

        if args.action == "test-cleanup":
            test_cleanup(ctx)
            return 0

        area = {"presets": PRESETS, "analysis": ANALYSIS, "logs": LOGS}.get(args.area, EXPORTS)

        if args.action == "pull":
            refresh(ctx)
            pull_back(ctx, area, ctx.yes)
            return 0

        # Always interactive: which files go is typed, never assumed by --yes.
        if args.action == "delete":
            delete_on_github(ctx, area)
            return 0
        if args.action == "restore":
            restore_from_github(ctx, area)
            return 0

        if args.action == "test":
            area = TEST_AREA
            make_test_files(ctx)

        if not sync_push(ctx, area):
            return 0
        if not args.no_pull_back:
            pull_back(ctx, area, ctx.yes)
        if args.action == "test":
            test_report(ctx)
        return 0
    except SyncError as e:
        print("\nERROR: {}".format(e))
        print("Your code and working folder were not changed by the failed step.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
