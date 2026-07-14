# ATTACKS-Commands.md — full command matrix (4-board setup)

> ⬅️ Companion to [`ATTACKS.md`](ATTACKS.md) (attack/topology mechanics, boot
> order, signatures, and the [official topology diagrams](ATTACKS.md#topology-diagrams-thesis-proposal-4-2-2-figures-4-16-4-23))
> and [`WORKFLOWS.md`](WORKFLOWS.md) (build/flash basics). Every `run.ps1`
> command below is copy-pasteable — swap ports if your board layout differs.
> (This file is allowed to run long — it's a reference, not prose.)

## Board assignment (all 4 confirmed boards: COM20, COM21, COM25, COM26)

| Port | Baseline run | Blackhole run | Wormhole run |
|---|---|---|---|
| **COM20** | root | root (announces phase) | root (announces phase) |
| **COM25** | plain victim | **attacker** (`blackhole_victim.c`) | **Node A** (exit, `-WormholeEnd A`) |
| **COM26** | plain victim | control (plain, unaffected) | **Node B** (entry, `-WormholeEnd B`) |
| **COM21** | plain victim | control (plain, unaffected) | control (plain, unaffected) |

Control victims get **no `-Attack` flag** (`run.ps1` defaults to `-Attack none`,
which safely clears any previously-cached attack build) — they still take the
same `-Topology` as everyone else so the mesh shape is correct, they just don't
run attacker firmware.

### Diagram node ↔ board mapping (proposal Figs 4.16–4.23)

Each figure draws **6 nodes**; the testbed has **4 boards**, so COM26/COM21 stand
in for the figures' extra normal `NODE 3/4/5/6`. The attack is always emulated on
a **victim-role board** running attack firmware — the root only *announces/labels*
the attack phase ([`root_main.c`](NIS16-ESP32-Environment/root_node/main/root_main.c)
phase broadcast), it never drops or tunnels packets:

| Board | Wormhole figs — 4.16 star · 4.18 tree · 4.20 linear · 4.22 partial | Blackhole figs — 4.19 tree · 4.21 linear · 4.23 partial |
|---|---|---|
| **COM20** | `ROOT` | `ROOT` (announces the phase, does **not** drop) |
| **COM25** | `ATTACKER A` | `ATTACKER` |
| **COM26** | `ATTACKER B` | normal `NODE` (control) |
| **COM21** | normal `NODE` (control) | normal `NODE` (control) |

Which normal nodes land *behind* the attacker (the figures' "PACKETS DROPPED"
ones) is set by the self-organised mesh position, **not** by port choice — the
commands can't force it; confirm the real shape with `verify_topology.py`.

> ⚠️ **Star + blackhole (Fig 4.17) is the one case the boards can't match as
> drawn.** It puts the attacker on the **ROOT** (`ROOT (ATTACKER)`, all five
> leaves dropped), but `root_node` has no packet-drop path today (only the
> phase-announce one), so the testbed currently keeps **COM25** as the
> star-blackhole attacker. Matching Fig 4.17 literally would need **new root
> firmware** — see the decision flagged below the star block.

Boot order (always): **victims first, root LAST** — the root's phase clock
starts at its own boot and won't wait for children.

## Where exports land (auto-routed) — and the control-victim safeguard

With `-Export`, each board's CSV is auto-filed into
`tools/exports/<attack>/<topology>_topology/` — e.g. blackhole-on-star →
`exports/blackhole/star_topology/`, a plain baseline-on-tree →
`exports/baseline/tree_topology/`. No manual sorting; the four topologies never
mix. See [`tools/README.md`](NIS16-ESP32-Environment/tools/README.md).

⚠️ **SAFEGUARD — a control victim in an attack run needs `-DestAttack`.** A
control board is flashed `-Attack none`, so *by default its CSV would land in
`exports/baseline/…`* — split off from the very attack run it's the control for,
corrupting that run's dataset with a file in the wrong folder. Adding
**`-DestAttack blackhole`** (or `-DestAttack wormhole`) files it **with the
run** (`exports/wormhole/…`) while the board still runs plain — no attack
firmware, filename still reads `none`. Only the export folder changes.

```powershell
# WRONG — COM21 control in a wormhole run, exports to exports/BASELINE/... (wrong folder):
.\run.ps1 -Port COM21 -Role victim                     -Topology linear -Wipe -Flash -Export
# RIGHT — same board, -DestAttack routes it into exports/WORMHOLE/linear_topology/:
.\run.ps1 -Port COM21 -Role victim -DestAttack wormhole -Topology linear -Wipe -Flash -Export
```

Every **with-export** attack block below already includes `-DestAttack` on its
control line(s). It only affects `-Export`, so the **without-export** (dry-run)
blocks omit it.

## One command from Ctrl+] to feature_table.csv + EDA — `-Analyze`

`-Analyze` implies `-Export`: it exports the board's CSVs (same auto-routing as
above) **and then** runs the full pipeline over that run's whole
`exports/<attack>/<topology>_topology/` folder — M6 (`windowed_dataset.csv`), M7
(`feature_table.csv`), and M8/EDA (`eda_output/`), all written into the
mirroring `analysis/<attack>/<topology>_topology/`. See
[`analysis/analysis_README.md`](NIS16-ESP32-Environment/analysis/analysis_README.md).

Every **"with export"** block below puts `-Analyze` on the **root's** line —
root boots last, so by the time it runs every other board's CSV (plus root's own
`arrivals.csv`, needed for PDR) is already in the exports folder, and `-Analyze`
picks up all of them in one pass. Victim lines keep plain `-Export` — analyzing
per-victim would only see a partial, PDR-less folder. If a board has no
pandas/numpy python available, `-Analyze` skips analysis with a warning but still
leaves the CSVs safely exported; if it has pandas but not the M8 plotting deps
(matplotlib/seaborn/scipy/scikit-learn), it does M6+M7 and skips only M8 —
nothing is lost either way.

---

## Baseline — no attack (all boards plain victims)

Pure baseline capture: every victim is a normal probe generator, no attacker.
These land in `exports/baseline/<topology>_topology/` — that IS the correct
folder, so **no `-DestAttack` here**.

### Baseline · star
```powershell
# without export (dry run):
.\run.ps1 -Port COM25 -Role victim -Topology star -Wipe -Flash
.\run.ps1 -Port COM26 -Role victim -Topology star -Wipe -Flash
.\run.ps1 -Port COM21 -Role victim -Topology star -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology star -Wipe -Flash
# with export + auto-analyze -> exports/baseline/star_topology/ + analysis/baseline/star_topology/:
.\run.ps1 -Port COM25 -Role victim -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM26 -Role victim -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role victim -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology star -Wipe -Flash -Analyze
```

### Baseline · tree
```powershell
# without export (dry run):
.\run.ps1 -Port COM25 -Role victim -Topology tree -Wipe -Flash
.\run.ps1 -Port COM26 -Role victim -Topology tree -Wipe -Flash
.\run.ps1 -Port COM21 -Role victim -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology tree -Wipe -Flash
# with export + auto-analyze -> exports/baseline/tree_topology/ + analysis/baseline/tree_topology/:
.\run.ps1 -Port COM25 -Role victim -Topology tree -Wipe -Flash -Export
.\run.ps1 -Port COM26 -Role victim -Topology tree -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role victim -Topology tree -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology tree -Wipe -Flash -Analyze
```

### Baseline · linear
```powershell
# without export (dry run):
.\run.ps1 -Port COM25 -Role victim -Topology linear -Wipe -Flash
.\run.ps1 -Port COM26 -Role victim -Topology linear -Wipe -Flash
.\run.ps1 -Port COM21 -Role victim -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology linear -Wipe -Flash
# with export + auto-analyze -> exports/baseline/linear_topology/ + analysis/baseline/linear_topology/:
.\run.ps1 -Port COM25 -Role victim -Topology linear -Wipe -Flash -Export
.\run.ps1 -Port COM26 -Role victim -Topology linear -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role victim -Topology linear -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology linear -Wipe -Flash -Analyze
```

### Baseline · partial
```powershell
# without export (dry run):
.\run.ps1 -Port COM25 -Role victim -Topology partial -Wipe -Flash
.\run.ps1 -Port COM26 -Role victim -Topology partial -Wipe -Flash
.\run.ps1 -Port COM21 -Role victim -Topology partial -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology partial -Wipe -Flash
# with export + auto-analyze -> exports/baseline/partial_mesh_topology/ + analysis/baseline/partial_mesh_topology/:
.\run.ps1 -Port COM25 -Role victim -Topology partial -Wipe -Flash -Export
.\run.ps1 -Port COM26 -Role victim -Topology partial -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role victim -Topology partial -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology partial -Wipe -Flash -Analyze
```

---

## Star topology (`-Topology star`, N=0 — every node a direct child of root)

**Blackhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole -Topology star -Wipe -Flash  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim                   -Topology star -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role victim                   -Topology star -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack blackhole -Topology star -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Blackhole, with export + auto-analyze** (controls carry `-DestAttack blackhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole      -Topology star -Wipe -Flash -Export  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -DestAttack blackhole  -Topology star -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM21 -Role victim -DestAttack blackhole  -Topology star -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack blackhole      -Topology star -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

> 🔻 **DECISION — star blackhole vs. Fig 4.17.** The proposal figure draws the
> **ROOT** as the blackhole attacker; the block above keeps **COM25** as the
> attacker (root only announces the phase) because `root_node` has no drop path.
> The two ways to reconcile: **(A)** keep COM25 as the attacker and amend Fig 4.17
> to a leaf-attacker (documentation change), or **(B)** add a blackhole drop path
> to `root_node` so the root can be the real attacker for star (firmware change).
> Not yet resolved — pick one before defending the star-blackhole result.

**Wormhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology star -Wipe -Flash  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology star -Wipe -Flash  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim                                 -Topology star -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology star -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Wormhole, with export + auto-analyze** (control carries `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology star -Wipe -Flash -Export  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology star -Wipe -Flash -Export  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim -DestAttack wormhole            -Topology star -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology star -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

## Tree topology (`-Topology tree`, N=1, default — native self-organising, multi-hop)

**Blackhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole -Topology tree -Wipe -Flash  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim                   -Topology tree -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role victim                   -Topology tree -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack blackhole -Topology tree -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Blackhole, with export + auto-analyze** (controls carry `-DestAttack blackhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole      -Topology tree -Wipe -Flash -Export  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -DestAttack blackhole  -Topology tree -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM21 -Role victim -DestAttack blackhole  -Topology tree -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack blackhole      -Topology tree -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

**Wormhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology tree -Wipe -Flash  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology tree -Wipe -Flash  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim                                 -Topology tree -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology tree -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Wormhole, with export + auto-analyze** (control carries `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology tree -Wipe -Flash -Export  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology tree -Wipe -Flash -Export  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim -DestAttack wormhole            -Topology tree -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology tree -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

*(Tree is the only topology with a real hardware capture so far — the
`..._tree_..._2343*` / `..._0350*` data already in `tools/exports/`.)*

## Linear topology (`-Topology linear`, N=2 — forced chain, 1 child/node)

**Blackhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole -Topology linear -Wipe -Flash  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim                   -Topology linear -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role victim                   -Topology linear -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack blackhole -Topology linear -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Blackhole, with export + auto-analyze** (controls carry `-DestAttack blackhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole      -Topology linear -Wipe -Flash -Export  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -DestAttack blackhole  -Topology linear -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM21 -Role victim -DestAttack blackhole  -Topology linear -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack blackhole      -Topology linear -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

**Wormhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology linear -Wipe -Flash  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology linear -Wipe -Flash  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim                                 -Topology linear -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology linear -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Wormhole, with export + auto-analyze** (control carries `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology linear -Wipe -Flash -Export  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology linear -Wipe -Flash -Export  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim -DestAttack wormhole            -Topology linear -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology linear -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

*Chain order (root→COM25→COM26→COM21 or whatever the RSSI-driven chain forms)
isn't controllable by port choice — physical placement decides link order.
Confirm the resulting chain with `verify_topology.py --expect linear`.*

## Partial-mesh topology (`-Topology partial`, N=3 — fan-out capped at 2)

**Blackhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole -Topology partial -Wipe -Flash  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim                   -Topology partial -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role victim                   -Topology partial -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack blackhole -Topology partial -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Blackhole, with export + auto-analyze** (controls carry `-DestAttack blackhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack blackhole      -Topology partial -Wipe -Flash -Export  # REAL attacker (blackhole firmware) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -DestAttack blackhole  -Topology partial -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM21 -Role victim -DestAttack blackhole  -Topology partial -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack blackhole      -Topology partial -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

**Wormhole, without export:**
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology partial -Wipe -Flash  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology partial -Wipe -Flash  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim                                 -Topology partial -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology partial -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```
**Wormhole, with export + auto-analyze** (control carries `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM25 -Role victim -Attack wormhole -WormholeEnd A -Topology partial -Wipe -Flash -Export  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM26 -Role victim -Attack wormhole -WormholeEnd B -Topology partial -Wipe -Flash -Export  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM21 -Role victim -DestAttack wormhole            -Topology partial -Wipe -Flash -Export  # control -- plain victim firmware, no attack (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology partial -Wipe -Flash -Analyze  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT drop/tunnel packets -- COM25 (attacker firmware) does
```

---

## Notes that apply to every block above

- **`-DestAttack` is the dataset safeguard** — it keeps a control victim's CSV
  in the same `<attack>/<topology>_topology/` folder as the run it belongs to,
  so no stray `none` file lands in `baseline/` and confuses the dataset. It
  changes ONLY the export folder — never the firmware (still plain victim) nor
  the filename (still `..._none_...`).
- **`-Export` just auto-pulls CSVs on Ctrl+]; `-Analyze` also builds
  `feature_table.csv`** — the run itself is identical regardless of either
  flag. Drop both (and `-DestAttack`, which only affects export/analysis
  routing) for a dry run that leaves data on the board.
- **`WORMHOLE_NODE_A_MAC`** in `mesh_config.h` must be set to COM25's STA MAC
  before any wormhole build (Node A prints it at boot) — see `ATTACKS.md`.
- Only **tree** is physically verified today (🟠 ORANGE in `thesis-deviate.md`'s
  M3 status table) — star/linear/partial build-verify but have no hardware
  capture yet. Baseline + both attacks across all four topologies is the full
  grid to close that gap.
- None of the 4 boards have been reflashed with the 20 Hz / 4MB config yet —
  see `thesis-deviate.md` before starting a fresh capture round.
