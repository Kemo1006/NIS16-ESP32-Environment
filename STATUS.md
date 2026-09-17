# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 17, 2026 (+ analysis pipeline hardening, arrivals-flush fix — pushed `a4f87b4`; capture-matrix re-run still not started)

## Current focus
**Re-running the capture matrix from empty**; TWO `blackhole/linear/G402` attempts are now known void
(Next step 4): sep. 16 (stale `BLACKHOLE_ATTACKER_MAC`) and sep. 17 (wrong board imported as "root",
real root `B0CBD8F33218`'s arrivals never pulled). Recent sessions were tooling only, not capture.
PENDING: root-as-blackhole-attacker for STAR — `.claude\plans\mutable-honking-spindle.md`, team decides.

## Next step
1. **Build firmware before any capture** — build-stamp + arrivals-flush fix both still uncompiled (no
   working ESP-IDF python env found yet); confirm `runs.csv` gains `built` and arrivals survive a test.
2. **Team decision:** review the root-as-attacker plan before any code moves.
3. **Capture matrix is EMPTY — start the re-run.** M4 = 24 attack runs (no baseline, D-5) ≈ 12k rows;
   protect QUALITY over 10k (clean run discards ~1%, bad G402 44%); 6k/run needs T4.10 + D-1.
4. **REDO `blackhole/linear/G402`** — reflash every board, then import all 4 cards incl. root
   `B0CBD8F33218` (move stray `*_2805A532D7B4_*` out of `tools/exports/` first).

## Blockers / open questions
- **Angelo Calpoporo's bootloader build fails** on Windows `MAX_PATH` (265 chars — MEMORY.md's "Failed
  approaches") — needs admin-rights answer: registry `LongPathsEnabled` vs. an `$env:ESP32_BUILD_ROOT` override.
- `presets/*.json`: g402 one GONE (`-Force` delete; try OneDrive's **online** bin); other two show
  deleted in `git status`, deliberately NOT committed — recover or confirm intentional.
- `mesh_config.h` `BLACKHOLE_ATTACKER_MAC` → `20:50:0d:e7:1c:38` ("attacker_5", wizard pre-flight,
  mid-run); **uncommitted on purpose** — names whichever board is the attacker right now.
- Heartbeat: mesh traffic, NOT build-tested, ~21s multi-hop floor. `menu.ps1`: no `--scenario` on "Verify a run", `b`-back unwired, no add/remove-node step.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13) — read both first.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 17, 2026 — **Analysis pipeline hardening**, pushed `a4f87b4`: "Run analysis only" now defaults
  to `trimmed\`, blocks on stale trim / missing root arrivals (PDR was silently NaN); fixed
  `csv_logger.c`'s arrivals-flush bug + a PS5.1 `ConvertFrom-Json` crash in the SD-import picker. MEMORY.md.
- sep. 17, 2026 — **"Trim exported CSVs only"** split into its own DATA menu option in both wizards
  (was missing entirely — "Run analysis only" never trimmed); `run_wizard.ps1` child-count prompt
  accepts `0` for a root-only capture. MEMORY.md.
- sep. 17, 2026 — **SD-card capture provenance**: build stamp → `runs.csv` `built` + status report;
  `import_sdcard.py --list-json`/`--files`; dated numbered file picker in both wizards. MEMORY.md.
