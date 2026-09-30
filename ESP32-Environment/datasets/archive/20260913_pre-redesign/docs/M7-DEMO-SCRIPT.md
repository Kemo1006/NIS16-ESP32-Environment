# 🎬 M7 — Feature Engineering, 16 Features (10%)

> ## ⚠️ Criteria not supplied
> **Paste M7's criteria and I'll map each bullet.** The one criterion recorded in your own notes
> is: *"no feature is uniformly NaN"*.

## 🎯 Verdict: **all 16 features populated across the assembled dataset**

On 2026-07-24 this milestone had a real gap — two features were NaN in **every** run. Both now
populate.

| Feature | 2026-07-24 | **now** |
|---|:--:|---:|
| `LatencyHopRatio` | 🔴 NaN everywhere | 🟢 **7,239** windows |
| `TunnelLatency` | 🔴 NaN everywhere | 🟢 **299** windows |

---

## 📍 THE HEADLINE COMMAND — all 16 across the whole dataset

```powershell
cd analysis
python -c "import csv,collections,glob;tot=collections.Counter();nan=collections.Counter();cols=None
for f in sorted(glob.glob('*/*_topology/feature_table.csv')):
    rows=list(csv.DictReader(open(f)))
    if not rows: continue
    if cols is None: cols=[c for c in rows[0] if c[0].isupper() and c!='Label']
    for c in cols:
        tot[c]+=len(rows); nan[c]+=sum(1 for r in rows if r[c] in ('','nan','NaN'))
print('%-24s %10s'%('feature','populated'))
[print('%-24s %10d'%(c,tot[c]-nan[c])) for c in cols]"
cd ..
```

### 📋 SCREENSHOT — this is your M7 slide
```
feature                   populated
RetryRate                     14430
ParentSwitchRate              14430
LayerChangeCount              14430
HopStabilityDuration          14430
RSSI_mean                     14430
RSSI_var                      14430
RSSI_stability                14430
RSSI_Hop_Diff                 14430
PDR                            9718
LatencyHopRatio                7239
TunnelIntensity                2338
TunnelBytes                    2338
IngressEgressDelta             1204
ForwardingRatio                1125
ConsistencyScore               1125
TunnelLatency                   299
```

> 🗣️ *"All sixteen Table 4.11 features, across 14,430 windows in the assembled dataset. **Every
> one is populated** — none is uniformly NaN. The counts differ because several features are
> role-exclusive by design, which is the next slide."*

---

## 📊 SLIDE — the three tiers, and why the counts differ ⭐

| Tier | Features | Populated on | Count |
|---|---|---|---:|
| **Universal** | `RetryRate`, `ParentSwitchRate`, `LayerChangeCount`, `HopStabilityDuration`, all four `RSSI_*` | every node, every run | **14,430** |
| **Victim-keyed** | `PDR`, `LatencyHopRatio` | nodes that originate probes | 9,718 / 7,239 |
| **Role-exclusive** | `ForwardingRatio`, `ConsistencyScore`, `IngressEgressDelta` | the blackhole relay only | ~1,125 |
| | `TunnelIntensity`, `TunnelBytes` | the two wormhole ends only | 2,338 |
| | `TunnelLatency` | Node B, while the tunnel is live | 299 |

> 🗣️ *"NaN here means **not applicable to this node role**, not missing data. Table 4.12 states
> it explicitly: tunnel fields are present only for attacker nodes during topology-distortion
> runs. A victim has no `ForwardingRatio` because it doesn't relay anything — that's a
> definition, not a gap.*
>
> *And the criterion is about the **assembled dataset**, not any one run. Per run type: baseline
> populates 10 of 16, blackhole 13, wormhole 13 — and 16 of 16 across the combined matrix,
> because every feature is populated by at least one run type."*

💡 **Say "not applicable, not missing"** before anyone reads the NaN counts as holes.

---

## 📍 The per-run view — what a single dataset looks like

```powershell
cd analysis
python features.py ..\tools\exports\wormhole\star_topology\trimmed -o wormhole\star_topology\feature_table.csv
cd ..
```

### 📋 SCREENSHOT the NaN report
```
── Feature NaN Counts ──────────────────────────────
  RetryRate: 0/2531 NaN
  PDR: 828/2531 NaN [1703 value(s) on 4 node(s) — not applicable elsewhere]
  TunnelIntensity: 1660/2531 NaN [871 value(s) on 2 node(s) — not applicable elsewhere]
  TunnelLatency: 2420/2531 NaN [111 value(s) on 1 node(s) — not applicable elsewhere]
  ForwardingRatio: 2531/2531 NaN [all-NaN — RELAY-NODE ONLY: needs a blackhole run]
─────────────────────────────────────────────────────
```

> 🗣️ *"The report tells you **which nodes** carry each feature, so a NaN count can be checked
> rather than assumed. `TunnelIntensity` on two nodes is the two tunnel ends; `ForwardingRatio`
> all-NaN here is correct — this is a wormhole run, there's no blackhole relay in it."*

---

## 📊 The two recovered features — worth 30 seconds

### `LatencyHopRatio` — 7,239 windows
> 🗣️ *"Originally NaN everywhere because the probe protocol has no round-trip leg. It's now
> computed as a **relative one-way delay** instead of mean RTT — deviation **D-2**, recorded with
> the reasoning and what it would take to restore literally."*

### `TunnelLatency` — 299 windows
> 🗣️ *"Same story. Rather than a UART echo round-trip, it's the **divergence between the two
> arrivals of the same probe** — the mesh copy and the tunnelled copy. Deviation **D-3**."*

### 📍 Show the divergence directly
```powershell
cd tools\exports\wormhole
python -c "import csv,glob,collections,statistics as st;f=glob.glob('linear_topology/trimmed/*_r1_*arrivals.csv')[0];rows=[r for r in csv.DictReader(open(f)) if r['phase_id']=='2'];g=collections.defaultdict(list);[g[(r['src_mac'],r['seq_num'])].append(int(r['latency_us'])) for r in rows];d=[max(v)-min(v) for v in g.values() if len(v)==2];print('%d duplicate pairs, median divergence %.1f ms'%(len(d),st.median(d)/1000))"
cd ..\..\..
```
```
181 duplicate pairs, median divergence 9.8 ms
```

> ⚠️ **Both deviations are documented, not hidden.** If asked whether this still satisfies
> Table 4.12: *"the keying differs — it's the manipulated traffic rather than the attacker node —
> and that's recorded in `thesis-deviate.md` D-3, flagged for adviser sign-off."*

---

## 📄 The feature table itself

```powershell
cd analysis
python -c "import csv;r=list(csv.DictReader(open('wormhole/star_topology/feature_table.csv')));print('columns:',len(r[0]));print('rows:',len(r));print();[print(' ',c) for c in list(r[0])[:12]]"
cd ..
```

> 🗣️ *"Each row is one node-window with its 16 features, plus identifiers — node, source file,
> window start, phase, label, and `run_repeat`, which we added so per-repeat variance stays
> recoverable from the published table."*

---

## 🗣️ 75-second script

> *"M7 computes the sixteen Table 4.11 features from the windowed dataset.*
>
> *\[headline table] All sixteen are populated across the assembled dataset — 14,430 windows.
> None is uniformly NaN.*
>
> *\[tiers slide] The counts differ because features are role-scoped. Eight are universal —
> every node, every run. `PDR` and `LatencyHopRatio` are keyed to nodes that originate probes.
> And the relay and tunnel features exist only on the attacker roles, which Table 4.12 specifies
> directly. **NaN there means not applicable, not missing.***
>
> *Two features were NaN in every run three days ago — `LatencyHopRatio` and `TunnelLatency`.
> Both now populate, via documented deviations D-2 and D-3: relative one-way delay instead of
> RTT, and duplicate-arrival divergence instead of a UART echo. \[divergence output] That
> divergence measures at about **10 milliseconds** between the mesh copy and the tunnelled
> copy."*

---

## 🛡️ Questions

**"Why is `TunnelIntensity` NaN on most rows?"** ⭐
> *"It's attacker-keyed by design — Table 4.12 says tunnel fields are present only for attacker
> nodes. It populates on both tunnel ends and nowhere else: 2,338 windows across the dataset.
> Role-exclusive, not missing."*

**"Doesn't 299 windows for `TunnelLatency` seem very few?"**
> *"It's Node B only, and only while the tunnel is actively carrying traffic — the attack window.
> That's about 37 windows per wormhole run, and we have six wormhole cells. The number is small
> because the scope is narrow, not because samples are lost."*

**"Is your `LatencyHopRatio` still the Table 4.14 feature?"**
> *"It's the same quantity in spirit — per-hop delay — but computed as relative one-way delay
> rather than mean RTT, because the probe protocol has no response leg. It's deviation D-2 with
> the restoration path written down: add a root-to-victim response message. That's a firmware
> change that would invalidate every run already captured, so it's deferred to CTTHES3."*

**"Could you just drop the features that are mostly NaN?"**
> *"We'd lose the attack-specific evidence — `ForwardingRatio` and `TunnelIntensity` are the
> features that most directly express what each attack does. They're sparse because attacker
> roles are sparse, which is a property of the experiment, not the data."*

---

## ✅ Checklist
- [ ] Headline table — all 16 populated across 14,430 windows
- [ ] Three-tiers slide *(universal / victim-keyed / role-exclusive)*
- [ ] Per-run NaN report from `features.py`
- [ ] The two recovered features + the ~10 ms divergence output
- [ ] `thesis-deviate.md` open at D-2 and D-3
- [ ] Know: **16/16 populated** · **14,430 windows** · **~10 ms divergence**
- [ ] Say **"not applicable, not missing"** before showing any NaN count
