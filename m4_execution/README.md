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
.\run.ps1 -Port COM3 -Role child  -Wipe -Flash -Export
```

Confirm in the root monitor that it announces baseline → attack → cooldown →
terminate on schedule, then confirm the exported CSVs show the same `phase_id`
progression on every node.

## Drive the 24-cell matrix — `../tools/run_matrix.py`

`run_matrix.py` (ported + adapted from `Carlos(Testing)`, 2026-07-14) is the
bookkeeping + command generator for the full **4 topologies × 2 attacks × ≥3
repeats = 24** matrix. It does **not** flash boards (placement + the ~10-min run
stay manual) — it removes the "which run am I on / what were the flags" errors:

```powershell
cd tools
python run_matrix.py --status                                   # progress grid + next pending
python run_matrix.py --cmds --topology tree --attack blackhole  # exact run.ps1 block for a cell,
                                                                #   in boot order (victims first, root last)
python run_matrix.py --next                                     # next pending cell + its block
# after running + exporting a cell on the boards:
python run_matrix.py --record --topology tree --attack blackhole --repeat 1
#   -> finds the cell's CSVs, runs validate_integrity.py, and marks it done
#      in exports/run_ledger.csv ONLY if root+3 victims are present and validation passes.
```

The emitted commands mirror [`../../ATTACKS-Commands.md`](../../ATTACKS-Commands.md)
exactly (board→role from its Board-assignment table). `--export-cmds` prints the
standalone `export_logs.py` fallback for a cell run without `-Export`. Use
`--sample-interval-ms 1000` on `--record` for pre-2026-07-12 (1 Hz) captures.

## Status & the gap

**PARTIAL.** The phase controller + `ACTIVE_ATTACK` override work, and
`run_matrix.py` now organises/validates the matrix. What remains is a
**data-collection** gap, not a tooling one: the physical 24 runs still have to be
executed on the boards (only tree/wormhole/r1 is captured + recorded so far), and
each cell is still triggered one board at a time (no single-command unattended
sweep across boards).
