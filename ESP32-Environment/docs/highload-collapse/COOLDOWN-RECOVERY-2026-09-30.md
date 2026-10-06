# Cooldown recovery — why r3 (7 nodes) failed verification — sep. 30, 2026

**Who this is for:** everyone on the team. The findings are in plain language; the commands and
file paths are for whoever continues the study.
**This is the working file for the dataset issue.** Add to it; don't start a new one.

**Short version:** the blackhole attack in r3 is the **best one we have ever captured** — a total
blackout, all 5 victims at PDR exactly 0.000. Nothing is wrong with the attack. The run fails
verification because of what happens **after** the attack: the mesh never recovers during the
cooldown phase. Recovery fell from 100% (4 nodes) to 70% (6 nodes) to 51% (7 nodes).

**Status:** diagnosis only. **No code, data or firmware was changed.** The `nocooldown` files used
to prove the cause were temporary copies outside the repo and are gone.

> **Update, sep. 30 (later the same day) — see §10.** r4 and a **no-attack** 7-board highload run
> were checked the same way. The no-attack run collapses too, with the same recovery as r3 (51%), so
> **the collapse is caused by 7 boards at highload, not by the blackhole.** r4 fails the r4 gate
> (recovery 23%). The r3 capture now answers part of item 1 in §7. §8 is updated to match.

---

## 1. What was asked

`verify_attack.py` returned INCONCLUSIVE on the sep. 29 r3 run (root + 6 children). The same
pipeline returned CONFIRMED on the 4-node run. The question raised was whether the MAC retry rate
caused it.

## 2. It is not the retry rate — ruled out

`RetryRate` is a **secondary** feature. The verdict counts only `tier == "primary"`
(`verify_attack.py:400-429`), which is `ForwardingRatio` and `PDR`. `RetryRate` cannot change the
verdict under any value. It also read `0.000 → 0.000` in **every** run including the 4-node one
that PASSED, so it does not distinguish them. `MacRetryRate` is not in `SIGNATURES` and is never
tested. This stays the pre-registered Table 3.4 miss we already report.

## 3. The real cause — cooldown is pooled into the "normal" baseline

`preprocess.py` labels **both** `baseline` and `cooldown` as `Label 0`, and `verify_attack.py:361`
takes its normal reference as `lab == LABEL_BASELINE`. So the 2859 "baseline windows" in the report
are 2100 baseline + **759 cooldown**.

Measured on `datasets/analysis/blackhole/linear/home/highload/feature_table_r3.csv`:

| segment | PDR | |
|---|---|---|
| baseline | **0.9988 ± 0.0214** (n=1499) | clean |
| cooldown | **0.5425 ± 0.4320** (n=582) | not clean |

Pooling those gives the 0.862 in the report, which trips two guards at once:
- PDR 0.862 < `BASELINE_FLOOR` 0.90 → **EXCLUDED**
- ForwardingRatio sd/mu = 0.16 > `BASELINE_DISPERSION_CEILING` 0.15 → **EXCLUDED**

Both primaries excluded = INCONCLUSIVE. The attack rows were never the problem.

**Proof.** Same table, same verifier, nothing else changed, cooldown rows removed:

```
ForwardingRatio  primary  0.999+-0.018 (305)  0.800 (185)  -10.88  PASS
PDR              primary  0.994+-0.047 (305)  0.000 (185)  -21.06  PASS
VERDICT: BLACKHOLE CONFIRMED (2/2 primary signatures exceed 3-sigma).   exit 0
```

r2 recovers the same way (PDR z = −13.82, CONFIRMED). r2's ForwardingRatio stays excluded for a
**separate** reason — a genuine baseline outlier in r2 — which is still unstudied.

## 4. Why the cooldown collapses

Every relaying node runs a 128-slot queue (`probe_relay.c:28`): the receive callback pushes into it
with a zero timeout and counts a **drop** if it is full (`:113`); a relay task pulls packets out and
calls `esp_mesh_send()`, counting a **drop + send_fail** if that errors (`:148`).

The code guarantees `recv == forward + drop`. That residual is 0 for every node in every phase
**except the attacker in cooldown**, where it averages **+1.07 per window** — packets accepted,
not forwarded, not dropped, i.e. sitting in the queue.

Timeline on the attacker (`NODE_F42DC973E618`, hop 1):

| window | recv/s | forward/s | drop/s | reading |
|---|---|---|---|---|
| 541 | 20 | 20 | 0 | cooldown starts — **clean, phase switch works** |
| 565–568 | 20 | 20 | 0 | still healthy, 35 s in |
| 569–583 | 20 | 13 → 3 | **0** | relay slows; queue filling at ~12/s |
| 584 onward | 20 | 3–9 | **4–15** | queue hit 128 → arrivals rejected at the door |

128 slots ÷ ~12/s ≈ 11 s of accumulation, matching t=573 → t=584 exactly.

**What it is not:** not a parent switch (`ParentSwitchRate` 0, `parent_mac` constant
`B0:CB:D8:F3:32:19`), not a layer change (2 throughout), not RSSI (−63 to −70, and it was −70 while
healthy), not a send error (`retry_count` = `s_send_fail` = **0** the whole time, so every
`esp_mesh_send()` that returned, returned OK).

**Open question — the actual cause is not established.** `esp_mesh_send()` is returning OK but
taking roughly 140 ms instead of ~50 ms. Telemetry cannot say why.

**Hypothesis to test (not proven):** the stop-start is chain-wide, not attacker-local. The hop-2
victim goes four straight seconds at forward 0, then dumps **91 packets in one window**. Over the
segment its residual averages 0, which is why only the attacker shows in the table — but the
pattern suggests ESP-MESH layer behaviour after 180 s of a blackholed subtree, not one bad node.

**There was no post-attack backlog.** During the attack the decision callback discards packets
immediately on dequeue, so the queue stayed empty and the first 35 s of cooldown ran at 20 in /
20 out. Whatever slowed the relay started well after the attack ended.

## 5. What the thesis requires — the criteria already exist

`EXPECTED-RESULTS.md §3` and `ATTACK-VALIDATION.md:39` specify on/off/**on**, not on/off. Cooldown
recovery is what separates "the attacker chose not to forward" from "the node died", and
`WIRESHARK-GUIDE.md:509` calls the I/O graph climbing back in cooldown *"the single most convincing
screenshot in your whole thesis."*

| criterion | thesis target | r3 actual | |
|---|---|---|---|
| baseline PDR | 0.999 | 0.999 | PASS |
| attack PDR | 0.001 | **0.000** | PASS (better) |
| **cooldown PDR** | **0.997** | **0.543** | **FAIL** |
| **cooldown recovery** | **99%** | **51%** | **FAIL** |
| attacker cooldown ForwardingRatio | 0.998 | 0.545 | FAIL |
| ParentSwitchRate | 0.000 | 0.000 | PASS |
| RSSI flat | yes | −63 to −70 | PASS |

Root arrivals per second, all three runs:

```
run  nodes  baseline/s  attack/s  cooldown/s  recovery
r1     4       8.00       4.00       8.00      100%   <- CONFIRMED
r2     6      15.53       3.56      10.80       70%
r3     7      19.80       0.00      10.11       51%
```

## 6. Do not discard r3

r3 is the only run with a **perfect** blackhole: root arrivals 0.00/s during the attack and all
5 victims (hops 2–6) at PDR exactly 0.000. r1 "passed" with attack PDR **0.502**, because only one
of its two children sat behind the attacker — the other was a bystander. One criterion fails on r3;
everything else is our strongest capture.

## 7. What to do

1. **Find out why the relay slowed. The capture already exists** —
   `datasets/PCAP/blackhole/linear/home/highload/linear-blackhole-highload-home_r3_sept29_1011PM.pcap`
   covers this run. Narrow question: what happened on the attacker's uplink at t≈569, given no
   parent switch, no layer change, no send error and flat RSSI. Everything below is guesswork until
   this is answered.
2. **`PHASE_COOLDOWN_S` 120 → 300** (`mesh_config.h:203`), matching `PHASE_BASELINE_S`. The collapse
   starts 35 s in, so 120 s never shows whether it recovers; and a symmetric baseline/cooldown makes
   the two reference distributions comparable. **Log it in `thesis-deviate.md`** the way D-9 was
   logged — it is a protocol deviation, not a design change.
3. **Keep `highload` at 7 nodes.** The congestion follows from the intended topology: the design puts
   the attacker at H01–H02 *specifically* so all victim traffic transits it, which at 7 nodes and
   highload means 20 probes/s through one relay. Backing off to `stationary` dodges the finding.
4. **Separately, fix the verifier's baseline scope** — reference should be `segment == 'baseline'`,
   not `Label == 0`. Pooling a recovery phase into "normal" is wrong on its own terms, the same
   reasoning that excluded `pre_baseline` in `assign_segments()` on sep. 18. Do this as a documented
   methodology correction, **not** as the thing that rescues r3: it would produce a CONFIRMED verdict
   on a run that still fails the thesis's own recovery criterion, and it would not fix the Wireshark
   screenshot.

**Gate for r4:** `verify_attack.py` exits 0 with both primaries PASS and neither EXCLUDED, **and**
cooldown recovery ≥ 95%. The first alone is not enough.

## 8. What is and is not established

| claim | status |
|---|---|
| RetryRate did not cause the verdict | **established** — verdict counts primaries only |
| Cooldown pooling causes both EXCLUDED verdicts | **established** — removing it flips r2 and r3 to CONFIRMED |
| Attacker's queue overflows in cooldown | **established** — residual +1.07, 128 slots, timing matches |
| Not a link/parent/send failure | **established** — counters and link state all flat |
| *Why* `esp_mesh_send()` slowed at t≈569 | **partly answered (§10.4)** — the root starts sending ~15–20× more frames down to hop 1 at that moment; *what* those frames are is still unknown |
| Chain-wide mesh congestion | **supported (§10.2)** — the same collapse happens in a run with **no attacker**; still not explained |
| The blackhole causes the collapse | **ruled out (§10.2)** — the no-attack run collapses, and recovers the same 51% as r3 |
| Root storage filling to ~1.1 MB triggers it | **ruled out (§10.3)** — no-attack run collapsed at 890 KB; a 3-board run wrote 948 KB with no collapse |
| r2's ForwardingRatio outlier | **unstudied** — separate from everything above |

## 9. Reproduce

Run from `ESP32-Environment/`. `FT` is the r3 feature table under
`datasets/analysis/blackhole/linear/home/highload/`.

```powershell
# the failing verdict, as reported
python tools/verify_attack.py datasets/analysis/blackhole/linear/home/highload/feature_table_r3.csv
```

Per-segment split (shows baseline clean, cooldown not) and the queue residual (0 everywhere except
the attacker in cooldown):

```python
import pandas as pd
d = pd.read_csv("datasets/analysis/blackhole/linear/home/highload/feature_table_r3.csv")
print(d[d.exposure == "downstream"].groupby("segment")["PDR"].describe())

d["r"] = d.recv_count_delta - (d.forward_count_delta + d.drop_count_delta)
print(d.pivot_table(index=["node_role", "hop"], columns="segment",
                    values="r", aggfunc="mean").round(2))
```

---

## 10. Update, sep. 30 — r4 and a no-attack run (same diagnosis, wider)

**Status:** diagnosis only, like §1–9. No firmware, data or verifier code was changed for this.
MACs are written first-byte:...:last-byte (`70:...:68`); full MACs only where a filter needs them.

### 10.1 What was checked

| run | boards | probes/s per node | what it is |
|---|---|---|---|
| sep. 25 G402 stationary | 7 | 1 | older run, archived (`datasets/archive/2026-09-26_tested-4-nodes-at-home-/`) |
| sep. 26–27 home stationary | 3 | 1 | older runs, archived |
| blackhole highload r1 | 3 | 4 | sep. 27 |
| blackhole highload r2, r3 | 6–7 | 4 | sep. 28, sep. 29 (§1–9) |
| **blackhole highload r4** | 7 | 4 | sep. 30, 00:59 — attacker at **hop 4**, 2 victims, 3 bystanders above it |
| **baseline highload r1** | 7 | 4 | sep. 30, 02:40 — **no attacker at all** (`datasets/exports/baseline/linear/home/highload/`) |

Sources: each run's root `*_arrivals.csv` (one clock — the root's), the `feature_table_r*.csv` files,
the r3/r4 sniffer captures (`*_retry.csv`), and the r4 root run log. ⚠️ The no-attack run's two run
logs hold only wizard text (~3 KB); the root's console was not saved for it.

### 10.2 The collapse is not caused by the blackhole

"Collapse" = partway through the run, the node next to the root stops getting its **own** probes to
the root, then the nodes below it follow, one hop at a time.

| run | boards × rate | collapsed? | cooldown recovery (root arrivals/s, same method as §5) |
|---|---|---|---|
| G402 stationary | 7 × 1/s | no | — |
| home stationary | 3 × 1/s | no | — |
| blackhole highload r1 | 3 × 4/s | no | 100% (8.00 → 8.00/s) |
| blackhole highload r2 | 6 × 4/s | yes (cooldown) | 70% |
| blackhole highload r3 | 7 × 4/s | yes (cooldown) | 51% |
| blackhole highload r4 | 7 × 4/s | **yes, ~100 s into the attack** | **23%** (19.81 → 4.61/s) |
| **baseline highload r1 (no attack)** | 7 × 4/s | **yes, ~210 s into baseline** | **51%** (22.21 → 11.22/s) |

- The no-attack run breaks the same way and "recovers" exactly as much as r3 — **with nothing to recover from.**
- It is not one faulty board: the node next to the root is `70:...:68` in r4 but `f4:...:18` (the usual
  attacker board, built as a plain child) in the no-attack run. Both collapse first.
- The pattern needs **both** many boards **and** highload: 7 boards at 1/s is fine, 3 boards at 4/s is fine.
  7 boards at 4/s = ~24 probes/s all funnelled through one node next to the root.

This supports the chain-wide congestion hypothesis in §4 and **rules out** "ESP-MESH behaviour after
180 s of a blackholed subtree" — the no-attack run never had one.

### 10.3 Ruled out: root storage filling up

An earlier reading (same day, in chat) was that the collapse starts once the root has written
~1.0–1.16 MB of CSV (r2 1,016 KB, r3 1,161 KB, r4 1,122 KB). **It does not hold:** the no-attack run
collapsed at **890 KB**, and 3-board r1 wrote **948 KB** without collapsing. The root's logging may
still play a part, but a fixed storage level is not the trigger. This is also not I-017 (children's
SPIFFS): every child export in r4 is 500–600 KB and complete.

### 10.4 What the captures show at the moment it breaks (partial answer to §7 item 1)

Both captures show the **same signature**: when the relay slows, the root suddenly sends far more
frames **down** to the node next to it, while fewer probes come up.

| capture | when | root → hop 1 frames | hop 1 → root frames |
|---|---|---|---|
| r3 (hop 1 = attacker `f4:...:18`) | cooldown +30 s (t ≈ +210 s, = window 569 in §4) | ~1–18 → **~250–317 per 15 s** | ~440–540 → ~510–615 per 15 s |
| r4 (hop 1 = `70:...:68`) | ~100 s into the attack (root uptime ~480 s) | ~30 → **~400 per 20 s** | ~110–200 → ~580–870 per 20 s |

So the link gets **busier** while delivery falls. Nothing in the root console explains it (r4: no
errors, no disconnects, only topology tables). **Next:** identify those downward frames in Wireshark
on the r3 capture around t ≈ +210 s:
`wlan.ta == b0:cb:d8:f3:32:19 && wlan.ra == f4:2d:c9:73:e6:18` (root softAP → attacker).
Frame type/size will say whether it is ESP-MESH control/flow-control traffic, root broadcasts, or
retransmitted data.

### 10.5 r4 in detail — the r4 gate FAILS

- **The attack itself worked perfectly.** Attacker `f4:...:18`: baseline received 2,382 / forwarded 2,382;
  attack received 1,422 / forwarded **0** / dropped 1,422. Both victims (`20:...:38`, `20:...:80`) went
  from PDR 0.999 to **0.000** the moment the attack started.
- **Placement differs from the design in §7.3.** The attacker sat at hop 4 (root → `70:...:68` →
  `28:...:b4` → `b4:...:80` → attacker → victims), so only 2 victims; the design puts it at H01–H02.
- **The collapse began during the attack**, at hop 1, then hop 2, then hop 3 — so the late attack
  windows and all of cooldown hold a breaking mesh, not a clean attack or a clean recovery.
- **The cooldown announcement reached hops 2–6 about 47 s late** (root started cooldown at uptime 557 s;
  the root's heartbeat table still showed them in BLACKHOLE at 561/576/590 s, COOLDOWN only at 605 s).
  Both victims were marked OFFLINE at 619 s.
- **Gate (§7):** verifier gave BLACKHOLE CONFIRMED on PDR only, with ForwardingRatio **EXCLUDED**, and
  cooldown recovery is **23%**. Both conditions fail.

### 10.6 The verifier — what actually flips PASS to FAIL

Same verifier, same tables, ForwardingRatio / ConsistencyScore / IngressEgressDelta:

| run | as-is (cooldown counted as normal) | cooldown rows removed (all nodes still pooled) |
|---|---|---|
| r2 | FAIL / INFEASIBLE / FAIL | FAIL / INFEASIBLE / FAIL — r2's baseline itself is unstable (§8) |
| r3 | FAIL / FAIL / FAIL | **PASS / PASS / PASS** (z −10.9 / 9.6 / 9.2) |
| r4 | FAIL / INFEASIBLE / FAIL | **PASS / PASS / PASS** (z −15.0 / 7.8 / 3.8) |

- **Pooling all nodes only weakens the result; it does not flip it.** On r4 (cooldown removed), keeping
  the attacker plus 0, 1, 2, 3 or 4 other relaying nodes passes every time (ForwardingRatio z −31 → −15).
  Leaves add nothing (no forwarding ratio). Testing the forwarding features on the attacker's rows only
  is still the more honest test, since only the attacker is supposed to change.
- **The flip comes from cooldown being in the "normal" reference**, as §3 found — and in highload that
  cooldown is the collapse.
- ⚠️ This is **diagnosis, not a rescue** — same as §7 item 4 and the sep. 30 MEMORY.md decision. A verdict
  that ignores cooldown would pass r3/r4 while they still fail the thesis's own recovery criterion.

### 10.7 Would another topology pass?

Not reliably, and it should not be chosen for that reason — topology is an experiment variable to run
and report as-is.
- **Star:** should fail, correctly. Every board is a direct child of the root, so no one's traffic passes
  through the attacker; nothing to drop, no PDR change. A real result ("blackhole has no effect in star").
- **Tree / partial:** traffic splits across several nodes next to the root, so the collapse may not
  happen, the cooldown may stay clean, and the verdict may pass. **Prediction only** — there are no
  tree/partial runs on the current firmware (the July ones used the pre-redesign attack).
- A tree highload run is also a useful **diagnostic**: no collapse there → the cause is load on one relay;
  collapse anyway → the cause is on the root side.

### 10.8 What this means for the dataset

- **Stationary runs:** unaffected.
- **7-board highload runs (r2–r4 and the no-attack run):** the attack windows are usable (the victims'
  PDR = 0.000 is real). The later part of each run is a breaking mesh, not "normal" or "recovery" data.
- ⚠️ **The benign highload class is affected too.** The no-attack highload run is the dataset's
  "high-but-legitimate load" example (panel item 7). From ~210 s into its baseline it is a collapsing
  mesh, not normal operation — do not use its later windows as benign data.
- §7 item 3 ("keep highload at 7 nodes") needs revisiting as a **team decision**: 7-board highload
  currently breaks down on its own, with or without an attacker.

### 10.9 Next steps (adds to §7)

1. Wireshark on r3 at t ≈ +210 s with the filter in §10.4 — what are the extra root → hop 1 frames?
2. Re-run the no-attack 7-board highload run **with the root console saved** (answer yes to the wizard's
   save-log question) so the moment of collapse is on record.
3. A 7-board highload run as a **tree** (§10.7), and/or one with the root's per-probe arrivals logging
   reduced — separates "one relay overloaded" from "root can't keep up".
4. Sniffer placement: the victims' uplinks are almost unheard in both r3 and r4 (r4: 45 frames from
   `20:...:38` to the attacker all run). Put the sniffer near the attacker and the first victim.

### 10.10 Reproduce

Run from `ESP32-Environment/datasets/exports/`:

```python
# cooldown recovery per run - root arrivals per second in each phase
import csv, collections
f = "baseline/linear/home/highload/root_node1_linear_none_r1_sept30_0240AM_arrivals.csv"
span, n = collections.defaultdict(list), collections.Counter()
for r in csv.DictReader(open(f, encoding="utf-8-sig")):
    span[r["phase_id"]].append(int(r["timestamp_us"]) / 1e6); n[r["phase_id"]] += 1
rate = {p: n[p] / (max(v) - min(v)) for p, v in span.items() if max(v) > min(v)}
print({p: round(x, 2) for p, x in rate.items()}, "recovery", round(rate["3"] / rate["0"], 2))
```

Per-node collapse timeline: count `src_mac` per 30 s in the same file (column per sender, ordered by the
`layer` in each child's `*_telem.csv`). Capture signature: sum `frames` per `ta`→`ra` per 15 s in
`datasets/PCAP/blackhole/linear/home/highload/*_r3_*_retry.csv`, using `t_rel_attack_s`.

---

## 11. Update, sep. 30 (later) — is `jitter` the same problem, and can firmware handle more load?

**Status:** discussion only. Nothing in this section was built, changed, or tested. It answers two
questions asked about this study, for whoever continues it.

### 11.1 `jitter` is not a highload variant — it cannot cause this collapse

`-DTRAFFIC_PROFILE=3` (`jitter`) only randomises how long baseline (+0..45 s) and attack (+0..30 s) run,
drawn fresh by the **root only** every boot (`root_main.c` `jitter_extra_s()`, additive-only so a fixed-
length baseline slice is never shortened). **No child's probe rate or traffic volume changes at all** —
`PROBE_INTERVAL_MS` stays 1000 ms under jitter; only `TRAFFIC_PROFILE_HIGHLOAD` touches it (250 ms,
`mesh_config.h:534-539`). Since §2–§10's collapse only appears at 7 boards × the highload rate (7 × 1/s
and 3 × 4/s both stayed clean, §10.2), and jitter never raises the rate above 1/s, jitter cannot trigger
it. This was missing from `memory/run-scenarios-2026-09.md` (only 5 of the 6 real scenarios were
documented) — fixed the same day this section was added.

### 11.2 Where the relay's actual limits are, read from the code

Read for "can the boards be made to handle more load", not tested. `components/mesh_common/src/probe_relay.c`
is the one function every hop's forwarding runs through — root, attacker, and every child relay through
the same `relay_task`:

1. **`RELAY_QUEUE_SIZE 128`** (`probe_relay.c:28`) — an app-level FreeRTOS queue per node. A full queue is
   counted as a drop (`s_drop++`, "Relay queue full"). Raising this only delays the point where drops
   start; it does not raise how many packets/second the node can actually move, so on its own it would
   turn a sudden collapse into a slower one, not prevent it. ⚠️ Per the comment at `probe_relay.c:23-27`,
   any run that ever logs "Relay queue full" has its `drop_count` (and therefore `ForwardingRatio`)
   **contaminated** — a congestion drop is indistinguishable in the telemetry from an attacker's
   deliberate drop. Worth grepping run logs for this string on every highload run collected so far.
2. **`TASK_PRIO_PROBE_SINK 6`** (`mesh_config.h:772`) — the relay task's own FreeRTOS priority, already
   above `TASK_PRIO_PROBE_GEN 5` (that board's own probes) on every board alike. Raising it further would
   not reorder anything relative to other boards, since every board runs the identical priority table —
   it cannot fix a mesh-wide bottleneck by itself.
3. **`esp_mesh_send()` is called with no `MESH_DATA_NONBLOCK` flag** (`probe_relay.c:75`) — it blocks
   until the mesh stack's own internal send queue accepts it. While blocked, `relay_task` cannot drain
   `RELAY_QUEUE_SIZE`, so the app queue backs up *because* the underlying send is stalled — this is a
   candidate explanation for the "recv stays 20/s, forward drops to 3-9/s, `send_fail` stays 0" pattern
   in §4 (the calls are slow, not failing).
4. **The mesh stack's own internal queue size is unconfirmed.** `grep CONFIG_MESH_ child_node/sdkconfig
   root_node/sdkconfig` returns nothing — it is still whatever ESP-MESH's Kconfig default is, never
   overridden in this repo. This is upstream of `RELAY_QUEUE_SIZE` and has not been measured.
5. **All 7 boards share one 2.4 GHz channel** (one AP per hop, one radio each, same channel). This is a
   physical ceiling no queue size or task priority changes: every hop's forward spends real airtime on a
   channel every other board is also using. **This is the most likely reason a fix would need to be
   architectural** (fewer hops per relay — a tree, §10.7) rather than a constant tweak.

### 11.3 If this gets tried

⚠️ **§11.2 item 5 (shared-channel airtime) is WRONG — disproved in §12.2. §12 supersedes §11.2.**

None of items 1-4 have been tried. In order of expected usefulness per item 5's ceiling: a **tree
highload run** first (§10.7 — already the planned diagnostic, and doesn't require a firmware change),
then reading the actual `CONFIG_MESH_TXQ_SIZE`/`CONFIG_MESH_RXQ_SIZE` the build is using, then
`RELAY_QUEUE_SIZE` as a cheap, low-confidence experiment. Any firmware change here needs a rebuild +
reflash + a real highload run to test, same as every other item in §10.9 — not done as part of this
diagnosis.

---

## 12. CAUSE FOUND — the ROOT's logging blocks its own mesh receive path (sep. 30)

**This section supersedes §10.4 and §11.2.** Measured with tshark on the r4 capture plus the boards'
own exports. **Two earlier claims in this document were wrong and are corrected below.** No code was
changed; the fix is proposed, not applied.

### 12.1 The children never failed — the root stopped receiving

The single measurement that overturns the earlier reading. Per 20 s, from each child's own
`*_telem.csv` (`tx_count` = its own probes that `esp_mesh_send()` returned OK for; `recv_count` =
packets it relayed for others), across the whole collapse window:

| node uptime | hop 1 own/relay | hop 2 own/relay | hop 3 own/relay | hop 5 own/relay |
|---|---|---|---|---|
| 420 s | 79 / 320 | 79 / 237 | 79 / 158 | 80 / 79 |
| 500 s | 80 / 317 | 79 / 238 | 79 / 159 | 79 / 80 |
| 560 s | 80 / 318 | 79 / 238 | 80 / 159 | 79 / 80 |

**Every node kept sending its own probes at the full highload rate (79-80 per 20 s = 4/s) and kept
relaying at a constant rate, for the entire run.** No node ever slowed down, and no node's queue
starved. §4's "the attacker's relay throughput collapses" describes what the ROOT recorded, not what
the attacker did.

Meanwhile the root's own `probes_count` fell from 19.8/s (baseline) to 9.9/s (attack) to **4.6/s**
(cooldown), and its `arrivals.csv` shows the per-hop fade described in §10.2. So: **packets were sent,
they were on the air, and the root did not take them in.**

### 12.2 ❌ CORRECTION — the channel is nowhere near saturated (§11.2 item 5 was wrong)

`tshark -q -z io,stat,30` over the whole r4 capture — **every frame on channel 11**, not just ours:

| capture window | frames / 30 s | bytes / 30 s |
|---|---|---|
| 60-90 s (baseline, healthy) | 8,333 | 721 KB |
| 420-450 s (mid-collapse) | **2,655** | 172 KB |
| 570-600 s (cooldown) | 8,056 | 577 KB |

Peak is **~278 frames/s and ~24 KB/s (≈192 kbps)** — orders of magnitude below what a 2.4 GHz channel
carries, and traffic **falls** during the collapse rather than hitting a ceiling. Airtime contention
is **not** the limit, and the "everyone shares one radio channel" explanation (§11.2 item 5, and the
same claim made in chat) is **withdrawn**.

### 12.3 ❌ CORRECTION — §10.4's "root → hop 1 frame surge" was real but misread

Per-phase QoS-data rates, root softAP `b0:...:19` ↔ hop 1 `70:...:68` (r4):

| phase | root → hop 1 | hop 1 → root |
|---|---|---|
| baseline | 2.83/s | 33.28/s |
| attack | 8.0/s | 19.25/s |
| cooldown | 17.67/s | 29.44/s |

The rise is real (2.8 → 17.7/s, ~6×, not the "13-20×" §10.4 claims) and it steps up sharply at
capture t≈500 s. But **retry rates do not spike with it** (13-14% downstream, 36-38% upstream — inside
the baseline range of 25-59%), so it is **not** a retransmission storm, and the payloads before and
after are the same relayed-probe frames. It is the root working *harder* on a link that is delivering
*less* — a symptom of the flow-control throttling in §12.4, not a cause.

### 12.4 The mechanism — blocking file I/O inside the single mesh-receive task

`root_main.c:202-203` states the design: `esp_mesh_recv()` is called from **ONE task only** (the phase
listener, `TASK_PRIO_PHASE_LISTENER 8`, commented *"High priority — must wake quickly"*), which
dispatches to the probe-sink callback. That callback (`root_main.c:536-566`) then does, **per arriving
probe, inline, in that same task**:

1. `esp_wifi_sta_get_rssi()` — a Wi-Fi driver call;
2. `csv_logger_append_probe_arrival()` → `fputs()` to **SPIFFS** (`csv_logger.c:1479`);
3. `sd_mirror_ensure()` + `fputs()` to the **SD card** (`:1486-1488`);
4. every `LOGGER_FLUSH_RECORDS` = **10** rows: `fflush()` on both files (`:1493-1497`);
5. every `LOGGER_SD_SYNC_INTERVAL_MS` = 5 s: an SD `fsync` (`sd_mirror_sync_due()`).

At 7 boards × 4 probes/s the root takes ~20 arrivals/s, so this is ~20 SPIFFS writes + ~20 SD writes
per second and **two flushes per second**, all on the thread that must call `esp_mesh_recv()` to drain
the mesh RX queue. Whenever that I/O stalls — an SD write latency spike, or SPIFFS garbage collection,
which gets slower as the partition fills — `esp_mesh_recv()` is not called.

The root's mesh RX queue is `esp_mesh_set_xon_qsize()`, **never called in this repo** (`grep xon`
returns nothing), so it is the **default 32** packets. Once those 32 fill, ESP-MESH's own flow control
throttles the children upstream — which is exactly the observed picture: children transmitting at full
rate, extra root↔hop-1 control traffic, and arrivals not reaching the application.

This also explains the parts that never fitted: it is **independent of the attack** (the no-attack run
collapses identically, §10.2), it needs **7 boards × highload** (≈20 arrivals/s is what saturates the
write path; 7×1/s and 3×4/s do not), it **worsens over time** rather than failing instantly (SPIFFS GC
slows as the file grows — the loose byte-count correlation §10.3 rightly rejected as a trigger), and it
leaves `retry_count`/`send_fail` at **0** because nothing ever fails — it only blocks.

⚠️ **Confidence:** the measurements (§12.1-12.3) and the code path (§12.4) are verified. That the
stall is specifically SD/SPIFFS latency is the **best-supported explanation, not proven** — proving it
needs the root instrumented (§12.5 item 1).

### 12.5 So: can it be solved? Yes — and the fixes are in our code, not ESP-MESH

In order. None have been applied or tested; all need a rebuild, reflash and a real 7-board highload run.

1. ✅ **Measure first (no behaviour change) — BUILT, NOT YET RUN. See §12.6.**
2. **Get the file I/O out of the receive path** — the actual fix. Push arrivals onto a FreeRTOS queue
   and let a *lower-priority* writer task do the SPIFFS/SD work, so `esp_mesh_recv()` is never blocked
   by a flush. This is the same split `probe_relay.c` already uses for forwarding (ingest → queue →
   task), applied to logging.
3. **`esp_mesh_set_xon_qsize(64…128)` before mesh start** (default 32, min 16) — widens the root's RX
   queue so a write stall has to last far longer before flow control kicks in. One line, cheap to try,
   but a buffer, not a cure.
4. **Cheap mitigations if 2 is too invasive for now:** raise `LOGGER_FLUSH_RECORDS` above 10 and/or
   drop the SD mirror on the **root** during highload runs (SPIFFS only — the export path already
   reads SPIFFS), and hoist `esp_wifi_sta_get_rssi()` out of the per-probe path (sample it in the
   10 Hz telemetry task instead and reuse the last value).

⚠️ **Until this is fixed, a 7-board highload run's root-side arrival data is a measurement of the
root's logging, not of the mesh.** The victims' PDR = 0.000 during the attack is still sound (§10.8) —
the attacker's own counters prove the drops independently of the root.

### 12.6 The measurement — built, compiled, NOT yet run on hardware

`root_node/main/root_main.c`, inside `probe_data_cb()`, tagged `RXSTALL INSTRUMENTATION — TEMPORARY`.
**Uncommitted; the user flashes.** It is deliberately *not* a `D-` number: it changes no behaviour and
is not a methodology deviation, so it must not imply an entry in `thesis-deviate.md` (D-15 is still the
last one). ✅ Compiles clean against local IDF 5.3.5 (root app 27% flash free); `sdkconfig` /
`dependencies.lock` rewritten by that build were reverted.

**What it does:** brackets the existing `csv_logger_append_probe_arrival()` call with
`esp_timer_get_time()`, samples `esp_mesh_get_rx_pending()` (`.toSelf`) each arrival, and every 200
arrivals (~10 s at the 20/s highload rate) emits one `ESP_LOGW` line, then resets its running maxima:

```
W (412345) ROOT_MAIN: [RXSTALL] write avg 3120 us / max 18400 us over 200 probes | RXQ max 4 of 32 (now 1) | phase 0
```

Cost: one timer-pair per probe plus one log line per 10 s. Nothing else changes.

**How to run it:** flash the ROOT only (children unchanged), do a normal 7-board highload run — the one
that collapses — and answer **yes** to the wizard's save-the-run-log question. Afterwards:

```bash
grep "\[RXSTALL\]" datasets/run_logs/blackhole/linear/home/highload/<run>.log
```

**How to read it.** The root takes ~20 probes/s, so each arrival has a **50 ms budget**, and the RX
queue holds **32** packets ≈ **1.6 s** of buffer:

| observation | verdict |
|---|---|
| `RXQ max` climbs across the run toward 32 | **§12.4 CONFIRMED** — the queue is filling; this is the throttle firing |
| `write max` reaches hundreds of ms or seconds | **CONFIRMED** — one stall that long alone overflows 1.6 s of buffer |
| `write avg` rises above ~50 ms | **CONFIRMED** — the root cannot keep up even on average |
| `RXQ max` stays 0-3 **and** `write avg` stays in µs/low ms, yet arrivals still collapse | **§12.4 REFUTED** — the stall is elsewhere; re-open the diagnosis |

The **trend matters more than any single line**: compare the first minute's lines against those around
the collapse. `RXQ max` going 0 → 1 → 4 → 20 → 32 while `write max` grows is the whole mechanism in
order. The trailing `phase` field (0 baseline / 1 attack / 3 cooldown) lines the numbers up against
where the collapse appears in the arrivals data.

**If confirmed → §12.5 item 2** (move the write onto a queue + lower-priority writer task). **If
refuted**, the next suspects are the phase-listener task's other work and ESP-MESH's own internal
scheduling — neither examined yet.

## 13. FIX APPLIED — oct. 1, 2026 (§12.5 items 2, 3, 4) — built, NOT yet run on hardware

Before the fix, Angelo's laptop's linear highload runs reached the root at these rates (per second, from each root `arrivals.csv`):

| run | children send | baseline, 1st min | cooldown, last min |
|---|---|---|---|
| baseline r1 (NO attack) | 24/s | 23.3/s | **7.1/s** |
| blackhole r3 | 20/s | 19.8/s | **6.5/s** |
| blackhole r4 | 20/s | 19.9/s | **2.9/s** |
| blackhole r1 (2 children) | 8/s | 8.0/s | 8.0/s (fine) |

What changed (root only, plus one root-only line in `mesh_setup.c`):

1. **Item 2, the actual fix:** `probe_data_cb` no longer writes. It snapshots the row (every field captured at arrival, so rows are identical to before) and `xQueueSend(…, 0)` into a 256-row queue (`ROOT_ARRIVAL_QUEUE_LEN`, ~13 s at 20/s). `arrival_writer_task` (priority 6, below the phase listener's 8) does the SPIFFS + SD write. It never blocks the receive path: a full queue drops and **counts** the row, logs `[RXSTALL] arrival queue FULL`, and the end of the run prints `N ARRIVAL ROW(S) NOT LOGGED`. Before the log closes, `arrival_queue_drain()` writes whatever is still queued.
2. **Item 3:** `esp_mesh_set_xon_qsize(ROOT_MESH_XON_QSIZE = 64)` on the root, before `esp_mesh_start()` (default 32).
3. **Item 4:** arrival rows reuse the telemetry task's 10 Hz RSSI reading (`s_last_rssi`) instead of an `esp_wifi_sta_get_rssi()` call per probe. Every root arrival row in every run so far has `rssi_dbm = 0` (the root has no parent AP), so the data is unchanged.

The `[RXSTALL]` line now comes from the writer, every 200 rows:
`[RXSTALL] Saving one probe to storage took X ms on average (slowest Y ms) over the last 200 probes | Waiting-to-save line: longest Q of 256, N lost so far | Mesh incoming buffer: longest R of 64 | Test phase: baseline|attack|cooldown`

Plain meaning: "Waiting-to-save line" is rows waiting in the root's memory for the SD card. "Mesh incoming buffer" is packets the mesh network is holding for the root. "lost so far" counts rows dropped because the waiting line was full.

**How to read the next 7-board highload run:** arrivals stay at about the send rate (about 20/s) through cooldown, the mesh incoming buffer stays low, and "lost so far" stays 0 means the fix worked. The waiting line climbing toward 256 means the SD card is slower than the arrival rate on average (a bigger queue or less SD work is next). Arrivals still collapsing while both stay low means §12.4 was not the cause, so re-open the diagnosis.
Built clean (`-Werror`, IDF 5.5.4): root blackhole, root baseline+burst, child blackhole-victim burst. Static RAM 51 KB used / 129 KB free; the queue takes ~14 KB of heap.
