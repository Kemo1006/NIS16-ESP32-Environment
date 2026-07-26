# 🎬 M4 Demo Script — Phase-Controlled Experiment Execution (15%)

> ## 📋 Criterion *(from `run_matrix.py`, your own tool's specification)*
> **≥ 24 runs = 4 topologies × 2 attacks × ≥ 3 repeats.**
> A cell is marked done **only** once its exported CSVs pass `validate_integrity.py`.
>
> ⚠️ **Paste M4's full criteria if the form lists more** — e.g. wording about phase control or
> repeat independence. This script covers the count, the phase control, and the validation gate.

> ## 🎯 This is your honest slide. It is also your most credible one.
> **10 of 24.** Volunteering a shortfall with a clear plan reads as control. Being caught
> hiding it reads as the opposite. Hold the slide, let them read it, don't fill the silence.

---

## 📊 SLIDE 1 — The matrix ⚡ *safe to run live*

```powershell
python tools\run_matrix.py --status
```
Two seconds. No hardware. Reads a local CSV ledger. **This is the only live command worth
running in the room.**

```
topology  attack     r1  r2  r3
-------------------------------
star      blackhole  [x]  [ ]  [ ]
star      wormhole   [x]  [x]  [x]
tree      blackhole  [ ]  [ ]  [ ]
tree      wormhole   [ ]  [ ]  [ ]
linear    blackhole  [x]  [x]  [x]
linear    wormhole   [x]  [x]  [x]
partial   blackhole  [ ]  [ ]  [ ]
partial   wormhole   [ ]  [ ]  [ ]

Progress: 10/24 runs collected (Milestone-4 minimum is 24)
```

> 🗣️ *"Ten of twenty-four. **Three cells fully replicated** at three repeats each — linear
> blackhole, linear wormhole, and star wormhole. Every recorded cell passed validation with
> **zero failures**. What remains is runtime: roughly eleven minutes per run plus exports.
> There are no unknowns left in the method — only runs left to do."*

> ⚠️ **Hold this slide for a beat.** The instinct to rush past it is exactly what makes it look
> bad. Two seconds of silence while they read is fine.

> 📌 **Re-run the morning of.** This number has moved four times in the last day.

---

## 📊 SLIDE 2 — What "phase-controlled" means ⭐ *the milestone's actual subject*

This is the part people forget to present. The milestone isn't just *"do 24 runs"* — it's
*"phase-controlled execution."*

```
┌─────────────────────────┬──────────────────┬────────────┐
│  phase 0 · BASELINE     │ phase 1/2 ATTACK │ phase 3    │
│  300 s   gt_label = 0   │ 180 s  label 1/2 │ COOLDOWN   │
└─────────────────────────┴──────────────────┴────────────┘
   60 s stabilise before  ·  blackhole = 1  ·  wormhole = 2
```

Live evidence from the root:
```
I (64680)  ROOT_MAIN:      ════════ PHASE 0 — BASELINE ════════
I (65240)  PHASE_LISTENER: [ROOT] Broadcast phase_id=0  seq=1  label=0  (0 failed sends)
I (365240) ROOT_MAIN:      ════════ PHASE — ATTACK ════════
I (365770) PHASE_LISTENER: [ROOT] Broadcast phase_id=2  seq=2  label=2  (0 failed sends)
```

> 🗣️ *"Every run follows the same controlled timeline. The **root** drives it — it broadcasts
> the phase ID, and every node stamps that ID into every telemetry row. So the experiment
> controls the labelling; there's no manual annotation step. `0 failed sends` means every node
> acknowledged the transition."*

---

## 📄 SLIDE 3 — The audit trail

`tools/exports/run_ledger.csv`
```
topology,attack,repeat,status,recorded_at,files
linear,blackhole,1,done,2026-07-26 17:06:38,child_node2_...;child_node3_...;...
linear,blackhole,2,done,2026-07-26 17:06:32,...
linear,blackhole,3,done,2026-07-26 17:22:05,...
```

> 🗣️ *"One row per recorded cell: topology, attack, repeat, when it was validated, and every
> file that was checked. This is what's behind the grid — the grid is a rendering of this."*

---

## 📊 SLIDE 4 — The gate that makes the count trustworthy ⭐

> 🗣️ *"A cell can't be ticked by hand. `--record` runs `validate_integrity.py` **first** and
> refuses on any FAIL. So '10 of 24' doesn't mean 'we ran 10 times' — it means **10 cells
> produced data that passed every integrity check**."*

And the guard that came from a real mistake:

> 🗣️ *"We also lost a run early on to a mistyped `--repeat` — it silently re-recorded the
> previous repeat while a complete run sat on disk unticked. `--autorecord` now reads the
> repeat number off the filenames instead of asking us to type it. That's the flag we use now."*

💡 This is a strong 20 seconds. It shows the count is defended, not just reported.

---

## 🗣️ The 90-second M4 script

> *"M4 is phase-controlled execution — the 24-run matrix.*
>
> *\[slide 2] Every run follows the same controlled timeline: 60 seconds to stabilise, five
> minutes baseline, three minutes attack, two minutes cooldown. The root broadcasts each phase
> ID and every node stamps it into every row, so the experiment produces its own labels.*
>
> *\[slide 1 — run it live] Ten of twenty-four. Three cells fully replicated at three repeats.
> Every recorded cell zero-FAIL.*
>
> *\[slide 4] And a cell can only be marked done once its files pass validation — the ledger
> can't be ticked by hand. So this number means ten cells produced data that passed every
> integrity check, not ten attempts.*
>
> *What remains is runtime. The method, the tooling and the analysis pipeline are complete and
> exercised on three cells end-to-end."*

---

## 🛡️ M4 questions

**"Your matrix is less than half complete."** ⭐ *expect this*
> *"Correct — ten of twenty-four. Three cells fully replicated, every recorded cell zero-FAIL.
> The infrastructure and analysis are done and proven on those three; what's left is about
> eleven minutes of runtime per run plus exports. I'd rather present ten validated cells than
> twenty-four unvalidated ones."*

**"Why three repeats?"**
> *"The milestone specifies at least three. It's what turns a signature into a reproducible
> result rather than a one-off — the wormhole came out at 181, 181, 180 and 180 across four
> runs on two topologies."*

**"Are the repeats independent?"**
> *"Boards are cleared between repeats and the mesh re-forms from scratch each time — parents
> are re-chosen by signal at boot. So they're independent runs of the same configuration, not
> re-slices of one capture. One consequence, recorded as deviation **D-6**: the topology class
> is fixed but the specific parent assignment varies between repeats."*

**"How do you stop a cell being marked done by mistake?"**
> *(See slide 4 — the validation gate and `--autorecord`.)*

**"What if a run fails partway?"**
> *"It doesn't get recorded. Validation runs first and refuses on any FAIL, so the cell stays
> pending. We've had exports fail — a device sent the wrong file once — and the guard caught it
> at capture time rather than twenty minutes later in analysis."*

**"Which cells will you do next?"**
> *"Star blackhole r2 and r3 — the boards are already placed for star, so it's the cheapest
> next runs. Then tree, then partial."*

---

## ✅ M4 checklist

- [ ] ⚠️ **Re-run `--status` the morning of** — the number keeps moving
- [ ] Screenshot as backup in case the live command fails
- [ ] `run_ledger.csv` open in a second window
- [ ] Phase-timeline diagram on a slide *(the milestone's actual subject)*
- [ ] Boot-log lines showing `Broadcast phase_id=... (0 failed sends)`
- [ ] Know: **10/24** · **3 cells at 3/3** · **0 FAIL** · **~11 min per run**
- [ ] Rehearse **holding the slide** without apologising for the number
