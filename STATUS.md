# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 17, 2026 (SD-card provenance + wizard fixes — firmware NOT compiled yet; re-run below untouched)

## Current focus
**Re-running the capture matrix from empty**; the sep. 16 15:36 attempt must itself be redone — a
stale `BLACKHOLE_ATTACKER_MAC` silently voided it (Next step 4). This session was tooling, not
capture: SD cards now carry **provenance** (each `runs.csv` boot records the firmware's build
date/time; both wizards' import option [3] lists files with that date, so leftovers from an older
flash are obvious), plus `run_wizard.ps1` gained add/remove-node, save-back-to-preset, a no-preset
mode and 3 live-run fixes — MEMORY.md. Still PENDING: root-as-blackhole-attacker for STAR, designed
but NOT built — plan at `.claude\plans\mutable-honking-spindle.md` (Basti profile), team decides.

## Next step
1. **Build the firmware before any capture.** The build-stamp change (`sd_status.c`, `csv_logger.c`,
   `CMakeLists.txt` + `esp_app_format`) was never compiled — no ESP-IDF in that shell. Build/flash
   once; confirm the boot report shows `Firmware built:` and `runs.csv` gains a `built` column.
2. **Team decision:** review the root-as-attacker plan before any code moves.
3. **Capture matrix is EMPTY — start the re-run.** M4 = 24 attack runs (no baseline, D-5) ≈ 12k rows;
   10k is thin, so protect QUALITY (clean run discards ~1%, bad G402 44%). 6k/run needs T4.10 + D-1.
4. **REDO the sep. 16 15:36 `blackhole/linear/G402` run — unusable** (stale attacker MAC → zero
   arrivals, PDR 100% NaN). **Reflash EVERY board** first.

## Blockers / open questions
- `presets/*.json`: g402 one GONE (`-Force` delete; try OneDrive's **online** bin); other two show
  deleted in `git status`, deliberately NOT committed — recover or confirm intentional.
- `mesh_config.h` `BLACKHOLE_ATTACKER_MAC` → `f4:2d:c9:73:e6:18` (wizard pre-flight, mid-run);
  **uncommitted on purpose** — it names whichever board is the attacker right now.
- Heartbeat: mesh traffic, NOT build-tested, ~21s multi-hop floor. `menu.ps1`: no `--scenario` on
  "Verify a run", `b`-back unwired, no add/remove-node step.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13) — read both first.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 17, 2026 — **SD-card capture provenance**: build stamp → `runs.csv` `built` + status report;
  `import_sdcard.py --list-json`/`--files`; dated numbered file picker in both wizards. MEMORY.md.
- sep. 17, 2026 — **`run_wizard.ps1`**: add/remove node, save-back-to-preset, no-preset mode, 3
  live-run fixes (missing `Mac` crash, forced blackhole attacker, "Type 1-1"). MEMORY.md.
- sep. 17, 2026 — **Heartbeat: instant disconnect reporting**, `mesh_setup.c`. MEMORY.md.
