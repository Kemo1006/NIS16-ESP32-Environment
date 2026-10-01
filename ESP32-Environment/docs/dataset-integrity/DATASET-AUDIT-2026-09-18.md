# Dataset audit — G402 linear·blackhole captures (sep. 17–18, 2026)

**Scope.** Every raw CSV from the G402 linear sessions: the sep. 17 set (now in
`archive/2026-09-18_incomplete/exports/`) and the sep. 18 set (deleted from
`tools/exports/blackhole/linear/G402/` at 14:47 and audited from read-only copies;
the originals are still in the Windows Recycle Bin). 40 files, 33 with data.
The raw files were **only read**. Nothing was edited, deleted or regenerated.

**Tool.** `tools/audit_dataset.py` (new). It regenerates everything below:

```powershell
cd tools
python audit_dataset.py <export dir> [<more dirs>] --out ..\analysis\dataset_audit_<date> --location G402
```

**Output** (`analysis/dataset_audit_2026-09-18/`): `run_manifest.csv` (every file,
its run, the evidence, its issues) · `clean_telemetry.csv` · `clean_arrivals.csv` ·
`pdr_by_segment.csv` · `topology_snapshots.csv`.

**Ground rules kept** (from the thesis constraints, not negotiable here):
raw capture CSVs stay byte-for-byte as logged; provenance never goes into raw rows;
boards share no clock, so **nothing cross-node is joined on time**. Cross-node
joins are on `seq_num`, or on the phase broadcast as a shared event.

---

## A. Data quality report

### A1. Wrong — must be fixed

| # | Finding | Evidence | Fix |
|---|---|---|---|
| 1 | **One folder, several runs.** Every file is `r1`, but the G402 folders hold at least **6 separate runs**, and some boards appear 2–5 times (0C80: 5 files). Pooling them mixes runs and boots. | `run_manifest.csv`. Seq-matching proves which file belongs to which run (see A4). | Tooling + firmware (C1, C2) |
| 2 | **Runs with no root arrivals log** can't produce PDR at all: sep. 17 11:3x (root telem only), sep. 18 13:0x (no root file at all). | `NOT IN ANY RUN` list | Re-capture |
| 3 | **Sep. 17 12:4x run: 3 of 5 victims never delivered a probe**, in baseline too (2805: 800, 704B: 662, FE90: 652 successful sends, **0** at the root). The attacker received exactly 2 victims' worth (598 = 2 × 299 in baseline). 2805 is the attacker's own **parent**, one hop away, and still got nothing through. That points to a wrong destination (stale `BLACKHOLE_ATTACKER_MAC` in those three builds), not a routing failure. From the CSVs alone this is unprovable. | `clean_arrivals.csv` has only 0C80 and F42D for that run | Firmware (C3) |
| 4 | **7 empty or header-only files** (0 bytes or header only): the card file was never written or closed. | `run_manifest.csv` `issues` | Import pre-flight (C4) |
| 5 | **Filename role ≠ row role.** All four `victim_NODE-20500DE71C38_*` files contain `role=blackhole` in every row. Nicknames also don't identify boards: `child-6` is 0C80, `child-8` is 704B, `child-9` is 2805. | `run_manifest.csv` | Import naming (C4) |
| 6 | **`phase_id = 0` means three things:** real baseline; the root's 60 s stabilise window (`mesh_config.h:121` says "not logged", but it is); and "hasn't heard any phase broadcast yet" (`phase_listener.c:34`). In the committed G402 feature table, **178 of 1,569 `window_label = 0` windows (11%) are pre-baseline**. There, 0C80's probes reached the root at 93%, in a 60 s backlog burst. Normal-class training data is contaminated. | `segment` column; D-4 already fixed this for `verify_topology.py` only | Firmware (C5); interim filter `usable` |
| 7 | **`rssi_dbm = 0` is a placeholder, not a reading.** `esp_wifi_sta_get_rssi()` leaves the 0 initialiser when there is no parent link. It is 0 on every root row and on unjoined rows, and on only **1 of 146,310** joined non-root rows. In the committed feature table, **692 of 2,471 rows have `RSSI_Hop_Diff` of exactly 0**, because a fake 0 dBm was compared with a baseline median that was also 0. | audit counts | Pipeline (C6) + firmware (C5) |
| 8 | **`latency_us` is not a latency.** It subtracts the root's boot clock from the victim's: values are −1004 s … +361 s, and 100% negative in two runs. This is expected from the design and already handled by D-2. It must never be used as an absolute value. | `latency_us_raw` | Documented; `rel_latency_us` added |

### A2. Suspicious — explained, keep as is

- **Relative latency up to 60 s** (sep. 18 run B, 0C80): its first ~70 probes were sent before a
  route to the root existed and arrived together in one burst when it came up (rel. latency
  60 s → 11 s → ms, within 0.8 s of root time). That is real store-and-forward behaviour,
  so it is kept and not clipped. It is also why pre-baseline data must not count as baseline.
- **Re-parenting inside a linear run** (run B, 0C80 at layers 2 → 4 → 5): real mesh behaviour,
  and the chain still validates (A5). Kept.
- **Attacker `child_attacker-5_…_101458`**: 600 ms median sample step, 308 gaps > 1 s. A
  degraded capture (the logger task stalled). No run matches it.
- **Run B victims 2805 and 704B joined ~2 s before the attack**: only 2–3 baseline probes each,
  so they have no usable baseline control (D-5). They are real, but thin for training.

### A3. Legitimate — do not "fix"

- Constant `role`, `node_id`, `parent_mac = 00:…:00` and `layer = 1` on the root: correct metadata.
- `retry_count` constant 0 on some victims: the send simply never failed.
- Probes lost around phase edges (1 of 181 in attack delivered, 0C80 run A): broadcast skew.
- RSSI −94 … −39 dBm, sample steps 100 ms (p99 ≤ 250 ms except the degraded `101458` file), counters monotonic, no reboots
  inside any file, `gt_label` matches `phase_id` on every row, all MACs well-formed.
- **No exact duplicate rows, no malformed cells, no timestamp regressions** in any file.

### A4. How files were assigned to runs (no clock used)

| Link | Rule | Strength |
|---|---|---|
| root telem ↔ arrivals | same `node_id`; last `probes_count` == last `probes_received` | exact |
| victim → run | the victim's own `probes_count + retry_count` (== `seq_num`) at its phase-0 exit equals the root's last baseline `seq_num` from that MAC (±2), **and** its final value equals the root's max (±2) | exact (e.g. 404 vs 403, 1162 vs 1162) |
| attacker → run | probes forwarded in cooldown == root's cooldown arrivals, and unique | **weak**: the count is set by the design (victims × 120 s), so two runs can tie. A run claimed by two files of one board is marked ambiguous for all of them. |

Result: **4 runs** holding 17 files (4 root arrivals logs, 11 proven by sequence or root pairing, 2 attackers by count only); 23 files unassigned or ambiguous (7 of them empty), each with its reason.

| run_id | Root | Members | Notes |
|---|---|---|---|
| `linear_blackhole_20260918_111347` | ✓ | 0C80, 2805, 704B + attacker 1C38 | **The only complete run.** Topology OK on 302/302 snapshots |
| `linear_blackhole_20260918_095950` | ✓ | 0C80, 2805 + attacker 1C38 | 4 of 6 victim files empty or missing |
| `linear_blackhole_20260917_125131` | ✓ | 0C80, F42D | attacker ambiguous; 3 dead victims (A1 #3) |
| `linear_none_20260917_124617` | ✓ (board 2805 as root) | none | the victim's file is missing |

### A5. Phase anchoring — validated

Each node's clock is re-based on **its own first exit from phase 0**, which is a mesh broadcast
that every node sees. Checked against the firmware's schedule with no clock involved:

- Root boot → phase exit: **363–366 s on all 5 roots** = 60 s stabilise + 300 s baseline + boot time.
- Probes sent per segment (from counters): baseline **299–300**, attack **180–181**, cooldown
  **120–121**, which matches `PHASE_BASELINE_S / PHASE_ATTACK_S / PHASE_COOLDOWN_S` at 1 probe/s.

**PDR by segment (seq-joined, `pdr_by_segment.csv`)**: baseline 0.948–1.000,
attack 0.000–0.006, cooldown 1.000. Pre-baseline 0.07–0.93: this is the contamination in #6.

**Layers**: the rebuilt tree (BFS over each node's parent at 1 s steps of anchored time) matches
the stack-reported layer on **99.3%** of 5,444 comparable rows. The mismatches fall at
re-parent instants, where broadcast skew is ~100 ms. Layers are the mesh stack's live depth, not
assigned values, and nothing is capped: run B reaches layer 5 and the raw data layer 7.

---

## B. Cleaned dataset — what changed and what didn't

| Changed (derived column added; raw value kept or blanked) | Unchanged |
|---|---|
| `rssi_dbm` 0 → empty · `layer` −1 → empty + `in_mesh` · zero `parent_mac` → empty · `parent_node_id` resolved (BSSID − 1) · `t_anchor_s` · `segment` · `layer_derived` · `seq_sent` · `usable` · `rel_latency_us` · `sender_segment` · `run_id` | every other raw value, `gt_label` as logged, all rows (none deleted; unassigned files are kept with `run_id = UNASSIGNED`, `usable = False`) |

**Not added, because the experiment never measured them** (no fabricated columns):
`neighbor_count`, per-frame MAC retries, byte counts, absolute one-way latency, throughput,
wall-clock time. See C7 for which ones are worth logging.

---

## C. Data dictionary — `clean_telemetry.csv`

| Column | Meaning | Unit | Kind | Range seen | Source |
|---|---|---|---|---|---|
| `run_id` | proven run (A4) or `UNASSIGNED` | — | metadata | 4 runs | derived: root arrivals file name |
| `source_file` | raw file the row came from | — | metadata | | import filename |
| `node_id` / `mac_address` | board STA MAC | — | metadata | 7 boards | raw / derived |
| `role` | `root` · `victim` · `blackhole` | — | metadata | | raw (firmware build) |
| `topology`, `attack_type`, `location` | experiment cell | — | metadata | | filename / `--location` |
| `timestamp_us` | node's own `esp_timer` since boot. **Not comparable across nodes** | µs | raw | 2.7 s–1905 s | raw |
| `t_anchor_s` | time from this node's own first phase-0 exit | s | derived | | A5 |
| `segment` | `pre_baseline` · `baseline` (last 300 s of phase 0) · `attack` · `cooldown` | — | derived | | phase + `t_anchor_s` |
| `phase_id` | last phase broadcast heard (0 also = none heard) | — | raw | 0, 1, 3 | `phase_listener` |
| `gt_label` | 0 normal · 1 blackhole · 2 wormhole, **network-wide** for the window | — | ground truth | 0, 1 | raw, `phase_id_to_label()` |
| `in_mesh` | node had a parent / was root | bool | derived | | `layer ≥ 1` |
| `layer_reported` | mesh stack depth, root = 1 | hops | raw | 1–7 | `esp_mesh_get_layer()` |
| `layer_derived` | depth rebuilt from the run's parent links | hops | derived | 1–5 | BFS |
| `parent_mac` / `parent_node_id` | parent's SoftAP BSSID / its node_id | — | raw / derived | | `get_parent_bssid()` |
| `rssi_dbm` | RSSI of the parent link; **empty = not measured** | dBm | raw | −94 … −39 | `esp_wifi_sta_get_rssi()` |
| `retry_count` | **victim**: failed probe sends · **blackhole**: probes dropped · **root**: failed phase broadcasts | events, cumulative | raw | | app counters |
| `tx_count` | **victim**: probes sent OK · **blackhole**: probes forwarded · **root**: phase broadcasts OK | events, cumulative | raw | | app counters |
| `probes_count` | **victim**: probes sent OK · **blackhole**: probes received · **root**: probes received | events, cumulative | raw | | app counters |
| `seq_sent` | victim send attempts so far (== next `seq_num` − 1) | count | derived | | `probes + retry` |
| `usable` | assigned run ∧ in mesh ∧ segment in baseline/attack/cooldown | bool | derived | 69,596 / 103,243 run rows | |

`clean_arrivals.csv`: `root_timestamp_us` (root clock) · `src_mac`/`src_node_id` · `seq_num`
(sender's attempt counter, raw) · `root_phase_id`/`root_gt_label` (**the root's** phase on arrival) ·
`sender_segment` (the sender's segment when it **sent** that seq, derived) · `probes_received`
(cumulative, raw) · `latency_us_raw` (clock-offset contaminated, raw) · `rel_latency_us` (offset
cancelled per (run, src), ≥ 0, µs, derived, D-2).

**Semantics warning.** The same counter column means different events per role (table above).
That is how the thesis features are defined (ForwardingRatio, RetryRate), so the columns are
**not** renamed, but never compare `tx_count` across roles.

---

## D. Validation (on the cleaned output)

| Check | Result |
|---|---|
| Negative latency | 0 in `rel_latency_us` (raw values kept and labelled as not being latencies) |
| Timestamps | monotonic in every file, no reboots, same unit (µs); cross-node alignment only via the phase anchor, validated in A5 |
| MAC addresses | all 6-octet and valid, uppercased; none needed correcting |
| Layers follow the structure | 99.3% agreement stack vs rebuilt; no layer cap anywhere (`topology_graph.py`) |
| Linear stays linear | run B: 302/302 snapshots `OK` (chain of 5). Runs with missing boards: `WARN` "not attached", because a parent is absent from the data, not because of a branch |
| Star / tree / partial | **not testable**: no star, tree or partial captures exist yet. The same rules (`topology_graph.py`) apply when they do |
| Ground truth | `gt_label` = broadcast phase on 100% of rows; `segment` separates real baseline from pre-baseline; PDR per segment confirms the attack window (A5) |
| Nothing fabricated | only blanks (placeholders → empty) and derived columns; no imputed, interpolated or random values |

---

## C-series — what to change so the next capture is clean

| # | Where | Change |
|---|---|---|
| C1 | `import_sdcard.py` / wizards | Import `runs.csv` (boot #, `built` stamp) with the CSVs and write **one folder per run** (or a run-id in the filename). Right now all of that provenance stays on the card and every capture is `r1`. |
| C2 | `validate_integrity.py` / `analyze.ps1` | Refuse to analyse a cell with **more than one file per node_id** or **no root arrivals file**. `audit_dataset.py`'s manifest already detects both. |
| C3 | `blackhole_victim.c`, `victim_main.c`, `sd_status.c` | Write the compiled `BLACKHOLE_ATTACKER_MAC` into `status_<node>.txt`, and have the attacker log how many **distinct source MACs** it relayed per phase. A dead victim is then visible from the files, not from a missing-arrivals puzzle. |
| C4 | `import_sdcard.py` | Skip 0-byte and header-only files with a warning. Take the filename prefix from the rows' `role`, not the card nickname. |
| C5 | `phase_listener.c`, `csv_logger.c` | Start `s_phase_id` at a new **`PHASE_ID_UNSET` (e.g. 255)** until the first broadcast arrives, and have the root announce a **stabilise** phase before baseline. Log `rssi_dbm` as empty when `esp_wifi_sta_get_rssi()` fails or there is no parent. Note this changes the M6 schema contract, so it needs a matching `preprocess.py` change and a new D-entry. |
| C6 | `preprocess.py` / `features.py` (**no re-capture needed**) | Treat `rssi_dbm == 0` as missing, and exclude pre-baseline windows (phase-0 windows earlier than `PHASE_BASELINE_S` before the node's first phase exit) from `window_label = 0`. Fixes #6 and #7 on existing data. |
| C7 | optional new logging | If the panel wants them, these are measurable (not fabricated): child count (`esp_mesh_get_routing_table_size`), real MAC retries (`esp_wifi_get_*` / promiscuous stats), a root→victim echo for true RTT (the thesis's original Mean RTT; D-2). |

**Deliberately not done** (from the enhancement prompt, conflicts with the thesis):
adding `run_id` or topology columns to **raw** CSVs (the provenance rule); computing
`latency = rx − tx` across boards (no shared clock); interpolating or filling RSSI or
counters; relabelling `gt_label` (it is kept as logged, and `segment`/`usable` sit beside it).

**Next step before any re-analysis:** decide C6 (pipeline, no re-capture) vs C5 (firmware,
needs re-capture), then re-capture G402 linear with C1–C4 in place. Only run B is complete today.
