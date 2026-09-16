# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 16, 2026 (PDR fixed; grid/window changed; stale attacker MAC found — re-run needed)

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
3. **REDO the sep. 16 15:36 `blackhole/linear/G402` run — it is unusable.** `BLACKHOLE_ATTACKER_MAC`
   was stale (`0c:80`) while the attacker board was `1c:38`, so victims P2P'd every probe to a board
   not in the mesh: root logged ZERO arrivals in all phases, PDR + ForwardingRatio 100% NaN. MAC is
   now fixed in `mesh_config.h` — **reflash EVERY board** (victims compile it in) before re-running.
4. Low priority: `menu.ps1`'s "Verify a run" lacks a `--scenario` question (hardcoded flat path).

## Blockers / open questions
- `presets/linear-blackhole-g402.json` is GONE, not in the Recycle Bin (picker deletes with
  `-Force`). Recovery: OneDrive's **online** recycle bin. `linear-blackhole-home.json` is current.
- **Two unreconciled panel-response tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06 DRAFT) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13, in-flight). Read both first.
- Fresh git history, uncommitted to remote; CC/NIS16-ESP32-Environment frozen refs.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 16, 2026 — **FIXED PDR** (it WAS a code bug — corrects an earlier "not a code bug" note):
  per-window attribution replaces the run-wide coverage gate, so `PDR==0` can finally be recorded
  (was 0 of 446 rows); also killed a `0/(0+EPSILON)` false-zero. thesis-deviate **D-8**. MEMORY.md.
- sep. 16, 2026 — Grid 1Hz→10Hz + window 5s→1s (**D-9**, 577→2,894 rows/run); attack/topology/
  location/scenario now columns on every row (**D-10**, fixes combine_all pooling scenarios). MEMORY.md.
- sep. 16, 2026 — Rewrote `ANALYSIS-Commands.md`; `analyze.ps1` gained a menu; archived twice
  (`pre-restart`, `mobility-run`) and reset the scaffold. MEMORY.md.
