# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 17, 2026 (heartbeat: instant disconnect reporting added — still NOT build-tested; re-run below untouched)

## Current focus
**Re-running the capture matrix from empty**, and the sep. 16 15:36 attempt must itself be redone —
a stale `BLACKHOLE_ATTACKER_MAC` silently voided it (see Next step 3). Pipeline work this session:
PDR attribution fixed (**D-8** — it could never record `PDR==0`, the blackhole's own signature),
analysis grid 1Hz→10Hz + window 5s→1s (**D-9**, 5× rows), and run identifiers now on every row
(**D-10**). Analysis/validation runs through `.\analyze.ps1` (menu or flags); docs rewritten in
`analysis/ANALYSIS-Commands.md`. Still PENDING, unrelated: root-as-blackhole-attacker for STAR —
designed, NOT built, team decides; plan at `C:\Users\Basti\.claude\plans\mutable-honking-spindle.md`.

## Next step
1. **Team decision first:** review the plan file and approve/adjust before any code is touched.
2. **Capture matrix is EMPTY and reset — start the re-run.** M4 = 24 attack runs (baseline not among
   them, D-5) ≈ 12k rows: 10k is reachable but thin, so protect it via capture QUALITY (clean run
   discards ~1%, the bad G402 one 44%). 6k rows/run needs Table 4.10 + D-1 changes — adviser call.
3. **REDO the sep. 16 15:36 `blackhole/linear/G402` run — it is unusable.** Stale
   `BLACKHOLE_ATTACKER_MAC` (`0c:80` vs actual `1c:38`) meant zero arrivals, PDR/ForwardingRatio
   100% NaN. MAC now fixed in `mesh_config.h` — **reflash EVERY board** before re-running.
4. Low priority: `menu.ps1` "Verify a run" lacks `--scenario`; its `b`-back still unwired.

## Blockers / open questions
- `presets/linear-blackhole-g402.json` is GONE, not in the Recycle Bin (picker deletes with
  `-Force`). Recovery: OneDrive's **online** recycle bin. `linear-blackhole-home.json` is current.
- **Two unreconciled panel-response tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13). Read both first.
- Command Center heartbeat (sep. 17): adds mesh traffic, UNCOMMITTED + NOT build-tested (this
  machine's idf5.3 Python venv is broken, unrelated — MEMORY.md). A multi-hop disconnect still
  can't report under ~21s (3 missed heartbeats); only the root's direct children get instant eviction.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 17, 2026 — **Heartbeat: instant disconnect reporting.** `CHILD_DISCONNECTED` evicts + reprints
  the root's direct child immediately; `ROUTING_TABLE_REMOVE` forces an immediate reprint for the
  multi-hop case (no MAC there, so it forces a PRINT but not an early EVICT). MEMORY.md.
- sep. 17, 2026 — **Command Center heartbeat revived + fixed** into `mesh_setup.c/.h`. Table
  reprints on change AND periodically; a stale node now logs OFFLINE and is EVICTED. Also fixed
  `mesh_setup_is_root()` root-gating + a timer-reset bug. Final: 7000/14000/21000ms. MEMORY.md.
