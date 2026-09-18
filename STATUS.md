# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 18, 2026 — the day's tooling batch (topology graph, mesh layer-cap fix, CC heartbeat, per-member presets, run-log/SD-delete, data sync) PUSHED to `origin/Unified` (`1cf76e3`), resolving the sep. 17 conflict. Since then (uncommitted): a build-dir self-heal fix (`run.ps1`/`run_wizard.ps1`) and a presets-upload sync feature (`push_data.py`/`run_wizard.ps1`). Mid-session: root node hit a reboot loop during a live `blackhole/linear/G402` capture — diagnosed as a power brownout, NOT a firmware bug; that attempt is void.

## Current focus
**Re-running the capture matrix from empty**; `blackhole/linear/G402` now has at least THREE void attempts (two pre-existing + today's brownout loop) — worth checking whether the earlier two share the same root cause before the next try.
PENDING: root-as-blackhole-attacker for STAR — `.claude\plans\mutable-honking-spindle.md`, team decides.

## Next step
1. **Fix the root's power before the next capture attempt** — direct laptop USB port (never a shared hub), known-good short cable. Root cause is a brownout during WiFi/mesh radio startup, not code — see Blockers + MEMORY.md.
2. **Commit today's uncommitted code**: build-dir self-heal fix (`run.ps1`, `run_wizard.ps1`) and presets-upload sync (`tools\push_data.py`, `run_wizard.ps1`) — neither has been exercised against a real corrupted build dir / a real GitHub push yet.
3. **Prove the data sync laptop-to-laptop** before real captures: "Sync capture data with GitHub" → Test, here, then on a teammate's WITHOUT pulling first → both computers must be listed; `y` cleans up.
4. **Reflash + hardware-test `DELETE_SD_PATH`** (`run_wizard.ps1` "Delete a folder from a running board's SD card") — build-clean, never flashed. Same reflash carries the sep. 17 arrivals-flush-counter fix.
5. **Fill `member_boards.json`**: roles for Cal's 20:80 / F4:18, Bas's boards, confirm Kyle's `70:C8` + `28:B4` (photo hard to read); Cal's `20:38 attacker` was hand-moved to Kyle as `child_8` sep. 18 evening — confirm intentional.
6. **Team decision:** root-as-attacker plan, then restart the re-run: M4 = 24 attack runs (no baseline, D-5) ≈ 12k rows; protect QUALITY over 10k.

## Blockers / open questions
- **SD-card picker shows only `C:\`/`S:\`, no `D:\`** (`run_wizard.ps1`'s import flow, `Get-SdCardCandidates`) —
  checked live via both `Get-PSDrive` AND `[System.IO.DriveInfo]::GetDrives()`, both agree no `D:\`
  (or any removable drive) currently exists at the OS level — not a script bug, script reports Windows
  accurately. Waiting on user to confirm whether File Explorer also shows nothing for the reader
  (points at card/reader/driver) vs. shows a drive the script somehow still misses (would be a real bug).
- ⚠️⚠️ **ROOT REBOOT-LOOP (brownout) — verify the root's power before EVERY capture from now on.** sep. 18, 2026: boot count climbing every ~2s, `rst:0x3 SW_RESET`, garbled UART (abrupt reset) right as WiFi/mesh radio powers up. Root runs dual-radio (softAP+STA; children don't) plus a brownout detector at its most sensitive default — full diagnosis in MEMORY.md. Confirmed NOT caused by the same-session `MESH_STACK_MAX_LAYER_CHAIN=1000` change.
- **Angelo Calpoporo's bootloader build fails** on Windows `MAX_PATH` (265 chars) — needs admin answer: registry `LongPathsEnabled` vs. an `$env:ESP32_BUILD_ROOT` override.
- `mesh_config.h` `BLACKHOLE_ATTACKER_MAC` → `20:50:0d:e7:1c:38`; **uncommitted on purpose**. `menu.ps1` still has its own unmerged 3-item data-sync menu and wasn't given the presets-upload option either — both times scoped to `run_wizard.ps1` only per explicit request, port over if desired.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13).

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 18, 2026 — **Pushed** the sep. 18 tooling batch to `origin/Unified` (`1cf76e3`), resolving the sep. 17 index conflict (stale `presets/linear-blackhole-none-g402.json` superseded by `presets/Bas/...`). MEMORY.md; ARCHIVE.md.
- sep. 18, 2026 — **Build-dir self-heal fix** (uncommitted, `run.ps1`/`run_wizard.ps1`): auto-detect + wipe a build dir left half-configured by an interrupted `idf.py`. MEMORY.md.
- sep. 18, 2026 — **Presets upload/sync** (uncommitted, `tools\push_data.py`/`run_wizard.ps1`): data sync now covers saved presets, not just capture CSVs. MEMORY.md.
