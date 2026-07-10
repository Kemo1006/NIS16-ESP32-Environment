# M4 — Phase-Controlled Experiment Execution (15%)

How to **test** Milestone 4. No script is moved here — the phase controller is
**firmware** (the root board broadcasts phase transitions; `phase_listener.c`
tags every telemetry row), and the host-side run wrapper is
[`../run.ps1`](../run.ps1). This folder is M4's documentation home. See
[`../../WORKFLOWS.md`](../../WORKFLOWS.md) (build/flash + `run.ps1`) and
[`../../MILESTONES.md`](../../MILESTONES.md) for status.

## What M4 has to prove

The root drives the experiment through its phase timeline
(**baseline → attack → cooldown → terminate**) automatically, and every
telemetry row is tagged with the phase that was active when it was sampled.

Phase IDs (from `components/mesh_common/include/mesh_config.h`): baseline=0,
blackhole=1, wormhole=2, cooldown=3, terminate=4. `gt_label` collapses
cooldown/terminate to 0 (normal).

## Test it NOW — no hardware needed

Every exported `telem.csv` carries `phase_id` + `gt_label` columns. Their
sequence IS the phase controller's fingerprint. On the captured wormhole root:

```powershell
cd tools
python -c "import pandas as pd,glob; d=pd.read_csv(glob.glob('exports/root_*telem.csv')[0]); print(d['phase_id'].value_counts().sort_index())"
```

Verified output — a clean, ordered timeline:
`phase_id 0 (baseline, 358 rows) -> 2 (wormhole, 179 rows) -> 3 (cooldown, 118 rows)`,
with `gt_label` mapping correctly (wormhole→2, cooldown→0). That single sequence
demonstrates the root sequenced the phases and the tagging propagated to victims.

## Full test — needs the boards

Flash + run, and watch the **root monitor** print each phase transition live over
the ~8-minute timeline:

```powershell
.\run.ps1 -Port COM8 -Role root   -Wipe -Flash -Export
.\run.ps1 -Port COM3 -Role victim -Wipe -Flash -Export
```

Confirm in the root monitor that it announces baseline → attack → cooldown →
terminate on schedule, then confirm the exported CSVs show the same `phase_id`
progression on every node.

## Status & the gap

**PARTIAL.** The phase controller + the `ACTIVE_ATTACK` override work, but runs
are triggered **by hand, one board at a time** — there is no `run_matrix.py` to
automate the full topologies × attacks × repeats matrix unattended. If the panel
expects automated matrix execution, that automation is the missing piece.
