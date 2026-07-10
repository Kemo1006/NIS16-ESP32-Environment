# M3 — Multi-Topology Testbed Deployment (15%)

How to **test** Milestone 3. The tooling itself is not moved here — it lives with
the rest of the host-side scripts in [`../tools/verify_topology.py`](../tools/verify_topology.py)
(wired to the firmware run workflow via `run.ps1`); this folder is its
documentation home. See [`../../WORKFLOWS.md`](../../WORKFLOWS.md) for the full
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

Build **every** board in the run with the same topology flag, run ~8 min, export,
then verify against `--expect`. `run.ps1` passes the right `-DMESH_TOPOLOGY=N`:

```powershell
# example: STAR run (do the same -Topology on EVERY board, each in its own shell)
.\run.ps1 -Port COM8 -Role root   -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM3 -Role victim -Topology star -Wipe -Flash -Export

# then verify the exported CSVs match the intended shape
cd tools
python verify_topology.py --dir exports --topology star --attack none --repeat 1 --expect star
```

Repeat for `tree`, `linear`, `partial`. Each board logs its active shaping at
boot: `MESH_SETUP: Topology shaping: STAR (max_layer=2, max_children=...)`.

## Status & the gap

**PARTIAL.** The knob + verifier work and build-verify, but only a **tree** run
has been captured end-to-end. To reach COMPLETE, physically deploy and capture
**star / linear / partial** too — it's a data-collection gap, not a code gap.
There is also no unattended sweep (runs are triggered by hand via
`run.ps1 -Topology`).
