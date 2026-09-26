# 🎬 M6 — Preprocessing Pipeline (10%)

> ## ⚠️ Criteria not supplied
> **Paste M6's criteria and I'll map each bullet precisely.** Built below from the milestone
> scope recorded in `2026-07-24.md`: *per-node re-basing · cumulative→delta · 5 s windowing ·
> low-sample discard · modal labels*.

## 🎯 Verdict: complete and exercised on all 7 datasets

| Stage | Evidence | Status |
|---|---|:--:|
| Per-node re-basing | each node's clock zeroed to its own first sample | ✅ |
| Cumulative → delta | counters converted to per-window deltas | ✅ |
| 5 s windowing | `WINDOW_SECONDS = 5` (Table 4.10) | ✅ |
| Low-sample discard | **0.2 – 0.8 %** across every dataset | ✅ |
| Modal labels | window label = modal `phase_id` | ✅ |
| Deterministic | same folder in → same table out | ✅ |

---

## 📍 THE COMMAND — this one output covers most of the milestone

```powershell
cd analysis
python preprocess.py ..\tools\exports\wormhole\star_topology\trimmed -o wormhole\star_topology\windowed_dataset.csv
cd ..
```

### 📋 SCREENSHOT the quality report
```
── Preprocessing Quality Report ──────────────────────────
  Files loaded:               18
  Files skipped (bad/empty):  0
  Rows dropped (contaminated):0
  Rows dropped (corrupt ts):  0
  Rows downsampled to 1Hz grid: 110162
  Raw rows ingested:          122862
  Windows formed:             2552
  Windows discarded (<4 smp): 21
  Windows discarded (gap>2s): 0
  Windows kept:               2531
  Discard fraction:           0.8%
  Per-node window counts:
    NODE_2805A532D7B4: 396
    NODE_704BCA25B768: 433
    ...
───────────────────────────────────────────────────────────
```

> 🗣️ *"Every stage reports itself. Files loaded, rows dropped and why, windows formed, windows
> discarded and why, and the final per-node counts. Nothing is silently absorbed — if a file
> were unreadable or a row contaminated, it appears here as a number."*

💡 **Point at `Rows dropped (contaminated): 0`** — that's ESP-IDF log noise interleaved into a
CSV during serial export. Zero means clean captures.

---

## 1️⃣ Per-node re-basing

### 📄 SHOW — why it's needed
```powershell
Select-String -Path analysis\preprocess.py -Pattern "def handle_missing_values" -Context 0,8
```

> 🗣️ *"Each ESP32 runs `esp_timer_get_time()`, which starts at zero on **its own** boot. Six
> boards booted at different moments have six unrelated clocks. So each node's series is
> re-based to its own first sample — every node's timeline starts at t=0 — and windows are then
> aligned on that relative clock."*

⚠️ **This is why cross-node timestamp comparison is invalid**, and why M1/M4's phase-tolerance
evidence compares *durations* rather than timestamps. Say it here and it pre-empts the question
later.

---

## 2️⃣ Cumulative → delta

### 📄 SHOW — a raw counter climbing
```powershell
cd tools\exports\wormhole\star_topology\trimmed
python -c "import csv,glob;rows=list(csv.DictReader(open(glob.glob('child_node6_*_r2_*telem.csv')[0])));[print('t=%7.1fs  tx_count=%s  retry=%s'%(int(r['timestamp_us'])/1e6,r['tx_count'],r['retry_count'])) for r in rows[::1200][:6]]"
cd ..\..\..\..\..
```
```
t=    0.0s  tx_count=0     retry=0
t=  120.0s  tx_count=118   retry=0
t=  240.1s  tx_count=239   retry=0
...
```

> 🗣️ *"The firmware writes **cumulative** counters — `tx_count` only ever climbs. A raw value is
> meaningless for a 5-second window; what matters is how much it changed. Preprocessing converts
> each counter to a per-window delta, which is what the features are built from."*

---

## 3️⃣ 5-second windowing

### 📄 SHOW the constants
```powershell
Select-String -Path analysis\preprocess.py -Pattern "WINDOW_SECONDS|EXPECTED_SAMPLES_PER_WINDOW"
```
```python
WINDOW_SECONDS = 5                  # Table 4.10
EXPECTED_SAMPLES_PER_WINDOW = 5     # 1 Hz logging rate × 5 s window
```

> 🗣️ *"Five-second windows, per Table 4.10. We capture at 10 Hz and downsample to a 1 Hz grid
> for analysis — that's deviation D-1, recorded in `thesis-deviate.md` — so a full window holds
> five samples. The attack phase is 180 seconds, which gives 36 windows per node per run."*

---

## 4️⃣ Low-sample discard

Visible in the same report:
```
Windows discarded (<4 smp): 21
Windows discarded (gap>2s): 0
Discard fraction:           0.8%
```

### 📍 COMMAND — the figure across every dataset
```powershell
cd analysis
foreach ($t in 'baseline\linear_topology','blackhole\linear_topology','blackhole\star_topology','blackhole\tree_topology','blackhole\partial_mesh_topology','wormhole\linear_topology','wormhole\star_topology') { $n=(Get-Content "$t\feature_table.csv" | Measure-Object -Line).Lines - 1; "{0,-34} {1} windows" -f $t,$n }
cd ..
```

> 🗣️ *"A window with fewer than four of its five expected samples is discarded rather than
> imputed — the variance features would be unreliable. Across every dataset that's between
> **0.2 and 0.8 percent**, and the report states it rather than hiding it."*

---

## 5️⃣ Modal labels

### 📄 SHOW — labels in the output
```powershell
cd analysis
python -c "import csv,collections;rows=list(csv.DictReader(open('wormhole/star_topology/feature_table.csv')));print('window_label:',dict(sorted(collections.Counter(r['window_label'] for r in rows).items())));print('window_phase_id:',dict(sorted(collections.Counter(r['window_phase_id'] for r in rows).items())))"
cd ..
```
```
window_label: {'0': 1881, '2': 650}
window_phase_id: {'0': 1449, '2': 650, '3': 432}
```

> 🗣️ *"Each window takes the **modal** phase ID of its samples — the majority value. A window
> straddling a phase boundary gets the phase it mostly belongs to rather than being split or
> dropped. Note `phase_id` keeps 0, 2 and 3 separate while `label` maps baseline and cooldown
> both to 0, since both are benign."*

---

## 6️⃣ Deterministic · folder in → table out

### 📍 COMMAND — run it twice, compare
```powershell
cd analysis
python preprocess.py ..\tools\exports\baseline\linear_topology\trimmed -o /tmp_a.csv 2>$null | Out-Null
python preprocess.py ..\tools\exports\baseline\linear_topology\trimmed -o /tmp_b.csv 2>$null | Out-Null
if ((Get-FileHash /tmp_a.csv).Hash -eq (Get-FileHash /tmp_b.csv).Hash) { "IDENTICAL - deterministic" } else { "DIFFERS" }
Remove-Item /tmp_a.csv,/tmp_b.csv -ErrorAction SilentlyContinue
cd ..
```

> 🗣️ *"Same input folder, same output, every time — no randomness, no timestamps baked into the
> result. That matters for a dataset others will reproduce."*

---

## 🗣️ 75-second script

> *"M6 turns raw telemetry into the windowed dataset the features are built from.*
>
> *\[report] Every stage reports itself — files loaded, rows dropped and why, windows formed and
> discarded.*
>
> *Four transformations. Each node's clock is **re-based** to its own first sample, because six
> boards have six unrelated clocks. Cumulative counters become **per-window deltas**, since a raw
> `tx_count` means nothing in a 5-second slice. Windows are **5 seconds** per Table 4.10, on a
> 1 Hz grid. And each window takes the **modal** phase ID, so a window on a boundary gets the
> phase it mostly belongs to.*
>
> *Windows with fewer than four of five expected samples are discarded rather than imputed —
> between **0.2 and 0.8 percent** across every dataset. And it's deterministic: same folder in,
> same table out."*

---

## 🛡️ Questions

**"Why downsample 10 Hz to 1 Hz?"**
> *"Table 4.10 specifies the window structure on a 1 Hz basis. We capture at 10 Hz for headroom
> — it means a lost sample doesn't create a gap — and downsample for analysis. It's recorded as
> deviation D-1, and the pipeline needs no change if the rate is set back to 1 Hz."*

**"Why discard rather than interpolate a short window?"**
> *"Because several features are variances and stability measures. Interpolating would invent
> the very property being measured. Discarding under a percent of windows is the more honest
> trade, and the count is reported."*

**"How do you know windows align across nodes?"**
> *"They don't align on wall-clock — they can't, since each board has its own clock. They align
> on each node's **relative** timeline and are grouped by phase label, which is what the analysis
> compares."*

**"What if two runs of the same node land in one folder?"**
> *"`trim_run.py` flags it before preprocessing — duplicate captures of the same board and repeat
> are reported. That check exists because one silently double-counted a node: 264 windows against
> ~150 for every other node, with totals that still looked plausible."*

---

## ✅ Checklist
- [ ] Preprocessing quality report screenshotted *(covers most of the milestone)*
- [ ] `WINDOW_SECONDS` / `EXPECTED_SAMPLES_PER_WINDOW` constants shown
- [ ] A cumulative counter climbing, to motivate the delta step
- [ ] Label distribution output
- [ ] Determinism check run
- [ ] Know: **5 s windows** · **0.2–0.8 % discard** · **0 contaminated rows**
- [ ] Can explain **re-basing** and why cross-node timestamps aren't comparable
