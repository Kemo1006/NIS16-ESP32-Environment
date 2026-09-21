# What a good run should look like — expected results, with real numbers

**Created:** sep. 21, 2026 · **Use this right after every capture, before you trust the data.**

Every number below is either **measured from your own sep-18 G402 capture** (marked ✅ REAL) or a
**prediction for post-C7 firmware** (marked 🔮 EXPECTED, not yet observed). Nothing here is invented
without saying so.

**The point of this file:** a run can fail *silently* — boards look healthy, CSVs are full, and the
data is still worthless. These are the checks that catch that in five minutes instead of at analysis
time three weeks later.

---

## 0. HOW TO READ THE NUMBERS (read this first)

Every number in this file is one of six kinds. Once you know which kind you are looking at, the
tables below read themselves.

### 0.1 Ratios — numbers between 0 and 1

`PDR`, `ForwardingRatio`, `RetryRate`, `ConsistencyScore`.

**Think of them as percentages with the % sign removed.** `0.999` = 99.9%. `0.001` = 0.1%.

| You see | It means |
|---|---|
| `1.000` | 100% — everything got through |
| `0.999` | 99.9% — essentially perfect, one probe in a thousand lost |
| `0.500` | half |
| `0.001` | 0.1% — essentially **nothing** got through |
| `NaN` | **not a number** = this could not be measured here. **Not zero.** See §5 |

⚠️ **`0.001` and `NaN` mean completely different things.** `0.001` = "we measured it, and almost
nothing got through" (that's the attack). `NaN` = "there was nothing to measure here at all."

**`PDR`** = Packet Delivery Ratio = *of the probes a victim sent, what fraction reached the root?*
**`ForwardingRatio`** = *of the probes a node received to pass on, what fraction did it actually
pass on?* A node forwarding honestly ≈ **1.0**. A node dropping everything ≈ **0.0**.

> Why `ForwardingRatio` sometimes reads slightly **above** 1.0 (e.g. `1.005`): a probe can arrive in
> one 1-second window and get forwarded in the next, so a window can forward *slightly more than it
> received*. Anything up to ~1.05 is normal timing jitter. Values like **19.5** are not — that is a
> queue flushing, and `features.py` now warns about it.

### 0.2 Signal strength — the negative numbers (dBm)

`RSSI_mean` is around **−68**. Negative is normal and correct — that is just how radio strength is
written.

**Closer to zero = stronger.** Think of it like temperature below freezing: −10 °C is warmer than
−40 °C.

| Value | Meaning |
|---|---|
| −30 dBm | very strong (right next to each other) |
| **−68 dBm** | **normal for our boards across a room** |
| −85 dBm | weak, starting to struggle |
| −95 dBm | basically unusable |

⚠️ A value of **exactly `0`** is *not* a perfect signal — it is impossible. It is the firmware's
"I have no parent" placeholder, which is why the pipeline blanks it to `NaN`.

### 0.3 Per-window counts — "5.67" probes?!

`probes_count_delta`, `tx_count_delta`, `recv_count_delta`.

These are **averages per 1-second window**, so decimals are expected. `5.67` doesn't mean two-thirds
of a probe — it means *"across all the windows we measured, the typical window carried about 5.67
probes."* Six victims each sending ~1 probe/second ≈ 5.7 arriving per second. That checks out.

**`delta` means "how much this counter went UP during this window"**, not its running total. The
boards count cumulatively from boot (1, 2, 3, … 4000). The analysis subtracts to get the per-window
change, because "how many in *this* second" is what matters.

### 0.4 `mu ± sd` — the average and how much it wobbles

Written in the verifier output as `1.002+-0.025`.

- **`mu`** (the Greek letter mu, µ) = **the average**. Here: 1.002.
- **`sd`** = **standard deviation** = **how much the number normally bounces around** that average.
  Here: 0.025.

So `1.002 ± 0.025` means: *"normally this sits at about 1.00, and it's routine for it to wander
0.025 either side."* Roughly 2 out of every 3 windows land inside 0.977–1.027.

**A small `sd` means the measurement is stable and trustworthy.** A large one means it was already
jumping around wildly, and it becomes very hard to prove *anything* stood out.

### 0.5 `z` — the most important number, explained properly

You'll see `z = -40.22`. **This is the number that decides whether the attack is real**, so it's
worth understanding.

> **`z` answers one question: "how many `sd`s away from normal is this?"**

Using the real numbers: baseline `ForwardingRatio` is `1.002 ± 0.025`. During the attack it's
`0.001`. How far is that?

```
   1.002 - 0.001  =  1.001     ← how far the attack value moved
   1.001 ÷ 0.025  ≈  40        ← how many "normal wobbles" that distance is
   →  z = -40     (negative just means it went DOWN)
```

**Interpretation:**

| z | Meaning |
|---|---|
| 0 to 1 | completely ordinary, indistinguishable from normal |
| 2 | slightly unusual |
| **3** | **our threshold** — unusual enough to call it real (from Zhukabayeva et al. 2025) |
| 10 | extremely far outside normal |
| **40** | **astronomically far outside normal** |

So `z = -40.22` means: *during the attack, forwarding dropped to a level roughly **40 times further
from normal than its usual wobble**.* That's not a subtle statistical effect — it's the difference
between "a bit quiet today" and "the road has vanished."

**Why we use 3 and not something else:** it's the threshold from the paper our method is based on
(Zhukabayeva 2025), so we're not inventing a bar that happens to flatter our results. Our values
being ~40 instead of barely 3 is what makes the finding safe.

### 0.6 `(n)` — the sample count

`1.002+-0.025 (86)` — the `(86)` is **how many measurements that average came from**.

**Bigger is more trustworthy.** An average from 500 windows is far more reliable than one from 5.
If you ever see an `n` in single digits, be suspicious of the conclusion drawn from it.

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

**Read that middle row carefully — it is the whole attack, in three numbers.**

> **received 5.64** — probes were still arriving at the attacker every second. It was **not**
> offline, **not** jammed, **not** disconnected. The network was working fine.
>
> **forwarded 0.006** — of those ~5.6 probes per second, it passed on about **1 in a thousand**.
>
> **ratio 0.001** — that is `0.006 ÷ 5.64`, i.e. **0.1% forwarded, 99.9% silently discarded.**

Compare to the row above it: baseline received 5.67 and forwarded 5.69 — **everything it got, it
passed on.** Then cooldown: 4.83 in, 4.81 out — **back to normal again.**

That on/off/on pattern, from a node that stayed connected the whole time, is what a blackhole *is*.
A crashed or unplugged board would show **received = 0** — no traffic reaching it at all. This board
kept receiving and chose not to forward.

### How to sanity-check these numbers yourself

Two arithmetic checks you can do by eye, which catch most bad captures:

1. **`forwarded ÷ received` should equal `ForwardingRatio`.**
   Baseline: `5.69 ÷ 5.67 = 1.004` ✅ matches the 1.005 shown.
   Attack: `0.006 ÷ 5.64 = 0.001` ✅ matches.
   *If these don't match, something is wrong with the feature computation.*

2. **`received` should roughly equal (number of victims upstream) × (probes per second).**
   Six victims at 1 probe/s ≈ 5.7/s ✅ matches the ~5.6–5.7 observed.
   *If `received` is far lower than your victim count, traffic isn't reaching the attacker — check
   its placement (see §2).*

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

**Reading this table line by line** (using `ForwardingRatio`):

| Column | Value | What it's telling you |
|---|---|---|
| `tier` | `primary` | This is one of the two features the verdict depends on. `secondary` ones are supporting evidence only |
| `baseline mu+-sd (n)` | `1.002+-0.025 (86)` | Normally 1.002, wobbling ±0.025, measured over 86 windows |
| `attack mean (n)` | `0.001 (37)` | During the attack it was 0.001, over 37 windows |
| `z` | `-40.22` | That's **40 wobbles** below normal. Negative = it went **down** |
| `verdict` | `PASS [v]` | Beyond the 3σ threshold. `[v]` = we expected it to go DOWN, and it did |

**What to look for:** both *primary* features PASS with |z| far beyond 3. `PDR` and
`ForwardingRatio` at −39 and −40 are not a marginal result — the pattern is unmistakable.

⚠️ **A PASS on `RetryRate` is NOT good news** (pre-C7 data): that feature was reading the attacker's
own drop counter, so it "detected" the attack by looking at the attack's own switch. That's the
leakage F3 fixed — see §5 and `analysis/leakage.py`.

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
