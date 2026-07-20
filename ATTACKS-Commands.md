# ATTACKS-Commands.md — full command matrix (5-board setup)

> ⬅️ Companion to the per-scenario, step-by-step physical-setup guides:
> [`BASELINE-SETUP.md`](BASELINE-SETUP.md), [`BLACKHOLE-SETUP.md`](BLACKHOLE-SETUP.md),
> and [`WORMHOLE-SETUP.md`](WORMHOLE-SETUP.md) (which board is USB-connected vs.
> power-only at each step, phase timing, wiring, and verification). Those guides
> teach ONE run end-to-end; THIS file is the flat copy-paste command matrix for
> every attack × topology combination once you know the flow. Build/flash basics
> and the mesh/phase constants live in [`CLAUDE.md`](CLAUDE.md) and
> [`components/mesh_common/include/mesh_config.h`](components/mesh_common/include/mesh_config.h).
> Every `run.ps1` command below is copy-pasteable — swap ports if your board
> layout differs. (This file is allowed to run long — it's a reference, not prose.)
>
> **Phase timeline (all runs, from `mesh_config.h`):** 60 s stabilize → 300 s
> baseline (label 0) → [180 s attack (label 1 blackhole / 2 wormhole), attack
> runs only] → 120 s cooldown (label 0) → terminate. Baseline ≈ 8 min total;
> each attack run ≈ 11 min. The root's `experiment_controller_task` drives this
> clock on-chip and broadcasts every transition over the mesh — no board needs
> the laptop connected during the run itself (USB is only for flash + export).

## Board assignment (all 5 confirmed boards: COM20, COM21, COM25, COM26, COM27)

| Port | Baseline run | Blackhole run | Wormhole run |
|---|---|---|---|
| **COM20** | root | root (announces phase) | root (announces phase) |
| **COM26** | plain victim | **attacker relay** (`-BlackholeRole attacker`) | **Node A** (exit, `-WormholeEnd A`) |
| **COM27** | plain victim | **victim → attacker** (`-BlackholeRole victim`) | **Node B** (entry, `-WormholeEnd B`) |
| **COM25** | plain victim | **victim → attacker** (`-BlackholeRole victim`) | control (plain, unaffected) |
| **COM21** | plain victim | **victim → attacker** (`-BlackholeRole victim`) | control (plain, unaffected) |

### Board STA MACs (read with `esptool.py --port COMxx read_mac`)

| Port | STA MAC | Role note |
|---|---|---|
| **COM20** | `28:05:a5:32:d7:b4` | root |
| **COM26** | `b0:cb:d8:f3:32:18` | **blackhole attacker / wormhole Node A** — this is `BLACKHOLE_ATTACKER_MAC` |
| **COM27** | `f4:2d:c9:73:e6:18` | wormhole Node B / blackhole victim |
| **COM25** | `b4:bf:e9:34:ed:80` | control / blackhole victim |
| **COM21** | `b4:bf:e9:32:fe:90` | control / blackhole victim |

`BLACKHOLE_ATTACKER_MAC` in `mesh_config.h` is already set to COM26's MAC above
(`{0xB0, 0xCB, 0xD8, 0xF3, 0x32, 0x18}`). If you ever change which board is the
blackhole attacker, update that define to the new attacker's MAC from this table.

> 🕳️ **BLACKHOLE IS A RELAY MODEL** (thesis §4.2.1.2 C / Milestone 2). The
> attacker board no longer generates its own probes — it **relays** the victim
> boards' probes to root (baseline) or **drops** them (attack). So a blackhole
> run has THREE distinct roles, chosen with `-BlackholeRole`:
> - **attacker** (COM26): `-Attack blackhole -BlackholeRole attacker` → relay.
> - **victim** (COM25/COM27/COM21): `-Attack blackhole -BlackholeRole victim` → sends
>   its probes to the attacker's MAC (these are the boards whose traffic gets
>   dropped; they are NOT plain controls anymore).
> - **root** (COM20): `-Attack blackhole` → just announces the phase.
>
> **Set `BLACKHOLE_ATTACKER_MAC` in `mesh_config.h` to COM26's STA MAC before
> building** (read it with `.\tools\Get-EspMac.ps1 -Port COM26`, or from the
> attacker's boot log). The victim boards send to that MAC; if it's wrong, no
> probes reach the attacker and there's no signature. Full walkthrough:
> [`BLACKHOLE-SETUP.md`](BLACKHOLE-SETUP.md).

For **wormhole**, control victims get **no `-Attack` flag** (`run.ps1` defaults to
`-Attack none`) — they still take the same `-Topology` so the mesh shape is
correct, they just don't run attacker firmware.

> 🔌 **WORMHOLE RUNS NEED A PHYSICAL UART CABLE between COM26 (Node A) and
> COM27 (Node B).** Per Milestone 2 ("a wired UART link between A and B acts as
> the out-of-band tunnel... CRC-protected") and the thesis Figure 4.9, the A↔B
> tunnel is a real wire, **not** a WiFi/MAC message. Wire the two attacker
> boards **crossed** before powering them on — Node A TX2/GPIO17 → Node B
> RX2/GPIO16, Node A RX2/GPIO16 → Node B TX2/GPIO17, and shared GND (3 wires
> total; pins configurable via `WORMHOLE_UART_*` in `mesh_config.h`). This
> cable stays connected for the ENTIRE run (baseline + attack + cooldown), is
> separate from each board's USB-to-laptop cable, and is only needed for
> wormhole. **Verify the link with the `uart_link_test` loopback firmware BEFORE
> the real run** — flash it to both attacker boards and confirm `[LINK OK]`.
> Full wiring diagram + WROVER-PSRAM caveat: [`WORMHOLE-SETUP.md`](WORMHOLE-SETUP.md).
> Blackhole and baseline runs need no such cable.

### Diagram node ↔ board mapping (proposal Figs 4.16–4.23)

Each figure draws **6 nodes**; the testbed has **5 boards**, so COM25/COM21 stand
in for the figures' extra normal `NODE 3/4/5/6`. The attack is always emulated on
a **victim-role board** running attack firmware — the root only *announces/labels*
the attack phase ([`root_main.c`](NIS16-ESP32-Environment/root_node/main/root_main.c)
phase broadcast), it never drops or tunnels packets:

| Board | Wormhole figs — 4.16 star · 4.18 tree · 4.20 linear · 4.22 partial | Blackhole figs — 4.19 tree · 4.21 linear · 4.23 partial |
|---|---|---|
| **COM20** | `ROOT` | `ROOT` (announces the phase, does **not** drop) |
| **COM26** | `ATTACKER A` | `ATTACKER` |
| **COM27** | `ATTACKER B` | normal `NODE` (victim) |
| **COM25** | normal `NODE` (control) | normal `NODE` (victim) |
| **COM21** | normal `NODE` (control) | normal `NODE` (victim) |

Which normal nodes land *behind* the attacker (the figures' "PACKETS DROPPED"
ones) is set by the self-organised mesh position, **not** by port choice — the
commands can't force it; confirm the real shape with `verify_topology.py`.

> ⚠️ **Star + blackhole (Fig 4.17) is the one case the boards can't match as
> drawn.** It puts the attacker on the **ROOT** (`ROOT (ATTACKER)`, all five
> leaves dropped), but `root_node` has no packet-drop path today (only the
> phase-announce one), so the testbed currently keeps **COM26** as the
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
**`-DestAttack wormhole`** files it **with the run** (`exports/wormhole/…`) while
the board still runs plain — no attack firmware, filename still reads `none`.
Only the export folder changes. (Wormhole controls are COM25 and COM21.)

```powershell
# WRONG — COM25 control in a wormhole run, exports to exports/BASELINE/... (wrong folder):
.\run.ps1 -Port COM25 -Role child                      -Topology linear -Wipe -Flash -Export
# RIGHT — same board, -DestAttack routes it into exports/WORMHOLE/linear_topology/:
.\run.ps1 -Port COM25 -Role child  -DestAttack wormhole -Topology linear -Wipe -Flash -Export
```

Every **with-export** wormhole block below already includes `-DestAttack` on its
control lines. Blackhole victims are `-Attack blackhole`, so they auto-file into
`exports/blackhole/…` and need no `-DestAttack`.

## One command from Ctrl+] to feature_table.csv + EDA — `-Analyze`

`-Analyze` implies `-Export`: it exports the board's CSVs (same auto-routing as
above) **and then** runs the full pipeline over that run's whole
`exports/<attack>/<topology>_topology/` folder — M6 (`windowed_dataset.csv`), M7
(`feature_table.csv`), and M8/EDA (`eda_output/`), all written into the
mirroring `analysis/<attack>/<topology>_topology/`. See
[`analysis/analysis_README.md`](NIS16-ESP32-Environment/analysis/analysis_README.md).

Put `-Analyze` on the **root's** line only — root boots last, so by the time it
runs every other board's CSV (plus root's own `arrivals.csv`, needed for PDR) is
already in the exports folder, and `-Analyze` picks up all of them in one pass.
Victim lines keep plain `-Export`.

---

## Baseline — no attack (all boards plain victims)

Pure baseline capture: every victim is a normal probe generator, no attacker.
These land in `exports/baseline/<topology>_topology/` — that IS the correct
folder, so **no `-DestAttack` here**.

### Baseline · star
```powershell
# without export (dry run):
.\run.ps1 -Port COM26 -Role child  -Topology star -Wipe -Flash
.\run.ps1 -Port COM27 -Role child  -Topology star -Wipe -Flash
.\run.ps1 -Port COM25 -Role child  -Topology star -Wipe -Flash
.\run.ps1 -Port COM21 -Role child  -Topology star -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology star -Wipe -Flash
# with export + auto-analyze -> exports/baseline/star_topology/ + analysis/baseline/star_topology/:
.\run.ps1 -Port COM26 -Role child  -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM27 -Role child  -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM25 -Role child  -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role child  -Topology star -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology star -Wipe -Flash -Analyze
```

### Baseline · tree
```powershell
# without export (dry run):
.\run.ps1 -Port COM26 -Role child  -Topology tree -Wipe -Flash
.\run.ps1 -Port COM27 -Role child  -Topology tree -Wipe -Flash
.\run.ps1 -Port COM25 -Role child  -Topology tree -Wipe -Flash
.\run.ps1 -Port COM21 -Role child  -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology tree -Wipe -Flash
# with export + auto-analyze -> exports/baseline/tree_topology/ + analysis/baseline/tree_topology/:
.\run.ps1 -Port COM26 -Role child  -Topology tree -Wipe -Flash -Export
.\run.ps1 -Port COM27 -Role child  -Topology tree -Wipe -Flash -Export
.\run.ps1 -Port COM25 -Role child  -Topology tree -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role child  -Topology tree -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology tree -Wipe -Flash -Analyze
```

### Baseline · linear
```powershell
# without export (dry run):
.\run.ps1 -Port COM26 -Role child  -Topology linear -Wipe -Flash
.\run.ps1 -Port COM27 -Role child  -Topology linear -Wipe -Flash
.\run.ps1 -Port COM25 -Role child  -Topology linear -Wipe -Flash
.\run.ps1 -Port COM21 -Role child  -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology linear -Wipe -Flash
# with export + auto-analyze -> exports/baseline/linear_topology/ + analysis/baseline/linear_topology/:
.\run.ps1 -Port COM26 -Role child  -Topology linear -Wipe -Flash -Export
.\run.ps1 -Port COM27 -Role child  -Topology linear -Wipe -Flash -Export
.\run.ps1 -Port COM25 -Role child  -Topology linear -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role child  -Topology linear -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology linear -Wipe -Flash -Analyze
```

### Baseline · partial
```powershell
# without export (dry run):
.\run.ps1 -Port COM26 -Role child  -Topology partial -Wipe -Flash
.\run.ps1 -Port COM27 -Role child  -Topology partial -Wipe -Flash
.\run.ps1 -Port COM25 -Role child  -Topology partial -Wipe -Flash
.\run.ps1 -Port COM21 -Role child  -Topology partial -Wipe -Flash
.\run.ps1 -Port COM20 -Role root   -Topology partial -Wipe -Flash
# with export + auto-analyze -> exports/baseline/partial_mesh_topology/ + analysis/baseline/partial_mesh_topology/:
.\run.ps1 -Port COM26 -Role child  -Topology partial -Wipe -Flash -Export
.\run.ps1 -Port COM27 -Role child  -Topology partial -Wipe -Flash -Export
.\run.ps1 -Port COM25 -Role child  -Topology partial -Wipe -Flash -Export
.\run.ps1 -Port COM21 -Role child  -Topology partial -Wipe -Flash -Export
.\run.ps1 -Port COM20 -Role root   -Topology partial -Wipe -Flash -Analyze
```

---

## Star topology (`-Topology star`, N=0 — every node a direct child of root)

**Blackhole, without export** (set `BLACKHOLE_ATTACKER_MAC`=COM26's MAC first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology star -Wipe -Flash  # attacker RELAY (forwards/drops victim probes)
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology star -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology star -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology star -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology star -Wipe -Flash  # root -- ANNOUNCES the phase (sets the ground-truth label); does NOT drop
```
**Blackhole, with export + auto-analyze** (victims are `-Attack blackhole`, so their CSVs auto-file into `exports/blackhole/` — no `-DestAttack` needed):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology star -Wipe -Flash -Export   # attacker RELAY
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology star -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology star -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology star -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology star -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

> 🔻 **DECISION — star blackhole vs. Fig 4.17.** The proposal figure draws the
> **ROOT** as the blackhole attacker; the block above keeps **COM26** as the
> attacker (root only announces the phase) because `root_node` has no drop path.
> The two ways to reconcile: **(A)** keep COM26 as the attacker and amend Fig 4.17
> to a leaf-attacker (documentation change), or **(B)** add a blackhole drop path
> to `root_node` so the root can be the real attacker for star (firmware change).
> Not yet resolved — pick one before defending the star-blackhole result.

**Wormhole, without export** (wire + `uart_link_test` verify COM26↔COM27 first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology star -Wipe -Flash  # REAL attacker (wormhole Node A / exit) -- -Role still says "victim"
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology star -Wipe -Flash  # REAL attacker (wormhole Node B / entry) -- -Role still says "victim"
.\run.ps1 -Port COM25 -Role child                                  -Topology star -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role child                                  -Topology star -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology star -Wipe -Flash  # root -- phase controller: -Attack makes it ANNOUNCE the attack phase (REQUIRED, sets the ground-truth label); it does NOT tunnel packets -- COM26/COM27 do
```
**Wormhole, with export + auto-analyze** (controls carry `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology star -Wipe -Flash -Export  # Node A (exit)
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology star -Wipe -Flash -Export  # Node B (entry)
.\run.ps1 -Port COM25 -Role child  -DestAttack wormhole            -Topology star -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM21 -Role child  -DestAttack wormhole            -Topology star -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology star -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

## Tree topology (`-Topology tree`, N=1, default — native self-organising, multi-hop)

**Blackhole, without export** (set `BLACKHOLE_ATTACKER_MAC`=COM26's MAC first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology tree -Wipe -Flash  # attacker RELAY (forwards/drops victim probes)
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology tree -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology tree -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology tree -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology tree -Wipe -Flash  # root -- ANNOUNCES the phase (sets the ground-truth label); does NOT drop
```
**Blackhole, with export + auto-analyze** (victims are `-Attack blackhole`, so their CSVs auto-file into `exports/blackhole/` — no `-DestAttack` needed):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology tree -Wipe -Flash -Export   # attacker RELAY
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology tree -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology tree -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology tree -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology tree -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

**Wormhole, without export** (wire + `uart_link_test` verify COM26↔COM27 first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology tree -Wipe -Flash  # Node A (exit)
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology tree -Wipe -Flash  # Node B (entry)
.\run.ps1 -Port COM25 -Role child                                  -Topology tree -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role child                                  -Topology tree -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology tree -Wipe -Flash  # root -- ANNOUNCES the attack phase (REQUIRED); does NOT tunnel -- COM26/COM27 do
```
**Wormhole, with export + auto-analyze** (controls carry `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology tree -Wipe -Flash -Export  # Node A (exit)
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology tree -Wipe -Flash -Export  # Node B (entry)
.\run.ps1 -Port COM25 -Role child  -DestAttack wormhole            -Topology tree -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM21 -Role child  -DestAttack wormhole            -Topology tree -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology tree -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

## Linear topology (`-Topology linear`, N=2 — forced chain, 1 child/node)

**Blackhole, without export** (set `BLACKHOLE_ATTACKER_MAC`=COM26's MAC first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology linear -Wipe -Flash  # attacker RELAY (forwards/drops victim probes)
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology linear -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology linear -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology linear -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology linear -Wipe -Flash  # root -- ANNOUNCES the phase (sets the ground-truth label); does NOT drop
```
**Blackhole, with export + auto-analyze** (victims are `-Attack blackhole`, so their CSVs auto-file into `exports/blackhole/` — no `-DestAttack` needed):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology linear -Wipe -Flash -Export   # attacker RELAY
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology linear -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology linear -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology linear -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology linear -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

**Wormhole, without export** (wire + `uart_link_test` verify COM26↔COM27 first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology linear -Wipe -Flash  # Node A (exit)
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology linear -Wipe -Flash  # Node B (entry)
.\run.ps1 -Port COM25 -Role child                                  -Topology linear -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role child                                  -Topology linear -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology linear -Wipe -Flash  # root -- ANNOUNCES the attack phase (REQUIRED); does NOT tunnel -- COM26/COM27 do
```
**Wormhole, with export + auto-analyze** (controls carry `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology linear -Wipe -Flash -Export  # Node A (exit)
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology linear -Wipe -Flash -Export  # Node B (entry)
.\run.ps1 -Port COM25 -Role child  -DestAttack wormhole            -Topology linear -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM21 -Role child  -DestAttack wormhole            -Topology linear -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology linear -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

*Chain order (root→…→leaf) isn't controllable by port choice — physical placement
decides link order. Confirm the resulting chain with `verify_topology.py --expect linear`.*

## Partial-mesh topology (`-Topology partial`, N=3 — fan-out capped at 2)

**Blackhole, without export** (set `BLACKHOLE_ATTACKER_MAC`=COM26's MAC first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology partial -Wipe -Flash  # attacker RELAY (forwards/drops victim probes)
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology partial -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology partial -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology partial -Wipe -Flash  # victim -> sends probes to the attacker's MAC
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology partial -Wipe -Flash  # root -- ANNOUNCES the phase (sets the ground-truth label); does NOT drop
```
**Blackhole, with export + auto-analyze** (victims are `-Attack blackhole`, so their CSVs auto-file into `exports/blackhole/` — no `-DestAttack` needed):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack blackhole -BlackholeRole attacker -Topology partial -Wipe -Flash -Export   # attacker RELAY
.\run.ps1 -Port COM27 -Role child  -Attack blackhole -BlackholeRole victim   -Topology partial -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM25 -Role child  -Attack blackhole -BlackholeRole victim   -Topology partial -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM21 -Role child  -Attack blackhole -BlackholeRole victim   -Topology partial -Wipe -Flash -Export   # victim -> attacker
.\run.ps1 -Port COM20 -Role root   -Attack blackhole                         -Topology partial -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

**Wormhole, without export** (wire + `uart_link_test` verify COM26↔COM27 first):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology partial -Wipe -Flash  # Node A (exit)
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology partial -Wipe -Flash  # Node B (entry)
.\run.ps1 -Port COM25 -Role child                                  -Topology partial -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM21 -Role child                                  -Topology partial -Wipe -Flash  # control -- plain victim firmware, no attack
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology partial -Wipe -Flash  # root -- ANNOUNCES the attack phase (REQUIRED); does NOT tunnel -- COM26/COM27 do
```
**Wormhole, with export + auto-analyze** (controls carry `-DestAttack wormhole`):
```powershell
.\run.ps1 -Port COM26 -Role child  -Attack wormhole -WormholeEnd A -Topology partial -Wipe -Flash -Export  # Node A (exit)
.\run.ps1 -Port COM27 -Role child  -Attack wormhole -WormholeEnd B -Topology partial -Wipe -Flash -Export  # Node B (entry)
.\run.ps1 -Port COM25 -Role child  -DestAttack wormhole            -Topology partial -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM21 -Role child  -DestAttack wormhole            -Topology partial -Wipe -Flash -Export  # control -- plain victim (only its export folder changes)
.\run.ps1 -Port COM20 -Role root   -Attack wormhole                -Topology partial -Wipe -Flash -Analyze  # root announces phase, boots LAST -> analyzes
```

---

## Notes that apply to every block above

- **`-DestAttack` is the dataset safeguard** — it keeps a control victim's CSV
  in the same `<attack>/<topology>_topology/` folder as the run it belongs to,
  so no stray `none` file lands in `baseline/` and confuses the dataset. It
  changes ONLY the export folder — never the firmware (still plain victim) nor
  the filename (still `..._none_...`). Wormhole controls are COM25 and COM21.
- **Wormhole tunnel is a WIRED UART link between COM26 (Node A) and COM27 (Node
  B), not a MAC-addressed WiFi message.** `WORMHOLE_NODE_A_MAC` in `mesh_config.h`
  is **no longer used by the firmware** — you do NOT set it for a wormhole run.
  Wire COM26 ↔ COM27 over UART (TX2/GPIO17 ↔ RX2/GPIO16 crossed, shared GND)
  before powering them on, and **verify with `uart_link_test` (`[LINK OK]`)
  BEFORE the real run.** Node A/B print `Wormhole UART tunnel ready: UART1
  TX=GPIO17 RX=GPIO16 ...` at boot; watch Node A (COM26) for `Re-injected probe
  ...` and Node B (COM27) for `Tunnelled probe ... via UART` during the attack
  window to confirm the wire works. `CRC mismatch` / `bad magic` = loose or
  mis-crossed jumpers.
- **Blackhole attacker is COM26; victims are COM25, COM27, COM21.** Set
  `BLACKHOLE_ATTACKER_MAC` in `mesh_config.h` to COM26's STA MAC before building,
  or the victims address the wrong MAC and there's no signature.
- **`-Topology` defaults to `tree`** if omitted (`run.ps1` param default). Build
  EVERY board in a run with the SAME `-Topology` value, or nodes disagree on
  mesh shaping.
- **Storage-full crashes** (`Failed to open ... file`, `fprintf failed`) mean a
  board's SPIFFS filled from stacked runs. **`run.ps1` now auto-fixes this:**
  `-Wipe -Flash` does a full `esptool erase_flash` before flashing (works even on
  a crash-looping board), so you no longer need a manual `idf.py ... erase-flash`.
  (Manual erase is still available if you ever want it.)
- **Port-busy on flash** (`Access is denied`) means a leftover `idf.py monitor`
  is still holding the port. **`run.ps1` now auto-frees the port** — it kills any
  stale idf.py/monitor process on that exact port before flashing. Still good
  practice to press `Ctrl+]` to close a monitor before the next command.
- **Verify the wormhole UART wire with `uart_link_test/` BEFORE a real run.** It's
  a tiny standalone loopback firmware: flash it to both attacker boards and watch
  for `[LINK OK]`. A missing GND or straight-through (uncrossed) TX/RX makes the
  tunnel silently deliver nothing (Node A `probes_count` stays 0, no duplicate
  signature at root). See [`uart_link_test/README.md`](uart_link_test/README.md).
- After any change under `components/mesh_common`, rebuild BOTH `root_node` and
  `child_node` from clean (`Remove-Item -Recurse -Force build*`) before the next
  flash — stale shared-component builds are a common source of confusing errors
  (see `CLAUDE.md`).
