# Verification: "The docs entry point for this project is at `docs/2026-09-14_START-HERE.md`"

**Date:** sep. 30, 2026
**Verdict:** ❌ CONTRADICTED (as stated) — the file exists, but that path is no longer where it lives

## The claim

Someone said the project's onboarding/entry-point doc is located at
`ESP32-Environment/docs/2026-09-14_START-HERE.md`.

## What this means (plain language)

That exact path doesn't work anymore — if you (or a script, or a link in another doc) go looking there,
you'll find nothing. The file itself is fine and still the right place to start; it just moved into a
subfolder called `operations/` during a recent reorganization, so the correct path today is
`ESP32-Environment/docs/operations/2026-09-14_START-HERE.md`. This is a "your bookmark is outdated," not
a "the guide is gone" situation.

## Evidence

- **`test -f ESP32-Environment/docs/2026-09-14_START-HERE.md` → file not found.** (Ran the check directly
  against the real filesystem, not memory — the old path is empty.)
- **`test -f ESP32-Environment/docs/operations/2026-09-14_START-HERE.md` → file found.** The document is
  real and present, just under a new folder.
- **`git status --short` on both paths → `RM ...docs/2026-09-14_START-HERE.md -> ...docs/operations/2026-09-14_START-HERE.md`.**
  Git itself records this as a rename (a "git rename" is git's way of confirming this is the same file's
  history continuing under a new name/location, not a new file replacing a deleted one) — so this isn't
  two unrelated files, it's one file that was moved as part of a docs-folder reorganization dated sep. 30,
  2026. That move is currently **uncommitted** (staged locally but not yet pushed), which is why a
  teammate on another machine, or an older note, could still reasonably reference the pre-move path.
- **`CLAUDE.md:109`** — the project's own root instruction file already points at the new path:
  `Entry point: ESP32-Environment\docs\operations\2026-09-14_START-HERE.md`.
- **`FILEMAP.md:96, 179`** and **`ESP32-Environment/docs/README.md:47`** — the file map and the docs
  folder's own index both independently describe `operations/2026-09-14_START-HERE.md` as the current
  location, consistent with the CLAUDE.md reference above. Three independent sources agree.

## Conflicts between sources

None found — every source checked (filesystem, git, and all three of this project's own reference docs)
agrees on the new `operations/` path. The only thing "in conflict" is the claim itself against all of
them, which is exactly what makes this a clean CONTRADICTED rather than an ambiguous case.

## What remains unverified

Whether any *other* file in the repo (outside `CLAUDE.md`/`FILEMAP.md`/`docs/README.md`, which were
checked) still hardcodes the old pre-move path — this check looked at the authoritative reference docs
and the filesystem/git state, not every file in the tree. If a script or a teammate's local note points
at the old path, it would fail the same way this claim did.

## Sources

- `ESP32-Environment/docs/operations/2026-09-14_START-HERE.md` — the actual current file, on disk
- `CLAUDE.md:109` (this repo) — root instruction file's own "Entry point" line
- `FILEMAP.md:96` (this repo) — file map's description of the `operations/` folder
- `ESP32-Environment/docs/README.md:47` (this repo) — docs index's own entry for `operations/`
