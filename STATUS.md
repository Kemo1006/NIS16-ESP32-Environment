# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 17, 2026 (+ standalone trim menu option, root-only capture fix — firmware NOT compiled yet; re-run below untouched)

## Current focus
**Re-running the capture matrix from empty**; the sep. 16 15:36 attempt must itself be redone — a
stale `BLACKHOLE_ATTACKER_MAC` silently voided it (Next step 4). Recent sessions were tooling only
(SD provenance, wizard fixes, trim menu, root-only capture — MEMORY.md/Recently-done), not capture.
Still PENDING: root-as-blackhole-attacker for STAR, designed but NOT built — plan at
`.claude\plans\mutable-honking-spindle.md` (Basti profile), team decides.

## Next step
1. **Build the firmware before any capture** — build-stamp change never compiled (no ESP-IDF in that
   shell); confirm boot report shows `Firmware built:` and `runs.csv` gains `built`.
2. **Team decision:** review the root-as-attacker plan before any code moves.
3. **Capture matrix is EMPTY — start the re-run.** M4 = 24 attack runs (no baseline, D-5) ≈ 12k rows;
   protect QUALITY over 10k (clean run discards ~1%, bad G402 44%); 6k/run needs T4.10 + D-1.
4. **REDO sep. 16 15:36 `blackhole/linear/G402`** (stale attacker MAC → zero arrivals, PDR NaN) —
   reflash EVERY board first.

## Blockers / open questions
- **Angelo Calpoporo's bootloader build fails** on Windows `MAX_PATH` (265-char path, same bug class
  as MEMORY.md's "Failed approaches") — needs his admin-rights answer: registry `LongPathsEnabled`
  vs. a `run.ps1` `$env:ESP32_BUILD_ROOT` override for `subst`.
- `presets/*.json`: g402 one GONE (`-Force` delete; try OneDrive's **online** bin); other two show
  deleted in `git status`, deliberately NOT committed — recover or confirm intentional.
- `mesh_config.h` `BLACKHOLE_ATTACKER_MAC` → `f4:2d:c9:73:e6:18` (wizard pre-flight, mid-run); **uncommitted on purpose** — names whichever board is the attacker right now.
- Heartbeat: mesh traffic, NOT build-tested, ~21s multi-hop floor. `menu.ps1`: no `--scenario` on "Verify a run", `b`-back unwired, no add/remove-node step.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13) — read both first.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 17, 2026 — **"Trim exported CSVs only"** split into its own DATA menu option in both wizards
  (was missing entirely — "Run analysis only" never trimmed); `run_wizard.ps1` child-count prompt
  accepts `0` for a root-only capture. MEMORY.md.
- sep. 17, 2026 — **SD-card capture provenance**: build stamp → `runs.csv` `built` + status report;
  `import_sdcard.py --list-json`/`--files`; dated numbered file picker in both wizards. MEMORY.md.
- sep. 17, 2026 — **`run_wizard.ps1`**: add/remove node, save-back-to-preset, no-preset mode, 3
  live-run fixes (missing `Mac` crash, forced blackhole attacker, "Type 1-1"). MEMORY.md.
