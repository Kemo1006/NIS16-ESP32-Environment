# File map

<!-- Update whenever files are added, moved, or deleted. Map meaning, not every file —
     skip generated/vendor dirs (build/, __pycache__, .git). Cap: 200 lines. -->

**Updated:** sep. 16, 2026 (archive/ added — pre-restart data snapshot)

## What this workstation is

`combined` merges two independently-forked copies of the same ESP-WIFI-MESH thesis repo:
**CC** (SD-card logging, `run_wizard.ps1`, presets, Command Center) supplied the firmware
and tooling base; **NIS16-ESP32-Environment** (the Sept-2026 onboarding redesign) supplied
`menu.ps1`, the dated `docs/` set, and `tools/verify_attack.py` — the panel-cited
paper-backed attack verification. Command Center was **removed** at this merge (sep. 14,
2026) then **revived sep. 17, 2026** — see MEMORY.md — as a heartbeat sender + root-side
node table folded into `mesh_setup.c/.h` (not a separate `heartbeat.[ch]`), for live
per-node MAC/layer verification against the built topology. The multi-laptop
capture-split remains **removed**, not merely disabled. Both source trees are left untouched at
`../CC/` and `../NIS16-ESP32-Environment/` — this is a from-scratch git history, not a
`git merge` (the two trees share no commit history, only a GitHub origin).

## Layout

```
combined/                             ← workstation root (this anchor)
├── CLAUDE.md        # anchor: rules + routing (auto-loaded)
├── AGENTS.md        # agent behavior: task complexity + roles (loaded at session start)
├── STATUS.md        # current state — read first
├── MEMORY.md        # facts, decisions, preferences
├── FILEMAP.md       # this file
├── ARCHIVE.md       # completed-work log — never read unless asked
├── CLAUDE.local.md  # personal overrides — git-ignored, never shared
├── GEMINI-BRIEFING.md          # reusable full-context dump to paste into a fresh AI with zero prior exposure — carried over from CC, may still describe CC's pre-merge state; verify before trusting
├── Miguel Sebastian Carlos-1.pdf  # personal résumé — unrelated to thesis work
├── Resources/       # this workstation's OWN domain-specific reference
│   ├── INDEX.md
│   ├── reference/   # ATTACK-MECHANICS.md, OUTPUT-VERIFICATION.md, NODE-INVENTORY.md,
│   │                # + the 4 verification-basis PDFs (Zhukabayeva/Airehrour/Ramírez/Zhan)
│   └── figures/
├── 0_Resources/     # GLOBAL/shared resources only — never loaded whole; see INDEX.md
├── Plan/            # THESIS 3 planning — THESIS3-PANEL-PLAN.md (the adviser-facing
│                     # framework, 7 problems × 5 workstreams) + MEMBER-HOWTO/TASK-SPLIT
├── Implementation Issues/   # panel Q&A: bugs + limitations along the way
├── Paper/           # the thesis deliverable (reference, not code)
├── Setups/          # SD-CARD-WIRING.md (the real wiring facts, incl. the VIN/5V and
│                     # 4MHz-clock gotchas) + a stale runbook snapshot — prefer
│                     # ESP32-Environment/docs/ for anything current
├── ESP32_Pictures/  # reference photos: 30/38-pin ESP32 wiring variants, SD reader wiring
├── skills/          # Claude Code skill packages used in this workstation
│
└── ESP32-Environment/   ← THE CODE — fresh git repo, no remote
    ├── README.md                           # Part 1 of 2: fresh-laptop → running mesh
    ├── menu.ps1                            # ONE-BOARD onboarding: ~7 prompts, no state,
    │                                        # shows the equivalent command before running it
    ├── run_wizard.ps1                      # MULTI-BOARD maintenance: presets, MAC verify,
    │                                        # bulk wipe/set-location, firmware self-test —
    │                                        # NO multi-laptop split (removed)
    ├── run.ps1                             # the engine both call — requires -Location
    │                                        # whenever -Export/-Clean/-Analyze is used;
    │                                        # -Scenario/-ScenarioTarget (sep. 2026, run
    │                                        # scenarios v1 — see mesh_config.h TRAFFIC_PROFILE)
    ├── analyze.ps1                          # shortcut: trim→M6→M7→M8 on existing tools/exports/
    │                                        # data, no board needed (sep. 16, 2026)
    ├── archive.ps1                          # one command: MOVE captures+analysis into
    │                                        # archive/<date>_<label>/ + reset the scaffold
    │                                        # (-WhatIf to preview; sep. 16, 2026)
    ├── docs/                                # NIS16's 2026-09-14 dated redesign
    │   ├── 2026-09-14_START-HERE.md         # read this first
    │   ├── 2026-09-14_{MENU-WALKTHROUGH,SETUP-RULES-CONFIG,LOCATIONS,SD-CARD,REFERENCES}.md
    │   ├── runbooks/    2026-09-14_{BASELINE,BLACKHOLE,WORMHOLE,TOPOLOGIES}.md
    │   ├── issue_logs/  esp32-issues.md (+Part2/3), thesis-deviate.md, dated 2026-07-*.md
    │   └── _archive/    CC's OLDER guides/runbooks/setups — superseded, kept for reference
    ├── CMakeLists.txt, partitions.csv       # top-level ESP-IDF project (spiffs partition)
    ├── memory/                              # working-state memory (both trees' notes merged):
    │                                         # panel-change-2026-09, thesis-citations,
    │                                         # resources-papers-assessment, verified pipelines
    ├── components/mesh_common/              # shared firmware: mesh setup, csv_logger,
    │   │                                     # phase_listener, node_identity, sd_status
    │   │                                     # (Command Center heartbeat sender + root node
    │   │                                     # table live IN mesh_setup.c/.h, sep. 17, 2026 —
    │   │                                     # no separate heartbeat.[ch] file; see MEMORY.md)
    │   ├── include/  (mesh_config.h ← MESH_ID/PASSWORD/BLACKHOLE_ATTACKER_MAC, csv_logger.h,
    │   │              mesh_setup.h ← now also heartbeat_start()/heartbeat_table_init()/
    │   │              heartbeat_ingest(), phase_listener.h, node_identity.h, sd_status.h,
    │   │              mesh_messages.h ← MSG_TYPE_PHASE_SYNC + node_heartbeat_pkt_t, both live)
    │   └── src/      (mesh_setup.c, csv_logger.c ← SD mirror woven in, phase_listener.c,
    │                  node_identity.c, sd_status.c)
    ├── root_node/     main/root_main.c      # ROOT firmware — timeline controller + arrivals
    ├── child_node/    main/victim_main.c    # VICTIM firmware (+ blackhole_/wormhole_victim.c)
    ├── uart_link_test/, sd_card_test/       # standalone bring-up tests (UART tunnel; SD reader)
    ├── presets/                             # run_wizard.ps1 rosters — no `split` key on any
    │                                         # real preset (that field only existed for the
    │                                         # removed multi-laptop mode)
    ├── tools/                               # host-side Python (see Key locations)
    │   └── exports/<attack>/<topology>/<location>/[<scenario>/]   # RAW captured CSVs (tracked)
    │                                                   # + run_ledger.csv. topology: star/tree/
    │                                                   # linear/partial_mesh; location: home/
    │                                                   # G402/DLSU_Library/Goks; scenario (sep.
    │                                                   # 2026): burst/highload/mobility/powercycle
    │                                                   # — folder ONLY for an actual scenario;
    │                                                   # "none" (most runs) has NO extra folder
    ├── analysis/                            # M6→M7→M8 pipeline (see Key locations)
    │   └── <attack>/<topology>/<location>/[<scenario>/]  # windowed_dataset.csv, feature_table.csv,
    │                                         # eda_output/ (git-ignored) — some pre-merge
    │                                         # captures predate the <location> layer
    └── archive/<date>_<label>/               # pre-restart snapshots of tools/exports/ +
                                               # analysis/, moved (not copied) wholesale, same
                                               # attack/topology/location layout; each has its
                                               # own README.md. Raw CSVs + run_ledger.csv stay
                                               # tracked there too; derived/eda_output stay
                                               # git-ignored (same policy as the live trees)
```

## Key locations

| What | Where | Notes |
|---|---|---|
| Firmware entry — root | `ESP32-Environment/root_node/main/root_main.c` | controls phase timeline; logs arrivals |
| Firmware entry — victim | `ESP32-Environment/child_node/main/victim_main.c` | + `blackhole_victim.c`, `wormhole_victim.c` variants |
| Shared mesh config | `ESP32-Environment/components/mesh_common/include/mesh_config.h` | MESH_ID/PASSWORD (identical every board); `BLACKHOLE_ATTACKER_MAC` (per-rig, set from the attacker's boot banner); `TRAFFIC_PROFILE` (sep. 2026 — burst/highload run scenarios, `-DTRAFFIC_PROFILE=1/2`) |
| CSV schema source of truth | `ESP32-Environment/components/mesh_common/src/csv_logger.c` | telem = **14 cols (schema v2, F3)** — v1's 11 unchanged and in place + `recv_count,forward_count,drop_count`; root arrivals = 14 cols; SD mirror lives here too. Both telem widths accepted by `validate_integrity.py` |
| **What every column actually means** | `ESP32-Environment/docs/DATA-DICTIONARY.md` | per-role semantics of `retry_count`/`tx_count`/`probes_count`, the RSSI-is-per-link and root-is-layer-1 corrections, what is derived host-side. **Read before writing anything about the schema in the paper** |
| **Model-input leakage guard** | `ESP32-Environment/analysis/leakage.py` | the single definition of which columns a model may see, with a written reason per exclusion; `single_feature_decidability()` scores the panel's "one feature decides it" objection numerically. `eda.py` imports it and writes `leakage_audit.csv` every pass |
| Runtime attacker MAC (F2) | `ESP32-Environment/components/mesh_common/src/blackhole_target.c` | NVS override for `BLACKHOLE_ATTACKER_MAC`, read once at boot. Moving the attacker no longer means re-flashing every victim — what makes "vary the attacker position" affordable |
| **M4/M5 run inventory** | `ESP32-Environment/tools/inventory_cells.py` | `python tools/inventory_cells.py` — scans live **and archived** exports, judges every run against the M4/M5 criteria, prints which are COMPLETE and why the rest are not. **Use this instead of trusting a remembered count** — `archive.ps1` MOVES captures out of `tools/exports/`, which is how "zero wormhole captures" got recorded while six existed |
| Segment-assignment tests | `ESP32-Environment/analysis/test_segments.py` | `python test_segments.py` — 20 checks, incl. that schema v1 and v2 produce IDENTICAL segments (what keeps the two firmwares' captures comparable) |
| Pipeline M6 → M7 → M8 | `ESP32-Environment/analysis/preprocess.py` → `features.py` → `eda.py` | byte-identical to NIS16's — this is what lets `verify_attack.py` drop in unmodified |
| One-board onboarding | `ESP32-Environment/menu.ps1` | run / export / wipe / identify / **verify** a board — the simple on-ramp |
| Multi-board maintenance | `ESP32-Environment/run_wizard.ps1` | presets, MAC verify, bulk wipe/set-location, firmware self-test |
| Run engine | `ESP32-Environment/run.ps1` | `-Wipe -Flash -Export -Location <loc> -Analyze`; `-Location` is required with `-Export`/`-Clean`/`-Analyze`; `-Scenario {none\|burst\|highload\|mobility\|powercycle} -ScenarioTarget` (sep. 2026) |
| Re-analyze existing captures | `ESP32-Environment/analyze.ps1` | shortcut for trim→M6→M7→M8 on `tools/exports/` data already on disk (no board needed); no args = every combo with data, or `.\analyze.ps1 <attack> <topology> [<location>]`; `-Verify` runs **three exit-code-checked gates** — integrity → topology → attack — and calls a NOT-CONFIRMED on a capture that failed either earlier gate INCONCLUSIVE rather than a negative result |
| **Paper-backed attack verification** | `ESP32-Environment/tools/verify_attack.py` | 3-sigma normal-vs-attack (Zhukabayeva 2025; blackhole signature from Airehrour 2018) — the panel-cited check |
| Capture / integrity tools | `ESP32-Environment/tools/` | `export_logs.py` (+ `--set/--get/--clear-attacker-mac`, F2), `import_sdcard.py`, `trim_run.py`, `validate_integrity.py`, `verify_topology.py`, `run_matrix.py`, `recover_spiffs.py`, `board_check.py` |
| Raw evidence (tracked) | `ESP32-Environment/tools/exports/<attack>/<topology>/<location>/` | primary data; `run_ledger.csv` tracks the matrix |
| Pre-restart snapshots | `ESP32-Environment/archive/<date>_<label>/` | e.g. `2026-09-16_pre-restart/` — everything captured before a board-wipe/restart, moved wholesale out of `tools/exports/`+`analysis/`; read its `README.md` first |
| Archive a run + reset | `ESP32-Environment/archive.ps1` | one command: moves captures + analysis into a new dated archive, writes its README, resets the scaffold + ledger. `-WhatIf` previews; `-Label`/`-Reason`/`-Force` for scripting |
| Deps | `ESP32-Environment/analysis/requirements.txt` | pandas, numpy (M6/M7) + matplotlib, seaborn, scipy, scikit-learn (M8) |
| Runbooks | `ESP32-Environment/docs/runbooks/2026-09-14_*.md` | current — BASELINE/BLACKHOLE/WORMHOLE/TOPOLOGIES |
| Superseded docs | `ESP32-Environment/docs/_archive/` | CC's older guides/runbooks/setups — reference only |
| Issue logs / deviations | `ESP32-Environment/docs/issue_logs/` | `esp32-issues*.md`, `thesis-deviate.md`, dated milestone reports |
| SD wiring facts | `Setups/SD-CARD-WIRING.md` | VCC→VIN/5V not 3V3; SPI clock capped at 4MHz — both cost real bench time to find |
| Thesis 3 planning framework | `Plan/THESIS3-PANEL-PLAN.md` | adviser-facing draft (7 problems × 5 workstreams) — see STATUS.md for what's actually been done against it |
| Panel comments (CTTHES2) | `Paper/Improvements.pdf` | the source document driving all Thesis 3 work |
| Verification citation basis | `ESP32-Environment/memory/thesis-citations.md`, `resources-papers-assessment.md` | which papers back which claim, and why |
| Retired Thesis 2 defense docs | `0_Resources/archive/` | defense scripts, Q&A banks — not auto-routed |

## Do-not-touch

- `**/build/`, `build_*/`, `__pycache__/`, `.git/` — generated/vendor.
- Per-board/per-variant build dirs under `root_node/` and `child_node/` (short names like
  `cbv`, `cwa`, `cwb`, `cv`, `bcc0` alongside the longer `build_<role>_<attack>_<topology>_COM<n>`
  ones) — all are `idf.py build` output, not source.
- `tools/exports/**` raw CSVs — irreplaceable captures; never overwrite or wipe before verifying.
- `archive/**` raw CSVs and `run_ledger.csv` — same irreplaceable-evidence rule as live `tools/exports/`.
