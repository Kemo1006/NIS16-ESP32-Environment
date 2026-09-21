# What a good run should look like — expected results, with real numbers

**Created:** sep. 21, 2026 · **Use this right after every capture, before you trust the data.**

Every number below is either **measured from your own sep-18 G402 capture** (marked ✅ REAL) or a
**prediction for post-C7 firmware** (marked 🔮 EXPECTED, not yet observed). Nothing here is invented
without saying so.

**The point of this file:** a run can fail *silently* — boards look healthy, CSVs are full, and the
data is still worthless. These are the checks that catch that in five minutes instead of at analysis
time three weeks later.

---

## 1. The 60-second check (do this before unplugging anything)

```powershell
python tools\inventory_cells.py                 # is the run even COMPLETE?
python tools\trim_run.py <that run's folder>    # is there exactly one real session?
python tools\verify_topology.py --dir tools\exports --topology linear --attack blackhole --structure
```

| Check | Good | Bad — and what it means |
|---|---|---|
| `inventory_cells.py` says **COMPLETE** | ✅ | `no root arrivals` → PDR is uncomputable, the run is unusable |
| `trim_run.py` finds **1 session** scoring **> 0** | ✅ | Two real-looking sessions = two experiments in one file. A `-100` score = idle/export session only |
| `--structure` shows every board, **REACHABLE = N of N** | ✅ | A board missing = it never joined; `NOT REACHABLE FROM ROOT` = it was orphaned |
| Sample coverage **≥ 95%** per node | ✅ | Below = the logger was dropping samples (M5 fails) |

---

## 2. What the topology table should look like ✅ REAL

```
 HOP   MAC ADDRESS        ROLE       UPLINK (= ITS PARENT)
 H00   B0:CB:D8:F3:32:18  ROOT       --:--:--:--:--:--  (root, no parent)
 H01   28:05:A5:32:D7:B4  VICTIM     B0:CB:D8:F3:32:18
 H02   B4:BF:E9:34:ED:80  VICTIM     28:05:A5:32:D7:B4
 H03   B4:BF:E9:32:FE:90  VICTIM     B4:BF:E9:34:ED:80
 H04   70:4B:CA:25:B7:68  VICTIM     B4:BF:E9:32:FE:90
 H05   20:50:0D:E7:0C:80  VICTIM     70:4B:CA:25:B7:68
 H06   20:50:0D:E7:1C:38  BLACKHOLE  20:50:0D:E7:0C:80
 H07   F4:2D:C9:73:E6:18  VICTIM     20:50:0D:E7:1C:38
```

**Read it like a chain:** each row's UPLINK is the row above it. Unbroken = linear topology confirmed
**from the data**, no diagram needed.

⚠️ **Check where the attacker sits.** Above, it is at **H06 of H07** — only ONE victim is downstream
of it. Since C7 Option 1 the attacker only intercepts traffic that *passes through it*, so an
attacker at the far end intercepts **almost nothing**. For a meaningful blackhole run, **put the
attacker near the root** (H01–H02), so most victims' traffic must transit it.

---

## 3. Per-phase feature table — the core result

### ✅ REAL (your sep-18 capture, pre-C7)

| Feature | baseline | attack | cooldown | Reading |
|---|---|---|---|---|
| **PDR** | **0.999** | **0.001** | **0.997** | ⭐ The headline. Near-total delivery → near-zero → recovery |
| **ForwardingRatio** | 1.005 | 0.001 | 0.998 | Attacker forwarded everything, then nothing, then everything |
| RetryRate | 0.000 | 0.128 | 0.000 | ⚠️ This was the *leak* — see §5 |
| RSSI_mean | −68.6 | −68.9 | −67.8 | **Flat, correctly.** Radio conditions do not change |
| ParentSwitchRate | 0.000 | 0.000 | 0.000 | **Zero, correctly.** The tree never re-forms |

**The attacker's own counters** (`probes_count_delta` = received, `tx_count_delta` = forwarded):

| segment | received/window | forwarded/window | ForwardingRatio |
|---|---|---|---|
| baseline | 5.67 | 5.69 | 1.005 |
| **attack** | **5.64** | **0.006** | **0.001** |
| cooldown | 4.83 | 4.81 | 0.998 |

**Read that middle row carefully — it is the whole attack.** The attacker kept *receiving* ~5.6
probes per window and forwarded **essentially none**. It was not offline, not jammed, not
disconnected. It received and discarded. That is a blackhole.

### 🔮 EXPECTED after C7 + re-flash (the new, important change)

`ForwardingRatio` should now exist on **every relaying node**, not just the attacker:

| node_role | hop | ForwardingRatio (baseline) | ForwardingRatio (attack) |
|---|---|---|---|
| victim (relaying) | H01–H05 | **≈ 1.0** | **≈ 1.0** ← still forwarding honestly |
| **blackhole** | H06 | ≈ 1.0 | **≈ 0.0** ← the outlier |
| victim (leaf, no children) | H07 | NaN | NaN ← nothing transits it, correct |
| root | H00 | NaN | NaN ← the sink relays nothing, correct |

**This is the single most important thing to verify after your first post-C7 run.** If honest nodes
show ≈1.0 and the attacker ≈0.0, Option 1 worked and the panel's "one feature decides it" objection
is measurably fixed. If *every* node still shows NaN except the attacker, the relay is not running —
check that boards were actually re-flashed.

---

## 4. What the 3-sigma verifier should print ✅ REAL

```
  feature             tier      baseline mu+-sd (n)     attack mean (n)       z  verdict
  ForwardingRatio     primary   1.002+-0.025 (86)       0.001 (37)       -40.22  PASS [v]
  PDR                 primary   0.998+-0.025 (503)      0.000 (204)      -39.38  PASS [v]
  ConsistencyScore    secondary 0.011+-0.025 (86)       0.999 (37)        38.88  PASS [^]
  IngressEgressDelta  secondary 0.049+-0.115 (86)       5.604 (37)        48.51  PASS [^]

  VERDICT: BLACKHOLE CONFIRMED  (2/2 primary signatures exceed 3-sigma)
```

**What to look for:** both *primary* features PASS with |z| far beyond 3. A z of −40 means the attack
window sits forty standard deviations away from that run's own baseline — not a subtle effect.

**If you instead see:**

| Output | What it actually means |
|---|---|
| `INVALID-BASE` | The baseline is broken (mean far below Khan et al.'s >97%), not the attack. Usually the root joined late — check root power |
| `INFEASIBLE` | The feature is bounded and *cannot* reach 3σ against this baseline. A perfect attack would still "fail". Fix the capture, not the threshold |
| `INCONCLUSIVE` + "check for pre_baseline contamination" | Early-boot rows leaked into the baseline |
| `NOT CONFIRMED` **after** an integrity/topology gate failed | **Not evidence the attack failed** — the capture cannot support any claim. `analyze.ps1` now says this explicitly |

---

## 5. The NaN table — nulls are not bugs ✅ REAL

Reviewers ask about these every time. Each has a specific cause:

| Feature | NaN % | Why — and is it OK? |
|---|---|---|
| Tunnel×3 | **100%** | ✅ Correct. This is a *blackhole* run; tunnel features only exist on wormhole endpoints |
| ForwardingRatio / IngressEgressDelta / ConsistencyScore | **89.8%** | ⚠️ Pre-C7 only: one role could measure it. **Should drop sharply after C7** |
| LatencyHopRatio | 64.8% | ✅ Needs a matching arrival at the root. During the attack there are none — **the NaN IS the attack** |
| PDR | 33.0% | ✅ Same reason |
| RSSI_mean | 8.7% | ✅ `rssi_dbm == 0` is the "no parent" placeholder, blanked on purpose. 0 dBm would be a physically impossible perfect signal |
| RetryRate, ParentSwitchRate, HopChangeCount, HopStabilityDuration, RSSI_var, RSSI_stability | **0%** | ✅ Complete |

---

## 6. Two results you must REPORT, not hide

**a) Table 3.4 predicted victims would see more retransmissions. They do not.** Victims'
`retry_count` changes by **0** across the attack. Your own §3.3.1.2 explains why: the attacker still
ACKs every frame at the radio level, so victims' radios never see a failure.

**b) Table 3.5 predicted the wormhole would distort topology. It does not.** Measured across **two
independent runs** (r2 and r3): **0 parent switches, 0 layer changes** during the wormhole phase,
while the replay signature was perfect (**181 duplicate arrivals**, identical in both runs).

Both are **pre-registered misses** — predictions written before any capture, tested, and not
observed. **Report them; do not edit the tables.** A declared miss is a finding and evidence you
didn't fit the analysis to the data. An edited table is misconduct.

---

## 7. Red flags — stop and investigate

| Symptom | Likely cause |
|---|---|
| **All-NaN PDR + empty arrivals** | Root never joined, or no root file exported. ⚠️ Since C7 this is **no longer** the stale-attacker-MAC bug — do not reach for that first |
| Phase 0 has **2–3× expected rows** | Boards booted long before the root. `validate_integrity.py` WARNs on exactly this |
| `Converged within 60s: NO` | Same root cause — check root power (brownout loop) |
| Attacker `ForwardingRatio` ≈ 1.0 during attack | The attack never armed — was the root built with `-DACTIVE_ATTACK=1`? |
| Every node NaN for ForwardingRatio *post-C7* | Relay not running — boards not re-flashed |
| RSSI shifts 3–4 dB in the attack window | ⚠️ Probably **not** the attack. The attack always starts at the same point, so any slow room change aligns with it. Do not claim it without repeats |
| `Relay queue full` in the logs | That run's `drop_count` is contaminated — congestion drops are indistinguishable from attack drops |

---

## 8. Sample end-to-end analysis (what to write in the paper)

> During the attack window the root's arrival rate fell from **6.07 probes/s** to **0/s**, recovering
> to **6.01/s** (99% of baseline) in cooldown. The attacker continued to *receive* ~5.6 probes per
> 1-second window throughout, while forwarding fell from 5.69 to 0.006 — it remained an associated,
> responsive mesh member and discarded transit traffic at the application layer.
>
> Packet Delivery Ratio fell from **0.999 ± 0.025** to **0.001** (z = −39.38) and ForwardingRatio
> from **1.005** to **0.001** (z = −40.22), both far beyond the 3σ threshold of Zhukabayeva et al.
> (2025). The baseline PDR of 0.998 ± 0.025 falls inside the >97% range reported by Khan et al.
> (2022) for ESP-MESH, supporting the validity of the baseline.
>
> Physical- and topology-layer features were unaffected: RSSI_mean varied by <1 dB across phases and
> ParentSwitchRate was 0 throughout, confirming the manipulation was confined to the application
> forwarding layer and did not perturb the mesh tree — consistent with §3.3.1.2, and contrary to the
> retransmission increase predicted in Table 3.4, which was tested and **not** observed.

**Related:** `docs/ATTACK-VALIDATION.md` (conformance to literature) ·
`docs/DATA-DICTIONARY.md` (what each column means) · `docs/REVIEWER-QUESTIONS.md` (panel Q&A)
