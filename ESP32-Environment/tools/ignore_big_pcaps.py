"""Keep sniffer captures over GitHub's 100 MB file limit out of git.

Captures (.pcap / .pcapng) are pushed with the data since nov. 1, 2026. GitHub
rejects any single file over 100 MB, and .gitignore cannot match by size, so
this tool lists every capture over the limit in a managed block of
ESP32-Environment/.gitignore and leaves every smaller capture pushable.

The block is rewritten on every run (a capture that was trimmed or deleted
drops out of it). A capture that git ALREADY tracks is not untracked by
.gitignore - the tool names it and prints the `git rm --cached` to run.

Stdlib only. Run from anywhere:
  python tools/ignore_big_pcaps.py            # rewrite the block
  python tools/ignore_big_pcaps.py --check    # list only, change nothing
"""
import argparse
import os
import subprocess
import sys

LIMIT_BYTES = 100 * 1024 * 1024          # GitHub's per-file hard limit
EXTS = (".pcap", ".pcapng")
ENV_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GITIGNORE = os.path.join(ENV_DIR, ".gitignore")
BEGIN = "# >>> pcaps over 100 MB (tools/ignore_big_pcaps.py) >>>"
END = "# <<< pcaps over 100 MB <<<"


def find_big():
    """Return [(rel_path, size)] for captures over the limit, relative to ENV_DIR."""
    big = []
    for root, dirs, files in os.walk(ENV_DIR):
        dirs[:] = [d for d in dirs if d not in (".git", "build")]
        for name in files:
            if name.lower().endswith(EXTS):
                path = os.path.join(root, name)
                size = os.path.getsize(path)
                if size > LIMIT_BYTES:
                    big.append((os.path.relpath(path, ENV_DIR).replace(os.sep, "/"), size))
    return sorted(big)


def rewrite_block(rel_paths):
    """Replace the lines between BEGIN and END with one anchored path each."""
    with open(GITIGNORE, encoding="utf-8", newline="") as f:
        text = f.read()
    eol = "\r\n" if "\r\n" in text else "\n"     # keep the file's own line endings
    lines = text.splitlines()
    if BEGIN not in lines or END not in lines:
        sys.exit("ERROR: managed block markers not found in %s - restore them first." % GITIGNORE)
    b, e = lines.index(BEGIN), lines.index(END)
    if e < b:
        sys.exit("ERROR: managed block markers are out of order in %s." % GITIGNORE)
    new = lines[:b + 1] + ["/" + p for p in rel_paths] + lines[e:]
    if new != lines:
        with open(GITIGNORE, "w", encoding="utf-8", newline="") as f:
            f.write(eol.join(new) + eol)
    return new != lines


def tracked(rel_paths):
    """Return the subset of rel_paths that git already tracks."""
    if not rel_paths:
        return []
    out = subprocess.run(["git", "ls-files", "--"] + rel_paths, cwd=ENV_DIR,
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("WARNING: git ls-files failed, cannot check tracked captures: %s" % out.stderr.strip())
        return []
    return [p for p in out.stdout.splitlines() if p]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="list captures over the limit, change nothing")
    args = ap.parse_args()

    big = find_big()
    for rel, size in big:
        print("OVER 100 MB  %7.1f MB  %s" % (size / 1024 / 1024, rel))
    if not big:
        print("No capture over 100 MB - every capture can be pushed.")

    paths = [rel for rel, _ in big]
    if args.check:
        return
    changed = rewrite_block(paths)
    print(".gitignore block %s (%d capture(s) ignored)." % ("updated" if changed else "already current", len(paths)))

    for rel in tracked(paths):
        print("ALREADY TRACKED - GitHub will reject it. Untrack it (file stays on disk):")
        print('  git rm --cached "%s"' % rel)


if __name__ == "__main__":
    main()
