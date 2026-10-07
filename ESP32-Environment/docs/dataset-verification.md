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
