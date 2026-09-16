# NIS16 — Milestone Output Verification (are the results actually correct?)

Checked against the **real files in the repo** on jul. 27, 2026, not against the proposal. Every number below was pulled from the actual `analysis/` outputs and `tools/exports/` raw CSVs. Companion to [DEFENSE-PREP.md](0_Resources/archive/DEFENSE-PREP.md).

> ⚠️ **STALE as of aug. 06, 2026 — the run counts below are out of date.** This file was verified
> on jul. 27, 2026, when 4 runs existed. `tools/exports/run_ledger.csv` now lists **16 of 24**
> (linear + star complete for both attacks; tree/partial blackhole r1). The *per-milestone
> verification logic* below is still sound — only the matrix counts are wrong. Re-verify against
> the ledger before quoting any number from here. See `STATUS.md` for the current matrix.

**Scope of what exists right now:** only the **linear** topology is captured (4 of 24 runs). Of those, only **baseline** and **blackhole** have been pushed through features + EDA. **Wormhole is captured but not yet analyzed.** So "outputs correct?" can only be answered for linear baseline + blackhole in full, and for wormhole at the raw-capture level.

---

## Top-line verdict

| Milestone | Output that exists | Correct? | One-line reason |
|---|---|---|---|
| M1 Firmware | Logs from 6 boards, 11-col schema | ✅ Yes | All roles log; schema intact across every export |
| M2 Attacks | Blackhole + wormhole signatures in raw logs | ✅ Yes | Both signatures reproduce (numbers below) |
| M3 Topologies | Linear chain only | 🟡 Partial | Linear verified; tree/star/partial not captured |
| M4 Matrix | `run_ledger.csv` = 4 runs | 🟡 4 of 24 | linear·blackhole ×3 + linear·wormhole ×1 |
| M5 Extraction | Per-node CSVs + ledger | ✅ Yes | Files intact, labeled, no truncation seen |
| M6 Preprocessing | `windowed_dataset.csv` | ✅ Yes | Windows + delta + modal-label all produced |
| M7 Features | `feature_table.csv` (base + blackhole) | 🟡 Partial | 16 cols present; wormhole table not built yet |
| M8 EDA | stats, correlation, distributions, PCA/t-SNE | 🟡 Partial | Correct where run, but gaps (see below) |

Legend: ✅ output present and verified · 🟡 present but incomplete · ❌ not produced.

---

## The EDA — is it correct? (your main question)

**Where it's solid.** The blackhole EDA reproduces the exact attack signature, straight from `blackhole/linear_topology/eda_output/descriptive_statistics_by_phase.csv` (Baseline phase → Blackhole phase, *within the same run*):

| Feature | Baseline | Blackhole | Reads as |
|---|---|---|---|
| ForwardingRatio | 0.951 | **0.000** | relay stopped forwarding — primary signature ✅ |
| ConsistencyScore | 0.064 | **1.000** | perfect deviation from ideal forwarding ✅ |
| IngressEgressDelta | 0.82 | **15.9** | packets absorbed, not passed on ✅ |
| RetryRate | 0.019 | **0.166** | link stress spikes ✅ |
| PDR (mean/median) | 0.855 / 1.0 | **0.226 / 0.0** | delivery collapses ✅ |
| ParentSwitchRate / LayerChangeCount | 0 / 0 | **0 / 0** | zero re-routing → proves it's a drop, not a dead node ✅ |

**Attacker's own counters** (raw `child_node5` telem, attack window, all 3 repeats): forwarded **plateaus at ~1,400** (only what it relayed during baseline — nothing new during the attack), received **keeps climbing to ~2,120** (victims never stopped), dropped **≈720 / 925 / 720**. That is a deliberate drop, on the record.

**Wormhole** (raw `root ... arrivals.csv`, verified by direct count): 2,797 arrivals, 2,616 unique, **exactly 181 duplicate copies — every one from a single source MAC** (`F4:2D:C9:73:E6:18`, the tunneled node). The other victims show zero duplicates. The signature is real and clean.

### ⚠️ Correctness caveats you must know before quoting the EDA

1. **`LatencyHopRatio` mean is NOT trustworthy.** In the stats file its variance is ~7,053 and the mean is ~18 ms/hop, but the **median is ~4 ms/hop**. The mean is polluted by unsynchronized-clock outliers. **Quote the median (or the recovered 2.4–2.8 ms/hop from `features.py`), never the mean.** See [DEFENSE-PREP.md](0_Resources/archive/DEFENSE-PREP.md) Q10.
2. **`RSSI_mean` mean (−57) vs median (−68) disagree** because the window mixes nodes at different layers. Report per-layer or use the median; don't present −57 as "the" signal level.
3. **Blackhole PCA/t-SNE is missing** — `dimensionality_reduction.png` exists for baseline but **not** blackhole. So the 2-D separability picture wasn't generated for the attack run.
4. **Only 3 of 16 features have distribution plots** (ForwardingRatio, RetryRate, RSSI_Hop_Diff). The rest weren't plotted.
5. **No combined cross-label table exists.** Each label is analyzed in its own folder in isolation. The stated M8 goal — showing baseline vs blackhole vs wormhole *separate from each other* — **cannot be shown yet**; that needs all three in one table. This matches your own [STATUS.md](STATUS.md) blocker.
6. **Wormhole never went through `features.py` / `eda.py`.** Its output folders are empty — the 181-duplicate result is from the raw arrivals file only, not the feature pipeline.
7. **PDR baseline drifts between runs** (0.971 in the pure baseline run, 0.855 in the blackhole run's baseline phase). Normal run-to-run variation — but cite *which run*, don't present one canonical number.

### What the EDA is NOT (scope clarity)
`eda.py` produces **descriptive stats, by-phase stats, Pearson + Spearman correlation, distribution plots, and PCA/t-SNE only**. It does **not** run clustering (DBSCAN / K-Means / GMM / silhouette / purity / ARI). That's correct — M8 is *Exploratory Data Analysis*; clustering is later work. **Do not claim clustering results exist yet** — no cluster output files are in the repo.

---

## Milestone-by-milestone notes

- **M1 / M5 / M6 — solid.** Every board logs the 11-column schema; exports are intact and labeled; `windowed_dataset.csv` shows re-basing, cumulative→delta, 5 s windows, and modal labels all applied. `n_samples_present` vs `n_samples_expected` columns are there to prove coverage.
- **M2 — both attacks verified** (numbers above). Say plainly: signatures reproduce on real hardware.
- **M3 — linear only.** Slides 7–13 show all four topology *diagrams and floor plans*, but only linear has *data*. If a panelist asks "did you run all four?" the honest answer is **no, linear only so far**; the others are placed and diagrammed.
- **M4 — 4 of 24, and be upfront about it.** `run_ledger.csv` lists exactly: linear·blackhole r1–r3, linear·wormhole r1. Nothing else.
- **M7 — 16 columns present but run-type-gaps are by design.** In the blackhole table the 3 tunnel features are all-NaN (no wormhole), and the 3 relay features are populated only for the attacker row. Combined across run types you reach 16; per run you get 10–13. Flag every empty cell as "blank by design," not missing data (DEFENSE-PREP Q9).

---

## Fix / say-this-before-defense checklist
- [ ] **Never quote `LatencyHopRatio` or `RSSI_mean` *mean*** — use median / recovered value.
- [ ] Process **wormhole** through `features.py` + `eda.py` so M7/M8 aren't blackhole-only.
- [ ] Build the **combined baseline+blackhole+wormhole table** — it's the one output that unlocks the real M8 separability claim.
- [ ] Regenerate **blackhole PCA/t-SNE** (currently missing).
- [ ] If asked "is it done?": *pipeline works end-to-end; 4 of 24 runs; linear baseline + blackhole fully analyzed; wormhole captured, analysis pending; clustering is future work.* That sentence is defensible and matches the files.
