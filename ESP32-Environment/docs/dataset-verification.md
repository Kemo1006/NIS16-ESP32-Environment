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

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #81 — Oct 21, 2026 · ~12 AM — member's paper copy with the new Chapter 5: every Chapter 5 number recomputed, merged into v4

> **Requested by:** Basti · **Laptop:** Basti's · **Commit:** `f22ee5cd`
> **Request:** "check everything again the paper folder and plan folder like what we did 2 hrs ago" (`Plan/Paper-Editing/1-Working-Copy/All in one (CTHESIS3).docx`)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | all 4 | G402, DLSU_Library, Yuchengco | stationary, burst, highload | r1 | sep. 30 – oct. 19 | 36 feature tables as of `709e455` (the draft's snapshot) + the current tree/G402 burst/highload tables |

| Check | Result | Detail |
|---|---|---|
| Which copy the member's file is | ⚠️ | an older copy (43 runs, MacBook, dev dates, no D-23…D-32) + a new Chapter 5; 143 of v3's 165 green-fixed paragraphs are missing from it |
| Table 5.1 windows by phase | ✅ exact | 213,148 = 41,076 / 85,570 / 51,286 / 33,901 / 1,315 |
| Table 5.2 boards behind / not behind | ✅ exact | 33/21, 18/36, 54/0, 20/33 (125/90); FE90 missing in tree/G402/burst |
| Table 5.3 notes | ✅ | B768 94 s victim, neighbours 42 %, ED80 266/300 s, Yuchengco victim baseline 0.734, B768 no windows after +28 s |
| Table 5.4 coverage | ✅ (method) | matches only when counted over ALL 213,148 windows (incl. pre-baseline) — said so in the text now |
| Table 5.5 verifier checks | ✅ exact | FR 36/36 (1.000–1.004 → 0.000–0.007, \|z\| ≥ 22.9, median 115, 14 undefined), PDR 35/36, CS 31, IED 31, NFR 31 + 4 no data + 1 fail |
| Verifier outcome tree/G402/burst (snapshot) | ⚠️ | VERDICT confirmed, but OUTCOME INCONCLUSIVE (MAJOR GAPS, FE90) — added to Table 5.3 |
| Table 5.6 collapse / recovery | ✅ | 121 of 123 victims below 0.5 in their own first attack window; recovery median 2 s, max 3 s (from the last attack window); 1 silent board |
| Table 5.7 single-feature audit | ✅ exact | `analysis/leakage.py` method: 0.871/0.997, 0.846/0.998, clock 0.802/0.800, missingness 0.990, 99.5 % |
| Table 5.8 means + Cohen's d | ✅ | means exact; d = −16.55 uses √((s₁²+s₂²)/2), not the n-weighted pooled SD (−17.39) — wording changed |
| §5.3 correlations | ✅ | same four pairs ≥ 0.5 in all / baseline / attack |
| §5.4 clustering (spot check) | ✅ | pools 126,741 / 127,666 exact; 42 % bystander windows; ceiling 0.526 vs 0.528; K-Means REDUCED ARI 0.516 vs 0.515, victims 0.987 vs 0.991; FULL / no-PDR ≈ 0 |
| REDUCED low-variance rule | ❌ | ">90 % identical values" keeps RSSI_stability (74.6 %); the stated rule does not produce the stated set → PENDING added |
| Draft says re-analysed tree tables are not on GitHub | ❌ stale | pushed in `6fb00803`: burst now PASS (8 boards), highload CONFIRMED but INCONCLUSIVE (missing board role), windows 212,417 |
| Member's 7-board highload limitation | ❌ outdated | sep. 30 home test; campus 8-board highload baseline and cooldown PDR 1.000 (lowest run 0.998). v2 had already deleted it (tracked) |

**Verdict: ⚠️ Chapter 5 is computed correctly from its snapshot; 4 wording/method fixes + 1 stale note fixed in green. Merged into `…_8boards v4 (Chapter 5 merged and checked, oct. 21, 2026).docx` (v3 + the member's Chapter 5); the member's file is left as is. Action: rerun Chapter 5 on the current tables; the member says which low-variance filter was used.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #80 — Oct 21, 2026 · ~12:40 PM — paper Figure 5.4 (single-feature audit, three groups of nodes)

> **Requested by:** Basti · **Laptop:** Basti's · **Commit:** `f4834e50`
> **Request:** "check figure 5.4" (`Plan/Paper-Editing/1-Working-Copy/…_8boards v4 (Chapter 5 merged and checked, oct. 21, 2026).docx`, `word/media/image67.gif`)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | all 4 | G402, DLSU_Library, Yuchengco | stationary, burst, highload | r1 | sep. 30 – oct. 19 | 36 feature tables at `709e455` (draft snapshot, 213,148 rows) and at HEAD (212,417 rows); jitter + home excluded |

| Check | Result | Detail |
|---|---|---|
| Who made the figure | ⚠️ | no repo script draws it (no "victims only" / "Single-feature audit" string in code); recomputed with `analysis/leakage.py` `single_feature_decidability`, label attack = 1, baseline + cooldown = 0 |
| Groups | ✅ | all non-root = child + blackhole rows (149,191); child nodes = `node_role` child (127,680); victims only = child with `exposure` downstream (74,092) |
| Bars, panel 1 (all non-root) | ✅ | PDR 0.871, LHR 0.846, FR 0.804, CS 0.803, IED 0.737, RetryRate 0.731, rest 0.699-0.700; majority 0.700 |
| Bars, panel 2 (child nodes) | ✅ | PDR 0.871, LHR 0.846, FR = CS 0.717, rest 0.699-0.700; majority 0.700 |
| Bars, panel 3 (victims only) | ✅ | LHR 0.998, PDR 0.997, rest 0.698-0.699; majority 0.699 — matches the paragraph |
| Current data (HEAD) | ⚠️ minor | victims PDR 0.999, LHR 1.000, LHR missingness 0.992 (paragraph: 0.997 / 0.998 / 0.990); every other bar within ±0.002 — the picture does not change |
| Colour of LatencyHopRatio | ❌ | text + Table 5.4: "kept out of the clustering"; figure: blue "analysed feature" (panels 1-2) and red "analysed feature that decides the label alone" (panel 3) |
| Colour of FR / CS / IED | ⚠️ | blue "analysed" in panel 1, grey "kept out" in panels 2-3; Table 5.4: attacker-side record, kept out of the child-node clustering — caption does not explain the switch |
| Panel names vs text | ⚠️ | text says "the nodes behind the attacker" and "three groups of nodes" but never names them; panel 1 includes the attacker's rows (why FR/CS reach 0.80 there) |
| Image quality | ⚠️ | 779×362 GIF — low for print |

**Findings:**
- The numbers in the figure are right for the draft's snapshot; the drift on current data is ≤ 0.002 and does not change any conclusion.
- The legend contradicts the text for LatencyHopRatio: the paper says it is kept out because its *missing* value gives away the label (0.990), but the figure marks it as an analysed feature, and in panel 3 as the one that "decides the label alone" next to PDR.

**Verdict: ⚠️ figure data correct; fix the colours (LatencyHopRatio grey in all panels; FR/CS/IED consistent or explained), name the three groups in the text, re-export at print resolution. Logged as checklist B-fig54.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #79 — Oct 21, 2026 · ~11:25 AM — wormhole/star/DLSU_Library/burst: "how come there is no value" in the feature table + "is the dataset good"

> **Requested by:** Basti · **Laptop:** Basti's · **Commit:** `f4834e50` (feature_table.csv unmodified vs HEAD, built after `1ccb3a6e` phase-255 latency fix)
> **Request:** two screenshots of `feature_table.csv` (rows 98-131 = 0C80 pre_baseline, rows 1434-1467 = 1C38 attack) with blank columns — "how come there is no value … verify it" + "verify if the dataset is good or not"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | star | DLSU_Library | burst | r1 | oct. 21 ~10:01 AM run, exported 10:15-10:27 AM | root telem + arrivals, 7 children (E618 hub/A, 0C80 B, 5 plain), 6,118 feature rows |

| Check | Result | Detail |
|---|---|---|
| Blank ForwardingRatio / IngressEgress / Consistency / Neighbour* | ✅ by design | filled only where `recv_count_delta > 0` (`features.py:191-212`) = the hub E618 (100 % in phases 0-3); star leaves relay nothing → NaN, not 0 |
| Blank RetryRate (0C80 pre_baseline, screenshot 1) | ✅ by design | NaN when tx+retry = 0 (`features.py:515`); 0C80 sent 1 frame in its 312 pre-run windows |
| Blank LatencyHopRatio in pre_baseline | ✅ by design | root phase-255 arrivals dropped (`features.py:974-976`, fix `1ccb3a6e`); children 99-100 % filled in attack |
| Blank Tunnel* on child rows (screenshot 2) | ✅ by design | Tunnel features only for wormhole_a/b (`features.py:1291-1292`); TunnelLatency only on 0C80 (the duplicated sender), 99 % in attack |
| Blank MacRetryRate everywhere | ✅ expected | no sniffer capture for wormhole/star (`datasets/PCAP/wormhole/` has partial_mesh only); context feature, not scored |
| Gate 1 integrity | ✅ | 9 files, 9 PASS, 0 WARN; 180 duplicate deliveries from 0C80 in phase 2 |
| Gate 2 topology `--expect star` | ✅ | hub E618 = wormhole A, 6 direct nodes, settled before Phase 0, no baseline re-routing |
| Gate 3 attack | ✅ | WORMHOLE CONFIRMED 2/2 (TunnelIntensity 0 → 0.994, DuplicateRate 0 → 0.986), UART 178/178, CONFIDENCE STRONG, OUTCOME PASS |
| Burst | ✅ | ED80 +292 extra probes (verify_burst); +296 in 10 s at 62 s into the attack (verify_attack) |
| PDR plain children | ✅ | 1.0000 baseline and attack, all 5 |

**Findings:**
- None of the blanks is missing data. Every blank is a feature that is *undefined* for that board or phase, and the code writes NaN on purpose so "not applicable" is never read as a measured 0.
- The `missing_firmware_fields` column says `ForwardingRatio,IngressEgressDelta,ConsistencyScore` on all 6,118 rows, including the hub rows that do have values. It is a fixed schema label (`features.py:134-144`), not a per-row flag — misleading when read in Excel.
- E618 and 0C80 flip roles a/b in phase 255 (stabilisation) only; phases 0-3 are stable (same as #72). Cosmetic: integrity says "expected for the blackhole attacker" for E618 in a wormhole run.

**Verdict: ✅ usable. The empty cells are role/phase-gated features, not a fault; the capture passes all three gates plus the burst check with STRONG confidence.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #78 — Oct 21, 2026 · ~12:30 PM — Campaign "Selected run" vs Verify page out of sync (blackhole/tree/Yuchengco/burst)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `357d91f` + uncommitted (#75-#77, `run_gui.ps1`)
> **Request:** "check blackhole tree yuch burst why the selected run notes or verdict there didn't match what verify page showing ... make sure everything in sync and aligned"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole (+ all) | tree | Yuchengco | burst | r1 | oct. 11 8:29 PM | `%LOCALAPPDATA%\NIS16\reports\*.txt`, `verdicts.json`, live `tools/redo_list.py --json` |

| Check | Result | Detail |
|---|---|---|
| tree/Yuchengco/burst: saved report vs live redo check | ✅ same | CONFIRMED · MINOR GAPS · OUTCOME PASS; gap = 0C80 (bystander) 40 of 300 s baseline windows; note = force-start not checkable; Campaign CHECK (yellow) |
| All 63 runs: report VERDICT = verdicts.json line | ✅ 63/63 | all re-saved 11:40-11:41 |
| All 63 runs: report OUTCOME = redo outcome | ✅ 63/63 | |
| All 63 runs: report grade -> expected tile = redo severity | ✅ 61/63 | the 2 others are by design: blackhole/linear/G402/burst + linear/home/burst are CHECK because scenario burst NOT APPLIED |
| Reports older than their analysis | ✅ 0 | |

**Findings:**
- The stored results are aligned. The mismatch came from the GUI being open while results changed outside it (this session's batch Verify at ~10:18 and the full re-analysis 10:24-11:25).
- **GUI bug fixed (`run_gui.ps1` `Save-AnaResult`):** it saved its WHOLE in-memory verdict list (loaded at GUI start) on every Verify, writing every other run's old verdict back over newer ones -> Campaign (live re-check) and Verify (stored verdict) could disagree. It now calls `Read-Verdicts` first, so a save only changes its own run. Self-test passes. Takes effect on the next GUI start.

**Verdict: ✅ all 63 runs aligned across report, verdict store and redo check; the stale-overwrite cause is fixed. Restart the GUI once (or Campaign -> Re-check the redo list) to see it.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #77 — Oct 21, 2026 · ~12:00 PM — are all the analysis graphs correct?

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `357d91f` + uncommitted re-analysis of all 61 cells (#76)
> **Request:** "can you check all the graphs in analysis are those correct?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | r1 | 61 analysed cells, 1,170 PNGs | `datasets/analysis/**/eda_output/*.png` (+ the `correlation_*.csv` behind the maps) |

| Check | Result | Detail |
|---|---|---|
| Every plot newer than its feature table | ⚠️ 7 stale | `dimensionality_reduction_tunnel_ends.png` in 7 BLACKHOLE cells |
| Per-board timeseries = boards in the table | ✅ | 0 orphans, 0 missing (eda._find_orphan_timeseries + per source_file) |
| Blank / broken images (< 8 KB) | ✅ 0 | |
| Blackhole plots (linear/G402/stationary, tree/G402/burst) | ✅ data correct | PDR 1 -> 0 -> 1, root arrivals 6 -> 0 -> 6, attacker FR 0; PCA attack cluster separate |
| Wormhole plots (star/G402/stationary) | ✅ data correct | root arrivals 6 -> 7/s in the attack (tunnel duplicate); LatencyHopRatio correlations ~0 after #75 |
| Tunnel-end PCA | ❌ empty of its subject | every wormhole cell: "tunnel features INCLUDED: none survived" |
| Correlation maps: ForwardingRatio / IngressEgressDelta | ❌ misleading | 51 strong r (abs >= 0.7) in 24 cells are between-board artifacts |
| Distribution plots, right panel | ⚠️ layout | y-axis label longer than the panel: runs off the figure and over the title (all cells) |

**Findings:**
- **Stale tunnel-end plots (7 blackhole cells):** blackhole linear/G402/highload, linear/Yuchengco/highload, partial_mesh/G402/burst, tree/DLSU_Library/highload, tree/G402/burst, tree/G402/stationary, tree/Yuchengco/highload = exactly the cells that had a FAKE TunnelLatency before #75, so EDA drew a wormhole-only plot. Now skipped, but `plot_tunnel_end_projection` never deletes an old file.
- **Tunnel-end PCA has no tunnel features:** it calls `run_dimensionality_reduction(exclude_tunnel=False)` but keeps `exclude_leaking=True`, and `leakage.py` lists TunnelIntensity / TunnelBytes / TunnelLatency as role-gated leaks - so the plot titled "separability WITH the tunnel features" is built without them (eda.py:1323 vs leakage.py:117).
- **Correlation artifact:** ForwardingRatio / IngressEgressDelta exist only on forwarding boards; in the attack phase that is often 2 boards. blackhole/tree/G402/burst attack: FR vs RSSI_mean r = +0.95 from attacker 1C38 (FR 0, -71 dBm) vs relay E618 (FR 1, -64 dBm); WITHIN each board r = 0 / undefined. Signs flip between cells (+0.82 / -0.93) - the value says which board is the attacker, not a feature relationship. 31 attack, 12 baseline, 8 all-phase cases.
- Not checked visually: all 1,170 images one by one (sampled every plot type on 3 cells + programmatic checks on all).

**Verdict: ⚠️ the plotted DATA is correct; 3 plot problems: 7 stale tunnel-end plots (delete), tunnel-end PCA missing its tunnel features, FR/IED correlations misleading in 24 cells (do not quote them; checklist B-corr). Plus a cosmetic label overflow.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #76 — Oct 21, 2026 · ~11:30 AM — re-analysis of all 61 cells to fill MacRetryRate (B-mrr)

> **Requested by:** Angelo · **Laptop:** Angelo's (44 sniffer captures in `datasets/PCAP`) · **Commit:** `357d91f` + uncommitted `tools/pcap_retry.py`
> **Request:** "re-run analysis on all cells to fill MacRetryRate"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | r1 | every analysed cell (61) | `datasets/analysis/**`, `datasets/PCAP/**/*_retry.json` |

| Check | Result | Detail |
|---|---|---|
| analyze.ps1 -SkipTrim on all 61 cells | ✅ 61/61 exit 0 | ~1 min each |
| Sniffer captures with retry data | ⚠️ 12 / 44 (was 7) | bug fixed, see findings |
| Cells with MacRetryRate | ⚠️ 10 / 61 (was 6) | + blackhole linear/Yuchengco/stationary, tree/G402/burst, tree/G402/highload, tree/G402/stationary |
| Latency fix (#75) after re-analysis | ✅ | no cell > 2 % victim windows over 1 s/hop or TunnelLatency > 5 s except baseline/linear/home/highload (real congestion, test data) |
| Root-clock alignment for wormhole captures | ❌ not usable | on 4 blackhole runs with both, the fitted attack start is 31-39 s AFTER the root's SET_TIME banner time |

**Findings:**
- **Bug fixed - `tools/pcap_retry.py`:** GUI run logs (`NIS16 Capture Studio run log - ...`) have no `Start time:` transcript line, so `started` was None and every GUI-era capture was refused as "no run log started within 20 min". New `_log_started()` takes the start from the log's file-name stamp (`_oct20_1008PM`; the header date is locale-dependent: 20/10/2026 vs 10/20/2026). 29 cached refusals of that kind were deleted and rebuilt.
- **Wormhole captures (19) stay empty:** only blackhole runs can be aligned from traffic (the attacker's uplink step). The root clock (`--trust-stamp`) is 31-39 s behind the fit even with a laptop-set clock, which would put attack windows in the wrong phase. A wormhole traffic fit (end A's uplink should rise during the attack) is a possible next step - not built.
- Other refusals: incomplete runs (no attack/cooldown in the root log), no root log on this laptop (tree/G402 oct. 2 / oct. 17 / oct. 19 10:44 AM), exports missing, partial_mesh/DLSU_Library/highload 4:46 PM (no attack step). partial_mesh/DLSU_Library/highload 3:13 PM is usable but not the run the cell holds, so the cell stays NaN.
- `star-wormhole-highload-g402_r1_oct21_0137AM.pcap` (the Library run done with the G402 preset) moved to `PCAP/wormhole/star/DLSU_Library/highload/` as `..._dlsu_library_r1_oct21_0137AM.pcap` (+ MOVED note; PCAP is local, not committed).
- The 45 cells not in #75 also changed slightly: their stabilise (phase 255) windows lost LatencyHopRatio (the #75 fix), run-phase values unchanged.

**Verdict: ⚠️ MacRetryRate 10/61 cells (all blackhole). B-mrr stays open for wormhole: needs a wormhole alignment method, not more captures.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #75 — Oct 21, 2026 · ~10:00 AM — teammate audit: impossible LatencyHopRatio / TunnelLatency (pre-run arrivals)

> **Requested by:** Angelo (forwarding a classmate's audit of the S:\ copy) · **Laptop:** Angelo's · **Commit:** `e1380b7` + uncommitted `analysis/features.py`
> **Request:** classmate's report "Why some feature-table columns are empty" - item 3: LatencyHopRatio 39,396 ms/hop and TunnelLatency 315 s in ~17 folders

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | r1 | every analysed cell (61 feature tables) | `datasets/analysis/**/feature_table.csv` + `datasets/exports/**/trimmed/*_arrivals.csv` |

| Check | Result | Detail |
|---|---|---|
| Item 1: blanks are intentional (PDR, Tunnel*, LatencyHopRatio, RetryRate) | ✅ agreed | NaN = not measured, by design |
| Item 2: MacRetryRate empty | ✅ known | 6/61 cells here - checklist B-mrr (132 PCAPs on this laptop) |
| Item 3: impossible latency values | ❌ **CONFIRMED - 16 cells** (one fewer than the S:\ copy: wormhole/linear/Yuchengco/burst is 13 %, blackhole/star/G402/highload 1 %) | every fake duplicate pairs a ROOT phase-255 arrival with the run's same seq |
| Clock jumps inside the run phases (after dropping 255) | ✅ none | only blackhole/linear/home/highload (5 repeats in one folder, test data) |
| Fix: `features.compute_latency_features` drops root phase-255 arrivals | ✅ | broken cells 11-93 % -> 0 % victim windows > 1 s/hop (tree/G402/burst 1 % = 21 windows of 1.2-2.7 s in phases 0/3, real-size delays); blackhole TunnelLatency -> all NaN (was up to 270 s); wormhole TunnelLatency max 0.01-1.21 s, ~180 windows = the attack |
| Unaffected cells unchanged | ✅ | run-phase LatencyHopRatio max change 0.005 ms/hop; only stabilise (255) windows lose their value (~10 %, excluded from analysis anyway) |
| Attack verdicts | ✅ unaffected | verify_attack shows these two columns, does not score them (B-lat); DuplicateRate reads Node B rows only |

**Findings:**
- Cause (as the classmate found): the root logs probes while the boards still idle (root phase 255); the victims are then reset for the run, so seq restarts and their clocks restart. `compute_latency_features` (a) took each node's minimum latency from that idle period (different clock offset -> every value ~100-600 s / hops too high) and (b) grouped an idle seq with the run's same seq as a "duplicate" (100-600 s TunnelLatency, even in blackhole runs).
- Affected (old % victim windows > 1 s/hop -> new): blackhole linear/G402/highload 63->0, linear/Yuchengco/highload 42->0, partial_mesh/G402/burst 58->0, partial_mesh/Yuchengco/stationary 21->0, tree/DLSU_Library/highload 18->0, tree/G402/burst 93->1, tree/G402/stationary 47->0, tree/Yuchengco/highload 11->0; wormhole linear/DLSU_Library/highload 82->0, linear/G402/burst 83->0, linear/Yuchengco/burst 13->0, linear/Yuchengco/highload 64->0, linear/Yuchengco/stationary 66->0, partial_mesh/G402/stationary 64->0, star/G402/highload 83->0, star/G402/stationary 83->0.
- Fixed medians: 2-7 ms/hop (tree/DLSU_Library 14.6). baseline/linear/home/highload stays 15 % > 1 s/hop: real congestion (7-17 s), not this bug.
- Classmate's item 4 (1C38 wormhole_b for 54 idle rows) = the auto-switch's provisional role before Phase 0 locks it - expected (wormhole_victim.c header).
- **The saved feature tables / EDA still hold the old values until each affected cell is re-analysed** (`analyze.ps1` / GUI Analyze).

**Verdict: ❌ -> ✅ after re-analysis: LatencyHopRatio + TunnelLatency were wrong in 16 cells; fixed in features.py (verified on all 61 cells). Re-analyse the 16 cells before quoting either feature (checklist B-lat255).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #74 — Oct 21, 2026 · ~3:15 AM — new SCENARIO check in the attack verdict: was each run's scenario really applied?

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `dadccb3` + uncommitted `tools/attack_checks.py`, `tools/verify_attack.py`, `gui/CampaignVisual.ps1`
> **Request:** "can you also include the scenario in the verdicts if the scenario was applied" + "in campaign also add the scenario verdict"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | stationary / burst / highload / jitter | r1 | every analysed cell (61 feature tables) | `datasets/analysis/**/feature_table.csv` |

| Check | Result | Detail |
|---|---|---|
| highload = children probe ~4/s (250 ms) | ✅ 19/19 | baseline median 4.0/s in every highload cell, 1.0/s in every other |
| burst = one child +~300 probes in 10 s inside the attack | ⚠️ 15/17 | 296-297 extra probes at +62..64 s in 15 cells; non-burst cells <= 45 |
| jitter = attack longer than 180 s | ✅ 5/5 | 191-206 s (standard cells 180-181 s) |
| stationary = 1/s, no burst | ✅ 19/19 | |
| Verdict change | ✅ none | old vs new verifier: same exit code on all 61 cells; scenario not applied = WARN + tag, never SETUP INVALID (the attack evidence still stands) |

**Findings:**
- `blackhole/linear/G402/burst` (oct. 14): **the burst is NOT in this run's attack.** 0C80's file starts with 108 rows left from an EARLIER run (phase 2, before this run's stabilisation, unlabelled) that hold the burst (~297 probes); in the labelled attack 0C80 sent its normal 181. The attack verdict (BLACKHOLE CONFIRMED) is unaffected.
- `blackhole/linear/home/burst`: no child sent a burst at all (home test cell, not thesis data).
- The VERDICT line now ends `| scenario <x>: applied / NOT APPLIED / check (see [3])`; [3] SETUP CHECKS has a SCENARIO group; the Campaign journey has a 5th step "Scenario" (green applied / red NOT applied / amber check) and the tile tooltip a "scenario:" line. Needs "Verify only" again per cell to show (old reports say "press Verify").

**Verdict: ⚠️ scenarios applied in 58 of 60 attack cells; recapture blackhole/linear/G402/burst for the burst scenario (checklist C22) - the home cell is test data.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #73 — Oct 21, 2026 · ~2:40 AM — wormhole/star/G402/burst: "check if there is burst"

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `dadccb3`
> **Request:** "can you also check the burst in g402 wormhole star if there is burst"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | star | G402 | burst | r1 | oct. 20 11:11 PM run, root exported 11:34 PM | root telem + arrivals, 7 children (node2-node8), run logs |

| Check | Result | Detail |
|---|---|---|
| Boards set to burst | ✅ | wizard SCENARIO_CHECK highload -> burst on every child; each child log "Recorded scenario: burst" |
| Burst sender | ✅ | node8 = B4:BF:E9:34:ED:80: "TRAFFIC_PROFILE=burst: will fire 300 probes, 60 s into the attack-length window" |
| Did it fire | ✅ | "BURST: window opened (phase=2); firing in 60 s" -> "BURST: done - 300/300 sent ok in 3350 ms (seq 657..956)" |
| Reached the root | ✅ | root arrivals (raw and trimmed): 300 of 300 burst seqs, all phase 2 (attack); 56/89/86/70 arrivals per second over 4 s vs ~1/s normal |
| Attack verdict (saved, oct. 20 11:48 PM) | ✅ | WORMHOLE CONFIRMED 2/2, CONFIDENCE STRONG, TOPOLOGY OK, TUNNEL OK |
| Gate 2 after the #72 fix | ✅ | hub F4:2D:C9:73:E6:18 = wormhole end A, Structure matches star YES |

**Verdict: ✅ the burst is in the data - fired once, complete, inside the attack phase - and the run is a confirmed wormhole capture.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #72 — Oct 21, 2026 · ~2:30 AM — wormhole/star/DLSU_Library/highload: "console says topology FAIL but Verify says PASS"

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `dadccb3` + uncommitted `tools/verify_topology.py` fix
> **Request:** "in this console it says [Gate 2 FAILED, hub is a wormhole_b] but in the side panel or verify page it says it passed?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | star | DLSU_Library | highload | r1 | oct. 21 1:29 AM (ran with the G402 preset by mistake; re-filed, see MEMORY oct. 21) | root telem + arrivals, 7 children (collected 2:05-2:10 AM) |

| Check | Result | Detail |
|---|---|---|
| Integrity (gate 1) | ✅ | 9 files, 9 PASS |
| Topology (gate 2) as run | ❌ → ✅ false alarm | "hub NODE_F42DC973E618 is a wormhole_b" - but E618 is `wormhole_a` in every row from Phase 0 on |
| Why | ⚠️ verifier bug | E618's role column flips b/a/b/a in its first 405 rows (stabilisation, phase 255, star hub being settled); `verify_topology.load_files` took a node's role from its FIRST row only. `verify_attack` reads roles in the experiment -> its TUNNEL check said OK |
| Fix | ✅ | `verify_topology.py`: the role a node holds in phase != 255 rows overrides the first-row role |
| Re-run gate 2 (`--expect star`) | ✅ | DLSU_Library highload + stationary, G402 highload + stationary + burst: all "hub is the wormhole end A", Structure matches star YES, exit 0 |
| Attack (gate 3) | ✅ | WORMHOLE CONFIRMED 2/2 (TunnelIntensity 0 -> 4, DuplicateRate 0 -> 1), UART 716/720 frames, PDR 1.0 every plain child, all 8 boards full run |

**Verdict: ✅ usable. The topology FAIL was the verifier reading a stabilisation-time role; the run is a proper star with E618 as the hub / wormhole end A. Re-run "Analyse + verify" (or Verify only) so the console and saved status agree.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #71 — Oct 20, 2026 · ~10 PM — paper check of the 8-board working copy: run counts, G402 numbers, sniffer column lost in the oct. 19 re-analysis

> **Requested by:** Basti · **Laptop:** Basti's · **Commit:** `76659dc2`
> **Request:** "verify it again (…_no_jitter_8boards.docx) … highlight green … update the status of the paper"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole + wormhole | all 4 | G402, DLSU_Library, Yuchengco | stationary, burst, highload (no jitter) | r1 | sep. 30 – oct. 20 | 46 analysed feature tables (36 blackhole, 10 wormhole) + 435 campus export CSVs |

| Check | Result | Detail |
|---|---|---|
| Board count in the paper (8) | ✅ | inventory: 7 children + root in every campus run; verifier shows an 8-node chain for linear/G402/stationary |
| G402 linear stationary numbers | ✅ | ForwardingRatio 1.000 → 0.001 (1 of 1,077 forwarded), all 6 victims PDR 1.000 → 0.000 - matches the 8-board copy's Table 4.4 / §4.1.3.1; Table 4.23 still said 76 % (fixed in the paper) |
| Run status in the paper (43 runs) | ⚠️ stale | tree/G402/burst was recaptured oct. 19 and re-analysed in `6fb00803` (verifier PASS) -> **44 processed (35 + 9)**. Held out: tree/G402/highload (OUTCOME INCONCLUSIVE, B768 no data), wormhole tree/DLSU/stationary (REDO), partial/G402 st + hl and star/G402/st wormhole (not analysed) |
| verify_attack.py on all 46 campus runs | ✅ | 35 blackhole + 9 wormhole OUTCOME PASS; tree/G402/highload + wormhole tree/DLSU INCONCLUSIVE |
| Partial mesh, second parent | ✅ | all 9 blackhole partial runs: "8 nodes, each seen under only one parent" during the attack |
| Healthy baseline PDR (paper: 0.997) | ⚠️ | not reproducible; victims' baseline PDR averages **0.998** over 123 victim baselines in 36 campus blackhole runs (lowest run partial/Yuchengco/stationary 0.81) - paper now says 0.998 |
| Zero-row capture files | ✅ | 0 of 435 campus export CSVs (no jitter) has 0 rows |
| Wormhole roles (D-17) | ✅ | all 9 linear wormhole runs: one A + one B, roles stable, A shallower than B |
| **MacRetryRate in the analysis tables** | ❌ | **23 campus runs had it before `6ecbe3e1` (oct. 19 D-25 re-analysis); only 3 have it now** - the re-analysis ran without the PCAPs (datasets/PCAP on this laptop holds 2 files). The paper's sniffer figures (22 runs / 8 rose; 26 full-length captures) cannot be reproduced from the current tables |

**Verdict: ⚠️ data usable; the paper's counts and two numbers were corrected in green (status doc `Plan/Paper-Editing/4-Verification/THESIS3-Paper-Status oct. 20, 2026.docx`). Action: whoever holds the sniffer PCAPs puts them in `datasets/PCAP` and re-runs `analyze.ps1` so MacRetryRate comes back before §4.1.3.4 / D-14 are finalised (checklist B-mrr).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #70 — Oct 20, 2026 · ~9:05 PM — "still ABORTED in highload - double check the boards": the hub board 1C38 browns out

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `c461711`
> **Request:** "still aborted in highload please double check the boards why this happened"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | star | G402 | highload | r1 (3rd attempt) | oct. 20 8:22 PM | root run log (new NODESTAT lines), 7 child crash-watch logs, the 2:44 PM stationary logs |

| Check | Result | Detail |
|---|---|---|
| When did the hub drop? | ❌ | 1C38 (hub = end A) left the mesh at 61 s, 74 s and 151 s after the root booted - **before Phase 0** (no attack, no load yet); every child went OFFLINE with it each time |
| Did it restart? | ❌ yes | root NODESTAT: 1C38 uptime 180 -> 0 -> 7 -> 0 -> 7 -> 0 ... (several restarts in 3 min) |
| Its own record (status file) | ❌ | **Boot count 1,792 · crash resets 1,564 · brownout resets 207**. Every other board: 0 crashes; plain children 0 brownouts; 0C80 (end B) 16 brownouts |
| What the "crashes" are | ⚠️ brownouts | 2:44 PM log (1C38 on the laptop's USB, COM39): every boot shows `E BOD: Brownout detector was triggered` then `rst:0x3 (SW_RESET)` - the brownout handler restarts the chip, filed as a crash. It happens as the Wi-Fi radio starts (current burst) |
| UART pair | ❌ | 1C38: `UART link noisy: 308-326 bad frame windows`, `UART TUNNEL ONE-WAY` (its TX -> 0C80's RX not heard) |
| Code / scenario | ✅ not the cause | same firmware on 5 plain children: 0 resets; SD 8/8 writing; NODESTAT + safety net working |

**Verdict: ❌ hardware - 1C38's supply sags below the ESP32's brownout limit even on laptop USB (bad cable / board regulator / a jumper loading its 3V3), so the star hub keeps resetting and takes every child with it. Replace it as wormhole end A with a board that has 0 brownouts, re-do the A<->B jumpers (TX->RX, RX->TX, GND->GND only - no 3V3/5V link), then recapture (C21).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #69 — Oct 20, 2026 · ~8:30 PM — wormhole/star/G402/highload: every child ABORTED / EXTRA PIECE (two runs)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `aeaf1a2` + this change
> **Request:** "why nothing saved to the SD card - everything says extra piece and aborted ... did you do something to the code ... maybe because of the scenario on the card"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | star | G402 | highload | r1 (twice) | oct. 20 4:56 PM (Phase 0 17:40) and 6:15 PM (Phase 0 18:24) | root run logs, root exports, 14 child crash-watch logs, collect-scan 5:58 PM |

| Check | Result | Detail |
|---|---|---|
| Did the SD cards record? | ✅ | root `SD LOGGING : 8/8 boards writing` through baseline + attack in both runs; every child has a file of the run (~528 KB) |
| Did a child crash / restart? | ✅ none | the 5 plain children ran 25-37 min with no reset (crash-watch logs) |
| Why ABORTED | ❌ found | **the star hub (wormhole end A = 1C38) left the mesh 62 s (run 1) / 23 s (run 2) into the ATTACK**; every child joins only through the hub (D-28), so all 7 lost the root (`Cooldown start: only 0/7 children`), never heard COOLDOWN / TERMINATE, kept their files open -> ABORTED when unplugged; tiny post-reset pieces = EXTRA PIECE |
| Why the hub dropped | ⚠️ likely power | Collect: 1C38's piece ended by an *unknown reset (power cut)*; its boot counter 58 -> 1,426 -> 1,627 on oct. 20; 0C80 (end B) BROWNOUT earlier and `UART link noisy: 68 bad frame windows - check jumpers and common GND` before run 2. The 2:43 PM star STATIONARY run (less traffic) closed cleanly. Firmware on the hub not excluded until its card is read (`fetch_crashes.py --card`) |
| Scenario on the card (#68) | ✅ not the cause | runs.csv appends `scenario` LAST (header + rows agree); importer tested with an 11- and a 12-column header: a closed boot reads clean (8,800 rows, highload), an unclosed one not clean |
| Collect picked old files (ED80, 2805) | ❌ -> 🔧 | with no clean file it keeps pieces >= half the biggest: the OLD 14:49 stationary piece (1.08 MB, no scenario) beat the run's 0.53 MB highload piece -> wrong run. Now: when a piece recorded the run's scenario, pieces with another / no scenario are dropped (reproduced + fixed) |
| Safety net | 🔧 | firmware: a node that hears no phase for the rest of the planned run (+ max jitter + 60 s grace) closes its files itself -> manifest `root_lost`, no `clean` (cut short, safe to import); importer / GUI show **CUT SHORT - CLOSED SAFELY**; Collect says "lost the root". Before: only cooldown armed it |

**Verdict: ❌ both runs are NOT usable as wormhole captures (≈ 1 min / 23 s of attack, no cooldown) - recapture after the hub is fixed (power the two wormhole boards from a solid source, common GND on the UART pair, read 1C38's card for its crash rows). The data that exists is intact up to the drop; nothing was lost by the scenario change.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #68 — Oct 20, 2026 · ~4:00 PM — GitHub sync, GUI export ("success" but no file), Collect (failures, board picker, identity)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `709e455` + #66/#67 + this change
> **Request:** "fix GitHub sync (files mixed / wrong folders) ... GUI export said success but no files ... Collect All failed ... let me pick boards before scanning"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | burst + highload | r1 | oct. 19 night (the failed Collect + individual exports) | collect logs, exports, sync plan of this laptop |

| Check | Result | Detail |
|---|---|---|
| Collect at 8:57 PM (burst) | ✅ explained | 2 of 3 boards REFUSED correctly: their newest card file was the HIGHLOAD run (8:29-8:32 PM), not burst - 73-79 % of probes in another phase. The 3rd (1C38, attacker - sends no probes, root_match cannot test it) WAS filed into burst = the #65 wrong import |
| Fix: later-run rule | 🔧 | a child piece that STARTED after this run's root was exported is refused ("a later run") - tested: 1C38's 20:29 piece vs the burst root's 20:03 export -> refused |
| Fix: scenario on the card | 🔧 | scenario.txt written before every flash (run.ps1 -> export_logs --ensure-scenario), firmware records it in runs.csv (12th column); importer + Collect + Data page show attack / topology / location / SCENARIO; Collect refuses a piece recorded as another scenario - tested (highload piece vs burst -> refused) |
| "Exported, but no file" | ❌ -> 🔧 | import_sdcard.py exits 0 when every ticked file is SKIPPED (already imported / same node + repeat / aborted / still running); the GUI printed "N file(s) -> <card's folder>" from exit 0 + the TICKED count. Now: every copy is read back at its FINAL path (IMPORTED_FILE path\|rows), IMPORT_RESULT copied/skipped/...; the GUI shows only verified files with their real folder, and "NOTHING was imported" + the reasons when 0 - reproduced: same file twice -> copied=0 |
| Collect identity | 🔧 | the board's real MAC (GUI) goes with --expect-mac; a card whose files belong to another board (swapped card) is refused; each collected file is checked for its node_id and re-read after filing (COLLECT_FILE) |
| Board picker | 🔧 | Collect window: tick boxes per plugged-in board BEFORE the scan (keyed by MAC, port only if unknown), All / None, ticked-but-unplugged boards named and never read; Retry failed / Retry this board unchanged |
| GitHub sync | ❌ -> 🔧 | Push never sent deletions and Pull treated a file deleted HERE as "a teammate's file you don't have" -> deleted / replaced runs came BACK into the run folder (#48). Now: committed-but-deleted data files are detected (git ls-files -d); Pull never brings them back ('YOU DELETED IT'); Push offers 'DELETE ON GITHUB' UNTICKED (normal commit, recoverable); deleted here + changed on GitHub = held back as a conflict. On this laptop: 56 such files (oct. 2 burst + oct. 17 highload runs + their plots/logs) - before the fix all 56 were queued to be pulled back |
| Tests | ✅ | card-folder tests: one board, two boards (already-collected one skipped, no duplicate), retry (no duplicate), swapped card refused, later run refused, scenario mismatch refused; import twice -> copied=0; sync status read-only on real data; verifier 55/55; GUI self-test OK (sync: 208 of 264 ticked = 56 deletes unticked) |

**Verdict: 🔧 the "failed" Collect was mostly the safety net working (another run on the cards) - plus one gap that let the attacker's wrong-run file through, now closed; the GUI's false "success" came from treating exit 0 as "copied"; the sync's mixing came from deletions never travelling. All three fixed and tested on test cards / real plans; Collect over USB and Halt board not tried on hardware here (ports may be in use).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #67 — Oct 20, 2026 · ~1:00 PM — missing boards graded by their role (D-32) + the "standby board" question

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `709e455` + #66 + this change (uncommitted)
> **Request:** "evaluate the importance of the missing board before deciding whether the run needs to be repeated ... yellow / recapture required / inconclusive ... is missing data from a standby board acceptable?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | r1 | every live cell (56) | feature tables, root arrivals, root run logs |

| Check | Result | Detail |
|---|---|---|
| Was a board with NO file seen at all? | ❌ → 🔧 | completeness needed only ≥ 3 child files; the verifier never knew a board existed unless it had a file. Now `tools/missing_boards.py` names every board the root heard (≥ 100 arrivals, phases 0-3) with no file / no attack windows |
| Position of a missing board | 🔧 | structure only: own file → root run log PARENT/CHILD STRUCTURE → boards naming it as parent; never its delivery (a victim the attack failed to cut off must not be dropped as a 'bystander') |
| Grading | 🔧 | attacker CRITICAL; victim YELLOW if others keep ≥ 60 traceable s else CRITICAL; bystander YELLOW if another control remains, last control UNDETERMINED; unknown position UNDETERMINED; wormhole plain child YELLOW. New grade UNDETERMINED = OUTCOME INCONCLUSIVE + Campaign INVESTIGATE. Coverage-only incompleteness = CHECK, not REDO |
| blackhole/tree/G402/highload | ⚠️ YELLOW | **B768: no file**, root heard it; root run log places it as a BYSTANDER; 4 controls left → MINOR GAPS, OUTCOME PASS, footnote C19 |
| wormhole/partial_mesh/G402/highload | ⚠️ YELLOW | **2805 (D7B4): no data on its card (#63)** - was graded OK without knowing; plain child → MINOR GAPS, footnote C20 |
| Every other cell | ✅ | unchanged; statuses 46 OK / 6 CHECK / 1 REDO (the 2 above OK/CHECK → CHECK) |
| Tests | ✅ | test_verify_attack 55/55 (7 new: leaf victim YELLOW, victim carrying the other victim CRITICAL, bystander YELLOW, last control UNDETERMINED, no structure UNDETERMINED, placed by root log, grades); placebo 0/110; sensitivity 0 flips; sync 5/5; GUI self-test OK |
| Standby-board question | ✅ answered | acceptable with a footnote when its position is established, it carries no victim, another control remains, it is in no calculation the verdict uses, and its loss is unrelated to the attack (check crash records) - GRADING-AND-THRESHOLDS.md §0b |

**Verdict: 🔧 missing boards are now found and graded by their role in the attack; two real missing boards (B768, 2805) that had been overlooked are named as YELLOW footnotes. A standby board is acceptable to lose under the five conditions above; an unplaceable board or the last control is never silently accepted (INVESTIGATE).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #66 — Oct 20, 2026 · ~11:30 AM — SD-card failures, crashes, tree stability + verdict / Campaign / Verify consistency

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `709e455` + this change (uncommitted)
> **Request:** "fix and reassess the verdict system, Campaign statuses, status notes ... boards suddenly failing to save data to their SD cards ... investigate first ... tree topology ... make the Verify page also show the Campaign status"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | r1 | every live cell (56) | firmware SD/crash code, run logs + crash records of blackhole/tree/G402, verifier + redo list on every cell |

| Check | Result | Detail |
|---|---|---|
| Did recent code break SD mounting / file naming? | ✅ no | mount, SPI config, open modes, names unchanged since oct. 11-12; one card per board, names carry the MAC → no cross-board overwrite |
| Firmware handling of a transient card error | ❌ → 🔧 | no boot retry; mid-run failure = card copy lost for the run (pre-oct. 19: next row `fopen("w")` TRUNCATED it); SPIFFS failure skipped the SD row; failed flush/fsync only warned. Now: 3 boot tries, background recovery (reopen → remount, 6 × 5 s, append-only), missed rows counted + `sd_gap`/`sd_short`/`sd_lost` in runs.csv, importer prints CARD COPY INCOMPLETE, root shows INCOMPLETE / STALLED/RECOVERING / CARD GIVEN UP |
| Root "SD LOGGING" lines, oct. 19 tree runs | ✅ | no board on the new firmware reported a failure (4/8 = 4 boards on older firmware, not failures) |
| 2805 (no highload file) | ⚠️ hardware | status written at boot but telemetry file never opened, card reads inconsistent, brownouts → its card / power link (#62/#63) |
| Crash records (4 boards) | ❌ firmware | 0C80, 2805, FE90, E618: PANIC FAULT at the SAME PC 0x40081d4d (+ same backtrace) mid-run → deterministic. On IDF 5.5.4 oct. 19 builds = `ipc_task` (esp_ipc.c:85). Exact build ELF not kept → not proven. Mitigation: IPC stack 1024 → 2048, [HEALTH] now prints ipc0/ipc1; crash rows carry the ELF SHA, run.ps1 archives every .elf, fetch_crashes.py decodes against the exact build |
| Tree instability | ⚠️ explained | firmware: parent selection stock since f786c07, only D-26 sticky switching left; the moves in the records follow crashing / browning-out parents (#55) → the crash above is the main cause |
| Campaign REDO vs Verify STRONG | ❌ → 🔧 | two different questions shown as one; now the Verify page RUN STATUS card shows CAMPAIGN STATUS (redo list) + ATTACK EVIDENCE (verifier OUTCOME PASS/FAIL/INCONCLUSIVE) + 5 dimension chips + THIS run's reasons with their source; warns on a saved report older than the analysis / disagreeing with the live re-check |
| Notes leaking between runs | ❌ → 🔧 | (1) redo_list `split_shared` removed a reason from every cell that shared it with ≥ 3 others and recomputed the cell's status (8 partial_mesh cells read OK only because of that) — now non-mutating; D-29 written on each cell as a decided note; (2) GUI drew a finished Verify result on whatever run was selected; (3) a report without a verdict left the old cached verdict on the banner; (4) log blocks were classified by words anywhere in the verdict ("no need to recapture" = REDO) — now by the leading ✅/⚠️/❌ |
| Attacker moving (D-23 rule 4) | 🔧 D-31 | judged by what it changes: tolerated only when no board flipped class + attacker outage ≤ 10 %; victims' seconds with no working path THROUGH the attacker (attacker detached / crashed) excluded |
| Statuses before → after | ✅ | planned cells 47 OK / 5 CHECK / 1 REDO → identical; outcomes: 52 PASS, 1 INCONCLUSIVE (wormhole/tree/DLSU_Library/stationary, MAJOR GAPS + incomplete capture) |
| Tests | ✅ | test_verify_attack 48/48; placebo 110 → 0 false positives; sensitivity 14 thresholds ±~50 % → 0 flips (controls flip 18); verdict-sync 5/5 rules; GUI self-test passes (card rendered, screenshot checked); firmware build: see MEMORY |

**Verdict: 🔧 no regression made the SD path skip a board, but the firmware turned every transient card error into a lost card copy, silently — fixed (retry, recovery, counting, reporting). The crash at one PC on four boards is a firmware/SDK fault and the most likely common cause of split files, missing windows and re-parenting trees — mitigated + made decodable, not yet proven fixed. Verdict logic: one OUTCOME per run (PASS/FAIL/INCONCLUSIVE), Campaign status shown beside it with its own reasons; no existing status changed. NOT hardware-tested — reflash every board. Full write-up: docs/operations/2026-10-20_SD-CRASH-TREE-INVESTIGATION.md.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #65 — Oct 20, 2026 · ~10:00 AM — tree/G402 burst + highload (last night): burst used two HIGHLOAD files

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `4a8488d`
> **Request:** "check the run we did last night in tree blackhole G402, check the verdict, I'm confused"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | burst + highload | r1 | oct. 19 ~7:45 PM (burst, root exported 8:02) and ~8:37 PM (highload, root 8:53) | 8 + 7 boards |

| Check | Result | Detail |
|---|---|---|
| Why both verdicts showed the SAME attacker numbers | ❌ | the burst folder held byte-identical copies of HIGHLOAD's 0C80 (`..._0902PM`) and 1C38 (`..._0859PM`) next to burst's own files; the analysis takes one file per board and used them |
| burst before | ❌ | NOT CONFIRMED - SETUP INVALID: 'bystander 0C80 lost 63 %' = highload data against the burst root (root_match 79 % mismatch); attacker 'received 710' = highload's |
| Fix | 🔧 | the two copies moved to `archive/2026-10-20_tree-G402-burst-wrong-import/` (identical copies stay in highload); trim also moved their stale copies out of `trimmed/`; burst re-analysed |
| **burst now** | ✅ | **CONFIRMED - STRONG**: ForwardingRatio 1.000 -> 0.000, PDR 1.000 -> 0.833 (z -18.8), victim ED80 0.998 -> 0.000, 5 bystanders 1.000 -> 1.000, attacker received 180 / forwarded 0, all 8 boards one file each + MATCH the root |
| **highload** | ✅ | **CONFIRMED - STRONG** (unchanged); 70:68 not imported yet (root heard it) |

**Verdict: ✅ both tree/G402 runs of last night are good - burst was mis-graded only because two highload files had been imported into its folder. Saved GUI report refreshed (backup .bak_oct20_wrongimport). Note: root_match cannot catch an ATTACKER file from another run (it sends no probes) - the duplicate-file warning in the RUN SUMMARY is what flagged it.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #64 — Oct 19, 2026 · ~7:15 PM — root_match CORRECTED (false alarms) + SD-logging indicator

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `a7588c5` + this change
> **Request:** "check 28:B4" / Kyle's new highload files / "add an indicator in the root dashboard if all nodes are writing to their own SD card"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole / blackhole | partial_mesh / tree | G402 | highload, stationary / highload | r1 | oct. 17 + 19 | every child file of the three cells |

| Check | Result | Detail |
|---|---|---|
| **root_match was wrong for boards with failed sends** | ❌ -> 🔧 | `victim_main.c`: seq_num goes up on EVERY attempt, probes_count only on success (failures in retry_count). Board seq = probes_count + retry_count (wormhole ends: probes_count). Re-checked: partial highload B768 17.8 -> **0.1 %**, FE90 16.6 -> **0.0 %**; partial stationary **2805 18.9 -> 0.0 %**; tree oct. 17 child_node7 -> 0.0 % |
| **Corrections** | ⚠️ | #60 / #62: 2805's partial STATIONARY file is the right run AND in sync (the 18.9 % was this counting artefact, not drift). Only **FE90 stationary** is a real wrong-run file (9.6 % with either formula, 700 vs 672). Tree 2805 (33 %) stays a real mismatch (two brownouts) |
| partial highload now | ✅ | root + 0C80 + 1C38 + E618 + B768 (Kyle) + FE90 + ED80 (Kyle) all MATCH; 2805 has no telemetry (#63) |
| SD logger bug | ❌ -> 🔧 | `csv_logger.c::sd_mirror_drop` did not latch the failure: the NEXT row re-opened the card file with fopen("w") = **truncated the run's card copy** after a single failed write. Now latched (copy stops, nothing erased) |
| SD indicator | 🔧 | heartbeat +1 byte `sd_log` (OK / NO CARD / WRITE FAILED / STALLED >30 s / waiting; old 53-byte beats still read); root prints ` SD LOGGING  : N/N board(s) writing to their SD card` or `NOT WRITING on ...`; GUI pre-START check 'SD cards writing' (locks START) + alert |
| Tests | ✅ | all firmware variants -fsyntax-only clean (-Werror), A/B sim 79/79, GUI self-test exit 0 |

**Verdict: 🔧 the wrong-run check no longer raises false alarms (its own bug); only FE90 stationary is a wrong-run import. SD writing is now visible on the root's dashboard during the run, and a single SD hiccup can no longer erase a card copy. NOT hardware-tested - reflash all boards.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #63 — Oct 19, 2026 · ~6:45 PM — 2805's SD card read directly (card reader, E:)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `b6aaa06`
> **Request:** "the SD card is in the reader now, check it"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | partial_mesh | G402 | highload | r1 | oct. 19 ~5:46-6:07 PM | 2805's card (read-only) |

| Check | Result | Detail |
|---|---|---|
| Files on the card | ✅ read | 41 files, ~10 MB; nothing copied, moved or deleted |
| Session log `wormhole/partial_mesh/G402/runs.csv` | ❌ | boot 20 (16:20, stationary run, clean 6932 rows) -> next is boot 25 at **18:12:37** - the FIRST session of the highload firmware (built 17:29:19) on the card; no session of that firmware anywhere on the card before 18:12 |
| r17 / r18 / r19 (18:12 -> 18:29) | ⚠️ | phase 255 only (waiting for a root, after the run); r17 starts at probe #362 = the board had run ~90 s before the card recorded |
| Root side of 2805 | ✅ | complete: PDR 1.000 baseline 300 s / attack 180 s / cooldown 120 s, normal latency |

**Verdict: ❌ 2805's own telemetry of wormhole/partial_mesh/G402/highload was never written to its card (the session ran - the root got every probe - but SD logging did not happen at that boot; it resumed after the 18:12 restart). Usable: root-side delivery only. Footnote ('telemetry not recorded - SD not written during the run; root-side PDR only') or recapture. Replace 2805's SD card + check its power.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #62 — Oct 19, 2026 · ~6:30 PM — board 28:B4 (2805): highload file missing + CORRECTION to #60

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `c67b6e2`
> **Request:** "check 28:B4" (after "a file is missing although the root showed everything connected")

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | partial_mesh | G402 | highload (+ stationary, correction) | r1 | oct. 19 ~5:50-6:07 PM (root on this laptop, 7 children on other laptops) | root + 3 children imported; 4 not yet |

| Check | Result | Detail |
|---|---|---|
| Run itself | ✅ | 8/8 boards in the mesh, SAFE TO EXPORT, no disconnects, tunnel test 8/8 before Phase 0 |
| 'Missing files' | ✅ explained | 2805, 704B, FE90, ED80 ran from another laptop and were never imported; run_summary now lists them (root heard them) instead of 'COMPLETE - all 4 boards' |
| 2805 on the ROOT | ✅ | 2,719 arrivals, seq 964-3682 at ~4/s (highload firmware), baseline/attack/cooldown all present |
| 2805's SD card (COM38) | ❌ | NO file from the highload run under any folder: partial_mesh/G402 files at 16:20 (the stationary run) then 18:12 / 18:16 / 18:17 (power-on reboot pieces, board restarting repeatedly now); internal flash (SPIFFS) empty; a later card read did not answer |
| **Correction to #60** | ⚠️ | the 2805 file of partial_mesh/G402/**stationary** is `r16_b20`, started **16:20:26**, 547,469 B = run 2 = the ROOT's run. Its 18.9 % mismatch is **phase labels out of sync**, NOT a wrong run (FE90 stays: run-1 file). Same pattern as 2805 in the tree run (#61) |

**Verdict: ❌ 2805's highload telemetry is not on its card or flash - only the root's arrivals of its probes exist. 2805 is unstable (brownout reboots today in tree + partial runs; phase labels drift after reboots): replace its cable / power, or swap the board, before more captures. #60 corrected: only FE90 is a wrong-run import; 2805 (stationary) is the right run with drifted labels.**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #61 — Oct 19, 2026 · ~7:30 PM — Collect / import audit: nothing checked a child's file against the ROOT's run

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `e198378` + this change
> **Request:** "check the collect all plugins, check if there is issue in there"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole / blackhole | partial_mesh / tree | G402 | stationary / highload | r1 | oct. 17 + oct. 19 | the two cells with today's collect problems |

| Check | Result | Detail |
|---|---|---|
| Wrong-run guard | ❌ -> 🔧 | collect / Data > Import judged a file by the CARD only (attack, topology, location, start, complete). New `tools/root_match.py`: probe by probe, the child's phase at send vs the root's phase at arrival (reboots split at every seq restart). Right files 0.0 % (tree: <= 1.1 %); partial FE90 9.6 %, 2805 18.9 % -> MISMATCH (> 3 %) |
| Collect fell back to an OLDER run | ❌ -> 🔧 | newest-boot-first took the first piece with a baseline, even an attempt an hour earlier (FE90). Now: pieces > 15 min older than the newest run on the card are never tried; the scan refuses 'one complete file + a newer run in pieces'; a piece that does not match the exported root is not filed |
| RUN SUMMARY | ❌ -> 🔧 | flags 'does NOT match the root' per board (GUI status 'NOT the root's run?', red) and **two ROOT runs in one folder** |
| blackhole/tree/G402/highload folder | ⚠️ | holds TWO runs: oct. 17 (root + child_node*, pulled from GitHub 5:18 PM) and oct. 19 (root + victim_NODE-*). trimmed/ has only oct. 19 so far, but a re-analysis would mix them - team decides which stays live (oct. 17 = D9 recapture) |
| 2805 in the oct. 19 tree run | ⚠️ | MISMATCH 33.6 % but SAME run (seq continuous): its phase labels ran ahead of the root's after two brownouts (baseline 199 s, attack ~100 s early) - labels unusable as they are |
| Tests | ✅ | verifier 46/46, segments OK, GUI self-test exit 0, pick(): FE90 case refused / same-run reboot pieces still taken |

**Verdict: 🔧 the collect + import path now checks every child against the root's run and never falls back to an earlier attempt; open: the mixed tree/G402/highload folder (team decision) and re-importing partial_mesh FE90 + 2805 (#60).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #60 — Oct 19, 2026 · ~6:50 PM — wormhole/partial_mesh/G402/stationary: FE90 + 2805 files are from the WRONG RUN

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `2f6e0bb`
> **Request:** "check the FE90, maybe I accidentally imported a wrong file"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | partial_mesh | G402 | stationary | r1 | oct. 19: run 1 ~3:20 PM (START_ANYWAY 3:30) and run 2 ~4:20 PM (root exported 4:50) | 8 boards + root arrivals |

| Check | Result | Detail |
|---|---|---|
| Last probe in the board's file vs last seq the root received from it | ❌ FE90, D7B4 | 1C38 601=601, E618 778=778, B768 667=667, ED80 671=671; **FE90 700 vs 672**, **D7B4 (2805) 639 vs 691** |
| Root's phase at arrival vs the phase the board's file says it was in when sending (every probe) | ❌ FE90, D7B4 | 1C38 / E618 / B768 / ED80: **0.0 %** different; **FE90 9.6 %**, **D7B4 18.9 %** |
| How they were picked | ⚠️ | collect 5:01 PM (`--since 05:00` = 5 AM): 6 cards held BOTH runs -> refused; FE90's card had only ONE complete file (`r6_b9`, started 15:21:35 = **run 1**) -> auto-copied; its run-2 pieces were not complete ('NO_RUN' r9/r10). 2805 was imported by hand at 5:06 PM - the run-1 file. |
| Preprocessing | ⚠️ | phase_sync flagged FE90 (unlabelled) but **not** 2805 - 2805's run-1 data is IN the current analysis (plain child; the wormhole primaries do not use it) |

**Verdict: ❌ FE90 and 2805 (D7B4) are files from run 1 (3:20 PM) next to the root of run 2 (4:20 PM). The wormhole verdict (B + root) is unaffected, but both boards' per-node numbers are from the wrong run. Fix: re-import both from their cards picking the run-2 files (started ~16:20), then re-analyse. Cards were not readable now (COM3 busy).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #59 — Oct 19, 2026 · ~6:15 PM — grading rule: a missing PLAIN CHILD in a wormhole run goes to the impact check

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `e31563c` + this change
> **Request:** "go with option 3" (from verification #58: change the grading rule, not just this run)

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | all analysed cells (11) | all | all | r1 | sept.-oct. 19 | every wormhole feature_table on Angelo's laptop |

| Check | Result | Detail |
|---|---|---|
| Rule | 🔧 | `verify_attack.py::_gap`: 'NO labelled window' / 'no attack-window telemetry' was always MAJOR. Now, in a WORMHOLE run, when EVERY board named is a plain child (built role not wormhole_a / wormhole_b, role known), it is a MINOR gap with those boards, so the existing IMPACT CHECK re-runs the 3-sigma test without them (still confirmed -> minor; not -> MAJOR). A tunnel end or an unknown role stays MAJOR; a missing attacker stays FAIL. Blackhole runs unchanged (every board is a victim = evidence or a bystander = control group, #53). |
| Why it is fair | ✅ | same as the existing minor-gap rule: the impact check must confirm (never assumed), fixed in advance, applied to every wormhole run; the wormhole primaries are B's TunnelIntensity and the root's DuplicateRate - a plain child feeds neither |
| Tests | ✅ | test_verify_attack.py 46/46 (new: plain child minor, tunnel end / unknown role major, blackhole major) |
| Re-grade of all 11 wormhole cells | ✅ | only **wormhole/partial_mesh/G402/stationary** changes: MAJOR GAPS -> **MINOR GAPS** (FE90, impact check: still confirmed). wormhole/tree/DLSU_Library/stationary stays MAJOR GAPS; 9 others unchanged (STRONG / GOOD). Saved GUI report refreshed (backup `.bak_oct19_grade`). |

**Verdict: ✅ rule changed for every wormhole run; one grade moves (partial_mesh/G402/stationary: recapture REQUIRED -> ADVISED, footnote FE90). Thesis: state the rule with the other verifier rules (checklist B-plain).**

<!-- ═════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #58 — Oct 19, 2026 · ~5:45 PM — why wormhole/partial_mesh/G402/stationary says "RECAPTURE REQUIRED"

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `e31563c`
> **Request:** "why our wormhole partial mesh g402 stationary need recapture required?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | partial_mesh | G402 | stationary | r1 | oct. 19 ~4:50 PM (teammate's laptop, pulled from GitHub) | 8 boards + root arrivals |

| Check | Result | Detail |
|---|---|---|
| Attack signature | ✅ | WORMHOLE CONFIRMED - TunnelIntensity 0 -> 1.000, DuplicateRate 0 -> 0.995 (2/2 primaries) |
| Tunnel setup | ✅ | one A + one B, roles stable, A shallower than B, UART 180/180 frames, duplicates in 179 attack windows, normal START |
| Victim delivery | ✅ | the 4 traced plain children PDR 1.000 in baseline and attack |
| FE90 raw file | ✅ | complete: baseline 3006 rows, attack 1806, cooldown 1206 (same as every board) |
| **FE90 in the analysis** | ❌ | preprocessing marked it **UNLABELLED**: 122/510 probes (24 %) were sent in a different phase than the root was in - 61 'node baseline while root wormhole' + 61 'node wormhole while root cooldown' = a steady ~1-minute offset at BOTH transitions. Excluded from every statistic. |
| Grade | ⚠️ | 'a board never measured in the attack' is always a MAJOR gap -> MAJOR GAPS = RECAPTURE REQUIRED, although FE90 is a plain child that is not part of the tunnel and neither primary uses it |

**Cause of the offset - not settled:** either FE90 switched phase ~1 min late (it sat at hop 3 on a ~-81 dBm link; the root re-sends the phase every 10 s, so ~6 missed re-sends in a row) or its probes reached the root late. A seq-vs-probe-counter cross-check was inconclusive (the counter does not map 1:1 onto seq_num on every board).

**Verdict: ⚠️ the wormhole attack is confirmed and the setup ran as designed; the RECAPTURE flag comes from one plain child (FE90) whose phase labels are ~1 min off the root's and was excluded. Team decision (not taken here): keep it as 'WORMHOLE CONFIRMED - major gaps' with an FE90 footnote, recapture, or change the grading rule so a missing plain child in a wormhole run is judged by the impact check (minor) - a rule change applies to every run and must be logged.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #57 — Oct 19, 2026 · night — why wormhole/linear/Yuchengco/burst showed "topology FAIL" + logic review

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `a780c29` + this change
> **Request:** "check wormhole linear Yuchengco burst - why failed topology? verify how the verdict and logic work, I think you have flaws"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| wormhole | linear | Yuchengco | burst | r1 | oct. 19 ~11:57 AM (new, not on GitHub yet) | 8 boards + root arrivals |

| Check | Result | Detail |
|---|---|---|
| The run itself | ✅ | verifier: WORMHOLE CONFIRMED, **STRONG** - tunnel 180/180 frames, duplicates in 180 attack s, perfect linear chain of 8, A (H04) shallower than B (H06), no board moved in baseline / attack / cooldown |
| **Flaw 1 — Gate 2 (analyze.ps1 / verify_topology.py)** | ❌ -> 🔧 | failed it on "Converged within 60 s: NO": B768 settled 122.8 s and FE90 156.4 s after their FIRST LOG ROW - all during SETUP, 117-156 s BEFORE Phase 0. The 60-s Milestone-3 rule predates the manual START gate (D-22, setup lasts until START). It failed **31 of 54** captures. New rule (D-27): a board must be attached when Phase 0 begins + no re-routing in the baseline; formation time is reported, not judged; moves after Phase 0 stay the verifier's D-23 job. Old vs new on every capture: 29 now pass (nothing moved in their experiments); 2 still fail, both genuine (home/highload benign is not a linear chain; tree/G402/highload re-routed in the baseline = the verifier's FAILED) |
| Flaw 2 — benign Gate 3 | ❌ -> 🔧 | analyze.ps1 skipped the attack gate for benign runs ("no attack to verify"); it now runs the benign verifier (--attack none) |
| Flaw 3 — plain-words card | ❌ -> 🔧 | "Missing data never makes an attack look stronger" showed on COMPLETE runs too (read like a hidden problem); now only when something is missing |
| Saved GUI reports | ✅ refreshed | the Verify page showed the 12:10 PM output (old Gate 2). That run re-analysed; Gate 2 re-run for every saved report that carries it (backups kept). Only home/highload still shows topology FAIL - genuine |
| Analogies | ✅ added | one premade analogy per verdict (blackhole complete / witness left early / key record missing / suspect's logbook has holes; wormhole tunnel variants; FAILED: no suspect / experiment changed halfway / camera battery / neighbour passed every card; benign normal day / not-normal day) |
| Tests | ✅ | verifier 45/45, GUI self-test exit 0 |

**Verdict: ✅ the run is a clean, STRONG wormhole capture; the red topology pill was a stale result of a rule that no longer
fit the procedure. Fixed at the rule, the two tools now agree.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #56 — Oct 19, 2026 · night — "what if the ATTACKER is the one with missing data?"

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `421076a` + this change
> **Request:** "are you sure the 4th witness is okay to have incomplete data? what if the attacker itself has missing windows - what will the verdict be?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | stationary | r1 | oct. 18 10:11 PM | simulated cuts of the real table + all 52 attack runs re-graded |

| Check | Result | Detail |
|---|---|---|
| Victim B768 short (real) | ✅ MINOR | with / without B768: ForwardingRatio z = -42.02 both, pooled victim PDR 0.389 vs 0.402 - the verdict does not rely on it |
| Attacker missing entirely (simulated) | ✅ NOT CONFIRMED | no attacker data = no attack evidence (ATTACKER check FAIL) |
| **Attacker cut to 28 s / 10 s (simulated)** | ❌ -> 🔧 | was CONFIRMED + **MINOR** (at 10 s on PDR alone - the attacker's own test had NO DATA). Too lenient: the attacker IS the attack, and its forwarding is the only evidence that separates a blackhole from congestion (placebo, #53). **Rule added:** a gap in the attacker's (blackhole / wormhole end) baseline or attack data is always MAJOR; its cooldown stays minor (never used by the verdict). Both cuts now MAJOR |
| Real runs re-graded | ✅ 0 grade changes | only wormhole/tree/DLSU_Library/stationary gains an attacker-gap reason (already MAJOR) |
| Tests / audit | ✅ 45/45 · 5/5 rules | new test: attacker gap MAJOR, the same victim gap MINOR, attacker cooldown MINOR |
| GUI | ✅ | "WHAT THIS MEANS - in plain words" card on the Campaign run panel and the Verify page: the attack, the victims, the control boards, each gap as a bullet with why it does / does not matter, + a postcard analogy; self-test exit 0 |

**Verdict: ✅ a victim with incomplete data is one witness fewer (MINOR, proven by the impact check); an attacker with
incomplete data is incomplete evidence of the attack itself (MAJOR, recapture required).**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #55 — Oct 19, 2026 · evening — why tree boards change parent / disappear

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `426989a` + this change
> **Request:** "children suddenly disconnect and change parent, sometimes a node is gone totally even powered on - did you do something in the tree topology?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 53 captures + 1 live root log (teammate, ~10:48 PM PHT) | raw exports (parent_mac, rssi_dbm) |

| Check | Result | Detail |
|---|---|---|
| Firmware changes since oct. 10 | ✅ none to parent selection | tree gate / wormhole gate = root-side observers; [HEALTH] = 1 line / 30 s at priority 1; crash record = written once after a crash; sdkconfig 5.3.5 -> 5.5.4 regen: 0 values changed (14 renames, 121 new defaults) |
| Parent switches + resets in all captures | ✅ rare | 13 switches + 1 reset in 53 runs; star 0. Clustered on board B768 (70:68 = the D9 crash board) and on G402 |
| Link strength | ⚠️ marginal everywhere | median parent RSSI -71 to -78 dBm per topology/room; ~70 board-runs below -78 dBm = inside ESP-MESH's default re-parent bands (-78 / -82 / -85) |
| Why TREE | ✅ explained | tree is the only self-organised topology (linear / star / partial pin parents), so only tree children re-parent on a weak link or a crashed parent |
| Teammate's live log | ❌ attacker subtree dropped at START | the attacker's 2 children stopped reporting ~128 s, the attacker itself ~134 s (START at 135.6 s); 0C80 re-joined under the root, E618 went OFFLINE; attacker link -58 dBm (strong) -> the attacker board most likely crashed / rebooted. Needs its serial log or crashes_<node>.csv |
| Fix 1 (GUI) | ✅ | pre-START 'Links strong enough' warns below -78 dBm (ESP-MESH's own band; was -80) with the reason |
| Fix 2 (firmware, D-26) | ✅ compiles, ❌ not on hardware | tree non-root boards: ESP-MESH's own switch / RSSI thresholds read at boot and shifted 6 dB weaker, weak-link watch x3 (`TREE_STICKY_PARENTS`); 4 variants build with 0 warnings; tree builds link it, linear does not |

**Verdict: nothing we changed broke the tree. Causes: marginal links + tree being the only self-organising topology +
a crashing board (B768 earlier, the attacker in tonight's log). D-26 + the -78 dBm warning reduce the first two; the
crash needs the attacker's serial log / crash record.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #54 — Oct 19, 2026 · afternoon — every run re-analysed with D-25, then re-verified

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `5c0ba40` + this change
> **Request:** "re-analyse everything then verify; push after the analysis"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 53 runs (52 attack + 1 benign) | `analyze.ps1 -All -Verify` (paused at 31, resumed for the other 22) |

| Check | Result | Detail |
|---|---|---|
| Re-analysis | ✅ 53/53 | every run trimmed -> preprocess (D-25) -> features -> EDA -> verify, exit 0. baseline/partial_mesh/DLSU_Library/stationary is an EMPTY folder (no capture) - not a second benign run |
| Verdicts vs the committed (pre-D-25) tables | ✅ 52/52 attack verdicts identical | |
| Grades that changed | ✅ 3, all explained | blackhole/linear/G402/stationary MINOR -> GOOD (gaps were the D-25 artifact); blackhole/tree/G402/stationary MAJOR -> MINOR (only B768's crash left); blackhole/linear/Yuchengco/stationary MINOR -> STRONG - **a different capture**: it was recaptured oct. 19 1:37 AM (the oct. 9 files are archived locally) |
| Benign run (baseline/linear/home/highload) | ❌ | first analysis ever: BENIGN NOT CONFIRMED (cooldown PDR 0.72, no attacker) - C15 |
| Topology "Gate 2" warnings (linear DLSU+G402 highload, linear G402 stationary) | ✅ not from D-25 | verify_topology.py reads the RAW exports, not the windows - unchanged by the tick fix |
| Audits on the final tables | ✅ | tests 44/44 · audit_verdict_sync 5/5 rules · placebo 0 false positives / 104 · threshold sensitivity 0 flips |
| GUI bug found | ❌ -> 🔧 | Analyse on a benign run passed `-Attack none`; analyze.ps1 only accepts `baseline` -> it always failed. Fixed in Start-Analysis. New button: Verify page **Re-analyse everything** |
| Push | ⚠️ partial by design | analysis tables pushed with git (smart_sync would keep GitHub's pre-D-25 copies as "equivalent"). **blackhole/linear/Yuchengco/stationary held back**: the recapture would sit next to the oct. 9 files still on GitHub - needs the team's OK to replace them |

**Verdict: ✅ D-25 applied to every run; no verdict changed; grades are now measured on complete windows.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #53 — Oct 19, 2026 · ~5:30 AM — thresholds, signature formulas, missing windows, benign runs: honest re-assessment

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `8ac4515` + this change (pushed)
> **Request:** "check the thresholds are correct and have a basis; do we need a paper; what causes stalling / missing samples and can it be fixed; show the attack signature in Campaign and Verify; check every feature's calculation and study; why does an incomplete dataset still pass; re-assess the grading; what does verify do for benign"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 52 attack runs + 1 benign | every analysed cell; re-analysed in scratch only (repo tables untouched) |

| Check | Result | Detail |
|---|---|---|
| **Missing windows — root cause** | ❌ -> 🔧 | NOT the boards: FE90 logged 1,807 rows in 182 s of attack (full 10 Hz) yet lost 59 % of its windows. Firmware samples with `xTaskDelayUntil`; held-up samples come late and bunched; preprocessing's nearest-tick rounding put two on one tick, left false holes, and the 8-of-10 rule discarded the window. Fix D-25 (`_assign_ticks`): each sample on the tick it was scheduled for (≤ 300 ms late, never early) |
| Re-analysis with D-25 (trim → preprocess → features, like analyze.ps1) | ✅ | **52/52 verdicts identical**; 2 grades change, both explained: blackhole/linear/G402/stationary MINOR -> GOOD (gaps were the artifact); blackhole/tree/G402/stationary MAJOR -> MINOR (only B768's real crash at +28 s is left; the attacker's 'missing end' was the artifact too) |
| Gaps inside a phase (new check S9) | ✅ added | before: only a board going silent at the END was seen. Now every board needs windows for ≥ 95 % of each phase (the project's own coverage floor) |
| Impact check scope | ✅ added | may set aside at most half the boards (otherwise no control group is left); a failed check makes those gaps MAJOR, never "result not affected" |
| Placebo test (`tools/audit_false_positives.py`, new) | ✅ 0 FP | normal vs normal, both signatures, 104 tests: 0 false confirmations. 3-sigma alone passed once (home/highload: congestion took forwarding to 86 % pre-attack) - the attacker check (< 50 %) blocked it |
| Grade thresholds sensitivity | ✅ | every grade threshold moved down/up: 0 moves except at extremes (window floor 80 % / 98 %); majority rule 1/3..2/3: 0 moves |
| Verdict thresholds (`audit_threshold_sensitivity.py`) | ✅ 0 flips | unchanged |
| Signature formulas vs code | ✅ | FR = forward/recv (Eq 4.2, ratio-of-sums, attacker-scoped), PDR by sequence number (5 attribution rules), IED (Eq 4.3), CS (Eq 4.15, = FR information -> support only), NFR (neighbours' witness), TunnelIntensity (Eq 4.16), DuplicateRate [R]. Caveat stated: with sd = 0 the 3-sigma test reduces to MIN_EFFECT |
| Benign verification (new `--attack none`) | ✅ added | no-attack test (both signatures must stay still) + health (PDR ≥ 0.90 [K], relays ≥ 90 % [A]) + data. **The one benign capture (baseline/linear/home/highload) is NOT a clean reference**: cooldown PDR 0.72, two relays 83-85 % with no attacker |
| Hard-coded / forced results | ✅ none | one bare literal (cooldown 0.5) made a named, documented constant |
| Tests | ✅ 44/44 | + benign confirmed / dropping relay not benign / majority rule / S9 gap |
| GUI | ✅ | VALIDITY strip (ATTACK · SIGNATURE · SETUP · DATASET) + ATTACK SIGNATURE card on Campaign and Verify; EXCLUDED / NO DATA rows now shown; Verify works on benign runs; self-test exit 0 |

**Verdict: ✅ the verdicts were right and stay right; the GRADES were too strict where our own preprocessing
manufactured gaps — fixed at the cause (D-25), not by loosening a threshold. Thresholds now listed with their basis
(study / proposal / platform docs / engineering bound + sensitivity) in docs/attack-validation/GRADING-AND-THRESHOLDS.md.
To apply: re-run `analyze.ps1 -All` (the repo's analysis tables still use the old alignment), then Verify / Check all
verdicts. Recapture: the benign run (not clean); tree/G402/stationary advised (B768 crash), D2 / D8 / D9 as before.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #52 — Oct 19, 2026 · ~3:30 AM — final grade scale (MINOR GAPS / MAJOR GAPS) + bias re-check

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `4e8a826` + this change
> **Request:** "two types of incomplete data, minor (won't affect the result) and major; check for anything hard-coded / forced that became biased; why is tree/G402/stationary MAJOR instead of MINOR?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 52 attack runs | every analysed attack cell |

| Check | Result | Detail |
|---|---|---|
| Grades (all runs) | ✅ | 7 STRONG · 40 GOOD · 1 MINOR GAPS (blackhole/tree/G402/stationary) · 2 MAJOR GAPS (blackhole/tree/G402/burst, wormhole/tree/DLSU_Library/stationary) · 2 NOT CONFIRMED |
| **Bias found** | ❌ -> 🔧 | a fixed rule called a board with **< 60 s** of attack windows a MAJOR gap even when the report's own IMPACT CHECK (3-sigma test re-run WITHOUT that board) still confirmed the attack. tree/G402/stationary: B768 had 28 s, attack held without it -> was MAJOR, now **MINOR**. Fixed: a board that WAS measured in the attack (cut short / short / no cooldown) is a MINOR candidate and the impact check decides; a failed impact check = MAJOR |
| Minor/major cut-off sensitivity | ✅ 0 moves | all 52 runs re-graded with the cut at 30 / 45 / 60 / 90 / 120 s: no grade moves |
| Verdict thresholds (`audit_threshold_sensitivity.py`) | ✅ 0 flips | 14 settings ±~50 %; the two absurd controls flip 31 / 14 (the test can fail) |
| Verifier vs redo list (`audit_verdict_sync.py`) | ✅ all 5 rules hold | rules rewritten for the new pairing (below) |
| Hard-coded run names | ✅ none in code | run names appear only in comments / docstrings |
| Tests | ✅ 40/40 | new: short attack judged by the impact check; failed impact check -> MAJOR |

**Status pairing (one rule, verifier -> redo list -> GUI):** GOOD / STRONG = OK = 🟢 DONE · MINOR GAPS = CHECK = 🟡 DONE -
RECAPTURE ADVISED · MAJOR GAPS = REDO (evidence `verifier-data`) = 🟠 RECAPTURE REQUIRED · NOT CONFIRMED = REDO (`verifier`) = 🔴 REDO.
Gap lines are now specific ("1C38 (attacker): only 117 of 179 s of its attack were recorded - the last 62 s are missing").

**Verdict: ✅ no forced or biased result left; one over-strict fixed rule removed (it could only make a grade WORSE, never
better); grades do not depend on the cut-off; verifier, redo list and GUI agree on every run.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #51 — Oct 19, 2026 · ~2:50 AM — verdict, grade and REDO: in sync? hard-coded? decided by the data? backed by studies?

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `5f0d326` + this change
> **Request:** "double check how verdicts, grades and the REDO decision happen - synchronised, no hard-coding or bias, everything calculated properly on its basis and supported by studies"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 52 attack runs | every analysed attack cell (baseline cells have no attack verdict) |

| Check | Result | Detail |
|---|---|---|
| Verifier vs redo list, 5 rules (`tools/audit_verdict_sync.py`) | ✅ all hold | 7 STRONG = OK · 41 QUALIFIED = CHECK (same footnote count) · 2 not confirmed = REDO by the verifier · 2 CONFIRMED + REDO, each from a named NON-verifier source: tree/G402/burst (**D2**, 7 of 8 boards), wormhole/tree/DLSU/stationary (**D8** + incomplete capture). Every severity = the worst of its reasons |
| Hard-coded results | ✅ none | no verdict/grade/severity is set by hand; all come from the checks |
| Threshold basis | ✅ listed | from studies: 3-sigma (Zhukabayeva 2025), baseline PDR floor 0.90 (Khan 2022: > 0.97 on ESP-MESH), blackhole = drop of forwarded traffic (Airehrour 2018), position (Karlof & Wagner 2003), duplicates (Ramirez Gomez 2019), tunnel timing (Hu-Perrig-Johnson 2003), self-healing (Espressif); from our data: re-join budget (3-6 s re-joins), min effect 0.10 (one lost probe vs a real attack); project spec: 5-window blocks (Table 4.10), 95 % coverage (Milestone 5); engineering, deliberately loose: victim cut 0.50, bystander drop 0.30, attacker forward 0.50 |
| Sensitivity (`tools/audit_threshold_sensitivity.py`) | ✅ 0 flips | 14 settings (sigma 2.5/3.5, min effect 0.05/0.20, victim cut 0.25/0.75, bystander 0.15/0.45, attacker 0.25/0.75, flip 2/5, baseline floor 0.80/0.95) x 52 runs = 728 re-judgements: **no verdict changes**. Controls (sigma 1000; victim cut 0.0) flip 31 and 14 -> the test does change the judgement |

**Verdict: ✅ the verdict, the grade and the REDO decision agree on every run; nothing is hard-coded; the verdicts are
decided by the data (they do not move when any threshold is moved by ~50 %); each threshold has a stated basis - a study,
our own measurement, the project spec, or a deliberately loose engineering bound.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #50 — Oct 19, 2026 · ~2:30 AM — honesty audit of the verdict (no bias, no fake, aligned to the studies) + why tree/G402/burst = CONFIRMED but REDO

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `133a7ac` + this change
> **Request:** "check there is no bias or fake in the verdict, still aligned to the supporting papers. Why does my tree blackhole G402 burst say CONFIRMED and STRONG but need a redo?"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 54 attack captures | every analysed attack cell + the oct. 18 tree/G402 archives |

| Check | Result | Detail |
|---|---|---|
| Verdicts vs the verifier BEFORE all oct. 18-19 changes (`0e43f7e`) | ✅ 2 changed, both intended | tree/G402/stationary (10:11 PM) and its archived 7:21 PM run: SETUP INVALID -> CONFIRMED under D-23 (allowed self-healing moves; no-path seconds left out). Nothing else changed |
| Forced / hard-coded results | ✅ none | no code sets a verdict; the only `= True/False` hits are start values before the checks |
| Flat baseline (sd = 0 -> infinite sigma) | ✅ guarded | a primary also needs an absolute change >= 0.10 (MIN_EFFECT), so a tiny wobble on a flat baseline cannot pass |
| Study tags | ✅ 9/9 | Z Zhukabayeva, A Airehrour, KW Karlof & Wagner, K Khan, R Ramirez Gomez, H Hu-Perrig-Johnson, E Espressif, BA MacCoun & Perlmutter, PR Simmons / Nosek - all in docs/references or ATTACK-VALIDATION.md |
| **Grade bug found** | ❌ -> 🔧 | `_confidence()` dropped any WARN whose words were not on its footnote list -> tree/G402/burst (FE90 "NO labelled window") showed **STRONG**. Fixed: an unlisted warning becomes a footnote as it is; a missing run log (force-start not checkable) is a footnote too. Unit test now proves STRONG needs a normal START in the run log |
| Grades after the fix | ✅ | 7 STRONG · 43 QUALIFIED · 2 not confirmed. 42 of the QUALIFIED carry "force-start could not be checked (no run log saved)" (captures before run logs were saved) and 11 "partial mesh still a plain tree" (B-pm) - honest, verdicts unchanged |
| tree/G402/burst | ⚠️ explained | verdict CONFIRMED (2/2), now **QUALIFIED** (FE90 had no usable windows; no run log). The **REDO** comes from thesis checklist **D2** ("r1 lost FE90 - recapture with all 8 boards"): a COMPLETENESS decision (7 of 8 boards), not the attack verdict. Both are true at once |
| Tests | ✅ 38/38 | |

**Verdict: ✅ no fake or biased result found; one overstatement (STRONG) fixed. The verdict logic is unchanged
except the two documented D-23 runs; every cited study is vetted.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #49 — Oct 19, 2026 · ~2:30 AM — verifier change: 7 more situations (S1-S7) + CONFIDENCE grade; sweep of every capture

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `32454e5` + this change
> **Request:** "add more possible situations and decisions and enhance the final verdict"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| all | all | all | all | live | 54 attack captures | every `datasets/analysis/<attack>/<topology>/<location>/<scenario>/feature_table.csv` (baseline cells skipped) + the oct. 18 tree/G402 archives |

| Check | Result | Detail |
|---|---|---|
| Old (`32454e5`) vs new, all 54 | ✅ 0 changed | the new situations only add footnotes |
| CONFIDENCE grades | ✅ | 48 STRONG · 2 QUALIFIED (oct. 18 7:21 PM + 10:11 PM tree/G402) · 2 not confirmed (tree/G402/highload B768 flip; one INCONCLUSIVE) |
| A first draft that was wrong | ⚠️ caught + fixed | "attacker went silent" as a FAIL turned the 10:11 PM run SETUP INVALID: 1C38's file has data to +178 s but the feature table has its windows only to +117 s (windows discarded for too few samples). The table cannot tell silence from dropped windows -> WARNING only (S3) |
| Tests | ✅ 38/38 | new: flapping = WARN, baseline role change = WARN, confidence STRONG / QUALIFIED / not confirmed |

**Verdict: ✅ the verdict logic is unchanged; reports now carry a CONFIDENCE grade and named footnotes.**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #48 — Oct 19, 2026 · ~1:45 AM — blackhole · tree · G402 · stationary r1: duplicate files in the run folder (old run brought back by the GitHub sync)

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `df48870` + this change
> **Request:** "check the G402 stationary tree blackhole - why there are duplicate files; put a safety net so it never happens, also no duplicate / double analysis"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | stationary | r1 | oct. 18, 10:11 PM run (root session 9:55 PM) | `exports/blackhole/tree/G402/stationary/` - was 17 telem/arrivals files (2 runs), now 8 (root telem + arrivals, 6 children) |

| Check | Result | Detail |
|---|---|---|
| Duplicates found | ❌ → 🔧 | the **7:21 PM run's 9 files** (root 0738PM x2, children 0756-0808PM) were back in the run folder, all rewritten at **23:36** |
| Cause | 🔧 | the GUI **GitHub sync** at 23:36 (commit `8e070b7`): the files were archived at 22:11 into `ESP32-Environment/archive/` (tools/archive_replaced.py), but smart_sync.py only knew `datasets/archive/` as "archived locally" -> it saw them on GitHub, missing locally, and pulled them back as "a teammate's file you don't have" |
| Effect on the analysis | ❌ → 🔧 | trim kept the newest file per board, but **FE90** had only its OLD (7:21 PM) file - it was analysed as part of the 10:11 PM run (23:37 report). Verdicts #47 used that mixed table |
| Copies vs archive | ✅ | all 9 byte-identical to `archive/2026-10-18_...-replaced-2/exports/` -> moved to `.../resurrected-by-sync-2026-10-18_2336/` (nothing deleted) and their deletion committed so no laptop's sync brings them back |
| Re-analysis (clean folder) | ✅ | 8 files of ONE run (FE90 not yet collected); **BLACKHOLE CONFIRMED 2/2**, 4 victims cut off (PDR 0.000), ED80 ALLOWED (20 no-path s left out); the old FE90 time-series plot parked in `eda_output/_archive/` |

**Safety nets added:** (1) smart_sync.py treats `ESP32-Environment/archive/` as archived and never pulls a SECOND file
of the same board + repeat into a run folder; (2) trim_run.py analyses ONE file per board per run (the newest) and
LEAVES OUT a capture exported before the root's run began (an earlier run), naming each; stale copies in `trimmed/`
are parked in `trimmed/_archive/`; (3) eda.py parks plots of files no longer in the feature table.
**Verdict: ✅ folder = one run; the verdict stands (CONFIRMED). FE90 still to be collected (C13).**

<!-- ═══════════════════════════════════════════════════════════════════════════
<!-- ═══════════════════════════════════════════════════════════════════════════

## 🔎 VERIFICATION #47 — Oct 19, 2026 · ~12:30 AM — blackhole · tree · G402 · stationary r1 (10:11 PM recapture): collected, 70:68 fixed, verdict under D-23 exclusion rule

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `9ca5929` + this change
> **Request:** "do the export for the recent run" · "why didn't the setup pass - the change happened only under the blackhole, don't be too strict, don't be biased" · "why is 70:68 missing baseline, attack and cooldown"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | stationary | r1 | oct. 18, root session 9:55 PM log (START 37 s after READY), root export 10:11 PM | root + 6 children in `exports/blackhole/tree/G402/stationary/` (ED80 + 1C38 imported by hand 10:58 / 11:01 PM; 0C80, F4:18, D7B4, 70:68 by Collect 11:08-11:17 PM). **FE90 not collected** (COM32 `SD_NO_CARD` / COM3 no answer) |

| Check | Result | Detail |
|---|---|---|
| 70:68 piece | ❌ → 🔧 | Collect v1 filed `r7_b18` = 319 s of stabilise only ("missing baseline, attack, cooldown"); then `r8_b19` (most data) = the **9:40 PM root attempt**. Right piece = **`r10_b114`**: boot order b19 < b113 < b114, and the 9:55 PM log last heard 70:68 ~24 s into the attack (OFFLINE at +58.7 s, 35 s timeout) = its 29 s of attack. Both wrong files in `archive/2026-10-19_blackhole-tree-G402-stationary-r1-B768-stabilise-only/` (+ REPLACED.txt) |
| 70:68 coverage | ⚠️ | baseline 300 s, attack **29 s**, no cooldown: the board went down 29 s into the attack (94 reboots between b19 and b113 = a boot loop between the two attempts) - D9 / C12 pattern, 3rd victim under the attacker |
| [1] Attack signature | ✅ 2/2 primaries | attacker ForwardingRatio 1.000 → 0.000, PDR 1.000 → 0.25 pooled; 4 victims PDR 1.0 → **0.0**, 0C80 (above the attacker) stayed 1.0 |
| ED80 re-route | ⚠️ TOLERATED WITH EXCLUSION | its parent 70:68 went down → 20 of 160 attack windows had no traceable path (detached / dead parent) → **excluded from the 3-sigma test**; VICTIM in every traceable window. Before the 70:68 fix (only the wrong piece in the table) it read 52/160 → FAIL under the old budget rule |
| Robustness re-test | ⚠️ untestable | only 42 s of attack before the first re-route (needs 60 s) - the verdict rests on the layout rule; say so |
| 20:38 cooldown | ⚠️ | 92 s vs ~120 s on the others (file imported by hand at 11:01 PM) - check its card if cooldown is quoted |
| Gate 2 (topology convergence) | ⚠️ not a verdict input | "converged within 60 s: NO" for 0C80 / 1C38 = their files start with the **9:40 PM root attempt** (kept running across the root re-flash); the analysis excludes those rows (root-restart rule), the convergence timer does not |
| Sweep vs `5c5e3e1` | ✅ | 54 captures: only this run changed (SETUP INVALID → CONFIRMED). Tests 34/34 |

**Verdict: ✅ BLACKHOLE CONFIRMED, with footnotes** - 70:68 only 29 s of attack (crashed / reset), ED80's 20 dead-path
windows excluded, robustness untestable (42 s), FE90 not collected. Checklist C13.

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
