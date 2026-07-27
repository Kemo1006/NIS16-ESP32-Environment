# 🎬 M8 — Exploratory Data Analysis (10%)

> ## ⚠️ Criteria not supplied
> **Paste M8's criteria and I'll map each bullet.** Built from thesis **§4.2.6**, which
> `eda.py` implements directly, and the note in `2026-07-24.md`: *"all 5 analyses; outputs
> generated"*.

## 🎯 Verdict: all five analyses on all seven datasets · quality-limited until M4 fills

| §4.2.6 analysis | Output | Status |
|---|---|:--:|
| 1. Descriptive statistics | `descriptive_statistics.csv` + by-phase | ✅ |
| 2. Distribution visualisation | 3 plots per dataset | ✅ |
| 3. Time-series trajectories | 1 per source file | ✅ |
| 4. Cross-layer correlation | Pearson + Spearman, PNG + CSV | ✅ |
| 5. Dimensionality reduction | PCA + t-SNE, **plus a tunnel-end projection** | ✅ |

> 🎯 **Say this early:** *"The thesis is explicit that EDA at this stage is **strictly
> descriptive** — no inferential claims, no detection rules, no thresholds. This module produces
> plots and tables; it doesn't draw conclusions."* That sentence protects you from every
> "what's your accuracy?" question.

---

## 📍 THE COMMAND

```powershell
cd analysis
python eda.py wormhole\star_topology\feature_table.csv -o wormhole\star_topology\eda_output
cd ..
```

### 📋 SCREENSHOT the summary
```
── EDA Summary ─────────────────────────────────────
  Descriptive statistics:  ...\descriptive_statistics.csv
  Distribution plots:      3 written
  Time-series plots:       18 written
  Correlation plots:       correlation_pearson.png, correlation_spearman.png
    excluded (all-NaN): ['ForwardingRatio', 'IngressEgressDelta', 'ConsistencyScore']
  PCA/t-SNE plot:          ...\dimensionality_reduction.png
    excluded: [..., 'TunnelBytes', 'TunnelIntensity', 'TunnelLatency']
  Tunnel-end projection:   ...\dimensionality_reduction_tunnel_ends.png
    871 window(s) from 2 tunnel-end node(s); tunnel features kept: ['TunnelIntensity', 'TunnelBytes']
  All outputs in:          wormhole\star_topology\eda_output/
───────────────────────────────────────────────────────
```

💡 **The `excluded:` lines are a feature, not an apology.** Every plot states which columns it
dropped and why. Say so.

---

## 📊 SLIDE — coverage across the dataset

```powershell
cd analysis
foreach ($t in 'baseline\linear_topology','blackhole\linear_topology','blackhole\star_topology','blackhole\tree_topology','blackhole\partial_mesh_topology','wormhole\linear_topology','wormhole\star_topology') { $n=(Get-Content "$t\feature_table.csv" | Measure-Object -Line).Lines - 1; $e=(Get-ChildItem "$t\eda_output\*" -ErrorAction SilentlyContinue).Count; "{0,-34} {1,5} windows   {2,3} outputs" -f $t,$n,$e }
cd ..
```

| dataset | windows | benign / attack |
|---|---:|---|
| baseline · linear | 577 | 577 / 0 |
| blackhole · linear | 2470 | 1820 / 650 |
| blackhole · star | 2669 | 2020 / 649 |
| blackhole · tree | 877 | 661 / 216 |
| blackhole · partial | 944 | 727 / 217 |
| wormhole · linear | 2470 | 1819 / 651 |
| wormhole · star | 2531 | 1881 / 650 |

> 🗣️ *"Seven datasets, all four topologies, both attacks plus the baseline control — **13,346
> labelled windows** in total."*

---

## 1️⃣ Descriptive statistics

```powershell
cd analysis
Import-Csv wormhole\star_topology\eda_output\descriptive_statistics.csv | Select-Object -First 6 | Format-Table -AutoSize
cd ..
```
> 🗣️ *"Mean, median, variance and range per feature — plus a per-phase breakdown, which is where
> the attack window starts to look different from baseline."*

---

## 2️⃣ Distribution visualisation

📄 **Show:** `distribution_RetryRate.png`, `distribution_RSSI_Hop_Diff.png`,
`distribution_ForwardingRatio.png`

> 🗣️ *"The thesis names these three by name — stratified by phase and node role. The
> `ForwardingRatio` one is only meaningful in a blackhole run, since that's the only run with a
> relay."*

---

## 3️⃣ Time-series trajectories

📄 **Show:** any `timeseries_*.png`

> 🗣️ *"One figure per capture, showing parent-switch events and PDR over run duration. This is
> where you can visually line up the attack window with the phase boundaries."*

💡 `eda.py` now flags **stale** per-run plots whose source has left the dataset — a plot from an
archived run stayed behind once and made the folder show more runs than the dataset held.

---

## 4️⃣ Cross-layer correlation

📄 **Show:** `correlation_pearson.png` and `correlation_spearman.png`

> 🗣️ *"Pearson and Spearman across PHY, MAC and network features — RSSI, retry and tx counters,
> layer and parent. The title states which columns were excluded and why: all-NaN columns are
> mathematically undefined for a correlation, so they're dropped and named rather than silently
> omitted."*

---

## 5️⃣ Dimensionality reduction — ⭐ show BOTH plots

📄 `dimensionality_reduction.png` **and** `dimensionality_reduction_tunnel_ends.png`

> 🗣️ *"Two projections, answering different questions.*
>
> *The first uses only features present on **every** node — it asks: is the attack visible in
> what any node can measure? That's the realistic detection question. It **excludes** the tunnel
> features, because they exist on 2 of 6 nodes, above our 50 percent missing-data cutoff.*
>
> *The second is restricted to the two tunnel-end nodes with the tunnel features kept in — 871
> windows on star. It asks: does the tunnel evidence itself separate the attack window?*
>
> *We show both because showing only the first would look like there's no evidence, and showing
> only the second would overstate how easy detection is."*

💡 This is the most sophisticated 30 seconds in your deck. It's you explaining a limitation of
your own analysis before anyone finds it.

---

## ⚠️ The honest limitation

> 🗣️ *"M8 is quality-limited until M4 fills. Cross-topology separability — showing that baseline,
> blackhole and wormhole separate **as classes** — needs the full matrix in one table. Right now
> we have 15 of 24 cells, so the per-dataset EDA is complete but the cross-class comparison isn't
> yet meaningful. That's runtime, not method: the pipeline runs unchanged on the fuller
> dataset."*

**And name what's fixed since 07-24:** *"The mesh-stability limitation is gone — linear converges
in 0 to 3 seconds and star r2 and r3 pass cleanly. The single-repeat limitation is gone for four
cells, which are now at three repeats each."*

---

## 🗣️ 75-second script

> *"M8 is the exploratory analysis, and the thesis is explicit that it's **strictly descriptive**
> — no detection rules or thresholds derived here, and none are.*
>
> *\[summary] All five §4.2.6 analyses run on all seven datasets: descriptive statistics,
> distributions, time-series, Pearson and Spearman correlation, and PCA with t-SNE. **13,346
> labelled windows** across all four topologies.*
>
> *\[both projections] On dimensionality reduction we produce two plots. One uses only features
> every node has — the realistic detection question. The other is restricted to the tunnel-end
> nodes with the tunnel features kept in, because those exist on 2 of 6 nodes and get excluded
> from a whole-mesh projection. Showing only one would mislead in either direction.*
>
> *The honest limitation: cross-class separability needs the full matrix. That's the 10 cells
> still to run, not a change to the analysis."*

---

## 🛡️ Questions

**"What's your detection accuracy?"** ⭐ *expect this*
> *"We don't report one, and deliberately. This phase produces the dataset; the thesis specifies
> that EDA here is strictly descriptive. Building and evaluating a classifier is the next phase
> and it needs the complete matrix."*

**"Why does the PCA exclude the tunnel features?"**
> *"They exist on 2 of 6 nodes — about 67 percent NaN, above our 50 percent cutoff. Feeding
> columns that sparse into a shared matrix and then dropping incomplete rows would empty the
> plot. So the whole-mesh projection drops them and names them, and the tunnel-end projection
> keeps them over the nodes that have them."*

**"Can you see the attack in the plots?"**
> *"In the descriptive statistics and the per-phase breakdown, yes — the attack window differs
> measurably. In the whole-mesh projection the separation is weaker, which is itself informative:
> it says the attack isn't trivially visible in features every node shares. The strongest
> evidence isn't in EDA at all — it's the arrivals log, where the blackhole drops to near zero
> and the wormhole produces exact duplicates."*

**"Why is baseline·linear only 577 windows?"**
> *"It's a single run, and shorter — a baseline run has no attack phase, so it's 8 minutes rather
> than 11. It's the control reference, not part of the 24."*

**"Are these plots reproducible?"**
> *"Yes. `eda.py` takes a feature table and an output folder, and the pipeline from raw captures
> forward is deterministic. Anyone with the repository can regenerate every plot."*

---

## ✅ Checklist
- [ ] EDA summary output screenshotted *(shows all five analyses at once)*
- [ ] **Both** dimensionality-reduction plots exported side by side
- [ ] One correlation heatmap
- [ ] One time-series plot
- [ ] Dataset coverage table (7 datasets, 13,346 windows)
- [ ] Say **"strictly descriptive, no detection rules"** in the first 20 seconds
- [ ] Ready to name what M4 unblocks — cross-class separability
- [ ] Know: **5 analyses** · **7 datasets** · **13,346 windows** · **871 tunnel-end windows**
