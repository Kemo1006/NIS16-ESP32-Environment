# M3 — Multi-Topology Testbed Deployment (15%)

How to **test** Milestone 3. The tooling itself is not moved here — it lives with
the rest of the host-side scripts in [`../tools/verify_topology.py`](../tools/verify_topology.py)
(wired to the firmware run workflow via `run.ps1`); this folder is its
documentation home. See [`../../ATTACKS.md`](../../ATTACKS.md) for the full
multi-topology runbook and [`../../MILESTONES.md`](../../MILESTONES.md) for status.

## What M3 has to prove

Two things: (a) the topology-shaping firmware knob (`-DMESH_TOPOLOGY=N`) actually
biases the mesh into the intended shape, and (b) the reconstructed tree matches
what you intended and converged within the 60 s criterion.

The four shapes are real firmware knobs (`components/mesh_common/mesh_setup.c`,
build-verified zero-warning): **STAR (0)**, **TREE (1, default)**,
**LINEAR (2)**, **PARTIAL (3)**.

## Test it NOW — no hardware needed

`verify_topology.py` reconstructs the mesh from the `parent_mac` + `layer`
columns of already-exported `telem.csv` files. Run it against the captured
**tree** run that already exists in `tools/exports/`:

```powershell
cd tools
python verify_topology.py --dir exports --files exports/*_telem.csv --expect tree
```

Expected output (verified): reconstructs a depth-3 tree, prints
`PASS tree: multi-hop depth 3 with intermediate forwarders`, and
`Converged within 60s: YES`.

> ⚠️ On the current capture it also prints `Baseline re-routing free: NO` — two
> nodes switched parent once during baseline. That's real ESP-WIFI-MESH RSSI
> re-optimisation, not a bug; be ready to explain it to the panel.

## Full test — needs the boards

Build **every** board in the run with the same topology flag, run ~8-10 min,
export, then verify against `--expect`. `run.ps1` passes the right
`-DMESH_TOPOLOGY=N`. Boot order matters: **victims first, root LAST** (its 60 s
stabilise window must overlap the victims' join — see `ATTACKS.md`). Ports below
are the confirmed 4-board matrix from
[`../../ATTACKS-Commands.md`](../../ATTACKS-Commands.md):

```powershell
# example: STAR baseline run (do the same -Topology on EVERY board, each in its own shell)
.\run.ps1 -Port COM25 -Role victim -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM26 -Role victim -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role victim -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology star -Wipe -Flash -Export   # root LAST

# then verify the exported CSVs match the intended shape
cd tools
python verify_topology.py --dir exports --topology star --attack none --repeat 1 --expect star
```

Repeat for `tree`, `linear`, `partial`, and for the blackhole/wormhole variants of
each (full per-cell commands, including attacker/control roles, are in
`ATTACKS-Commands.md`, or generate them with `run_matrix.py --cmds` — see
"Tracking the captures" below). Each board logs its active shaping at boot:
`MESH_SETUP: Topology shaping: STAR (max_layer=2, max_children=...)`.

## Tracking the captures — `../tools/run_matrix.py` (M4)

M3's 4 topologies are one axis of M4's 24-cell matrix (topology × attack ×
repeat). [`../m4_execution/README.md`](../m4_execution/README.md) covers
`run_matrix.py`, which emits the correct per-board `run.ps1` block for any
topology/attack cell (in the right boot order) and records a cell done only
after `validate_integrity.py` passes — use it instead of hand-assembling the
commands above for anything beyond a quick baseline check.

## Status & the gap

**PARTIAL.** The knob + verifier work and build-verify, but only a **tree** run
has been captured end-to-end. To reach COMPLETE, physically deploy and capture
**star / linear / partial** too — it's a data-collection gap, not a code gap.
`run_matrix.py` now tracks which cells are captured, but placing boards and
flashing each one is still manual — there's no unattended multi-board sweep.
