# 📐 thesis-deviate.md — where the implementation departs from the proposal

> **What this file is:** every place the built system deliberately differs from the
> thesis proposal (*Cross-Layer Dataset Design and Exploratory Analysis of ESP32-Based
> ESP-WIFI-MESH Network*) or the CTTHES2 Milestones Form, with the reason, the measured
> impact, and what it would take to restore literal compliance.
>
> It exists so a panel question — *"the proposal says Mean RTT, why is this one-way?"* —
> has a written answer that was decided in advance, not improvised at the demo.
>
> `analysis/preprocess.py` and `analysis/features.py` cite this file by name.

---

## D-1 · Telemetry sampling rate: capture at 10 Hz, analyse at 1 Hz

| | |
|---|---|
| **Thesis says** | "Raw telemetry logs collected at **1 Hz**" (§4.2.4.1; Tables 4.4/4.5 list every metric at 1 Hz). |
| **We do** | Firmware samples at **10 Hz** (`SAMPLING_INTERVAL_MS 100U`, `mesh_config.h:327`). `preprocess.py` then **downsamples onto a 1 Hz grid** before windowing. |
| **Why** | A 1 Hz raw rate gives only 5 samples per 5-second window, so a single dropped sample costs 20% of a window and trips the "too few valid samples" discard. Capturing 10× and decimating keeps the thesis's 1 Hz analysis rate while making window formation robust — on the 2026-07-25 baseline·linear run only **6 of 583 windows (1.0%)** were discarded. |
| **Net effect on the thesis** | **None.** Everything downstream of `preprocess.py` sees the specified 1 Hz series. The extra resolution is discarded, not analysed. |
| **To restore literally** | Set `SAMPLING_INTERVAL_MS` to `1000U` and re-flash. The pipeline needs no change — the downsampler becomes a no-op. |

The preprocessing report prints `Rows downsampled to 1Hz grid: N` on every run so this is
never silent.

---

## D-2 · LatencyHopRatio (Eq 4.14): relative one-way delay, not Mean RTT

| | |
|---|---|
| **Thesis says** | Eq 4.14 = **Mean RTT** ÷ hop count, "computed from probe-response exchanges between victim nodes and the root". |
| **We do** | **Relative one-way delay** ÷ hop count. |
| **Why** | There is no response leg to time. Victim→root probes are one-way (`victim_main.c` probe generator); the root logs an arrival and sends nothing back, so **no round trip physically exists** in the captured data. |

**How the one-way figure is recovered.** `root_main.c:329` logs
`latency = now - pkt->send_ts_us`, where `now` is the *root's* `esp_timer_get_time()` and
`send_ts_us` is the *victim's*. Both clocks start at their own board's boot and are never
synchronised, so the raw column is

```
latency_us = true_one_way_latency − (root_boot − victim_boot)
```

— the truth plus a large constant offset, and **hugely negative in practice** because
children are powered before the root (−194 s on the 2026-07-20 wormhole run). Used raw it
is meaningless.

The offset is **constant per (arrivals file, src_mac)**, so subtracting that group's
minimum cancels it, leaving delay relative to that node's fastest observed delivery in the
run. Implemented in `features.py :: compute_latency_features`.

**Measured result — 2026-07-25 baseline·linear**, median LatencyHopRatio per layer:

| layer | hops | ms/hop |
|---|---|---|
| 2 | 1 | 2.72 |
| 3 | 2 | 2.39 |
| 4 | 3 | 2.82 |
| 5 | 4 | 2.44 |
| 6 | 5 | 2.67 |

Flat across the whole chain — which is precisely Eq 4.14's stated normal-operation
interpretation, *"consistent ratio → normal multi-hop forwarding"*. The proposal's
expected band is 10–30 ms/hop, but that is an a-priori estimate for a **round trip**; a
one-way leg on this hardware is roughly half an RTT, and these boards are faster than the
estimate assumed. **The discriminative property the feature exists for — delay that does
not match reported path length — is fully preserved**, because it depends on the ratio
varying, not on its absolute scale.

**Limits, stated plainly.** The zero point is per-node and per-run, so values are *not*
comparable in absolute terms across nodes or across runs; only the shape (ratio vs. hop
count, and its change over phases) is. Clustering uses standardised features, so this does
not affect M9/M10.

| | |
|---|---|
| **To restore literally** | Add a root→victim response message and have the victim log mean RTT into its telemetry row. This is a **firmware change that would invalidate every run already captured** — deferred to CTTHES3 (*Extended Experimental Runs*) rather than re-collecting the matrix. |

---

## D-3 · TunnelLatency: duplicate-arrival divergence, not UART echo RTT

| | |
|---|---|
| **Thesis says** | Table 4.11: "Round-trip latency of the tunnel itself, measured using **periodic echo messages**." (No equation number — the entry is descriptive.) |
| **We do** | The **latency divergence between the two arrivals of one probe** at the root: `max(latency_us) − min(latency_us)` over each `(arrivals file, src_mac, seq_num)` group of size > 1. |
| **Why** | The A↔B tunnel is a **one-way UART write** (B → A, `wormhole_victim.c :: tunnel_forwarder_task`). No echo frame is defined or sent, so no tunnel round trip exists to measure. |

What *does* exist is the signature the Milestones Form itself names for the wormhole:
*"the same logical probe arrives at root twice — once via slow multi-hop, once via fast
wormhole shortcut, with a **measurable latency mismatch**."* `root_main.c:316-320`
deliberately does **not** de-duplicate wormhole copies precisely so both arrivals survive
into `arrivals.csv`.

**This is a real measurement, not an estimate.** Both duplicate rows share one victim clock
and one root clock, so the D-2 offset **cancels exactly** in the subtraction — no
minimum-subtraction, no approximation.

**Measured result — 2026-07-20 wormhole·linear:** 541 duplicate `(src_mac, seq_num)` pairs;
divergence median 12.2 ms, range 1.2–242 ms. In the feature table, **102 of 109 populated
rows fall on `gt_label = 2`** (the wormhole attack window) and only 7 on baseline — the
feature concentrates where the attack is.

**Secondary deviation — keying.** Table 4.12 says tunnel fields are "present only for
attacker nodes". TunnelLatency is instead keyed to the **`src_mac` whose probes were
duplicated**, the same way PDR is keyed. Two reasons: the divergence is a property of the
manipulated *traffic*, and the arrivals row carries **no column marking which copy came
through the tunnel** (the `PROBE_MAGIC_WORMHOLE` flag is checked in firmware but not
logged). TunnelIntensity and TunnelBytes remain attacker-keyed as specified.

| | |
|---|---|
| **To restore literally** | Define an echo frame A→B over the existing (already bidirectional) UART link and have B time the round trip. Also log the wormhole-copy flag as an `arrivals.csv` column, which would additionally allow *signed* divergence — distinguishing "tunnel faster" from "tunnel slower". Both are CTTHES3 items. |

---

## D-4 · verify_topology.py excludes the mesh-formation window

| | |
|---|---|
| **Milestones Form says** | M3: "Each topology converges to its intended parent-child structure within 60 seconds" **and** "Mesh remains stable through a full 5-minute baseline phase (no spontaneous re-routing)." |
| **We do** | Parent/layer changes in the first `PHASE_STABILISE_S` (60 s) of a node's own log are counted as **formation**, not baseline re-routing. Reported separately, never hidden. |
| **Why** | These are two distinct criteria and the tool was conflating them. `phase_listener.c:33-34` stamps rows `PHASE_ID_BASELINE` **before the root's first broadcast arrives**, so a node's *initial parent acquisition* was being counted as a baseline re-route. On the 2026-07-25 baseline·linear run all 6 changes occurred at t = 0–12.8 s — inside the formation window, with **zero re-parenting for the remaining ~470 s**. The mesh was stable; the tool said otherwise. |
| **Net effect** | That run now reports `Converged within 60s: YES` / `Baseline re-routing free: YES`, which is what the data shows. The excluded count is printed on its own line and `--stabilise-s 0` restores the old behaviour for audit. |

---

## D-5 · Baseline control: each attack run's phase 0, not a separate baseline run

| | |
|---|---|
| **Milestones Form implies** | A baseline (no-attack) capture per topology, as the "normal" reference the attack runs are compared against. |
| **We do** | `baseline · linear` captured as a native-mesh reference. For **star, tree and partial**, the control is **phase 0 of each attack run** — the 300 s benign window every run already contains, labelled `gt_label=0`. |
| **Why** | It is a **better-matched control.** Phase 0 of an attack run shares the attack run's firmware, node roles, mesh session and placement — the attack turning on is the *only* variable. A separate baseline run differs in **two** ways at once: different firmware, and a different number of probing nodes, because in an attack run one board is the attacker or tunnel end and **relays** probes instead of originating them. Measured on `linear`: baseline has **5 probing victims at 4.90 probes/s**, attack-run phase 0 has **4 at ~3.9/s**. Comparing baseline-run windows against attack-run windows therefore confounds the attack with a traffic-composition change; comparing within a run does not. |
| **Cost** | Two things are given up, both modest. (1) No native-mesh reference for star/tree/partial — how each topology behaves with no attack firmware present at all. (2) The `star` phase-0 instability (Open Item 1, `2026-07-27.md`) cannot be attributed to the topology vs the wormhole firmware without a `baseline · star` run. |
| **Note on M4** | This changes nothing for Milestone 4, which is 24 **attack** runs gated on `validate_integrity.py`. The runbooks state baseline is "**not** part of the M4 24". |
| **To restore literally** | Run `baseline · <topology>` once per topology (~11 min each). Worth doing for **star specifically**, purely to settle Open Item 1. |

---

## D-6 · Repeats share a topology class, not a fixed parent assignment

| | |
|---|---|
| **Milestones Form implies** | Three repeats of the *same* configuration per cell. |
| **We do** | The **topology class** is fixed by a compile-time constraint (`MESH_TOPOLOGY` → `max_layer` / `max_children` in `mesh_setup.c` — the structure, never a board count; since sep. 17, 2026 depth is capped only by ESP-IDF's own ceiling) and verified per run by `verify_topology.py`, which rebuilds the structure from the logged parent links (`tools/topology_graph.py`). **Which board sits at which layer is not fixed** — parents are chosen by signal strength at each boot. |
| **Evidence** | Across `linear · wormhole` r1–r3 the Node A ↔ Node B separation was adjacent → 2 hops → 3 hops. All three still reported `PASS linear: one node per layer, depth 6`. |
| **Why not forced** | Pinning parents would require overriding the mesh's own parent selection, which is the behaviour under study. The self-organising layer is what makes this a mesh dataset rather than a fixed-route one. |
| **Net effect** | The attack signature is **unaffected** — 181 / 181 / 180 duplicates across repeats — because the wormhole tunnel is a physical UART wire whose behaviour does not depend on mesh distance. **Radio-path features legitimately vary between repeats** (`RSSI_Hop_Diff`, `LatencyHopRatio`, `HopStabilityDuration`). That variance is real mesh behaviour, not noise to be removed. |
| **Recoverable** | `preprocess.py` now writes a **`run_repeat`** column (see D-7), so per-repeat variance can be measured rather than assumed away. |

---

## D-7 · `run_repeat` column added to the windowed and feature tables

| | |
|---|---|
| **Context** | An analysis folder deliberately holds all three repeats at once — the M4 matrix counts them by the `_r1_`/`_r2_`/`_r3_` filename tag — and `preprocess.py` globs the whole folder. Every window from r1, r2 and r3 therefore landed in one table with no way to separate them. |
| **Why it mattered** | Fine for M8 separability, which pools benign vs attack windows regardless of run. But a reader **can always pool and cannot un-pool**: per-repeat variance, and any reproducibility question ("does the signature hold across runs?"), was unrecoverable from the published table. |
| **We do** | `_repeat_from_filename()` parses the repeat out of `source_file` and emits it as **`run_repeat`**. It flows into `feature_table.csv` automatically. NaN for any file not following the export naming convention. |
| **Verified** | `blackhole·linear` 786/863/821 · `wormhole·linear` 869/822/779 · `wormhole·star` 884 (r1 only). |
| **Net effect** | Nothing else changes — no feature value, no window count, no label. One extra identifier column, which matters for a dataset intended for reuse. |

---

## D-8 · PDR attribution: per-window evidence, not a run-wide coverage set

| | |
|---|---|
| **Context** | PDR (Eq 4.5) joins each victim's `probes_count_delta` against the root's `*_arrivals.csv`. The original code decided *whether a window could have a PDR at all* from a run-wide set of source MACs the root logged **anything** for (`covered_macs`). A victim the root never heard from at all got `NaN` for every window. |
| **Why it mattered** | That is precisely the node a blackhole hits hardest. On `blackhole·linear·G402/mobility` (2026-09-16) three of four victims were transmitting in nearly every window (`probes_count_delta` mean 3.8–4.1, statistically identical to the one victim that *did* get a PDR) yet were written off as "no data". Result: **`PDR == 0` appeared in 0 of 446 rows** — the feature that exists to detect forwarding suppression could not record the value it exists to detect, and `verify_attack.py` returned INCONCLUSIVE for want of attack-phase values. |
| **We do** | A window gets a real PDR (including `0.0`) only when all three hold: (1) the node **transmitted** that window (`probes_count_delta > 0`) — a 0/0 ratio is undefined and must stay `NaN`; (2) the node held a real **mesh association** (`layer > 0`, `parent_mac` not all-zero) — a detached node's undelivered probes are a connectivity artefact, not a forwarding failure; (3) the window falls inside the root's own **arrival-logging span**, which is what still protects a missing or never-pulled root CSV from reading as delivery failure. Where all three hold and the root logged nothing from that node, that is a genuine `PDR = 0`. |
| **Also fixed** | The old path divided by `(0 + EPSILON)`, so a window where a node sent **nothing** produced a literal `0.0` — indistinguishable from total delivery failure, and exactly how a false blackhole signature gets manufactured (cf. the 2026-09-15 false `BLACKHOLE CONFIRMED`). Such windows are now `NaN`. |
| **Verified** | Same capture, before → after: PDR non-null **41 → 238** of 446 rows; `PDR == 0` **0 → 201**; NaN **405 → 208**. Victim PDR by phase now reads baseline 0.217 → **attack 0.000** → cooldown 0.750, the expected suppression-and-recovery shape. `verify_attack.py` still returns **NOT CONFIRMED** on this capture (baseline itself is degraded: 0.164 ± 0.372), i.e. the change surfaces the signature **without fabricating** one. |
| **Remaining NaN is correct, not a gap** | Of the 208 left: 132 are the **root** (it receives probes, never originates them — PDR is undefined for it); ~67 are the attacker board's windows **outside the root's logging span** (that board ran 1027 s vs the root's 661 s log); 3 sent nothing; 2 were detached. |
| **Net effect on the thesis** | PDR keeps Eq 4.5's definition unchanged. What changes is only *when a window is judged attributable*, and the direction of change is conservative in both directions at once: it stops hiding real zeros **and** stops inventing fake ones. |

---

## D-9 · Analysis grid 1 Hz → 10 Hz, window 5 s → 1 s

| | |
|---|---|
| **Thesis says** | "Raw telemetry logs collected at **1 Hz**" (§4.2.4.1); Table 4.10 defines **5-second** windows; §4.2.4.1 point 4 discards a window with **< 4 of 5** samples. |
| **Context** | The panel asked for ~10,000 rows **per run**; the team proposed 6,000. Rows are fixed by `nodes × (analysed_seconds ÷ WINDOW_SECONDS)`, so the only levers are more nodes, longer runs, or smaller windows. At 5 s windows, 6,000 rows would need an 83-minute run and 10,000 would need 139 — both impractical. |
| **We do** | Analyse on a **10 Hz** grid (`GRID_HZ = 10`) with **1-second** windows, discarding a window with **< 8 of 10** samples — the same 80% completeness ratio the thesis's 4-of-5 rule expresses. No firmware or capture change: the boards **already sample at 10 Hz** (D-1), and this stops throwing 9 of every 10 captured samples away. |
| **Why it's not dilution** | Each window now carries **10 samples instead of 5** — *more* statistical support per row than the configuration it replaces, while yielding 5× the rows. Nothing is interpolated to achieve it; `MAX_INTERP_GAP_SAMPLES` stays at 2 samples, which at 10 Hz spans 0.2 s rather than the 2 s it spanned at 1 Hz, i.e. strictly **less** synthetic data than before. |
| **Verified** | Clean capture (`baseline·linear`, 6 nodes, 11-min run), before → after: **577 → 2,894 rows** (exactly 5.0×); window discard rate **1.0% → 0.1%**; `RSSI_var` 0 NaN (variance still well-defined); PDR non-null 2,295/2,894 (79%) across the same 5 nodes. Runtime M6 3.6 s, M7 3.0 s — unchanged in practice. |
| **Known consequence** | With `PROBE_INTERVAL_MS = 1000`, a 1-second window contains ~1 probe, so per-window PDR becomes near-binary (0 or 1) rather than a smooth ratio. This costs no information — the mean over 5× as many windows carries the same evidence — but per-window PDR should not be read as a fine-grained rate. 3% of clean-capture windows contain no probe at all and are correctly NaN. |
| **Net effect on the thesis** | Window length (Table 4.10) and the analysis rate (§4.2.4.1) both change and must be amended in the paper. The discard rule changes in absolute terms (4→8) but **not in ratio** (80%). Every feature definition is untouched. |
| **To restore literally** | `GRID_HZ = 1`, `WINDOW_SECONDS = 5`, `MIN_VALID_SAMPLES = 4` in `preprocess.py`. Nothing else needs touching. |

**Row targets at this configuration** (6 nodes, 600 s of analysed phases = 2,894 rows):

| Target rows/run | Analysed phase seconds needed | Run wall-clock | SPIFFS per node (2.44 MB available) |
|---|---|---|---|
| ~2,900 (today's phases) | 600 | ~11 min | 0.51 MB |
| **6,000** | ~1,245 | ~22 min | 1.06 MB |
| 10,000 | ~2,075 | ~36 min | 1.66 MB |

Both targets fit flash; reaching either requires lengthening `PHASE_BASELINE_S` /
`PHASE_ATTACK_S` / `PHASE_COOLDOWN_S` in `mesh_config.h` and re-flashing. Not yet done.

---

## D-10 · `attack` / `topology` / `location` / `scenario` columns added to both tables

| | |
|---|---|
| **Context** | Same argument as D-7 (`run_repeat`), one level up. The export tree encodes which cell of the M4 matrix a capture belongs to — `<attack>/<topology>/<location>/[<scenario>/]` — but **none of it reached the tables**. Only `combine_all.py` knew, and only by re-deriving it from the folder path at aggregation time. |
| **Why it mattered** | `combine_all.py` read `dir_parts[2]` as location and **ignored the scenario segment entirely**, so a `mobility` run and a `none` run in the *same* attack/topology/location collapsed into one group with no way to separate them afterwards. Same failure mode `verify_topology.py`'s `discover_groups` had to fix by keying on (attack, scenario, repeat). A reader can always pool and cannot un-pool. |
| **We do** | `preprocess.py` derives the four fields from the input path (`_run_context_from_path()`) and writes them as columns on every windowed row; `features.py` does `result = windowed.copy()`, so they reach `feature_table.csv` for free — the same mechanism D-7 uses. `combine_all.py` now **prefers those columns** and only falls back to path-parsing for tables generated before this change, and its summary groups by scenario too. |
| **Conventions** | Absent scenario segment ⇒ `scenario = "none"`, because the export convention is that `none` gets no folder — absence *is* the value, not missing data. Absent location ⇒ `"unrecorded"`, matching the name `run_matrix.py` already used when backfilling `run_ledger.csv`. A path that is not an export tree at all (synthetic fixtures from `generate_fake_data.py`) yields `None` for all four, so unknown provenance is never labelled as if it were known. |
| **Verified** | Path resolution across real, scenario'd, archived (`archive/<date>/exports/...`) and non-export paths. `combine_all.py` regression: two runs identical except for scenario now form two groups instead of one; a legacy table stripped of all four columns still resolves via the path fallback. |
| **Net effect on the thesis** | Four identifier columns added. No feature value, window count, or label changes. Makes each row self-describing, which is what the dataset needs to be reusable. |

---

## Not deviations (recorded so they aren't mistaken for gaps)

- **ForwardingRatio / IngressEgressDelta / ConsistencyScore are NaN in baseline and
  wormhole runs.** They are relay-node features and the only relay in this testbed is the
  blackhole attacker. They populate on its windows in a blackhole run (155/884 rows,
  2026-07-25 blackhole·linear). Correct by design, per thesis §4.2.4.
- **TunnelIntensity / TunnelBytes / TunnelLatency are NaN outside wormhole runs.**
  Table 4.12: "present only for attacker nodes during topology-distortion runs; for all
  other nodes and phases these fields are null or zero."
- **M7's "no feature is uniformly NaN" applies to the assembled dataset**, not to any one
  run. Per run type: baseline 10/16 populated, blackhole 13/16, wormhole 13/16 — and
  **16/16 across the combined matrix**, since every feature is populated by at least one
  run type.
## D-11 · `layer` → `hop`: renamed feature, new derived column, values unchanged

| | |
|---|---|
| **Context** | Panel and adviser feedback (sep. 21, 2026) — reviewers read the column name `layer` as an **OSI layer**. It is not. ESP-WIFI-MESH's `layer` is a node's depth in the mesh **tree**, and the mesh runs *below IP entirely*, so there is no OSI layer 3 involved at any point. Adviser (Sir Greg) asked directly: *"change layer to hop"*; a second reviewer independently asked to *"make it 'topology layer' instead of LAYERS (OSI MODEL)"*. Two reviewers, same confusion, unprompted — so the name was the problem, not the reader. |
| **Why it mattered** | This is a naming defect with a real cost: every time it is misread, the reader believes the dataset contains network-layer (IP) data that it does not contain, which makes the whole cross-layer framing look overclaimed. `docs/DATA-DICTIONARY.md` §3 had already flagged the same issue independently. |
| **We do** | (1) `preprocess.py` emits a new derived column **`hop`** = `layer − 1`, alongside the raw `layer`, which is kept untouched for traceability to what the firmware actually reported. (2) Table 4.11's feature `LayerChangeCount` is renamed **`HopChangeCount`**. (3) Analysis and docs lead with hop; `layer` survives only as the raw firmware value. |
| **⚠️ The off-by-one is the whole point** | Espressif numbers the **root as layer 1** (`mesh_setup.c`, "center(L1)"), so a direct child of the root is layer 2 — but it is **1 hop** from the root, and the root is **0 hops** from itself. A straight rename keeping the values would have made every hop count wrong by one and would read as *"the root is 1 hop from itself"*. `_layer_to_hop()` carries this reasoning in its docstring so it cannot be "simplified" away later. `layer == -1` (the firmware's no-parent sentinel) maps to **NaN**, never −2. |
| **Feature VALUES are unchanged** | `HopChangeCount` counts *changes* in depth. A count of changes is unaffected by whether depth is expressed as layer (root = 1) or hop (root = 0), because the two differ by a constant. **Only the name moved — no number in any feature table changed.** Verified: pipeline re-run produced identical values under the new name. |
| **Verified** | Real capture (`blackhole/linear/G402`): root layer 1 → hop 0; attacker layer 7 → hop 6; all 65 rows with `layer == -1` → `hop` NaN. `HopChangeCount` present, `LayerChangeCount` absent, `layer` retained. Full pipeline M6→M7→M8 green; `verify_attack.py` still BLACKHOLE CONFIRMED; 20/20 `test_segments.py`. |
| **Net effect on the thesis** | One column added (`hop`), one feature renamed. Table 4.11 must show `HopChangeCount`. No feature value, window count, or label changes anywhere. Dated issue logs (`2026-07-*.md`) deliberately keep the old name — they are a historical record of what was true then, not current documentation. |

---
## D-12 · C7 Option 1 — hop-by-hop application-layer relay on every node

| | |
|---|---|
| **Context** | Three of the 16 Table 4.11 features (`ForwardingRatio`, `IngressEgressDelta`, `ConsistencyScore`) existed on ONE node role only — the blackhole attacker — so "is this column NaN?" identified the attacker, and therefore the label. That is the CTTHES2 panel's 2:40–4:50 objection ("if a single feature determines whether an instance is an attack... machine learning would be unnecessary") at its root cause. |
| **Why it could not be fixed in Python** | Honest nodes sent with `esp_mesh_send(NULL, ..., MESH_DATA_TODS)`. The ESP-IDF mesh stack relays that **below the application layer**, so an intermediate node's own code never saw the traffic it forwarded. The numbers did not exist to be un-gated. Only the attacker saw transit packets, and only because victims were compiled to address it by MAC (`BLACKHOLE_ATTACKER_MAC`). |
| **We do** | New shared `components/mesh_common/{include,src}/probe_relay.{h,c}`. Every node sends to **its own parent** with `MESH_DATA_P2P` and relays what it receives one hop further up, counting `recv`/`forward`/`drop`. The blackhole attacker runs the **same relay** and differs only by a single boolean callback (`blackhole_forward_decision`). Both wormhole ends relay too, with their UART tunnel logic unchanged. |
| **⚠️ This IMPLEMENTS the paper; the old behaviour was the deviation** | Paper §3.1.3.2 *"Forwarding Discipline"*: **"Intermediate nodes must receive packets with `esp_mesh_recv()` and forward them with `esp_mesh_send()`, setting the MESH_DATA_P2P flag. This mandatory forwarding requirement establishes the behavioral baseline against which deviations can be observed."** Paper Table 4.2 already specifies `recv_counter` / `forward_counter` / `drop_counter` — exactly the F3 columns this feeds. |
| **⚠️ CONFLICTS WITH THE SIGNED MILESTONE FORM — adviser sign-off required** | The Milestone Form states: *"Victims address probes **directly to the attacker's MAC** (behavioral equivalent of a false short-route advertisement)."* Option 1 removes that. **Every milestone CRITERION is still met** — "root logs show the expected drop in arrivals during the attack window", "both attacks toggle cleanly on phase transitions", "behavior is consistent across all four topologies" — only the mechanism changed, and the form's own *"behavioral equivalent of"* concedes the old model was a substitute. **This must be declared and signed off, not slipped in.** |
| **What it fixes** | (1) The relay features stop being role-gated, so the attacker becomes an **outlier in a populated distribution** instead of the only value present. (2) The attacker now intercepts traffic because of **where it sits in the tree**, not because victims were compiled to address it — so attacker POSITION becomes a real experimental variable (panel 12:45–16:00) and `BLACKHOLE_ATTACKER_MAC` stops being load-bearing for targeting. (3) *"Stays protocol-compliant at PHY/MAC"* in `ATTACK-VALIDATION.md` becomes true **by construction**: the attacker is byte-for-byte an ordinary relay except for one boolean. |
| **No loops by construction** | Every hop targets the node's OWN parent, so traffic strictly ascends the tree. No TTL or visited-set needed. A node with no parent counts the packet as dropped rather than discarding it silently, keeping `recv == forward + drop`. |
| **⚠️ Trap found and fixed during implementation** | The relay initially forwarded only `PROBE_MAGIC`. Node A's re-injected wormhole duplicate carries `PROBE_MAGIC_WORMHOLE`, so **every intermediate relay would have silently dropped it** — the duplicate arrivals that ARE the wormhole signature would never have reached the root, and wormhole runs would have looked clean. The relay now forwards both magics. |
| **Host-side consequence** | `analysis/leakage.py` no longer hardcodes the three relay features as leaking. `relay_features_are_gated()` asks the DATA how many `node_role`s carry each column: pre-C7 captures still exclude them, post-C7 captures allow them. Both firmware generations coexist for months, so a hardcoded answer would be wrong for half the dataset. |
| **Verified** | All 7 firmware variants build clean under `-Wall -Wextra -Werror` (ESP-IDF 5.5.4). Leakage guard verified both ways: single-role data → excluded, multi-role data → allowed. Pre-C7 pipeline unchanged. |
| **Net effect on the thesis** | **Existing captures are NOT comparable to post-C7 captures** — the traffic model differs. With one complete cell captured and a re-capture already required for schema v2, the cost of doing this now is near zero and rises with every run. Table 4.5's per-role column semantics must be updated; Table 4.2's counters are now literally implemented. |

---
## D-13 · SD mirror is `fsync()`ed: the "0 rows off the card" failure

| | |
|---|---|
| **Context** | Operators reported that exporting from a pulled SD card *sometimes* produced a file with **zero rows**, with no pattern anyone could pin down. The data was not recoverable and the run had to be redone. |
| **Root cause** | `csv_logger.c` mirrored every telemetry row to the card and flushed with `fflush()` alone — it never called `fsync()`. On ESP-IDF's FAT VFS, `fflush()` only pushes the stdio buffer through `f_write()`: clusters are allocated and the bytes are written, but the file's **directory entry — its recorded size — is updated only by `f_sync()`/`f_close()`**. Any boot that did not reach `csv_logger_close()` (brownout, reset, card pulled live, a killed run) therefore left a card file whose directory entry still read **0 bytes**. The rows were physically on the card but unreachable, so every host tool counted the file as empty. |
| **Why it hid so long** | The failure needs an *unclean* ending, so clean runs were always fine and the bug looked random. The project had already met this mechanism's sibling and fixed only that half: the comment at `csv_logger.c:57-63` explains that an *eager* `fopen()` left 0-byte files behind, which is the same directory-entry lag seen from the other side. |
| **We do** | `sd_mirror_sync()` now does `fflush()` **plus** `fsync(fileno(fp))` on both mirrors. It is called on a rate limit (`LOGGER_SD_SYNC_INTERVAL_MS`, default **5000 ms**) from the row-append path, and **unconditionally** from `csv_logger_flush()`, which the node mains already call at phase boundaries. Worst-case loss goes from *the whole run* to *the last ~5 s*. |
| **Why time-based, not row-based** | The analysis grid has already moved 1 Hz → 10 Hz once (D-9); a row-count cadence silently changes meaning with the sampling rate. It is also deliberately **coarser** than `LOGGER_FLUSH_RECORDS` (10): each sync costs a FAT + directory write on a 4 MHz SPI card, and per-row flush cost has starved this logger before (I-016/I-017). |
| **⚠️ Effect on EXISTING captures** | This does not repair anything already on a card. A pre-fix capture that ended uncleanly is still unrecoverable by normal means, and a pre-fix card file reading 0 rows should be treated as **lost**, not as "the node logged nothing" — those are different claims and only the second one is evidence. Post-fix, a 0-row file genuinely means nothing was logged. |
| **New cross-check** | Importing now compares the streamed row count against the leaf's `runs.csv` manifest and prints `NOTE: got N rows, manifest said M` on a disagreement — the signature of a capture cut short. |
| **Status** | Firmware **compiles clean**; **NOT yet validated on hardware** — it needs a board, a mid-run reset, and a card read back. Do that before trusting it in the campaign. |

---
## D-14 · Radio pinned to 20 MHz (HT20) instead of the ESP32 default 40 MHz (HT40)

| | |
|---|---|
| **Context** | The paper never states a channel width (no "MHz", "bandwidth", "HT20/HT40" or "802.11n" in the proposal), so every capture before sep. 23 2026 ran the ESP32 default: **HT40**, logged as `channel 11, 40D` (40 MHz, secondary channel below). |
| **Why we changed it** | The only independent observer available — an M1 MacBook's Wireless Diagnostics Sniffer — captures **20 MHz only**, and a 20 MHz receiver cannot decode 40 MHz data frames. A real sep. 23 capture heard every board's beacons but ~0 of their data frames (root 0, child 3 of 1848). Without HT20 the sniffer cannot serve as the third-party check on the dataset (panel P6: *the attacker counts its own drops*). |
| **We do** | `MESH_FORCE_HT20 1` (`mesh_config.h`). `mesh_setup.c` sets `WIFI_MODE_APSTA` and forces both interfaces to `WIFI_BW_HT20` **before** `esp_wifi_start()`; the `MESH_EVENT_*_CONNECTED` handlers re-check and log it. Every boot prints `RF width (before wifi start): STA 20 MHz, AP 20 MHz`, and the SD status report `[6]` records it, so every capture carries its own width. |
| **⚠️ Trap found and fixed** | The first version forced the width **after** `esp_wifi_start()` / `esp_mesh_start()`. That hit the scan and the root's AP as they came up: **no node joined in a full 11-min run.** Moving it before the radio starts fixed it — verified on 4 boards in wizard order (all joined, correct chain, 20 MHz from boot, phases reached every child). Do not move the call back. |
| **⚠️ Effect on EXISTING captures** | **HT40 captures (everything before sep. 23 2026) are NOT comparable to HT20 captures** — the PHY differs (rates, airtime, possibly RSSI by a few dB). Label by width; never pool them unlabelled. The verifier compares within one run, so its verdicts are unaffected. **Re-check before citing: Table 3.3's absolute *Expected RSSI Ranges by Node Position* against HT20 data.** |
| **To restore the default** | `MESH_FORCE_HT20 0` and reflash. The sniffer then goes back to seeing beacons only. |
| **Status** | Mesh formation + width **hardware-verified** (sep. 24 2026, 3-min test). A full 11-min HT20 run and a sniffer capture of its data frames are **still to be validated**. |

---
