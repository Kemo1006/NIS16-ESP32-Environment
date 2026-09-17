# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 18, 2026 — main-menu declutter + SD-picker delete + per-member preset folders BUILT (uncommitted, `run_wizard.ps1`/`menu.ps1`, PS-unit + stdin tested, no hardware touched); earlier run-log/SD-delete/menu-merge tooling still BUILT-not-flashed; data sync still PUSHED `0a356df`; capture re-run not started.

## Current focus
**Re-running the capture matrix from empty**; TWO `blackhole/linear/G402` attempts are void (step 6). Sep. 18 was tooling only, from teammates' feedback plus a new SD-cleanup ask — not capture.
PENDING: root-as-blackhole-attacker for STAR — `.claude\plans\mutable-honking-spindle.md`, team decides.

## Next step
1. **Reflash a board, then hardware-test today's new `DELETE_SD_PATH` command** (`run_wizard.ps1` "Delete a folder from a running board's SD card") before relying on it — it's build-clean but every board still runs older firmware, so it will report "no ack" until reflashed. Same reflash also carries the sep. 17 arrivals-flush-counter fix (also never build-tested until sep. 18).
2. **Prove the data sync laptop-to-laptop** before real captures: "Sync capture data with GitHub" → Test, here, then on a teammate's WITHOUT pulling first → both computers must be listed; `y` cleans up. Then real use: Push after an import, Pull for teammates' CSVs. (Menu item merged sep. 18 — same 3 actions, now one submenu.)
3. **Commit + field-test sep. 18 wizard work** (`run_wizard.ps1`, `menu.ps1`, `tools\Show-MemberBoards.ps1`, `tools\export_logs.py`, `tools\import_sdcard.py`, `components\mesh_common\src\csv_logger.c/h`, `member_boards.json`, untracked `member_boards\`). Test: preset on different USB sockets → MAC match; snapshot save/look/load/delete; SD-import skips `_archive\`. Now ALSO: member-board-list submenu (was 3 main-menu items); SD-picker `d1,3` delete-from-card; per-member preset folders (`presets\Bas\` etc.) + `my_member.txt` — hardware-untouched, only PS-unit + scripted-stdin tested so far.
   ⚠️ Blocked repo-wide by the unresolved preset conflict below — resolve that before any commit lands.
4. **Fill `member_boards.json`**: roles for Cal's 20:80 / F4:18, Bas's boards, confirm Kyle's `70:C8` + `28:B4` (photo hard to read).
   ⚠️ Hand-edited sep. 18 evening — Cal's `20:38 attacker` now sits under Kyle as `child_8`; confirm with the team whether that was intentional.
5. **Team decision:** root-as-attacker plan. Then start the re-run: M4 = 24 attack runs (no baseline, D-5) ≈ 12k rows; protect QUALITY over 10k (clean run discards ~1%, bad G402 44%).
6. **REDO `blackhole/linear/G402`** — reflash every board, import all 4 cards incl. root `B0CBD8F33218` (move stray `*_2805A532D7B4_*` out of `tools/exports/` first). The new `DELETE_SD_PATH` command (step 1) can now clear the card's stale `blackhole/linear/G402` folder first if wanted — PERMANENT, confirm the right board/folder before using it.

## Blockers / open questions
- ⚠️ **Local tree still mid-failed-pull (sep. 17):** `presets/linear-blackhole-none-g402.json` is an unresolved index conflict + `stash@{0}` orphaned → `git commit` blocked repo-wide until resolved. `0a356df` was pushed from a separate clean clone to sidestep it. This same file is also the one legacy unfiled preset under the new per-member folder scheme (its MACs resolve to Bas) — resolve the conflict, THEN file it via the picker's "File this preset under a member" option.
- **Angelo Calpoporo's bootloader build fails** on Windows `MAX_PATH` (265 chars) — needs admin answer: registry `LongPathsEnabled` vs. an `$env:ESP32_BUILD_ROOT` override.
- `presets/*.json`: g402 one GONE (`-Force` delete; try OneDrive's **online** bin); other two show deleted in `git status`, deliberately NOT committed — recover or confirm intentional.
- `mesh_config.h` `BLACKHOLE_ATTACKER_MAC` → `20:50:0d:e7:1c:38`; **uncommitted on purpose**. Heartbeat: mesh traffic, NOT build-tested, ~21s multi-hop floor. `menu.ps1`: no `--scenario` on "Verify a run", `b`-back unwired, no add/remove-node step, still has 3 separate data-sync menu items (run_wizard's merged sep. 18 — port over if desired).
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13).

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 18, 2026 — **Main-menu declutter + SD-picker delete + per-member preset folders** (uncommitted, `run_wizard.ps1`/`menu.ps1`): member-board-list collapsed to one submenu in both launchers; SD import picker gained `d1,3` = delete off the card (not just import); presets now filed one folder per member with owner auto-detected by MAC, `my_member.txt` remembers whose laptop this is, picker shows YOURS first. 21 PS-unit checks + scripted-stdin runs; NO hardware touched. ARCHIVE.md; MEMORY.md.
- sep. 18, 2026 — **Run-log saving + viewer, permanent SD-folder delete, `_archive` import fix, GitHub-sync menu merge** (uncommitted, `run_wizard.ps1`): built and build-clean (child+root firmware), NOT flashed/hardware-tested yet. See MEMORY.md for full detail incl. a testing mishap this session (harmless, cleaned up — nothing reached GitHub).
- sep. 18, 2026 — **Data-only GitHub sync PUSHED** (`0a356df`): `tools\push_data.py` + push/pull/test; raw capture CSVs only, private clone so no one's code moves, teammates' pushes merge instead of clobbering. Sim-tested (44 + 9 checks); NOT yet proven laptop-to-laptop. MEMORY.md.
