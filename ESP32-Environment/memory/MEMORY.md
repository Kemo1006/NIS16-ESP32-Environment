# Memory index

- [Wormhole working state](wormhole-working-state.md) — wormhole confirmed working on COM26/COM27; mesh instability still degrades signature separation
- [Linear-blackhole pipeline verified](linear-blackhole-pipeline-verified.md) — full capture→export→M6→M7→M8 works end-to-end (2026-07-25 desk test); COM22 added; close-node caveats for final run
- [Latency features recovered](latency-features-recovered.md) — arrivals `latency_us` carries an unsynchronised-clock offset that cancels under subtraction; unblocked LatencyHopRatio + TunnelLatency without firmware changes
- [Panel-mandated redesign (Sept 2026)](panel-change-2026-09.md) — the CTTHES panel's 8 required fixes (variance, realistic scenario, cited verification, SD card, tooling, new schedule); all prior runs redone/archived
- [Run scenarios v1 (Sept 2026)](run-scenarios-2026-09.md) — `none|burst|highload|mobility|powercycle` in both front-ends, answering panel item 2 (variance); code-verified, not yet bench-tested on hardware
- [Thesis citation set](thesis-citations.md) — curated papers backing every attack/verification claim (Zhukabayeva 2025, Airehrour 2018, Khan 2022, Ramírez Gómez 2019); paste-ready APA references
- [Verification papers assessment](resources-papers-assessment.md) — why each of the 4 `Resources/reference/*.pdf` papers does or doesn't fit our blackhole/wormhole verification, and how `tools/verify_attack.py`'s 3-sigma method was chosen
- [Windows PS1 ASCII-only rule](reference-windows-ps1-ascii.md) — why `menu.ps1`/`run_wizard.ps1` avoid non-ASCII characters (Windows PowerShell 5.1 misreads them)
- [menu.ps1 navigation rebuild (Sept 2026)](menu-navigation-2026-09.md) — `b` back + sticky defaults via run_wizard-style step machines; the `$dir` skip rule, the `return ,$array` scalar-collapse bug, and the BackSignal `-eq` operand-order trap
- [Wizard pre-build + live identify (Sept 2026)](wizard-prebuild-and-live-identify-2026-09.md) — `run.ps1 -BuildOnly` + post-build menu skip the Ctrl+]/n dance; dropped board_check.py's hardcoded ROOT/ATTACKER roster labels for a live boot-banner read
- [Dynamic topology layers (Sept 2026)](dynamic-topology-layers-2026-09.md) — removed MESH_MAX_LAYER=7 and every fixed node-count table; layers now BFS-derived, shared C/Python rule set (topology_graph.c/.py); not bench-tested, every board needs re-flash (heartbeat wire format changed)
