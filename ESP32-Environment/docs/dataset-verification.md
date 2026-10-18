# Dataset Verification Log

Every time someone asks Claude to verify the datasets / analysis / EDA, one block is
added **at the top** (newest first). One block = one verification request, boxed by
`════` dividers and headed with its date and time.

**How to read a block:** the first table says WHICH data (attack · topology · location ·
scenario · repeat); the second says WHAT was checked and the result; then the details and
the verdict. ✅ = OK · ⚠️ = OK with a caveat / fixed · ❌ = not usable.

**Checks used:** `tools/validate_integrity.py` (files, sampling, phases) ·
`tools/verify_topology.py` (mesh shape, who is under the attacker) ·
`tools/verify_attack.py` (3-sigma attack test) · analysis tables vs exports ·
EDA plots (time series + PCA/t-SNE).

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #46 — Oct 18, 2026 · ~11:30 PM — verifier change: D-23 made outcome-blind + budget + robustness; regression sweep over every analysed capture

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `7f50858` + this change
> **Request:** "make the smart decision very clever as well and not cheating or biased"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 53 attack captures | every `datasets/analysis/<attack>/<topology>/<location>/<scenario>/feature_table.csv` (baseline cells skipped) + the 2 oct. 18 blackhole/tree/G402 archives |

| Check | Result | Detail |
|---|---|---|
| Old (`0e43f7e`, pre-D-23) vs new verifier, all 53 | ✅ 1 change | only the archived 7:21 PM blackhole/tree/G402/stationary r1: SETUP INVALID → CONFIRMED (2 TOLERATED, ROBUST) |
| Strictness kept | ✅ | blackhole/tree/G402/highload stays SETUP INVALID: B768 is a real VICTIM ↔ BYSTANDER flip |
| Outcome-blind | ✅ | the tolerate decision is identical with every attack PDR forced to 1.0 (unit test) |
| Re-join budget | ✅ FAIL fires | D7B4 forced detached 30 s (> 18 s) → FAIL |
| Robustness | ✅ both ways | real run: 156 s before the re-route confirm alone = ROBUST; signature moved to after the re-route = NOT ROBUST → FAIL |
| Phase comparison (new WARN) | ⚠️ 2 captures | blackhole/linear/home/highload and blackhole/tree/G402/highload: a board's class at the start of the cooldown differs from the attack (recovery measured in another layout) - information, verdicts unchanged |
| Verifier suite | ✅ 33/33 | 5 new (budget, robust, not robust, outcome-blind, GUI override line) |

**Verdict: ✅ the rule only changed the one run it was designed for, and it can only accept a re-route on layout
evidence fixed in advance.** The outcome is used once, to downgrade (robustness). Adviser sign-off: A26.

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #45 — Oct 18, 2026 · ~10:45 PM — verifier change: exposure-aware parent-change rule (D-23), re-run on the 7:21 PM blackhole/tree capture

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `0e43f7e` + this change
> **Request:** "lock the tree at START, or allow a changing parent? ... make it a smart decision - allow it if the change does not damage the dataset, check the topology differences"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | stationary | r1 | oct. 18, root 7:21 PM (archived 22:11 by the recapture) | `archive/2026-10-18_blackhole-tree-G402-stationary-r1-replaced-2/analysis/feature_table.csv` |

| Check | Result | Detail |
|---|---|---|
| [1] Attack signature (3-sigma) | ✅ 2/2 primaries | unchanged from #44 |
| D7B4 parent change | ⚠️ TOLERATED | F4:18 → (3 s detached) → attacker 1C38; VICTIM every window, PDR 0.00 |
| ED80 parent change | ⚠️ TOLERATED | F4:18 → (5 s detached) → D7B4; VICTIM every window, PDR 0.00 |
| Bystanders 0C80 / B768 / FE90 | ✅ | never under the attacker, PDR 1.00 |
| Negative test | ✅ FAIL fires | F4:18 moved under the root for the 2nd half of the attack → VICTIM↔BYSTANDER flip → FAIL (new unit test) |
| Verifier suite | ✅ 28/28 | 2 new tests (TreeReroute) |

**Verdict: ✅ BLACKHOLE CONFIRMED under the D-23 rule** (was NOT CONFIRMED - SETUP INVALID in #44). The re-routes were
ESP-MESH self-healing after F4:18 crashed; every moved board stayed behind the attacker, so the attack windows are one
experiment. This capture is already archived (replaced by the 10:11 PM recapture), so it is a fallback only. F4:18's
shortened attack (152 s, crash) stays footnoted (C12). Adviser sign-off on D-23 pending (A26).

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #44 — Oct 18, 2026 · ~8:30 PM — blackhole · tree · G402 · stationary r1 (recapture): why "signature PASS" but "SETUP INVALID"

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `fa545e3` + uncommitted
> **Request:** "check the blackhole tree G402 stationary validation notes - why it says it passes the attack signature but the setup is invalid, how is it possible"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | stationary | r1 | oct. 18, root 7:21 PM | the 8 files of #43 (F4:18 = card `r11_b18`), analysed 8:16 PM (GUI report `%LOCALAPPDATA%/NIS16/reports/blackhole__tree__G402__stationary.txt`) |

| Check | Result | Detail |
|---|---|---|
| Integrity | ✅ PASS | 7 PASS, 2 WARN: F4:18's attack 152 s / no cooldown (the crash, #43); the root saw F4:18 never return after the attack |
| [1] Attack signature (3-sigma) | ✅ 2/2 primaries | attacker ForwardingRatio 1.000 → 0.000, PDR 1.000 → 0.512; NeighbourForwardingRatio 0.999 → 0.000 confirms it from the neighbours; 3 victims behind the attacker PDR 1.0 → **0.0**, 3 boards above it stayed 1.0 |
| [3] Setup checks | ❌ 2 FAIL | **D7B4 and ED80 changed parent DURING the attack** - the attack windows mix two layouts |
| Why they moved | ⚠️ caused by the F4:18 crash | layout before the attack: root → **1C38 (attacker)** → **F4:18** → D7B4 (parent F4:2D:C9:73:E6:19) → ED80. F4:18 crashed at attack **+152 s**; at **+158 s** both D7B4 and ED80 show parent 00:00 (lost), then re-joined at +161 / +163 s (D7B4 under the attacker, ED80 under D7B4). Nothing moved during the baseline (Gate 2: "baseline re-routing free: YES"; it fails only on convergence - two logs start inside a phase) |
| Topology gate | ⚠️ FAIL | "converged within 60 s: NO" for D7B4 / ED80 (late moves during the attack) - same cause |

**Verdict: ❌ NOT CONFIRMED - SETUP INVALID (correct, not contradictory).** The signature test asks "did the attacker's
path lose its traffic?" - yes, clearly. The setup check asks "did the attack run in ONE layout?" - no: the victim under the
attacker crashed 152 s in and took its two children with it, so the last ~22 s of the attack are a second layout. The
verifier's rule is strict on purpose. Recapture once the victim crash (C12 / D9) is understood - or ask the adviser whether
a verdict on the attack window BEFORE the first parent change is acceptable (that would be a method change → D-entry).

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #43 — Oct 18, 2026 · ~8:15 PM — blackhole · tree · G402 · stationary r1 (recapture): 20:38 + F4:18 export warnings vs their SD cards

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `fa545e3` + uncommitted
> **Request:** "I have warning and issues on exporting 20:38 and F4:18 - look at the exported files and the board files itself to compare which one is the correct one"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | stationary | r1 | oct. 18, children flashed 6:28–6:35 PM, root 7:21 PM, root export 7:38 PM | root + 7 children in `exports/blackhole/tree/G402/stationary/` (the Sept 30 r1 was archived the same evening, see `archive/2026-10-18_blackhole-tree-G402-stationary-r1-replaced/`) |

| Check | Result | Detail |
|---|---|---|
| 20:38 (attacker 1C38) export vs card (COM33) | ✅ correct file | export = card `r5_b11`, the only clean file (9,347 rows, byte-identical 821,000 B); `r4_b10` / `r2_b8` = earlier attempts, POWERON-aborted |
| 20:38 "attack 214 s / cooldown 156 s" warning | ✅ not a problem | the first **742 rows** (phase 1 for 33 s, phase 3 for 41 s) are the TAIL of an earlier root attempt the board heard before the 7:21 PM root; then 255 → 0 (300 s) → 1 (180 s) → 3. `preprocess.py`'s root-restart rule marks everything before the last 255 that follows a real phase as `pre_baseline` (excluded). `trim_run.py` does NOT cut it (one boot session) - the analysis does. `run_summary.py` now applies the same rule (shows it as a NOTE) |
| F4:18 (E618) export vs card (COM9) | ❌ wrong piece exported → 🔧 replaced | the board booted **8×** this session; 2 boots ended by **PANIC**. The exported file = card `r12_b19` (the only CLEAN one): 19 s of attack + cooldown after a crash, **no baseline** (1,397 rows). Card `r11_b18` (ended by PANIC, 6,880 rows) = stabilise 235 s + **baseline 300 s** + **attack 152 s** → now in exports; `r12_b19` moved to `archive/2026-10-18_blackhole-tree-G402-stationary-r1-F418-tail-piece/` (+ REPLACED.txt) |
| Where F4:18 sat | ⚠️ finding | parent during the whole file = **20:50:0D:E7:1C:39 (the attacker)** at layer 3: the victim directly under the blackhole **crashed 152 s into the attack** - same pattern as verification #39 (blackhole/tree/G402/highload: victims PANIC / INT_WDT, D9) |
| Run summary after the swap | ⚠️ | 7 boards complete (baseline 300 s, attack 180 s, cooldown 120 s); F4:18 = baseline + 152 s of attack, no cooldown |

**Verdict: ⚠️ USABLE WITH A FOOTNOTE - not yet analysed / verified.** 20:38's export was right (its old-attempt prefix is excluded by the
analysis). F4:18's export was the wrong boot piece and is replaced by the one with the baseline. F4:18 - the victim under the attacker -
crashed during the attack: its attack data stops at 152 s. Report it (checklist C12) and treat it together with D9 (victim crashes under
blackhole): decide recapture vs footnote after the crash cause is known.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #42 — Oct 18, 2026 · ~4:10 PM — wormhole · linear · DLSU_Library · highload r1: Data page "OTHER RUN" + every board's SD file

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `ac68a5e` + uncommitted
> **Request:** "check the data page why the list ... tag a correct data as other run tag. check each board to verify it and know the other run is the correct data"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | linear | DLSU_Library | highload | r1 | oct. 18, children flashed ~2:57–3:03 PM, root 3:25 PM, TERMINATE ~3:37 PM | root telem + arrivals (USB export) + 7 children telem from their SD cards (`exports/wormhole/linear/DLSU_Library/highload/`) |

| Check | Result | Detail |
|---|---|---|
| Why "OTHER RUN" | ⚠️ cards had the wrong site | Every card's `location.txt` still said **G402** (left from oct. 17), so all 7 children filed the run under `wormhole/linear/G402/` on the card. The root's boot report says the same: `Recorded location: G402`, although run.ps1 got `-Location DLSU_Library`. The Data page was right to flag it: an import would have gone into the REAL G402/highload cell (oct. 17 r1) |
| Same run on every board | ✅ | 7 clean files (`runs.csv` clean), all from the 14:51–14:52 flash, booted 14:57–15:03, closed at TERMINATE. COM31 (root) could not be listed (port busy); its data came over USB |
| Phases per board (copied off the card, read with pandas) | ✅ complete | FE90, E618, ED80, D7B4, B768: 6,387 rows, phase 0 ≈ 3,005, phase 2 = 1,806, phase 3 = 1,206; 0C80 (B): 6,129 rows; 1C38 (A): 6,867 rows, same phase counts. Span 613–687 s |
| Tunnel roles | ✅ | 0C80 = `wormhole_b` all run; 1C38 = `wormhole_a` in phases 0/2/3 (`wormhole_b` for 6 stabilise rows only, before the auto pick). Root table at TERMINATE: B H05, A H02, UART OK both, shortcut 3 hops |
| Root export | ✅ | 7,218 telem rows + 16,210 arrival rows, already under DLSU_Library (USB export uses -Location) |
| ED80 imported earlier by the user | ✅ moved | `victim_NODE-B4BFE934ED80_..._oct18_0356PM_telem.csv` had been filed into **G402/highload**; byte-identical to the card copy; moved to DLSU_Library/highload. G402/highload analysis (1:19 AM) predates it - not contaminated |
| ℹ️ 1C38 size | ℹ️ | card manifest 6,869 rows / 605,677 B, copy 6,867 rows / 605,493 B (the import counts only complete rows) |

**Verdict: ✅ CORRECT DATA - USABLE (filed by operator).** All 8 boards hold one complete wormhole/linear/highload run; only the site
label on the cards was wrong. The 6 other children were copied off the cards and filed under DLSU_Library together with ED80. **Not analysed yet.**
Thesis footnote (checklist C11): location for this capture comes from the operator / preset / run log, not from `location.txt`.
Fix so it cannot recur: run.ps1 now checks + rewrites `location.txt` before every flash (`export_logs.py --ensure-location`), the
GUI alerts on a mismatched boot report, and the Data page offers "file under the picked location" (`import_sdcard.py --file-location`).

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #41 — Oct 18, 2026 · ~4:40 AM — CODE AUDIT: hardcoded / forced / fake values (firmware, analysis, verifier, tools)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `1ebd623` + uncommitted (one comment fix)
> **Request:** "can you check if there is hardcoded in our code and forced or fake"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | all | - (code, not one capture) | firmware `child_node/`, `root_node/`, `components/mesh_common/`; `analysis/*.py`; `tools/*.py`; `run.ps1`, `run_wizard.ps1`, `run_gui.ps1`; plus a scan of `datasets/exports`, `datasets/analysis`, `datasets/run_logs` |

| Check | Result | Detail |
|---|---|---|
| Fake / synthetic data | ✅ none in the data | `analysis/generate_fake_data.py` + `generate_eda_fake_data.py` are TEST generators: they write to `fake_data/` / `eda_fake_data/` (not `datasets/`) with names like `NODE_VICTIM01_RUN_001_telem.csv`; no such file or folder exists anywhere in `datasets/`; no `random` in preprocess / features / exposure / eda. ⚠️ minor: the generator stamps two REAL board MACs (`28:05:A5:32:D7:B4`, `1C:C3:AB:FA:54:98`) on its fake rows - only a risk if a fake file were renamed into `datasets/` |
| Gap filling (made-up samples) | ✅ bounded + marked | linear interpolation / forward-fill of at most 2 samples (0.2 s, `MAX_INTERP_GAP_SAMPLES`), every filled point flagged `_was_missing`, a window needs ≥ 8 of 10 REAL samples (Section 4.2.4.1); `rssi_dbm == 0` (no parent) is treated as missing, not as a reading |
| Labels (gt_label / phase) | ✅ from the hardware | set by the root's phase broadcasts (`phase_listener.c`), not by the analysis; `PHASE_*_S` lengths are READ from `mesh_config.h` (`mesh_config_int`) in preprocess + validate_integrity, not copied |
| Firmware randomness | ✅ by design | only `esp_random()` in `root_main.c` for the **jitter** scenario (adds extra seconds to phases); nothing else simulated |
| Forced verdicts | ✅ none | real 3-sigma test; protections against fake significance: MIN_EFFECT (≥ 0.10 change), ≥ 6 attack points, setup checks can turn CONFIRMED into SETUP INVALID; a verification-log ✅ can never clear a verifier REDO (`redo_list.py` severity = worst reason) |
| Hardcoded per-run / per-board special cases | ✅ none | no MAC, run name, date or location is special-cased in `analysis/` or the verifier; no hand-written exclusion / "OK" lists; EDA/leakage exclusions are rule-based and printed with their reason |
| Hardcoded MACs | ⚠️ 2 known | `BLACKHOLE_ATTACKER_MAC` in `mesh_config.h` = the wizard's per-laptop compiled fallback (boards can override in NVS; deliberately never pushed). `WORMHOLE_NODE_A_MAC` = DEAD constant (wired UART tunnel, A/B auto-switch) - unused, misleading only |
| Hardcoded paths / COM ports | ✅ | only in comments and in the GUI self-test's pretend boards; self-test turns "save a run log" OFF (no fake logs in `datasets/run_logs`, checked) |
| Dry run | ✅ | writes nothing (only prints WOULD …) |
| Verifier thresholds (hand-picked) | ⚠️ not in the paper | `BASELINE_FLOOR` 0.90, `BASELINE_DISPERSION_CEILING` 0.15, `MIN_EFFECT`, `MIN_ATTACK_POINTS` 6, 5-window blocks, and **CONFIRMED = ≥ 1 primary passes**; a broken-baseline primary is EXCLUDED, not a FAIL → checklist **B-rules**. Stale code comment said the floor was 0.50 → corrected (comment only; value was raised 0.50→0.90 on purpose, ARCHIVE.md); `test_verify_attack.py` 21/21 OK |
| START_ANYWAY (gate override) | ⚠️ invisible to the verifier | the root logs it only to serial (the run log), not to the SD CSVs → a forced-start run could be CONFIRMED with no flag. Scan of this laptop's `datasets/run_logs/`: 0 real uses (all 10 hits are help text). Runs without a saved run log cannot be checked → checklist **B-force** |

**Verdict: ✅ NO FAKE OR FORCED DATA; ⚠️ 2 disclosure gaps.** Nothing fabricates, simulates or forces values into the dataset or the verdicts;
gap-filling and labelling are bounded, marked and hardware-sourced. To fix before the paper: state the verifier's extra rules (B-rules) and
make START_ANYWAY runs traceable (B-force - footnote, or add a run-log check to the verifier). Optional cleanup: delete the dead
`WORMHOLE_NODE_A_MAC`, use made-up MACs in the fake-data generator.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #40 — Oct 17, 2026 · ~10:10 PM — wormhole · linear · G402 · stationary r1 (oct. 14 3:02 PM recapture)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted
> **Request:** "linear G402 stat has warning and it says I need to verify it but when I verify it still the warning persist"
> (Campaign tile CHECK: "verification #12 said redo, but a newer capture exists" + "D6 asks for a recapture". The GUI's
> Verify button runs the checks but writes no block and ticks no D-row, so the tile could never clear by itself.)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | linear | G402 | stationary | r1 | oct. 14 ~2:50–3:02 PM (Kyle's recapture after #12; `2f0c34d`) | root telem + arrivals, ends 0C80 (B) + 1C38 (A), 5 controls (`exports/.../stationary/*.csv`, NOT `trimmed/`) |

| Check | Result | Detail |
|---|---|---|
| Which files the analysis used | ✅ the recapture | `feature_table.csv` / `windowed_dataset.csv` `source_file` = the 2:50–3:02 PM files only. ⚠️ `exports/.../stationary/trimmed/` still holds the OLD 1:40 PM run (#12) - never point a tool at it by hand; analyze.ps1 re-trims |
| `validate_integrity` | ✅ PASS (5 WARN) | 0 FAIL. The 5 controls are named `..._linear_none_...` (flashed before the oct. 14 wormhole-control fix) yet carry phase 2 rows - filename label only, their rows are phase-labelled correctly |
| `verify_topology --expect linear` | ✅ | chain of 8, B0CB → ... → 0C80; baseline re-routing free; E618 1 parent switch outside the baseline |
| `verify_attack` 3-sigma | ✅ 2/2 primaries | TunnelIntensity 0 → 1.000 and root-measured DuplicateRate 0 → 1.000 (normal sd 0 → z +inf); TunnelBytes 0 → 30 (support) |
| Setup checks | ✅ all OK | one A + one B, roles stable, **A shallower than B** (1C38 layer 3, 0C80 layer 8 → 5 hops skipped), UART B sent ~180 / A received ~180 (100 %), root saw duplicates in 180 attack windows |
| PDR (controls) | ✅ | all 5 controls 1.0000 baseline and attack (a wormhole duplicates, it does not drop) |
| Tunnel latency (measured, not scored) | ℹ️ 29.3 ms | the two copies of B's probes reached the root 29.3 ms apart (#12's reversed run: 28 ms, the good #10 run: 2.8 ms) |

**Verdict: ✅ WORMHOLE CONFIRMED - USABLE.** The oct. 14 3:02 PM capture (taken again after #12) fixes everything #12 found (ends no longer
reversed, A shallower, tunnel 100 %). Supersedes #12 for this cell → checklist **D6 ticked**, C10 marked superseded.
Footnote only: the 5 control files' names say `none` (old firmware label) - the folder and the phase column are what
the analysis uses.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #39 — Oct 17, 2026 · ~6:30 PM — blackhole · tree · G402 · highload r1: file choice from the SD cards + trim + analysis

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted
> **Request:** "check which files or datasets are the correct one ... you the one who choose for tree g402 blackhole highload
> and also trim it then analysis it" (after node3 `20:80` showed only ABORTED files in the GUI)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | highload | r1 | oct. 17 ~5:00–5:41 PM (firmware built 4:55 PM) | root 3218 telem+arrivals, attacker 1C38 (already imported) + 6 victims read off their SD cards over USB (read-only, no reset, no delete) |

| Check | Result | Detail |
|---|---|---|
| Which file per board | ⚠️ chosen by content | Crashed boards left the run split over several boot files. One file per board (preprocess assumes one file = one run per node), picked with `trim_run.py`'s own rule (attack phase + progression, size = tiebreak): B768 b2 · D7B4 b4 (3/3 phases) · ED80 b4 · FE90 b4 (301/181/37 s, then PANIC) · E618 b3 (baseline + 79 s attack, then INT_WDT) · **0C80 b3 (attack 181 s + 21 s cooldown; its baseline is in b2, cut by a PANIC 12 s before the attack)** |
| How each piece ENDED (card `runs.csv` → `ended_by`) | ❌ 5 firmware crashes | 0C80 PANIC · E618 PANIC → INT_WDT → PANIC · FE90 PANIC. NOT power cuts and NOT the GUI: every earlier run on all 7 cards ends POWERON/none, never a crash - PANIC/INT_WDT appear only in this 5 PM run. Victim-side firmware changes since the last commit are inert (enum value, GET_ID/START commands, attacker-MAC line overridden by `-DBH_ATTACKER_MAC_HEX`) - cause NOT found (no serial backtrace: children had no monitor during the run) |
| A plain import would have kept | ❌ junk | `import_sdcard.py`'s "same node + repeat" guard keeps a board's FIRST piece - for FE90 and E618 that is stabilise-only (phase 255). Pieces were staged per folder and chosen by hand |
| `validate_integrity` | ✅ PASS (6 WARN) | short/missing phases on 0C80, E618, FE90 (the crash cuts), B768 attack 126 s (heard the attack late), ED80 6.4 Hz sampling |
| `verify_topology` | ❌ FAIL | B768: 3 parent switches, converged only at 542 s (inside baseline) - its path ran through boards that crashed and rebooted |
| `verify_attack` 3-sigma | ✅ signature / ❌ setup | ForwardingRatio(attacker) 1.000 → 0.000 (z −152) and PDR → 0.761 pooled: 2/2 primaries PASS. Victims B768 0.24, 0C80 0.50; 4 boards above the attacker stay 1.00. **Setup FAIL: B768 changed parent during the attack** |

**Verdict: ❌ BLACKHOLE NOT CONFIRMED - SETUP INVALID → recapture blackhole/tree/G402/highload.** The attack itself
worked (attacker forwarded 0 %, both victims collapsed); the mesh around it did not hold because 3 victims crashed
(PANIC / INT_WDT) and their children re-parented. Fix or at least CATCH the crash before the recapture: watch every
child's serial port during the run so the crash backtrace is recorded (GUI change, oct. 17). Analysis tables written
for the record under `datasets/analysis/blackhole/tree/G402/highload/`.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #38 — Oct 17, 2026 · ~2:40 AM — TOPOLOGY SWEEP of every live cell (redo list) + wizard navigation

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted
> **Request:** "include data that has warnings on their topology - only a warning, but if it is really wrong tell the user
> to redo it ... very smart and honest" + wizard: "add back to everything ... user friendly"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all (49 live cells) | all 4 | G402 · DLSU_Library · Yuchengco (+ home, off-plan) | all | latest per cell | sep. 30 – oct. 17 | `datasets/exports/**` raw telem CSVs |

| Check | Result | Detail |
|---|---|---|
| Structure rebuilt from raw CSVs (`verify_topology` rules) | ⚠️ 1 new REDO | **blackhole/linear/Yuchengco/stationary: NOT a linear chain** - `ED80` had 2 children (a branch), plus `B768` re-routed during the baseline. Already REDO for 94.5 % coverage (Kyle's D7); this is a 2nd, independent reason |
| Shared finding | ⚠️ team decision | all **11** live partial_mesh cells are structurally plain trees (no child ever used a 2nd parent) - checklist **B-pm**; shown ONCE in the redo list, not as 11 per-cell CHECKs |
| Other topology notes | ✅ explained | wormhole/tree/G402/stationary = flat like a star (already REDO, D3); blackhole/tree/G402/stationary: `ED80` re-routed in the baseline + attack (already REDO, D1) |
| Redo list result | ✅ | 5 REDO · 1 CHECK (wormhole/linear/G402: re-verify, #12/D6 superseded) · 40 OK (33 never checked by a person) |
| Wizard navigation (`tools/test_wizard_nav.ps1`) | ✅ 15/15 | 'b' on every menu (previous question where one exists, else back to the menu the tool came from); 'm' unchanged; 'b' blocked after flashing starts; question chains step back one at a time; main menu renders with no errors. **Bug found + fixed:** `[Console]::WindowWidth` throws without a real console (transcripts) - the test now fails on any printed error (mutation-checked) |

**Verdict: ✅ topology sweep clean apart from the cells already on the redo list; one new hard reason for
blackhole/linear/Yuchengco/stationary. Wizard navigation verified by test, not yet clicked through live.**

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #37 — Oct 17, 2026 · ~2:30 AM — WORMHOLE END-TO-END · firmware auto-switch + root gates + verifier + preprocessing

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted (firmware, verifier, preprocess, tools)
> **Request:** "check each topology and scenario for wormhole if every one has autoswitch ... is TunnelIntensity the only way
> ... add other paper ... put a safety net ... make sure to fix the issue in wormhole. VERIFY EVERYTHING"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | linear, tree | DLSU_Library, G402, Yuchengco | stationary, highload | r1 | oct. 7 - oct. 16 | all 5 live wormhole cells + the user's two oct. 16 root logs (linear: both B, then both A) |

| Check | Result | Detail |
|---|---|---|
| Root cause of "both B" / "both A" (user logs) | ✅ found | A **one-way UART jumper**: one end hears the peer, the peer hears nothing and sits on its BUILD fallback. Before the lock, `decide_role` ignored the peer's `hears_peer` flag, so the hearing end could pick the SAME end (log 1: deaf E618 fallback B + deeper 1C38 -> B; log 2 after re-plugging: the other direction failed -> both A). The reversed ends at 105 s were boards moved AFTER Phase 0 (roles lock there) |
| Topology / scenario coverage | ✅ same everywhere | `wormhole_victim.c` has no topology or scenario branch in the role logic - one image, one rule for linear/tree/star/partial and every scenario. Linear only exposed the cable fault |
| Fix 1 - ends | ✅ | `peer_is_deaf()`: before the lock a deaf peer makes this end take the OPPOSITE role; new link state `WH_LINK_ONEWAY` ("UART ONE-WAY") in the heartbeat + a repeated error naming the jumper to re-seat |
| Fix 2 - root wormhole gate | ✅ | `heartbeat_wormhole_ready()`: Phase 0 waits (WORMHOLE_GATE_STABLE_S = 15 s) for exactly 1 A + 1 B, both `UART OK` (both directions), both attached, A closer to the root than B. START_ANYWAY overrides |
| Fix 3 - manual START gate (both attacks) | ✅ | `MANUAL_START_GATE` (default 1): after every automatic gate the root prints READY and waits for the operator to type **START** in its monitor; START never starts a broken wormhole. `-DMANUAL_START_GATE=0` restores the automatic start |
| Host test (real `wormhole_victim.c`, simulated cable) | ✅ 62/62 | +[9] the oct. 16 linear case (old code: both B) and [9b] the mirror (both A): ends now opposite, ONE-WAY/NO SIGNAL reported, re-pick by depth after the jumper is fixed, clean lock. [3c] updated: the hearing end reports ONE-WAY, not OK |
| Firmware builds (ESP-IDF 5.5.4) | ✅ 5/5, 0 warnings | root wormhole (roster gate on), root tree+blackhole, root without manual gate, wormhole end, blackhole victim. Not yet flashed / run on hardware |
| Verifier - 2nd independent signature | ✅ | NEW primary **DuplicateRate** = share of Node B's windows in which the ROOT logged a probe twice (root-measured, independent of the attackers' own TunnelIntensity count) [Ramirez Gomez et al. 2019]. All 5 wormhole cells: **2/2 primaries** (linear/DLSU 0.012 -> 1.000, z 9.17; others normal 0 -> 1.000). Tests 21/21 |
| Preprocessing - phase-change windows | ✅ | A window whose rows carry two real phases is now segment `transition` (excluded). Wormhole/tree/DLSU: B's baseline TunnelIntensity 1 -> **0**, 8 windows reclassified. Dry run on every attack cell: verdicts unchanged (one apparent change = a stale `trimmed/` folder in wormhole/linear/G402, not the fix) |

### Findings
- The auto-switch logic was right for every topology; what it lacked was using the peer's "I hear you" bit BEFORE the
  lock. A one-way jumper is a WIRING fault software cannot repair - the fix makes it impossible to start a run on it.
- `datasets/exports/wormhole/linear/G402/stationary/trimmed/` still holds the OLD reversed 1:40 PM run; analyze.ps1
  re-trims so live tables are right, but do not point tools at that folder by hand.
- Hardware still to prove: flash ROOT + both tunnel boards, pull one jumper on purpose -> root must say UART ONE-WAY and
  hold Phase 0; re-seat -> READY -> type START.

**Verdict: ✅ wormhole fixed in firmware (tests + builds), verifier has 2 independent primaries, every live wormhole cell
CONFIRMED 2/2. ⚠️ Firmware not yet run on hardware - reflash root + tunnel boards before the next wormhole run.**

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #36 — Oct 16, 2026 · ~3:15 PM — WORMHOLE PIPELINE AUDIT · raw exports vs analysis · tree · DLSU_Library · stationary

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted analysis/verifier changes
> **Request:** "fix the analysis and preprocessing etc of wormhole, check if there is issue there like calculations and compare it with the datasets itself"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | tree | DLSU_Library | stationary | r1 | oct. 16 | `exports/.../trimmed/` (9 files) vs `analysis/.../feature_table.csv` (re-built) |

| Check (feature table vs raw) | Result | Detail |
|---|---|---|
| Counter deltas per segment (all 6 counters, every labelled node) | ✅ match | e.g. B attack: tunnelled 179 (raw 181), tx 179 (181); root probes 1223 (1232). Shortfalls = rows inside discarded windows only |
| TunnelIntensity (B `retry_count`, A `probes_count`) | ✅ match | B attack sum 179 = `retry_count_delta` 179; baseline 1 = the transition window (see below) |
| Duplicates / TunnelLatency vs root arrivals | ✅ match | raw: 181 dup seq, all phase 2, spread 17.6 ms; table: 179 attack windows, 17.7 ms. 0 dups in raw phase 0/3 |
| PDR (children) vs root arrivals by seq | ✅ match | `704B`, `2805` PDR 1.000 every phase = root logged every seq they sent |
| Label vs segment vs window phase | ✅ consistent | attack ⇔ Label 2 ⇔ phase 2; baseline/cooldown ⇔ Label 0; excluded segments ⇔ Label NaN |
| **Phase anchor for stalled boards** | ❌ → ✅ **fixed** (`analysis/preprocess.py`) | Bug: a node's phase anchor came only from KEPT windows. The 4 stalled boards' exit fell in discarded windows, so ALL their windows - incl. ~300 s of valid baseline - became `no_phase_seen`. Now `build_windows` records every window's phase and `assign_segments` falls back to it (same first-real-phase + root-restart rules). Result: baseline windows 1555 → 2028; the 4 boards' attack windows stay discarded (too few samples - correct). Dry-run on the only other cells with `no_phase_seen` (blackhole/tree/G402 burst + stationary): **identical** (their exclusions are real dropout / desync). `test_segments.py` passes |
| Verifier after re-analysis | ✅ CONFIRMED | TunnelIntensity z **10.86** (was 8.91 with the smaller baseline). A's missing attack windows → WARN, not FAIL, because the root's duplicates can only come from A re-injecting (new test; with NO duplicates a missing A still FAILs). Tests 21/21; sweep of all 44 attack cells: only this cell's verdict changed |

### Findings (not changed - for the team)
- ⚠️ **Node B has PDR = NaN by design** (`features.compute_pdr_features` rule 1: PDR only on role `child`). Raw: root got every
  B seq once in baseline/cooldown and twice in the attack (181 unique). Fine for the verdict (PDR is not a wormhole
  signature) but B's PDR column is empty in the dataset - say so if the paper reports per-role PDR.
- ⚠️ **One transition window per node is labelled baseline although it holds the first tunnelled probe** (window phase =
  modal row). Gives B 1 tunnel count + 1 TunnelLatency value in the baseline. Negligible (baseline mean 0.009) - boundary
  effect, not a bug.
- ⚠️ **Cooldown is short in the table** (B 79 of ~120 s, `704B` 68 of 117) - discarded windows; B also bunched (6.5 %), the
  same stall at a milder level.
- The 4-board telemetry stall itself (#34) is unchanged - this only stops it from deleting their valid baseline.

**Verdict: ✅ calculations match the raw data; one preprocessing bug fixed; WORMHOLE CONFIRMED.** Cell usability = D8.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #35 — Oct 16, 2026 · ~2:40 PM — VERIFIER FIX · wormhole · tree · DLSU_Library · stationary

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted verifier changes
> **Request:** "fix this like why its inconcl and infeasible ... make sure that verification are based from a study"
> + "is this real that tunnel isnt working ... please fix the verifier"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | tree | DLSU_Library | stationary | r1 | oct. 16 | same feature table as #34 (no data changed) |

| Check | Result | Detail |
|---|---|---|
| "Node A RECEIVED ~0 ... UART link carried nothing" | ✅ fixed (verifier bug) | It summed A's attack windows, and A has NONE (all `no_phase_seen`), so 0 = missing data, not a missing cable. A's raw `probes_count` (frames received from B) = 0 → 181. Now: A with no labelled attack windows → `-- cannot check UART delivery from Node A` (SKIP, not FAIL; `analysis/exposure.py`). A real cable fault (A has windows, ~0 received) still FAILs (test `test_no_uart_cable`) |
| Summary line "A shallower than B, tunnel carried data" | ✅ fixed | was printed although neither was checked; now only when no check was skipped (`tools/attack_checks.py`) |
| "topology: 2 node(s) ... not attached" | ✅ explained | NEW warn line names the nodes with no labelled window (`0C80, 1C38, FE90, ED80`) = a preprocessing gap, not evidence about the attack |
| TunnelLatency `INCONCL` | ✅ now `N/A` + note | Correct by design: it is the gap between the 2 copies of one probe, which exist only while the tunnel runs → no baseline. The 3-sigma method (Zhukabayeva et al. 2025) needs a normal distribution, so it cannot apply. Attack value 18.2 ms reported descriptively = the timing mismatch of Hu, Perrig & Johnson (2003). Never counted in the verdict (unchanged) |
| LatencyHopRatio `INFEASIBLE` | ✅ unchanged + WHY added | Unsynchronised clocks → relative one-way delay; normal mesh has rare 100s-of-ms spikes → baseline 45.9 ± 191.6, max attainable abs(z) 0.24. Secondary, never in the verdict. Raw check: B's latency median 21.5 ms baseline vs copies 28.8 / 43.9 ms in the attack - with a 1-hop shortcut the tunnel copy is NOT faster, so make no latency claim for this run |
| Tests | ✅ 20/20 | `test_verify_attack.py` (+1 new: A unlabelled ≠ cable fault), `test_topology_graph.py` OK |
| Sweep, all 3 wormhole cells, old vs new | ✅ only this cell changed | linear/DLSU + linear/G402 CONFIRMED before and after; tree/DLSU SETUP INVALID → **CONFIRMED** |

### Findings
- **"Baseline windows" ≠ the attack happening in the baseline.** The 3-sigma method compares the attack phase against
  the NORMAL phase of the same run; `baseline windows: 1555` is the size of that normal reference.
- **Attack verdict: ✅ WORMHOLE CONFIRMED** - TunnelIntensity z 8.91; root logged 2 copies of all 181 B probes; A's raw
  counter 181 received / 181 re-injected (cite these raw counts for checklist B-wh, since A's windows are unlabelled).
- **Dataset completeness unchanged from #34:** 4 of 8 boards (incl. A) have no labelled windows (telemetry stall). The
  attack is verified; whether the CELL is usable with 4 boards missing is the team's call (D8: recapture, or footnote).

**Verdict: ✅ ATTACK CONFIRMED (verifier false alarm removed). Cell usability → D8 decision.**

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #34 — Oct 16, 2026 · ~2:10 PM — wormhole · tree · DLSU_Library · stationary (re-check after #33 fixes)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted exports
> **Request:** "check the trimmed why node 2 is doubled and after checking or fixing it proceed to analysis"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | tree | DLSU_Library | stationary | r1 | oct. 16 | same as #33, B replaced by `child_node4_..._0149PM` (card `r4_b8`, 6667 rows); node2 `_0128PM` archived |

| Check | Result | Detail |
|---|---|---|
| node2 doubled in `trimmed/` | ✅ fixed | A was exported twice (`_0128PM`, `_0132PM`); `_0128PM` = strict subset (0 rows differ, `_0132PM` +1 attack row). `trim_run.py` copies every export into `trimmed/`, so the duplicate came back on every run. Moved to `datasets/archive/2026-10-16_wormhole-tree-DLSU-dup-nodeA/` (README there) |
| New B file | ✅ correct run | role `wormhole_b`, phases 0/2/3 = 3005/1806/1205 (= root), parent `FE90` layer 3 throughout |
| `analyze.ps1 -Verify` integrity / topology | ✅ PASS / PASS | tree, 8 nodes, depth 4, 0 parent switches |
| `verify_attack.py` signature | ✅ TunnelIntensity z 8.91 PASS | TunnelLatency INCONCL + LatencyHopRatio INFEASIBLE = by design (STATUS) |
| Setup check "A RECEIVED ~0 vs B SENT ~179" | ❌ FALSE ALARM | A's raw `probes_count` (= UART frames received, `wormhole_victim.c`) goes 0 → **181** in the attack; A's `tx_count` (re-injected) 0 → 181; root got 362 B arrivals. The check reads A's attack WINDOWS, and A has none (all `no_phase_seen`) |
| Telemetry timing per board | ❌ new stall | bunched rows (< 20 ms apart; healthy = 100 ms): **A 28 %, `0C80` 28 %, `FE90` 30 %, `ED80` 32 %** (root's 4 direct children); `704B` 8 %, B 6.5 %, `2805` 5 %; root 1 %. Same boards in oct. 11-12 tree runs: 0.3-2 %. Pattern = sampler blocked, then `xTaskDelayUntil` catches up with several rows in < 1 ms. The loop only reads state + `csv_logger_append_telemetry` → a slow storage write is the likely blocker (UNVERIFIED). Starts ~260 s into A's log, i.e. inside the baseline |
| Effect on analysis | ❌ | 10 Hz grid drops same-tick rows → those 4 boards' windows fall below `MIN_VALID_SAMPLES` → no phase exit → `no_phase_seen` (EXCLUDED). Labelled: root, B, `704B`, `2805` only |

### Findings
- **The tunnel worked end to end** (B tunnelled 181, A received 181 and re-injected 181, root logged each B probe twice).
- **Verdict SETUP INVALID is caused by the logging stall, not by the attack.** Not fixed: the only analysis-side
  fix would be a method change (anchoring phases on raw rows, or relaxing the window rule) = a D-entry decision for the team.
- The stall is NEW (same boards clean on oct. 11-12) and worst on the root's direct children. Not diagnosed - check those
  boards' serial logs (SD / SPIFFS write warnings) and card free space before the next run.

**Verdict: ❌ NOT USABLE as a dataset cell (4 of 8 boards incl. Node A unlabelled) → RECAPTURE.** Keep these files as
hardware proof of a working tree tunnel (1-hop shortcut). Before recapturing, find the cause of the stall, or it will repeat.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #33 — Oct 16, 2026 · ~1:45 PM — wormhole · tree · DLSU_Library · stationary

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `52da079` + uncommitted exports
> **Request:** "i dont get it why no attack happened can you check the actual datasets" (verifier said INCONCLUSIVE)
> **Numbering:** #33 because STATUS.md lists Kyle's #14-#32 (not yet pushed into this file) - avoids a collision on merge.

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | tree | DLSU_Library | stationary | r1 | oct. 16 (exports 1:02-1:35 PM) | root `_0102PM` telem+arrivals, children node2-node8 in `datasets/exports/wormhole/tree/DLSU_Library/stationary/` |

| Check | Result | Detail |
|---|---|---|
| `verify_attack.py --attack wormhole` | ❌ INCONCLUSIVE | Tunnel features "no attack-phase values"; setup: "ROOT logged no duplicate arrivals"; topology "2 node(s)" |
| Raw root arrivals vs verifier | ⚠️ verifier is wrong about the RUN, right about the TABLE | Root `_arrivals.csv`, phase 2: B `F4:2D:C9:73:E6:18` = **362** arrivals (= 2 × 181) vs ~177 for every other node; **362 duplicate (src, seq) arrivals, all in phase 2, all from B**. Phase 0 / 3: B = 300 / 120 like everyone else. **The tunnel fired.** |
| Node B's export (`child_node4_..._0125PM`) | ❌ WRONG FILE | 2110 rows, ends at t = 223 s, phases 255/0 only (never reached the attack), parent `20:50:0D:E7:1C:39` = under A at layer 3. That is an EARLIER, aborted boot (B under A layout), not the run the root recorded (root: 3006/1806/1205 rows in phases 0/2/3) |
| Run match, other files | ✅ same run | node5 `704B` + node6 `2805` (6667 rows) and root (6668) match exactly (phase 0/2/3 = 3006/1806-ish/1205); node6 is the card's `r4_b9` = the right pick, `r3_b8` is an earlier run. node2/3/7/8 have the same phase durations (300 s / 180 s), offset only by boot time |
| Telemetry density, root's 4 direct children (`1C38` A, `0C80`, `FE90`, `ED80`) | ❌ thinned from ~340 s | 10 rows/s through the baseline, then ~9.4/s just before the attack, ~3-6/s in the attack, ~1-3/s in cooldown (node3: 200 → 188 → 118 → 64 → 16 rows per 20 s). Nodes at H02/H03 (`704B`, `2805`) stay at 10/s the whole run. Root arrivals from those 4 stay normal (~177 in phase 2) - their PROBES got through, only their own logging thinned |
| Analysis tables | ❌ 5 of 8 nodes excluded | windowing kept those 5 only up to t ≈ 210-307 s (later windows < `MIN_VALID_SAMPLES`), so none saw a phase exit → segment `no_phase_seen` (EXCLUDED). Only root + `704B` + `2805` carry labels → verifier saw 2 children, no A, no B |
| Duplicate export | ✅ handled | node2 (A) exported twice (`_0128PM`, `_0132PM`); preprocess archived `_0128PM` to `trimmed/_archive/` |

### Findings
- **The attack DID happen.** The root received every one of B's attack-phase probes twice. The INCONCLUSIVE verdict
  comes from the analysis inputs, not from the hardware.
- ❌ **Cause 1 (fixable now): wrong Node B file imported.** B's card holds the real run; the imported file is an aborted
  earlier boot. Re-import B's newest COMPLETE file (~6600+ rows, phases 0/2/3; parent should be the layout seen at the
  run, not `...1C:39`), delete `child_node4_..._0125PM_telem.csv` + its `trimmed/` copy, re-run analysis.
- ❌ **Cause 2 (not fixed, cause unconfirmed): the 4 root-direct children logged sparsely from just before the attack.**
  Probes reached the root normally, so the mesh worked; the boards' own telemetry rows thinned. Not diagnosed here.
  Candidate, UNVERIFIED: the documented root-RX / flow-control throttling (`docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` §12)
  blocking `esp_mesh_send()` on the root's direct children (7 children + B's duplicates). Check those boards' serial
  logs / SD for errors before deciding. Until then A (`1C38`) has no usable attack windows → A-side tunnel features stay empty.
- Shortcut was 1 hop (A H01, B H02 natural formation, user's choice) - footnote, not a rejection.

**Verdict: ❌ NOT USABLE as analysed — RE-IMPORT B, then re-verify.** Hardware evidence (root arrivals) shows a working
tunnel. If A + the 3 other H01 children are still excluded after B's re-import, the cell needs a recapture or an
explained exclusion.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #13 — Oct 14, 2026 · 2:46 PM — VERIFIER AUDIT · all 42 analysed cells (blackhole + wormhole)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `a295a91` + uncommitted verifier changes
> **Request:** "enhance the verifier for both blackhole and wormhole, make sure to double check it if it's reliable"
> + "make sure to include the topology and uart or etc is correct"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole (40) + wormhole (2) | all 4 | G402 · DLSU_Library · Yuchengco · home | all analysed | r1 | sep. 30 – oct. 14 | every `datasets/analysis/*/*/*/*/feature_table.csv` on GitHub at `a295a91` |

| Check | Result | Detail |
|---|---|---|
| **New: setup checks** (`tools/attack_checks.py`, run by `verify_attack.py`) | ✅ added | **Topology during the attack** (same rules as `topology_graph.validate` / the root's live check; partial mesh judged on all links seen in the experiment), key nodes did not re-parent mid-attack, no board dropped out. **Blackhole:** exactly 1 attacker; it relayed traffic and really dropped it (forwarded ≤ 50 %); ≥ 1 victim behind it; victims ALIVE (own telemetry) yet cut off (PDR < 0.5); nodes NOT behind it lost ≤ 30 % (loss specific to the attacker's path); self-report vs neighbours; recovery after. **Wormhole:** one A + one B, no role change in the experiment, A shallower than B, **A received what B sent over UART**, the root saw duplicates. Any FAIL → `NOT CONFIRMED - SETUP INVALID` (exit 3) |
| **New: statistical guards** | ✅ added | minimum effect (PDR/FR/Tunnel move ≥ 0.10 absolute; a flat baseline made ONE lost probe a z of −∞ = PASS), ≥ 6 attack points; TunnelBytes demoted to secondary (= TunnelIntensity × 30 B, not a 2nd independent signature) |
| Sweep before vs after (42 cells) | ✅ no good run lost | before: 41 CONFIRMED / 1 INCONCL; after: **40 CONFIRMED / 1 INCONCL / 1 SETUP INVALID**. The only change is wormhole/linear/G402 (#12, ends reversed). Every blackhole cell passes every new FAIL check |
| Reliability: fault injection (`tools/test_verify_attack.py`, 19 tests) | ✅ 19/19 | good captures (#4, #10) broken one way at a time: attacker kept forwarding · attacker a leaf · no victim · root outage hitting everyone (C5-style) · victim dead not blackholed · victims not cut off · attacker re-parented mid-attack · linear with a branch · attacker telemetry missing · no UART cable · ends reversed · role switch in vs before the experiment · root saw no duplicates · two B ends · 1 lost probe on a flat baseline · too few points. Each is caught; the good tables stay clean |
| Reliability: each guard is load-bearing | ✅ | switching each guard off makes its test FAIL (7/7 mutations caught) - no check passes by accident |
| Reliability: numbers vs raw exports (blackhole/tree/Yuchengco/stationary, Kyle) | ✅ match | checks: attacker recv 181 / fwd 1, victim PDR 0.000, 5 bystanders fine. Raw: attacker 180 / 0 / dropped 180; root got 0 from victim `ED80` in the attack (300 baseline, 121 cooldown), ~180 from each of the other 5 |
| Other suites | ✅ | `test_topology_graph.py` OK; wormhole auto-switch host test 54/54 |

### Findings
- ⚠️ **Every partial_mesh capture is structurally a plain tree.** In all 9 partial_mesh cells no child ever used a 2nd
  parent during the experiment (raw exports confirm: DLSU stationary 0/3, Yuchengco highload 0/7). Reported as a WARN
  (shape comes from placement). The paper cannot describe these as multi-parent captures as they stand → checklist **B-pm**.
- ⚠️ **blackhole/tree/G402/stationary:** child `ED80` changed parent during the attack (not a key node → WARN; already DEGRADED in #2).
- ❌ **blackhole/linear/home/highload** (already INCONCLUSIVE, off-plan): parent links formed a cycle and 6 boards
  re-parented during the attack; victims still delivered 92 %. The 7-board highload collapse (MEMORY), now explained by the checks.
- **Wormhole auto-switch:** the board picked as "A" or "B" in the wizard only sets its FALLBACK role; the firmware makes
  the DEEPER board the entry (B) and the shallower the exit (A) before Phase 0 (host test [1]: boards built the wrong
  way round end up correct). The wizard now says "tunnel board 1/2 (entry/exit chosen automatically)". Hardware proof
  still pending: #10 matched the fallback, #12 had a one-way wire.

**Verdict: ✅ verifier now RELIABLE for both attacks on the data we have** — it checks the attack signature, the topology
during the attack, the attacker/victims (blackhole) and the UART tunnel (wormhole); every new check was shown to fire
on broken data and not on good data. Limits: thresholds are deliberately loose (they separate "the attack as designed"
from "something else", not good runs from great ones); the checks read the feature table, so a wrong export is still
caught by `validate_integrity.py` / `verify_topology.py`, not here.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #12 — Oct 14, 2026 · 2:27 PM — wormhole · linear · G402 · stationary

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `a295a91` (data pushed by Kyle)
> **Request:** "my classmate pushed the failed wormhole datasets can you check it and pull it first"
> (earlier the same day: "why it passed" - the old verifier said WORMHOLE CONFIRMED with the ends reversed)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | linear | G402 | stationary | r1 | Oct 14, ~1:40–1:55 PM | 9 (8 telem + root arrivals), all from Kyle's laptop |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ⚠️ 4 PASS / 5 WARN / 0 FAIL — harmless | the 5 WARN are `linear_none` filenames on boards whose rows carry phase 2 correctly (same as #10). Phase 0 "424 s" = the root restarted (see topology) |
| Topology (`verify_topology.py`) | ⚠️ FAIL — late convergence after a **root restart**, not re-routing | all children fell back to phase 255 at ~90–125 s of their logs (new root session) and re-joined late. `Baseline re-routing free: YES`. Final chain: root → **B `0C80` (L2)** → `D7B4` → `FE90` → `ED80` → `B768` → **A `1C38` (L7)** → `E618` (L8) |
| **A/B roles (raw telemetry)** | ❌ **REVERSED all experiment long** | `0C80` = `wormhole_b` from second 0 to the end and **never reacted to its peer**, although it was the SHALLOW board. `1C38` flipped A→B→A→B at 11.6 / 18.7 / 25.1 s (heard 0C80 only on and off), was B at Phase 0, then switched to A at 32.6 s (old higher-MAC conflict rule). From the real baseline on: A at hop 6, B at hop 1, stable |
| Cause | ⚠️ **UART link one-way / flaky** (most likely) | 0C80 → 1C38 worked (tunnel copies arrived, 1C38 heard HELLOs intermittently); **1C38 → 0C80 carried nothing** (0C80 never left its build fallback). Alternative: 0C80 flashed with pre-auto-switch firmware. The boards' boot logs tell them apart (auto-switch banner + `LOCKED ... BUILD FALLBACK`). Not a mesh reshuffle: an earlier pasted dashboard came from a different attempt |
| Root arrivals, recomputed by hand | ⚠️ duplicates yes, shortcut no | B's probes: baseline 301 single, **attack 181 probes → 360 arrivals (179 with 2 copies)**, cooldown 121 single. No other source duplicated. Copies arrive **28.2 ms apart** (median, p90 57.6) vs **2.8 ms** in the valid #10 run: the tunnel copy took the long way (wire + 6 hops) |
| Attack test (`verify_attack.py`, new rule) | ❌ **WORMHOLE DUPLICATION ONLY - SETUP INVALID** (exit 3) | TunnelIntensity 0.001 → 0.997, TunnelBytes 0.04 → 29.9 (z 52) pass; TunnelLatency INCONCL; setup check: **ends REVERSED in the attack windows (A hop 6, B hop 1)**. Before today's fix the same table printed "WORMHOLE CONFIRMED" |

### Small things found (and fixed today)
- **Verifier false alarm fixed:** the setup check flagged "1C38 changed role", but every flip was in `pre_baseline`
  (the auto-switch deciding before Phase 0, by design). `analysis/exposure.py` now counts role changes in
  baseline/attack/cooldown only. Re-checked: #10 DLSU still CONFIRMED, this run still SETUP INVALID (reversed).
- **68 windows with ForwardingRatio > 1** (max 3.0): queue flush across a window edge, as in #11.
- **Firmware fixes the run would have triggered** (not on the boards yet): the root now shows `UART NO SIGNAL` for
  the deaf end and "only ONE direction works"; the conflict rule now picks the DEEPER board as B (but with one
  dead direction software can only mirror the deaf board, so the cable must be fixed).

**Verdict: ❌ NOT USABLE as a wormhole capture** — duplication happened but the tunnel was never a shortcut (A deeper
than B for the whole experiment). Recapture wormhole/linear/G402/stationary after the UART test passes in **both**
directions; at most cite this run for "duplication only".

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #11 — Oct 7, 2026 · 7:11 PM — blackhole · linear · DLSU_Library · jitter

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `1f97dc2` (root files pushed in this commit)
> **Request:** "analyse and verify it BUT TRIM IT FIRST"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | linear | DLSU_Library | jitter | r1 | Oct 7, ~6:41–6:55 PM | 9 (8 telem + root arrivals); children from Kyle + Basti, root from Angelo |

| Check | Result | Detail |
|---|---|---|
| Trim (`trim_run.py`, dry run, then `--apply` via `analyze.ps1`) | ✅ nothing to cut | all 9 files = 1 boot session with baseline → attack → cooldown; 65,352 rows kept, 0 dropped. `trimmed/` = byte copies |
| Integrity (`validate_integrity.py`) | ✅ 9 PASS / 0 WARN / 0 FAIL | every board 100 % sample coverage at 10 Hz |
| **Jitter fired** | ✅ | root clock: baseline **331.4 s** (nominal 300), attack **206.5 s** (nominal 180), cooldown 120.5 s |
| Topology (`verify_topology.py`) | ⚠️ FAIL — **false alarm** (same as #4, #8) | linear chain of 8 as expected: root → `FE90` (L2) → `0C80` (L3) → **attacker `1C38` (L4)** → `B768` → `D7B4` → `E618` → `ED80` (L8). The FAIL is `FE90` losing the root at 57–107 s of its own log, which is **while the wizard wiped and reflashed the root** (run log line 33: `-Wipe -Flash`). That is the old root session, tagged `pre_baseline` and excluded. Real baseline (child log 175 s on) = 0 parent switches on every node |
| Root arrivals, recomputed by hand | ✅ | baseline 331/source (ED80 329); **attack: victims `B768`, `E618`, `ED80` = 0, `D7B4` = 1** (a boundary probe); bystanders `FE90`, `0C80` = 207 each; cooldown 120 each (ED80 115). 0 duplicate (src, seq) |
| Attacker counters (`1C38`), recomputed by hand | ✅ | received/forwarded/dropped per phase: baseline 1751/1751/0, attack **806/0/806**, cooldown 475/475/0 |
| Attack test (`verify_attack.py`) | ✅ **BLACKHOLE CONFIRMED** 2/2 primaries | attacker FR 0.997 → **0.000** (z −44.3); PDR pooled 0.997 → 0.335 (z −19.4). Per node: 4 victims 0.998 → **0.000**, 2 bystanders 1.000 → 1.000 (above the attacker, unaffected by construction) |
| Analysis tables | ✅ | 6,189 windows (3 dropped < 4 samples); baseline 2,400 · attack 1,648 · cooldown 965 · pre_baseline 1,176 (excluded) |
| EDA (`eda_output/`) | ✅ | PDR alone separates the label (0.889 vs 0.672 majority): expected for a blackhole (100 % drop in a fixed window), same warning as every blackhole cell |

### Small things found
- **Jitter's extra baseline is cut:** preprocess labels only the last `PHASE_BASELINE_S` = 300 s of phase 0 as baseline,
  so jitter's extra ~31 s go to `pre_baseline` (known quirk, MEMORY oct. 1). The longer attack (206 s) survives in full.
- **44 windows have ForwardingRatio > 1** (max 8.5): a relay queue flushed across a window edge. Verdict is unaffected (FR
  attacker uses ratio-of-sums over 5-window points).
- **Sniffer** (`…jitter-dlsu_library_r1_oct07_0640PM.pcap`) fitted; MacRetryRate covers 575–782 of ~820 windows on most
  boards but only **174/826 on `FE90`** (sparse, not a model input).
- **Child file names ≠ roles** (e.g. `child_node2_*` = the attacker `1C38`): names come from each laptop's preset; the
  analysis keys on `node_id`, so labels are correct.

**Verdict: ✅ USABLE** — clean single-session capture, jitter fired (331 s / 206 s), BLACKHOLE CONFIRMED with 4 victims
at 0 % delivery and 2 bystanders at 100 %. Footnote the topology FAIL as the root-reflash false alarm.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #10 — Oct 7, 2026 · 6:40 PM — wormhole · linear · DLSU_Library · stationary

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `69ef017`
> **Request:** "check my new dataset for wormhole for eda analysis and dataset and mostly why it has fail and incl"
> (the wizard's `verify_attack.py` output: WORMHOLE CONFIRMED, with TunnelLatency INCONCL and LatencyHopRatio INFEASIBLE)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | linear | DLSU_Library | stationary | r1 | Oct 7, ~5:57–6:11 PM | 9 (8 telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ⚠️ 4 PASS / 5 WARN / 0 FAIL — harmless | the 5 WARN are filenames only: boards exported on other laptops are named `linear_none`, but their rows carry phase 2 (wormhole) correctly |
| Topology (raw telemetry) | ✅ linear chain of 8, stable | root → `704B` (L2) → `2805` → `FE90` → **A `1C38` (L5)** → `F42D` → **B `0C80` (L7)** → `ED80` (L8). One parent per node all run |
| **Auto-switch on hardware** (first run) | ✅ works | the `role` column says `wormhole_a` / `wormhole_b` from start to end, no change; A is shallower than B, so the cable skips 2 hops (B → F42D → A) |
| Root arrivals, recomputed by hand | ✅ wormhole signature | B's probes: baseline 300 single, **attack 181 probes x 2 copies = 362**, cooldown 120 single. Every other source ~1/s, single, all phases. Node A sends no probes of its own (by design: it only re-injects B's) |
| Duplicate timing (root clock) | ✅ | the 2 copies of each B probe arrive **2.8 ms apart** (median; 90 % within 6.5 ms) |
| Analysis tables vs exports | ✅ | 5,271 windows, 8 nodes × (~420 label-0 + 180 label-2). Tunnel* columns exist only for A and B, as designed |
| Verifier output | ✅ correct, not hardcoded | TunnelIntensity 0.012 → 1.000, TunnelBytes 0.35 → 30.0 match the data. The tiny baseline values are **2 windows (A + B) at second 355**, the last baseline second before the attack starts at 356: an edge effect, 2 of 3,363 windows |

### Why INCONCL and INFEASIBLE (neither is a data problem)
- **TunnelLatency = INCONCL**: it measures the gap between the two copies of a duplicated probe. In the baseline there
  is no tunnel, so no duplicates: only **1** baseline window has a value (the edge window above). A 3-sigma test needs a
  baseline spread (≥ 2 windows), so it **cannot** be tested. Expected for every wormhole run. Report it as a
  descriptive number for the attack (2–4 ms between copies), not as a 3-sigma result.
- **LatencyHopRatio = INFEASIBLE**: its baseline is very spread out (4.12 ± 6.46) because each node sits at a different
  depth in an 8-hop line (per-node baseline means 2.1 to 8.7). Against that spread the largest possible |z| is 0.64, so
  **no attack could ever reach 3σ** on the pooled value. It is a **secondary** feature and is left out of the verdict.
  Also note the open issue in MEMORY (sep. 30): its expected direction ("down") is ours, not Zhukabayeva's.

**Verdict: ✅ USABLE** — WORMHOLE CONFIRMED is genuine (both primaries; B's probes duplicated 181/181 in the attack), and
this is the **first hardware proof that the A/B auto-switch works** (D-17). Fix nothing; just footnote the two statuses.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #9 — Oct 7, 2026 · 5:30 PM — blackhole · partial_mesh · DLSU_Library · highload

> _Numbered #9 at merge: Bas's star/DLSU #8 (below, 10:35 AM) reached GitHub first._

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `90f3382` (firmware = highload root fix `643adf8`)
> **Request:** "check my recent datasets, eda, analysis" + the wizard's `verify_attack.py` output (BLACKHOLE CONFIRMED)
> **Why it matters:** first run with the highload root fix (arrivals → SD card only, batched). The 15:13 run of
> this cell lost 3,151 arrival rows (C5) and is archived in `datasets/archive/2026-10-07_…_highload-invalid/`.

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | partial_mesh | DLSU_Library | highload | r1 | Oct 7, ~5:00–5:12 PM | 9 (8 telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| **Highload fix: root arrival loss** (recomputed from `seq_num`) | ✅ **0 rows lost** | every source complete, e.g. `20500DE70C80` seq 447–3097 = 2,651 rows, 0 missing, 0 dup; ~3.98 probes/s each (= 4/s at 250 ms). Root was built as `build_root_blackhole_partial_highload` |
| Integrity (`validate_integrity.py`) | ⚠️ 8 PASS / 1 WARN — harmless | WARN = `B4BFE934ED80` 91.6 % coverage: 20 of its 21 gaps are in **stabilise (phase 255, excluded)**; 1 gap of 4.1 s at the very start of baseline |
| Topology (`verify_topology.py`) | ✅ stable, 0 parent switches | root → `0C80`, `704B` (L2) → `1C38`, `2805` (L3) → `ED80`, attacker **`F42DC973E618`** (L4) → **`FE90`** (L5). One parent per node all run (a plain 5-layer tree, as the root printout says) |
| Root arrivals, recomputed by hand | ✅ | victim `FE90`: 1,195 baseline → **0** attack → 482 cooldown; missing seq block = **721** = 180 s × 4/s. The other 5 sources delivered 719–721 each in the attack |
| Attacker counters, recomputed by hand | ✅ | received/forwarded/dropped: baseline 1195/1195/0, attack **721/0/721**, cooldown 481/481/0 — the 721 drops are exactly FE90's 721 missing probes |
| Phase timing | ✅ | baseline 300 s, attack 180.5 s, cooldown 120.5 s |
| Analysis tables vs exports | ✅ | 5,261 windows, 8 nodes; per node 420 label-0 (300 baseline + 120 cooldown) + 180 label-1 (FE90 410 + 180) |
| Verifier output | ✅ correct, not hardcoded | attacker FR 0.996 → **0.000**, pooled PDR 0.833 = 5/6 sources, per-node table and exposure match the raw data above |
| EDA (`eda_output/`, 28 files) | ✅ | leakage audit: no feature beats the label by itself suspiciously (best = ForwardingRatio 0.80 vs majority 0.70) |
| Sniffer (`…0446PM.pcap`) | ⚠️ no retry rate | `pcap_retry.py` refused: could not place the attack on the laptop clock (needs `--attack-start HH:MM:SS`) → `MacRetryRate` is empty (NaN) in this table. 2,863 frames dropped in the sniffer ring of 1.06 M heard |

### Small things found
- **Garbled telemetry row in `ED80`** (line 91): node_id `NODE_B4BFE934E_B4BFE934ED80` plus NUL bytes in the next
  row — a torn write on that child, **in stabilise**. `verify_topology.py` lists it as a 9th "node" with 1 sample;
  the analysis tables contain **0** such rows. Harmless here.
- Latency column is negative (about −94 s): child and root clocks are not synced, so it is an offset, not a delay. Don't quote it.
- The archived 15:13 run's `.pcap` and its regenerated `_retry.csv/.json` are still in the live `PCAP/…/highload/`
  folder (Wireshark held the file) — move them to the archive.

**Verdict: ✅ USABLE** — the highload root fix works on hardware (0 arrival rows lost at ~24 rows/s), and BLACKHOLE
CONFIRMED is genuine: victim `B4BFE932FE90` 0/721 in the attack; the other 5 are above the attacker (unaffected by design).

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #8 — Oct 7, 2026 · 10:35 AM — blackhole · star · DLSU_Library · stationary

> _Numbered #8 because Angelo's #6 and #7 (below) reached GitHub first. Done at 10:35 AM._

> **Requested by:** Bas · **Laptop:** Bas's (`No`) · **Commit:** `3926b3d` (capture not committed; 4 victim files staged, the rest untracked)
> **Request:** "check the most recent dataset which is the blackhole star dlsu library stationary if its valid or not"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | star | DLSU_Library | stationary | r1 | Oct 7, 10:00:41 boot · baseline 10:02:03 · attack 10:07:03 · cooldown 10:10:04 · terminate 10:12:05 | 9 (7 child telem + root telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ✅ 9 PASS / 0 WARN / 0 FAIL | raw and `trimmed/` both. "phase 0 ran 396–429 s" infos = boot segment + baseline, both phase_id 0 (see below) |
| Topology (`verify_topology.py`) | ⚠️ FAIL, false alarm | shape ✅ root → attacker `20500DE70C80` (layer 2) → 6 leaves (layer 3) = STAR (attacker hub), as built (`max_layer=3`). "Converged NO / re-routing NO" = the attacker's boot segment only (see below) |
| Attack (`verify_attack.py`) | ✅ CONFIRMED 2/2 | FR attacker 0.996 → 0.000 (z −31.51) · PDR 0.996 → 0.000 (z −27.26) · NeighbourFR z −39.09 · ConsistencyScore z +28.83 · IngressEgressDelta z +10.06 |
| Per-node PDR | ✅ all 6 victims 0.000 in attack | baseline 0.995–1.000, n = 179–180 attack windows each |
| Root arrivals (raw) | ✅ | baseline 1,793/1,800 (704B 294, F42D 299, rest 300) · attack **1** · cooldown 720 · 0 duplicate (src, seq) |
| Re-trim (`trim_run.py --apply`) | ✅ no-op | 1 boot session per node → 0 rows dropped, byte-identical to the existing `trimmed/` |
| Analysis tables | ✅ reproducible | re-ran preprocess + features on a scratch copy → every data column identical (5,802 × 46 / 5,802 × 71); only the 4 path-derived tag columns differ, because the scratch folder has no attack/topology path |

### ⚠️ Gate 2 FAIL is a false alarm (same mechanism as #4)
- Run log `blackhole-star-dlsu_library-stationary_r1_oct07_1000AM.log:38-53`: the wizard **full-erased and
  reflashed the root at ~10:00** while the 7 children were already up. On the attacker's clock (booted
  ~64 s before the root): phase 0 at 18 s, lost the root at 40 s and 66 s (= the erase/flash), new root's
  phase 255 at 70 s, stable under the root from 138 s, **real baseline 146 → 447 s (301 s)**. The other
  children show the same 255 → 0 → 255 → 0 pattern. ED80's log starts inside the first phase 0 (96 s);
  its real baseline is 191 → 492 s.
- `verify_topology.py` reads phase_id 0 as baseline, so it counts the attacker's 40–138 s drop as
  "baseline re-routing" and its converge time as 133 s. Inside the real baseline **no node changes parent
  or layer**. Expect `Topology FAIL` on every re-run of this capture.
- The pipeline handles it: `preprocess.assign_segments` tags those windows `pre_baseline` (996 windows,
  Label NaN), and they are excluded. Labelled: baseline 2,399 + cooldown 962 (Label 0), attack 1,440
  (Label 1 = 8 nodes × 180).

### Small things that look wrong but aren't
- **The 1 attack-phase arrival** is `20500DE71C38` seq 339, logged at root t = 382.03 s, 0.6 s before the
  root's ATTACK banner (382.64 s). It is a baseline probe that landed on the boundary.
- **5 windows are `segment = attack` but Label 0**: one boundary window per node at the end of the attack
  (181st window). Same as #4's one-window note.
- **FE90 "1 gap"** = a single 0.5 s step at 298.8 s. Coverage is still 100 %.
- **The attacker has no PDR row**: it sends no probes of its own (see #4). In a star it is the only relay,
  so "FR (all relays)" equals the attacker row by construction.

### ⚠️ Metadata mismatch: the preset names the WRONG attacker
- `presets/Bas/blackhole-star-dlsu_library-stationary.json` (untracked, a copy of the old
  `blackhole-star-g402-burst.json`) says node2 `20:50:0d:e7:1c:38` = **attacker**, node4
  `20:50:0d:e7:0c:80` = victim.
- What actually ran: `child_node4` = `20500DE70C80` with `role = blackhole` in every row, and the root's
  dashboard lists `20:50:0D:E7:0C:80 ATTACKER (BLACKHOLE)` all run. `child_node2` = `20500DE71C38` is
  an honest leaf (`role = child`, PDR 1.000 → 0.000). The children were flashed from another laptop (no
  child run log here), so where the swap happened is not known.
- **The labels in the data are correct.** The analysis takes the attacker from the firmware's `role` column, not
  the preset. But anyone using the preset as the run's board → node map gets it backwards. Fix the
  preset (or record the real map) before the next run or the write-up.

### ⚠️ Stray file in a different cell
- `exports/blackhole/tree/DLSU_Library/stationary/child_node3_tree_blackhole_r1_oct07_1019AM_telem.csv`
  is **1 row** (`F42DC973E618`, t = 21.9 s, phase 3), exported one minute after node3's real star file.
  It is junk. Left in place, it creates a bogus tree/DLSU_Library cell that `analyze.ps1` (no args)
  and `push_data.py` will pick up. Not deleted (user's call).

**Verdict: ✅ USABLE.** Blackhole confirmed on all primaries. Attacker `20500DE70C80` is the star hub. All 6
victims (`1C38`, `2805`, `704B`, `FE90`, `ED80`, `F42D`) are 1.000 → 0.000 during the attack and back to
100 % in cooldown. Before committing: fix the preset's attacker entry and delete the stray tree file.
Expect wizard re-verify to show Integrity PASS · Topology FAIL (boot segment) · Attack CONFIRMED.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #7 — Oct 7, 2026 · 2:36 PM — blackhole · partial_mesh · DLSU_Library · stationary

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `5134649`
> **Request:** "verify if this output is correct and not hardcoded" (the wizard's `verify_attack.py` output)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | partial_mesh | DLSU_Library | stationary | r1 | Oct 7, 2:07–2:26 PM | 9 (8 telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ⚠️ 4 PASS / 4 WARN / 1 FAIL — all harmless | FAIL = 1 leftover root row from before its last reboot (phase 255, excluded); 4 WARN = filenames say `partial_none` (named on the importing laptop) — the rows inside are correct |
| Topology (`verify_topology.py`) | ✅ partial, 4 layers | attacker `20500DE71C38` at L2 with exactly 2 nodes under it: `20500DE70C80`, `B4BFE932FE90` |
| Root arrivals, recomputed by hand | ✅ | those 2 delivered **0** in the attack, ~1/s otherwise; the other 4 ~1/s throughout; 4/6 = **0.667** = the pooled PDR |
| Attacker counters, recomputed by hand | ✅ | received/forwarded: baseline 600/600, attack **360/0** (360 dropped), cooldown 240/240 → FR 1 → 0 → 1. 600 = 2 children × 300 s, 360 = 2 × 180 s |
| Analysis table vs exports | ✅ | built from exactly the 8 exported telem files; `attack` = blackhole on every node (the `none` filenames did not leak in) |
| Verifier output | ✅ correct, not hardcoded | every row traces to the raw data above |
| `B4BFE932FE90` firmware | ✅ in sync this run | no out-of-sync FAIL (cf. #3/#5) — it is a real victim here (under the attacker) |

### The two odd-looking numbers
- **`-inf` (FR, PDR, NeighbourFR) and `+inf` (IngressEgressDelta):** baseline σ = 0 — every baseline point was
  exactly 1.000 (or 0.000). By design (`verify_attack.py:305`); report as **"z undefined (σ = 0)"**.
- **ConsistencyScore z = 1,178,647:** not real either. `features.py` computes
  `ForwardingRatio = forwarded / (received + EPSILON)` with `EPSILON = 1e-6` (divide-by-zero guard), so a
  window where the attacker forwarded all of its 1, 2 or 3 probes scores 0.999999… and ConsistencyScore
  = |FR − 1| = **1e-6 ÷ 1, 2 or 3** — exactly the only three baseline values found (3.3e-7, 5e-7, 1e-6).
  That float residue gives σ ≈ 3e-7 instead of 0, so 0.335 / 3e-7 ≈ 1.2 million. Same situation as the
  `-inf` rows: **σ is effectively 0 → report "z undefined"**. The PASS is right; the number is meaningless.

**Verdict: ✅ USABLE** — BLACKHOLE CONFIRMED is genuine; victims `20500DE70C80`, `B4BFE932FE90` (0/180 each).

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #6 — Oct 7, 2026 · 1:28 PM — wormhole auto-switch code + wormhole · tree · G402 · stationary

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `732b6ed` (+ uncommitted test refactor)
> **Request:** "verify if code works and doesnt break and then push"
> **Scope:** the oct. 7 wormhole changes (auto-switch firmware, root printout, `exposure.py`,
> verifier) — and, as the end-to-end test, the one existing wormhole capture.

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | tree | G402 | stationary | r1 | Oct 2 (pushed `bfa6386`) | 8 telem |

| Check | Result | Detail |
|---|---|---|
| Auto-switch logic, real firmware file on a PC (`tools/test_wormhole_autoswitch/run_test.sh`) | ✅ 35/35 | two simulated boards over a simulated cable: wrong-way build, same depth, cable unplugged, reboot mid-run, both lock one end, noisy cable, tunnel vs HELLO frames, one-way cable |
| All firmware variants (`build_all_variants.ps1` list, IDF 5.5.4, `-Werror`) | ✅ 15/15 | root/child/blackhole/wormhole incl. burst, jitter, highload; every app 25 % free (first pass hit "No space left on device" on C: — not code; rebuilt on A:) |
| Python tests (`test_segments`, `test_topology_graph`, `test_name_stamp`) | ✅ pass | |
| Verifier on every live blackhole cell, old vs new code | ✅ 0 differences | full output diffed line by line, 11 cells |
| Exposure on every live blackhole table | ✅ 0 rows changed | |
| Pipeline end-to-end on the wormhole capture (scratch copy, repo untouched) | ✅ runs | exposure: 2 `attacker` + 5 `not_tunnelled` + root |
| **Wormhole setup check on that capture** | ⚠️ **SAME DEPTH** | both ends at hop 1 for the whole attack |

### Finding: the existing wormhole capture had no shortcut
- Raw telemetry: during the attack (phase 2, 1,806 rows each) **Node B `20500DE70C80` and Node A
  `20500DE71C38` were both layer 2, both with the root (`B0:CB:D8:F3:32:19`) as parent.**
- So the tunnelled copy entered the mesh at the same depth as B's normal copy: duplicates are real
  (`WORMHOLE CONFIRMED`, 2/2 primaries), but **no latency advantage can exist** — the shortcut that
  defines a wormhole was not there. This is exactly the case the auto-switch now prevents or flags.
- Analysis tables for this cell are **not** in the repo (never built); the scratch run changed nothing.

**Verdict: code ✅ verified (not yet on hardware) · wormhole/tree/G402/stationary r1 ⚠️ USABLE FOR
DUPLICATION ONLY — recapture with the auto-switch firmware** (THESIS-UPDATE-CHECKLIST C4 / D3).

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #5 — Oct 4, 2026 (merged Oct 6) — why `B4BFE932FE90` looked like it had the wrong parent (follow-up to #3)

> _Numbered #5 because Bas's DLSU_Library block (#4, below) reached GitHub first. Done on Oct 4._

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `0b667b1`
> **Request:** "why is fe90 parent wrong? investigate the firmware"
> **This corrects #3:** FE90's `parent_mac` was **right**. FE90 was running **old (pre-Sep 21) firmware**.

| Attack | Topology | Location | Scenario | Repeat | Board |
|---|---|---|---|---|---|
| blackhole | tree | G402 | burst | r1 (Oct 2, 8:05 PM) | `B4:BF:E9:32:FE:90` (Kyle's) |

| Check | Result | Detail |
|---|---|---|
| Does FE90's parent field come from the mesh stack? | ✅ yes | `mesh_setup_get_parent_mac()` → `esp_mesh_get_parent_bssid()` (`mesh_setup.c:337`). Current firmware also sends its probes to that same address (`probe_relay.c` `send_to_parent`). |
| Was the attacker carrying FE90 all run? | ✅ yes | attacker received ~3/s in pre-baseline, baseline AND cooldown (2 known children = 2/s + FE90 1/s), 4.62/s in attack (2.64 burst target + 1 + FE90 1) |
| Can current firmware do this? | ❌ no | tree runs don't pin parents; children change phase only when a root message arrives (no local timer); the attacker only sees packets addressed to it |
| Pre-C7 firmware (before `67c6475`, Sep 21) | ✅ matches exactly | every victim in a blackhole build sent probes **P2P to the attacker's MAC** (`bh_dest`, old `victim_main.c:154`), and the compiled attacker was `20:50:0D:E7:1C:38`, the attacker in this run |
| Pre-session-id firmware (before `add1e6e`, Sep 27) | ✅ matches the late phases | a board that remembered an earlier run's sequence numbers ignored the new root's phase messages until the numbers caught up, so it lagged 34 → 68 → 94 s (10 s resync can't fix it) |
| FE90 in earlier runs | ✅ was current firmware then | tree/G402/jitter (Oct 2, ~7 PM): 205 probes delivered during the attack; partial_mesh/stationary: 178 delivered from under a relay. A pre-C7 board would have lost all of them. |
| Was it flashed from this laptop? | ❌ no | this laptop built no child image after Oct 1 11:48; for the burst run its wizard flashed only the ROOT (run log) |

### What really happened
1. Between the jitter run (~7:24 PM) and the burst run (8:05 PM), FE90 was **reflashed from another laptop with a stale
   child image**, built between Sep 20 (it writes the 14-column schema) and Sep 21 (before C7). Every other child ran
   current firmware: the attacker relays honestly in baseline, and the Oct 2 burst fix fired on `F42DC973E618`.
2. FE90 really was connected to the root (its `parent_mac` is correct). Its old firmware addressed every probe to the
   attacker `20:50:0D:E7:1C:38`, so the mesh carried each one root → attacker. The attacker's app relayed them back
   up to the root in baseline and cooldown, and dropped them during the attack. That's the old *targeted*
   (non-positional) blackhole, so FE90 became a victim without being under the attacker.
3. The same old image doesn't know about root sessions, so it took the new root's phase messages late. That is the
   "out of sync" FAIL, and it's why preprocess unlabelled FE90.

### Effect on the data (unchanged from #3)
The labelled dataset is clean, because FE90 has no labelled windows. RootArrivals 6 → 3 includes FE90's loss.
**Footnote for the write-up:** "one board ran an outdated firmware image and was excluded."

### To prevent it
- **Before r2: reflash FE90 from an up-to-date checkout** (`git pull` first) and check that the laptop's wizard
  pre-build shows the current commit.
- Not built (user's call): have each board put its firmware commit in the heartbeat, and have the root's
  roster gate refuse a board on a different commit. That would have caught this before Phase 0.

**Verdict for tree/G402/burst r1: still ✅ USABLE (with caveat)**. The caveat is now "FE90 ran stale firmware",
not "unexplained wrong parent".

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #4 — Oct 5, 2026 · 11:47 AM — blackhole · linear · DLSU_Library · stationary

> **Requested by:** Bas · **Laptop:** Bas's (`NO`) · **Commit:** `0b667b1` (capture staged, not committed)
> **Request:** "is inf alright for the thesis or not verify it" → "check the dataset folder properly
> why it was inf" → "what result am i expecting if i trim again and verify in run wizard"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | linear | DLSU_Library | stationary | r1 | Oct 5, 10:52–11:07 AM | 9 (7 child telem + root telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ✅ 9 PASS / 0 WARN / 0 FAIL | "phase 0 ran 381–443 s" infos = boot segment + baseline, both phase_id 0 (see below) |
| Topology (`verify_topology.py`) | ⚠️ FAIL, false alarm | "Baseline re-routing free: NO". The only change is in the boot segment, not the baseline (see below). Chain of 8 matches linear ✅ |
| Attack (`verify_attack.py`) | ✅ CONFIRMED 2/2 | FR attacker 1.000 → 0.014 (z −60.85) · PDR 1.000 → 0.669 (**z −inf**) · NeighbourFR z −91.38 |
| PDR rebuilt from raw exports | ✅ matches | seq-number join of telemetry vs root arrivals, no pipeline code: baseline 1,805/1,805 delivered |
| Re-trim (`trim_run.py --apply`) | ✅ no-op | 1 boot session per node → 0 rows dropped, output byte-identical to the existing `trimmed/` |
| Analysis tables | ✅ reproducible | re-ran preprocess + features on a scratch copy → `feature_table.csv` identical (5,800 × 71) |

### Why PDR is `-inf`: the baseline genuinely lost zero probes
- `verify_attack.py:305-318`: when the baseline sd is exactly 0, the script does not compute z. It
  prints `-inf` as a flag meaning "the mean dropped at all" and counts that as PASS. This is the same
  mechanism as the FR `-inf` in #3.
- **Raw data, per phase (honest children, sent → received at root):**

| Phase | Sent → received | Root arrivals |
|---|---|---|
| 255 pre-start (65 s) | 390 → 390 | 390 |
| 0 baseline (300 s) | **1,805 → 1,805** | 1,805 |
| 1 attack (180 s) | 4 bystanders 721 → 721 · victims `704BCA25B768`, `B4BFE932FE90` **0/180 each** | 721 |
| 3 cooldown (120 s) | 724 → 724 | 724 |

- No duplicate (src, seq), no counter resets, 0 `_pdr_clipped` rows. σ = 0 is real, not a filtering
  artefact. The verifier's "baseline" (Label 0) = baseline + cooldown = 3,359 windows = 516 blocks,
  and both phases were perfect.
- **For the thesis:** the PASS stands, but do **not** write "z = −∞". Write: *"PDR baseline
  1.000 ± 0.000 (1,805/1,805 probes delivered); victims 0/180 during the attack. z is undefined
  (σ = 0); any sustained drop is outside the 3σ band, and the victims fell to the minimum possible
  value."* Caveat a panel may raise: with σ = 0 the band has zero width, so even one lost probe would
  pass. Here the drop is total, so the result is not marginal.

### What the pipeline handled correctly (looks like loss, isn't)
- **Boot segment.** The run log shows the wizard **full-erased and reflashed the root at 10:52**
  while the 7 children were already running. Each child logged `phase_id = 0` for 16–87 s before
  the new root's first broadcast. The root's arrivals log starts at its own boot (phase 255), so
  those probes have no delivery record. `preprocess.assign_segments` tags them `pre_baseline`
  (476 + 519 windows, Label NaN), and they are excluded.
- **Victim `704BCA25B768` reads 0.0055, not 0.000.** Window 423 is labelled phase 1 but holds seq 429,
  sent at the end of baseline, and that probe arrived. One window of 181 reads 1.0. True attack
  delivery is **0/180**: quote 0.000.
- **The attacker (`F42DC973E618`) has no PDR.** It sends no probes of its own
  (`child_node/main/blackhole_victim.c:40`). Its `probes_count` = probes **received for relay**
  (`:49`, `:388`), which is about 2/s = its two downstream victims. PDR excludes the `blackhole` role
  by design (features.py rule 1).

### ⚠️ Gate 2 FAIL is a false alarm
- The only parent/layer change in the run: `20500DE71C38` (root's direct child) lost its parent at
  t = 66.4 s and rejoined the root at 92.7 s, which is the root reflash above. That is **inside the
  boot segment**, before the first phase-255 broadcast at 96.3 s. The real baseline (161–462 s) has
  zero changes on every node.
- `verify_topology.py` counts the boot segment as baseline because it also reads phase_id 0. Expect
  `Topology FAIL` in every re-run of this capture. It does not touch the analysed data.

**Verdict: ✅ USABLE.** The attack is confirmed on all primaries. Victims: `704BCA25B768` (hop 6) and
`B4BFE932FE90` (hop 7), both 0/180. The other 4 children sit above the attacker and are unaffected
by construction. Re-trimming and re-verifying in the wizard reproduces exactly this: Integrity PASS ·
Topology FAIL (boot segment) · Attack CONFIRMED with PDR `-inf`.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #3 — Oct 3, 2026 · 9:16 PM — blackhole · tree · G402 · burst

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `4def0f8`
> **Request:** "verify is this is correct [verify_attack output] and if the analysis, eda,
> timeseries are correct and also put it to the verify docs"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | burst | r1 | Oct 2, 8:05–8:23 PM | 9 (8 telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ⚠️ 8 PASS / 1 FAIL | FAIL = `B4BFE932FE90` out of sync with the root (27 % of its probes in the wrong phase) |
| Burst fired | ✅ YES, inside the attack | target `F42DC973E618`: seq 389 → 866 over the 182 s attack ≈ +295 burst probes (firmware fix `6b90df5` now proven on hardware) |
| Topology (`verify_topology.py`) | ⚠️ tree, depth 2 — but FE90's parent is wrong | reported: 2 victims under attacker `20:50:0D:E7:1C:38`; really 3 (FE90, see below) |
| Attack (`verify_attack.py`) | ✅ CONFIRMED 2/2 | FR attacker 1.000 → 0.000 (−inf) · PDR 0.999 → 0.600 (z −23.36) |
| Analysis tables | ✅ match the verifier | 7 nodes labelled (~420 baseline+cooldown / ~180 attack windows each); FE90 unlabelled |
| EDA time series | ✅ correct | attacker FR → 0, both victims' PDR → 0, root arrivals 6 → 3, all recover in cooldown |
| EDA PCA / t-SNE | ✅ correct | attack windows form their own cluster (the Oct 2 fix works here) |

### The verifier output: correct
- **Pooled PDR 0.600** = average of the 5 labelled children: 2 victims at 0.0 (`20500DE70C80`,
  `F42DC973E618`, both hop 2 under the attacker) + 3 at 1.0. That is 2 out of 5 lost, so 0.6. It matches
  the per-node table and `feature_table.csv`.
- **ForwardingRatio (attacker)** 1.0 → 0.0. The one honest relay (`B4BFE934ED80`, which carries
  `704BCA25B768`) stays at 1.0, so the "all relays" row averages to 0.5. Arithmetic is correct.
- **ConsistencyScore 0.5 / IngressEgressDelta 0.654:** these move in the expected direction because the
  attacker's numbers change and the honest relay's don't.
- **Why `-inf`:** in baseline the attacker forwarded exactly 100 % in every 5-window point, so the
  standard deviation is 0. Any drop divided by 0 is infinite. `verify_attack.py:305-316` does this on
  purpose and counts it as a PASS ("baseline sd=0 (perfectly stable)"). This is not a bug. PDR gives a
  finite confirmation at z −23.36.

### ⚠️ Problem found: `B4BFE932FE90` was a hidden third victim
- Its own log says its parent is the root (`B0:CB:D8:F3:32:19`, layer 2) for the whole run, with
  0 send failures, sending 1 probe/s.
- **Not one of its probes reached the root during the root's attack (396–578 s on the root's clock).**
  They resumed the moment cooldown began. Its seq jumped 388 → 568 across that gap, so it did keep sending.
- **The attacker received 835 probes during the attack. The two known victims sent 656 (180 + 476).**
  The extra ~179 match FE90's 180. So FE90's traffic was going through the attacker, and its
  `parent_mac` field is wrong (stale). It also changed phase late (34 s at baseline, 68 s at attack,
  94 s at cooldown, despite a 10 s resync), which suggests the root's messages to it were also slow.
  Why the reported parent was wrong is not known yet. It is a firmware/mesh question, not a data bug.
- **Effect on the data:** preprocess already unlabels FE90 (out of sync), so it is in **no** labelled
  window, no verifier row and no EDA trajectory (the plot's title says so). The labelled data is clean.
  The only trace left is the root's **RootArrivals** feature: it falls 6 → 3 (3 victims), not 6 → 4.
- `verify_topology.py` shows the tree from the nodes' own parent fields, so it puts FE90 under the root.
  Don't quote "2 victims" for this run without this footnote.

### Other notes
- The attacker dropped 11 probes in baseline (queue or send failures, not the attack). Its baseline FR
  is 1.002, and the 5-window points are exactly 1.0.
- `20500DE71C38` (attacker), `704BCA25B768` and FE90 changed parent before baseline, which is the
  pre-baseline idle time and is excluded. No labelled node changes parent or layer inside
  baseline/attack/cooldown.
- PCA dropped IngressEgressDelta as "constant" after removing NaN rows. The verifier still uses it
  (z 19.98). This is the same expected behaviour as earlier cells.

**Verdict: ✅ USABLE (with caveat)**: 7 of 8 nodes are labelled and the attack and burst both fired. Footnote
FE90 as an unlabelled third victim with a wrong parent field. Before r2, watch the root's
PARENT/CHILD dashboard for a board whose reported parent doesn't match how its traffic actually travels.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #2 — Oct 2, 2026 · 7:58 PM — sweep of ALL live cells

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `12207b6`
> **Request:** "fix it and check the previous runs and datasets"
> **Scope:** the 9 cells under `datasets/analysis/` (archive folders not included).

| # | Attack | Topology | Location | Scenario | Repeat(s) | Captured | Integrity | Topology | Attack verdict | Analysis | EDA | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | blackhole | linear | G402 | jitter | r1 | Oct 1 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 2 | blackhole | linear | G402 | stationary | r1 | Sep 30 | ⚠️ 6 PASS / 3 WARN | ⚠️ | ✅ CONFIRMED | ⚠️ | ✅ | ✅ USABLE (caveat) |
| 3 | blackhole | linear | home | burst | r1 | Sep 30 | ✅ 8/8 | ✅ | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 4 | blackhole | linear | home | highload | r1–r4 | Sep 27–30 | ⚠️ 26 PASS / 2 WARN | ➖ not measured | ⚠️ INCONCLUSIVE | ✅ | ✅ | ⚠️ PARTIAL |
| 5 | blackhole | partial_mesh | G402 | jitter | r1 | Oct 1 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 6 | blackhole | partial_mesh | G402 | stationary | r1 | Sep 30 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ✅ | ✅ USABLE |
| 7 | blackhole | star | G402 | stationary | r1 | Oct 1 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ✅ | ✅ USABLE |
| 8 | blackhole | tree | G402 | jitter | r1 | Oct 2 | ✅ 9/9 | ✅ (see #1) | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 9 | blackhole | tree | G402 | stationary | r1 | Sep 30 | ⚠️ 5 PASS / 4 WARN | ⚠️ | ✅ CONFIRMED | ⚠️ | ✅ | ⚠️ DEGRADED — re-capture advised |

**Done in this verification**
- ✅ **EDA PCA/t-SNE fix** (`analysis/eda.py`, `run_dimensionality_reduction`): new rule drops a column
  that is present for a node in one phase but missing in another (its missingness *is* the label).
  Before, those rows were deleted and the victims' PDR = 0 windows vanished from the plot.
  Regenerated `dimensionality_reduction.png` for the 4 affected cells (#1, #3, #5, #8). Every EDA CSV
  stayed byte-identical; `test_segments.py` passes. Victim attack windows now in the plot:
  linear/jitter +191, linear/home/burst +190, partial_mesh/jitter 0 → 403, tree/jitter 0 → 202.
- Every cell: analysis feature table contains exactly the exported telemetry files (none missing, none
  extra), and no node changes parent or layer **inside** the analysed baseline/attack/cooldown
  windows — except tree/G402/stationary (below).

**Per-cell details**

- **#1 linear · G402 · jitter** — Jitter fired: baseline 312.5 s / attack 190.5 s (nominal 300/180).
  Linear chain of 8; attacker `20:50:0D:E7:1C:38`; 5 victims, 1 bystander above the attacker kept
  delivering. FR attacker 0.999 → 0.000 (z −101.5); PDR 1.000 → 0.169 (z −inf, baseline sd 0).
  ConsistencyScore FAIL is secondary (not counted). PCA dropped ForwardingRatio/ConsistencyScore — they
  carried nothing there (the attacker's rows were already dropped for having no PDR).
- **#2 linear · G402 · stationary** — Verdict sound: FR attacker z −137.9, PDR 0.997 → 0.000, 6 victims,
  0 probes reached the root during the attack. ⚠️ 3 victims (`704B…`, `FE90…`, `ED80…`) sat in phase 0
  for ~23 min before the real run (the root restarted) → integrity "4× baseline rows" WARN; that time
  is pre-baseline and excluded, so the WARN is harmless. ⚠️ `FE90` and `ED80` lost about half their
  attack (91 / 104 of 180) and cooldown (54 of 120) windows: their raw samples are complete but
  unevenly timed, so the paper's minimum-samples rule (§4.2.4.1) discarded those windows. Correct
  behaviour; those 2 nodes are thinner in the data.
- **#3 linear · home · burst** — FR attacker z −64.0, PDR 0.994 → 0.203, 4 victims. 3 nodes' logs start
  inside a phase (formation not recorded) — fine. PCA same column change as #1.
- **#4 linear · home · highload (r1–r4)** — ⚠️ INCONCLUSIVE when pooled, already known (MEMORY oct. 1):
  r2/r3 baselines are broken by the 7-board highload collapse (r2 cooldown only 70 % of baseline;
  r4 root logs WARN), so the pooled baseline is noisy. r1 + r4 alone confirm. Root fix (`cb22106`)
  is built but not yet run on hardware. Formation not measured (every log starts inside a phase).
- **#5 partial_mesh · G402 · jitter** — Jitter fired: baseline ~340 s / attack ~202 s. 2 victims
  (`FE90…`, `F42D…`), 4 sources kept delivering. FR attacker z −8.2, PDR 0.997 → 0.667. **Had the same
  PCA bug as tree/jitter** (0 victim attack windows in the plot) — fixed.
- **#6 partial_mesh · G402 · stationary** — FR attacker z −27.7, PDR 0.998 → 0.500, 3 victims. Clean.
- **#7 star · G402 · stationary** — Hub = attacker `20:50:0D:E7:1C:38`, all 6 victims hang off it; 1 probe of
  ~1077 reached the root during the attack. FR attacker z −24.0, PDR 0.995 → 0.000, 6 victims. Clean.
  (Topology check must be run with `--dir datasets/exports` + filters; pointed at the cell folder it
  reports "No captured telem CSVs" — tool quirk, not data.)
- **#8 tree · G402 · jitter** — see VERIFICATION #1 below.
- **#9 tree · G402 · stationary** — ⚠️ **Two boards dropped out mid-run.** `704B…` (child-4) logged only
  304 s and stopped ~53 s before the attack (no attack/cooldown windows). `2805…` (child-5) stopped
  97 s into the attack (no cooldown). `ED80…` lost its parent each time and re-parented
  (704B → 2805 at −50 s, → root at +113 s), so it changes parent **inside** the analysed windows.
  Root arrivals: 2 victims never returned in cooldown (71 % of baseline). The attack verdict still
  holds (FR attacker z −8.9, PDR 0.995 → 0.552, 2 victims), but the cell has 7 of 8 nodes and broken
  cooldowns. **Recommend capturing r2** before relying on this cell.

**Verdict: 7 ✅ usable · 1 ⚠️ partial (highload, known) · 1 ⚠️ degraded (tree/G402/stationary → re-capture r2)**

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #1 — Oct 2, 2026 · ~7:30 PM — blackhole · tree · G402 · jitter

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `9aec136`
> **Request:** "check if our dataset is correct, and the verifier, and also check if the analysis,
> eda timeseries are all correct for tree blackhole, g402 jitter. and why there is infinity value"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | jitter | r1 | Oct 2, 6:56–7:24 PM | 9 (8 telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ✅ PASS 9/9 | 10 Hz, 100 % coverage, trimmed = raw |
| Jitter fired | ✅ YES | baseline 331 s / attack 206 s (nominal 300/180), cooldown 120 s |
| Topology (`verify_topology.py`) | ✅ tree, depth 2 | 1 victim under attacker `20:50:0D:E7:1C:38` |
| Attack (`verify_attack.py`) | ✅ CONFIRMED 2/2 | FR attacker z −20.3 · PDR −inf (baseline sd 0) |
| Analysis tables | ✅ match exports | 300 s baseline / ~205 s attack / 120 s cooldown per node |
| EDA time series | ✅ correct | attacker FR → 0, victim PDR → 0, root arrivals 6 → 5 |
| EDA PCA / t-SNE | ⚠️ → ✅ FIXED | victim attack windows were dropped; regenerated (see #2) |

### Dataset: correct
- **Integrity:** all 9 files pass (8 node files plus the root's arrivals). Sampling is a steady
  10 Hz with 100 % coverage. The trimmed copies are byte-identical to the raw exports.
- **Jitter fired:** the root ran a 331 s baseline and a 206 s attack, against the normal 300 s and
  180 s. Cooldown was 120 s.
- **Topology:** a real tree, 2 hops deep, all 8 nodes reachable. The attacker is
  `20:50:0D:E7:1C:38` at hop 1, and one victim, `70:4B:CA:25:B7:68`, sits under it at hop 2.
- **Root arrivals:** 6 sources sent probes in baseline. During the attack exactly one went silent
  (the victim) and the other 5 kept delivering. Cooldown recovered to 100 %.
- **The "parent changed during baseline" warning is harmless.** Every node dropped its parent at
  once about 416 s before the attack and rejoined about 22 s later, which is the root rebooting
  when it was flashed last. The analysis uses only the last 300 s of baseline, so none of this
  enters the data. Hop and layer stay constant for every node through baseline, attack and cooldown.

### Verifier: correct
- **ForwardingRatio (attacker):** dropped from 1.0 to 0.0, z = −20. This is the main evidence.
- **PDR:** the victim went from 1.0 to 0.0, and the other 5 children stayed at 1.0. The pooled
  0.835 is about 5 of 6 nodes, so the pooled number matches the per-node rows.
- **IngressEgressDelta FAIL:** expected, and it doesn't affect the verdict because it's a secondary
  feature. Only the attacker changed (0.013 → 0.985), but the row averages all 8 nodes, which
  waters it down to z = 2.26.
- **Verdict:** BLACKHOLE CONFIRMED (2 of 2 primary checks), and the evidence supports it.

### Why there is `-inf`
z = (attack mean − baseline mean) ÷ baseline standard deviation. For PDR and
NeighbourForwardingRatio, every baseline point was exactly 1.000: no probe was lost during
baseline. That makes the standard deviation 0, and any drop divided by 0 is infinite.
`verify_attack.py:305-316` handles this on purpose: it prints ±inf and adds the note
"baseline sd=0 (perfectly stable)". It means any drop counts as an anomaly, not that there's a
bug. No inf values exist in the feature table or the EDA CSVs.

One caution for the write-up: pooled PDR passes only because the baseline was perfect. With one
victim among 6 children, even a little baseline loss would have made it fail. Quote the victim's
per-node PDR (1.0 → 0.0), which the verifier itself recommends.

### EDA time series: correct
- The combined plot shows what you'd expect: the attacker's forwarding drops to 0 only during the
  attack, the victim's PDR drops to 0 only during the attack, root arrivals go from 6 to 5 per
  window, and everything recovers in cooldown. The individual node plots match.
- **Known quirk:** the plots show a 300 s baseline, not the full 331 s, because the analysis keeps
  only the last 300 s. This was already noted in MEMORY on Oct 1.
- **Minor:** 7 of 2,328 ForwardingRatio windows go above 1 (max 3.0), when "forwarded" lands one
  window after "received". The 5-window plots and the verifier average this out.

### Problem found: the PCA/t-SNE plot missed the attack (fixed in #2)
The plot labelled PDR as "constant (no variance)", which is wrong for this run:
1. The victim's 205 attack windows have no LatencyHopRatio, because no probe reaches the root so
   there's no latency to measure.
2. The PCA step drops every row with a missing value, so all of the victim's PDR = 0 rows
   disappear.
3. The PDR values left are all 1.0, so PDR is thrown out as "constant". ForwardingRatio is also
   excluded because it only exists for relay nodes.

So the PCA/t-SNE plot had no attack signal left in it, which is why the phases looked mixed. It's
the same kind of bug as the one fixed on Oct 1, but the earlier fix didn't catch it because only
1 of 6 nodes is a victim here. It doesn't affect the dataset, the verifier or the time series.

**Verdict: ✅ USABLE** — quote the victim's per-node PDR, not the pooled one.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->
