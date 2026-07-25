---
name: linear-blackhole-pipeline-verified
description: Full linear-blackhole capture→export→M6→M7→M8 pipeline verified working end-to-end on 2026-07-25 (close-node desk test)
metadata:
  type: project
---

On **2026-07-25** a full **linear + blackhole** run was captured with all 6 boards
on the desk (very close, all USB-tethered to the laptop) and analyzed with
`-Export`/`-Analyze`. The **whole pipeline works end-to-end** — capture → export →
M6 (`windowed_dataset.csv`) → M7 (`feature_table.csv`, 884 windows) → M8
(`eda_output/`). This was a functional test, not clean final data.

**6th board added:** COM22 (STA MAC `70:4b:ca:25:b7:68`), a generic node — plain
child in baseline, `-BlackholeRole victim` in blackhole, plain control in wormhole.
Board→room layout and per-topology run steps are now in the repo runbooks
(`LINEAR-/TREE-/STAR-/PARTIAL-RUNBOOK.md`); flat matrix is `ATTACKS-Commands.md`.
Fixed placement: root=Bedroom 2 (laptop), COM26+COM27=Bedroom 1 (kept together for
the wormhole UART cable), COM25+COM22=Family Hall, COM21=Master's Bedroom.

**Blackhole signature was clean and correct** (`verify_topology --expect linear`
PASSed, depth-6 chain, attacker COM26 at layer 3 with victims behind it):
- Attacker COM26 `telem`: during attack (`gt_label=1`) `tx_count` delta = **0**
  (forwarding stopped) while `retry_count` climbed **+723** (all received probes
  dropped); baseline `tx` delta was +2083.
- Root `arrivals`: **1921** during normal, **0** during the attack window.
- `feature_table`: **PDR 0.70→0.47**, **RetryRate 0.013→0.166** by window label.
- Features 16/16 present, 13 populated as of 2026-07-26; 3 all-NaN
  (`TunnelIntensity`, `TunnelBytes`, `TunnelLatency`) — wormhole-only, correct here.
  `LatencyHopRatio` and `TunnelLatency` are no longer permanently NaN: both are now
  recovered from the root's arrivals log by cancelling the unsynchronised-clock
  offset, no firmware change needed. See [[latency-features-recovered]].

**Close-node caveats (why final data needs the spread-out room layout)** — same
root cause as [[wormhole-working-state]]: mesh convergence was slow/twitchy (COM22
took 118 s to converge vs the <60 s Milestone-3 target, 1 baseline parent-switch),
and baseline PDR was only ~0.70 with modest attack separation (0.70 vs 0.47).
**How to apply:** for the real dataset, spread boards across the 4 rooms (and/or
lower TX power) so baseline converges cleanly and PDR separation widens.

**Tooling gotchas learned:** (1) `validate_integrity.py` / `verify_topology.py`
default their export dir to `exports` **relative to CWD** — run them from `tools\`
(or pass `--dir`), or they scan a stray/empty folder. `verify_topology` also needs
`--files` or matching `--topology/--attack` filters. (2) Running an IDF/tool command
from the repo root creates junk (`build\`, `exports\`) because the root isn't an IDF
project — `idf.py set-target` must run inside `root_node\` / `child_node\`.
