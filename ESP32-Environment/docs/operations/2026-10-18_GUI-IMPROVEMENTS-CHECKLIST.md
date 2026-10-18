# GUI improvements (oct. 18, 2026) — checklist + notes

Review of the 10 GUI improvements plus the two features added after them (last-used preset,
smart alerts). Built while a live capture was running, so **nothing a run uses was touched**
(`run.ps1`, `export_logs.py`, `import_sdcard.py`, `gui_monitor.py`, firmware) and **no COM port
was opened** by any test.

**Legend:** ✅ verified by a test · 🔧 issue found in the review and fixed · ⏳ still to do · ℹ️ note / limit

## Before using it

- ⏳ **Run the GUI self-test when no capture is running**: `powershell -File run_gui.ps1 -SelfTest`
  in the FOREGROUND (a `Start-Process -Wait` launch gave a fake 0xC000013A). Not run during the
  capture on purpose: its stand-in Live run uses real port names (COM3…) and its import test lists
  USB ports.
- ⏳ Restart the GUI to load the new features (an open GUI keeps the copy it started with).
- ⏳ Commit. `run_gui.ps1` also holds another session's unfinished Trim/Archive redesign — commit
  it together with that work.

## The checklist

| # | Feature | Where | Status | Review notes |
|---|---|---|---|---|
| 1 | **Collect all children** — every plugged-in child's SD card, one port at a time; this run's newest clean file; filed under the run even when the card recorded another location | Live run end screen · wizard [31] · menu [19] · `tools/collect_run.py` | ✅ fake cards: wrong location, right location, other run, root · ✅ re-run skips · 🔧 fixed | 🔧 Over USB the card gives no row count → the "already imported?" check matched ANY file of that board, so **repeat r2 would have been skipped because r1 is in the same folder**. Now compares rows, or size ±3 % (the Data page's rule). ℹ️ Only boards on THIS laptop; a root's MAC is skipped; a file still being written is skipped. ℹ️ If you cancel the confirm, use the toast's "Import now" for the Data page. |
| 2 | **Real destination** on the Data page — names where the ticked files go; amber = only the location differs (Import asks to re-file), red = another run | Data page | ✅ parse · ⏳ self-test | ℹ️ The old line always showed your pick even though an import files by the CARD's folder (how ED80 landed in G402). |
| 3 | **Run summary** — per board: rows per phase, roles, one schedule, missing boards | pop-up after Import / Collect · wizard [32] · menu [20] · `tools/run_summary.py` | ✅ DLSU highload = COMPLETE 8/8 · ✅ blackhole/tree/G402/highload flagged (the #39 crashes) · ✅ benign run · ✅ window drawn | 🔧 Boards with every phase but a stalled length showed a green OK while the list below flagged them → now amber "look (see below)". 0.25 s per run. |
| 4 | **Pre-START checklist** on the START gate — children in, location, real clock, firmware built, attacker MAC (blackhole) / tunnel (wormhole), live "time in stabilise"; START asks only when a check FAILED | Live run → START gate | ✅ replayed on the real DLSU logs: flags the G402 card, asks before START, logs the stabilise length · 🔧 fixed | 🔧 "Firmware from this session" would false-alarm: an unchanged variant is not recompiled and keeps an older build time, and every board seen here was flashed by this run anyway → now information only. ℹ️ Only boards flashed on THIS laptop are seen (others = "…", never a failure). ℹ️ The stabilise length goes to the run log at Phase 0 (thesis A25). |
| 5 | **Pages refresh only when data changed** (Analyse page) | `gui/Stamps.ps1` | ✅ 60 ms scan of ~2,600 files · ✅ change / no-change | ℹ️ Analyse/Verify still refresh the page directly. |
| 6 | **Redo list re-checks only changed runs** (`redo_list.py --only`) | Campaign page · after Analyse / Verify | ✅ `--only` vs full = byte-identical output · ✅ 2 runs in 8 s (full ≈ 1 min) · 🔧 fixed ×2 | 🔧 A partial re-check kept the OLD verdict of a deleted run folder → it now drops the runs it re-checks first. 🔧 A new verification block / checklist row / campaign plan changes verdicts without touching data → those files now trigger a FULL re-check. Also: after Analyse / Verify only the changed run is re-checked (was always the full minute). |
| 7 | **Who holds a port** — "COM31 is held by idf.py monitor (PID …)" | Data page (USB list fails) · Live run (monitor can't open) · Collect failures | ✅ read-only process query · ✅ junk input | ℹ️ Runs only on a failure, never on a timer. |
| 8 | **Next step per run** — capture → import cards (k missing) → analyse → verify → done / redo | Campaign side panel · under each run on the Analyse page | ✅ DLSU highload "verify it", uncaptured "capture it", 8 boards expected from the preset · 🔧 fixed | 🔧 Added ~0.6 s to each Analyse refresh (presets folder listed once per run) → presets listed once (15 s cache) + plain .NET file calls: **0.09 s**. 🔧 Preset-named files (`child_node3_…`) carry no MAC → the board is read from the file's first row. |
| 9 | **Undo last import** — MOVES the newest import's files to `archive\_undone_imports\<stamp>\`, never deletes | Data page · wizard [33] · menu [21] · `Undo-ImportBatch` in `tools/ImportBatch.ps1` | ✅ moves 2/2, keeps them, a second undo does nothing · 🔧 fixed | 🔧 Undo only moves THIS laptop's copy: files already committed / on GitHub would come back with the next pull → undo now detects that (`git ls-files`) and says to delete them on GitHub too. ℹ️ The current record is the ED80 file at its old G402 path (moved by hand earlier) — an undo now would report "1 already gone" and move nothing. |
| 10 | **One file per GUI feature** in `gui\` — `run_gui.ps1` only has short hook lines | `gui/*.ps1`, loader near the top of `run_gui.ps1`, `Initialize-Gui*` at start-up | ✅ all 9 modules + `run_gui.ps1` parse · ✅ ASCII only (PS 5.1) | ℹ️ Existing pages were NOT moved out of `run_gui.ps1` — another session is editing it; new work goes in `gui\` from now on. |
| 11 | **Last used preset** — card on Run a capture (run, state, next step, "Show it"); the new-preset editor says if this run already has a preset (yours: saving replaces it · a teammate's: copy theirs) and what you used last | Run a capture · preset editor · `gui/LastPreset.ps1` · `.last_used_preset.json` (per laptop, git-ignored) | ✅ found the newest run log (DLSU burst) · ✅ editor note: "You already have…" + "Already made by Kyle" · ✅ drawn | ℹ️ Recorded when flashing starts / finishes / is stopped; before the first record it reads the newest run log. ℹ️ GUI only (CLI runs do not record it yet). |
| 12 | **Smart alerts** on the Live run dashboard — kind + icon, board chip, "do:" advice, repeats fold (×N), good news resolves problems, "during the capture" badge in baseline/attack, counts + All / Problems / Good filters | Live run → ALERTS FROM THE BOARDS · `gui/Alerts.ps1` | ✅ 10 checks (fold, resolve, chips, filters, new run = clean panel) · ✅ drawn · 🔧 fixed ×3 | 🔧 "back up after the crash" was classed CRASH (good news is now checked first). 🔧 "Attack phase started" was classed START ("started") → START is matched case-sensitively. 🔧 "WAITING: 6/7" got a board chip → chips only for real board labels. ℹ️ Only the new card is built (fade-in 0.26 s); nothing re-renders. The old list is still filled (the self-test reads it), just hidden. |

## Test record (oct. 18, ~5:30 PM)

- `test_modules.ps1` (scratch): **25/25** — stamps, next step, pre-START replay, port holder, undo.
- `test_ui2.ps1` (scratch, off-screen WPF): **15/15** — alerts, last-used card, editor note.
- `tools/test_wizard_nav.ps1`: **15/15** with the 3 new wizard items.
- `redo_list.py` full output before/after the `--only` change: identical (52 runs).
- `collect_run.py` on fake cards (no ports): OK / SKIP / FAIL cases as expected; size rule unit-tested.
- ⏳ `run_gui.ps1 -SelfTest`: pending — run when no capture is going.
