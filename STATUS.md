# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 17, 2026 (wizard/menu plan tables now show each board's MAC, pushed to GitHub; re-run below still untouched)

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
4. Low priority: `menu.ps1` "Verify a run" lacks `--scenario`; its `b`-back still isn't wired in (Recently done).

## Blockers / open questions
- `presets/linear-blackhole-g402.json` is GONE, not in the Recycle Bin (picker deletes with
  `-Force`). Recovery: OneDrive's **online** recycle bin. `linear-blackhole-home.json` is current.
- **Two unreconciled panel-response tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06 DRAFT) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13, in-flight). Read both first.
- Now pushed to `origin/Unified` (sep. 17, 2026) — no longer uncommitted; CC/NIS16-ESP32-Environment frozen refs still apply.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 17, 2026 — **`menu.ps1`'s multi-board flow gained run_wizard's pre-flash summary** (boxed
  Attack/Topology/Scenario/Location header, "Order (root is always last)" table, Exports/Analysis
  footer), and BOTH front-ends' plan tables now show each board's MAC (cached from a preset /
  Invoke-Identify / the blackhole precheck, else read live via `Resolve-BoardMac`). MEMORY.md.
- sep. 17, 2026 — **Fixed `cls` leaving a blank screen** in `run_wizard.ps1` + `menu.ps1`: the four
  numbered-menu functions (`Show-Menu`, `Show-CaptureWizardMenu`, `Read-Choice`, `Show-MainMenu`)
  now redraw their title/options after `Clear-Host` via a new `Read-Line -Redraw` scriptblock,
  instead of leaving just the one-line prompt. Committed + pushed to GitHub. MEMORY.md.
