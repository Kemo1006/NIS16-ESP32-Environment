# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 16, 2026 — DONE: `attack`/`topology`/`location`/`scenario` are now COLUMNS on every row of
  `windowed_dataset.csv` + `feature_table.csv` (thesis-deviate **D-10**). `preprocess.py`'s new
  `_run_context_from_path()` reads them off the input path; `features.py` does
  `result = windowed.copy()` so they propagate free (same mechanism as D-7's `run_repeat`).
  **Fixed a real pooling bug doing it:** `combine_all.py` read `dir_parts[2]` as location and
  DROPPED the scenario segment, so a `mobility` and a `none` run in the SAME attack/topology/
  location merged unrecoverably. It now prefers the columns, path-parses only for pre-D-10
  tables, and groups by scenario. Conventions: no scenario folder ⇒ `"none"` (absence IS the
  value), no location ⇒ `"unrecorded"`, non-export path (synthetic fixtures) ⇒ all None so unknown
  provenance is never labelled. Parsing anchors on the LAST known attack name, so
  `archive/<date>/exports/...` still resolves.
- sep. 16, 2026 — DONE: analysis grid 1Hz→**10Hz** + window 5s→**1s** in `preprocess.py`
  (thesis-deviate **D-9**), because the panel now wants ~10k rows PER RUN and the team wants 6k.
  Rows are fixed by `nodes × (analysed_seconds ÷ WINDOW_SECONDS)` — only more nodes, longer runs or
  smaller windows move it; at 5s windows 6k needs an 83-min run, so the window had to give. No
  firmware change: boards ALREADY sample at 10Hz, M6 was discarding 9 of 10 samples (D-1).
  Measured on clean `baseline/linear`: **577 → 2,894 rows/run (5.0×)**, discard rate
  **1.0% → 0.1%** (better), `RSSI_var` 0 NaN, runtime M6 3.6s / M7 3.0s (no slowdown). Windows now
  hold **10 samples vs 5** — more support per row, not dilution. Revert = `GRID_HZ=1`,
  `WINDOW_SECONDS=5`, `MIN_VALID_SAMPLES=4`. ⚠️ `MAX_GRID_ROWS` had to rise 500k→5M or the tripwire
  fires on legit 10Hz data. ⚠️ At `PROBE_INTERVAL_MS=1000` a 1s window holds ~1 probe, so per-window
  PDR is near-binary (no information lost in the mean; just don't read one window as a fine rate).
  **NOT done — targets need longer phases + reflash:** 6k/run ≈1,245s analysed (~22min, 1.06MB/node),
  10k/run ≈2,075s (~36min, 1.66MB/node); SPIFFS is 0x270000 = **2.44MB** (NOT the 1.1MB in the old
  I-017 note), so both fit. **M4 = 24 attack runs** (baseline not among them, D-5) → 24 × 2,894 ≈
  **69k rows total even without lengthening runs.**
- sep. 16, 2026 — FIXED (supersedes this entry's earlier "NaN logic is correct" claim — it was
  NOT): `features.py`'s PDR gated attributability on a run-wide `covered_macs` set, so a victim
  the root never logged ANYTHING for got NaN in every window — exactly the node a blackhole hits
  hardest. Consequence: `PDR == 0` occurred in **0 of 446 rows**; the feature could never record
  the value it exists to detect. Now gated per-window on evidence: node transmitted
  (`probes_count_delta > 0`) AND was associated (`layer > 0`, parent_mac non-zero) AND the window
  is inside the root's arrival-logging span (that last one replaces the old safety against a
  never-pulled root CSV). Also fixed a latent FALSE-POSITIVE: `0/(0+EPSILON)` returned a literal
  `0.0` for windows where a node sent nothing — a fabricated blackhole signature. Before→after on
  `G402/mobility`: PDR non-null 41→238, `PDR==0` 0→201, NaN 405→208; victim PDR by phase now
  baseline 0.217 → attack 0.000 → cooldown 0.750. `verify_attack.py` still says NOT CONFIRMED
  there (that capture's own baseline is degraded, 0.164±0.372) — i.e. it surfaces the signature
  WITHOUT fabricating one. Full rationale: `docs/issue_logs/thesis-deviate.md` **D-8**.
  ⚠️ Remaining NaN is correct, not a gap: root never originates probes (PDR undefined for it).
- sep. 16, 2026 — ⚠️ CAPTURE QUALITY, archived unresolved: `blackhole/linear/G402/mobility` — 3 of 4
  victims probed all run but root logged nothing from them in ANY phase (`B4BFE932FE90` changed
  layer 4→5 mid-run; `2805A532D7B4` at layer 6). NOT the MAC bug below (that run's attacker `0c:80`
  DID match the then-configured MAC, and one victim got through) — suspected mobility-disrupted TODS
  relay, still untested since the 15:36 re-run was itself voided by the MAC bug. `home/mobility`
  also exported ONLY root's CSVs — check `-Location`/`-Scenario` match on every board before export.
- sep. 16, 2026 — BUILT: `ESP32-Environment/analyze.ps1` — the analysis+validation front door
  (trim→M6→M7→M8→verify) on captured data. No args = `menu.ps1`-style menu, runs pickable from a
  numbered list; `-List` shows combos + row counts + running total; `-All`, `-Verify`, `-SkipTrim`
  for scripting. Finds captures at ANY folder depth (a v1 bug checked only one level and silently
  missed every `-Scenario`-tagged capture). Docs: `analysis/ANALYSIS-Commands.md`.
  ⚠️ `trim_run.py` does NOT clear `trimmed/` before re-trimming, so stale files from a prior partial
  run get loaded by every analysis tool — it warns `[!] N STALE file(s)`; menu [6] clears it.
- sep. 16, 2026 — ⚠️ **MEMORY.md has NO sync transport between laptops.** `combined/` is on a local
  drive (`A:\`, NOT OneDrive) and `ESP32-Environment/`'s repo has no remote. Transport undecided.
- sep. 16, 2026 — BUILT `ESP32-Environment/archive.ps1`, automating the archiving convention: one
  dated+labelled folder per run under `archive/<date>_<label>/`, each with an auto-written README
  giving the reason. MOVES (never copies/deletes) all captures + analysis output preserving the
  attack/topology/location/scenario layout, then resets the `.gitkeep` scaffold (3 attacks × 4
  topologies) + header-only ledger. Keeps `analysis/*.py|md|txt` and every `.gitkeep`. `-WhatIf`
  previews; `-Label`/`-Reason`/`-Force` script it; refuses to run on an empty tree (a lone
  header-only ledger doesn't count as data); auto-suffixes `-2` rather than overwrite an existing
  archive. Used for all 3 archives today (`pre-restart`, `mobility-run`, `bad-attacker-mac`).
  ⚠️ Git-Bash `mv` gives "Permission denied" on these dirs — the script uses `Move-Item`.
  ⚠️ **PS 5.1 `Out-File -Encoding utf8` writes a BOM.** That silently broke `run_ledger.csv`:
  `run_matrix.py` reads it with plain `encoding="utf-8"` + `csv.DictReader`, which does NOT strip a
  BOM, so field 1 became `﻿` + `topology` and every `row["topology"]` would fail (pandas hides
  this — it strips BOMs, so test with csv.DictReader). Use `-Encoding ascii`, or
  `[System.IO.File]::WriteAllText(..., New-Object System.Text.UTF8Encoding $false)` when the text
  may be non-ASCII.
- sep. 16, 2026 — REWROTE `analysis/ANALYSIS-Commands.md` (was badly stale: `star_topology` naming,
  no `<location>`/`<scenario>` layers, no tooling). Now: `analyze.ps1` first, trimming (+ the
  stale-`trimmed/` gotcha), manual M6→M7→M8, `verify_attack.py` incl. how to read PASS/FAIL/SKIP
  (a FAIL usually means a noisy baseline, not broken code), and a "looks like an error but isn't"
  section (PS 5.1 red numpy-stderr; by-design NaN columns). All 13 paths link-checked.
- sep. 16, 2026 — PROPOSED, NOT BUILT (team decides first): root-as-blackhole-attacker, STAR
  ONLY — thesis fig 4.17 shows ROOT as the attacker in star, since every child connects directly
  to root so no child-relay position exists there (tree/linear/partial keep a child attacker; all
  wormhole topologies unchanged). Design: `ROOT_BLACKHOLE_ATTACKER` flag (`#error`-gated to
  star+blackhole) + a drop branch in `root_main.c`'s `probe_data_cb` (just skip
  `csv_logger_append_probe_arrival`) + swap root's telemetry role string to `"blackhole"` so
  `features.py`'s existing mask picks it up with ZERO analysis changes. Children need NO firmware
  change. ⚠️ Biggest trap: pass `-DestAttack blackhole` for folder placement but NOT
  `BlackholeRole=victim` (that compiles in P2P-to-attacker-MAC addressing, wrong for this variant);
  the MAC pre-flight check does not apply and must be skipped, not extended. Full plan in
  `.claude\plans\mutable-honking-spindle.md` (under the Basti user profile) — read before building.
- sep. 16, 2026 — BUILT: run scenarios v1 (`none|burst|highload|mobility|powercycle`) in run.ps1
  (`-Scenario`/`-ScenarioTarget`), both front-ends, presets, `run_matrix.py`, `verify_topology.py` and
  the Python export chain — the panel's "real-world variation" ask. Build flag `-DTRAFFIC_PROFILE=1`
  burst / `=2` highload; `none` passes NO flag, so its compile line and build dir stay byte-identical
  to pre-scenario. Who gets it: burst → root + the ONE `-ScenarioTarget` child; highload → every
  child; mobility/powercycle → nobody (human-performed, label-only). Burst fires `BURST_COUNT`(100)
  probes `BURST_OFFSET_S`(60) into the attack-length window, and on a BASELINE run the root holds a
  matching extra window so a legit burst and a burst-under-attack form a matched pair.
  ⚠️ Export-folder rule: the scenario folder is added ONLY for a real scenario — `none` gets NO extra
  folder (all 5 path-builders agree on this; it was the bug fixed the same night). Build-dir suffix
  `_burst`/`_highload` is a SEPARATE concern (firmware variant, not export path).
  ⚠️ Verified only without hardware attached — NOT bench-tested on real boards yet.
- sep. 15, 2026 — ⚠️ ROOT-CAUSED a FALSE `BLACKHOLE CONFIRMED` (ForwardingRatio 0.995→0.000, z=-19.6): the
  `feature_table.csv` pooled THREE UNRELATED SESSIONS in one leaf — the real root export
  (`..._r2_20260915_211307_...`) plus two RAW SD-card files copied in by hand
  (`victim_NODE_20500DE70C80_r21_b22`, `..._F42DC973E618_r26_b28`). **THE FACT: an ON-CARD `r<N>` is that
  board's own on-device run counter (times IT logged to THAT card), NOT the campaign repeat.** A card
  mirrors the same `<attack>/<topology>/<location>/` tree as `exports/`, so dragging a card's folder over
  the exports folder merges raw captures into a leaf where they still end in `_telem.csv` and get globbed
  in silently; only `import_sdcard.py --repeat` restamps them to one campaign number. `verify_topology.py`
  had already flagged both orphans ("No root node identified"/"Unresolved parents") — that was the tell.
- ⚠️ TERMS-GLOSSARY.md (archived aug. 06 with the Thesis 2 defense docs) may still be live
  reference for THES3 writing (vocabulary for paper Tables 4.11/4.12) — pull it back to root
  if so. See ARCHIVE.md for the doc-reorganization history.

## Durable facts & constraints
- The code + docs live in the self-contained git repo `ESP32-Environment/` (fresh history, no remote — see sep. 14, 2026 combined-merge entry above); the paper (PDF + figures + milestone form) lives in `Paper/`. This repo is "Part 1 of 2" — firmware + tooling.
- Thesis: DLSU CCS, CTTHES2/THES3. Proponents: Calpoporo, Carlos, Ong, Reinante. Adviser: Cu, Gregory G.
- Toolchain: ESP-IDF **v5.3.5** (bundles Python 3.11 + compiler); boards enumerate as "Silicon Labs CP210x USB to UART Bridge"; Windows reassigns COM numbers every plug — always re-check.
- Mesh identity is shared across every board: `MESH_ID {0xAB,0xCD,0xEF,0x01,0x23,0x45}`, `MESH_PASSWORD "MeshSecure2026!"` in `components/mesh_common/include/mesh_config.h` — never change between flashing root and victims.
- The FOLDER you build from decides the role, not the COM port: `root_node/` → root, `child_node/` → victim.
- Blackhole signature (M2): attack-window PDR ~0.08 vs 0.94 benign, ForwardingRatio ~0.02, root logs zero arrivals. Wormhole signature: duplicated `(src_mac, seq_num)` arrivals (×2 on the tunnelled node).
- **aug. 29, 2026 — honest nodes cannot observe their own forwarding.** Victims send with `esp_mesh_send(NULL, ..., MESH_DATA_TODS)` (`victim_main.c:164`), so the mesh stack relays *below the app layer*; only the blackhole attacker sees transit packets, because victims address it explicitly (`victim_main.c:159`). The 11-column schema gives every node `probes_count`/`tx_count`/`retry_count`, but they mean "probes I originated" on a victim and "received/forwarded/dropped" on the attacker. ⇒ C7 (un-gate the relay features) is **not** a mask widening — there is no honest-relay data to un-gate. Three options in `Plan/THESIS3-MEMBER-HOWTO.md` §1 C7.
- Feature coverage is run-type-dependent: baseline 10/16, blackhole 13/16, wormhole 13/16, **combined matrix 16/16**. "No feature uniformly NaN" is a claim about the assembled dataset, not any single run.
- **THESIS 3 DRIVER — `Paper/Improvements.pdf`** (CTTHES2 panel comments, received ~aug. 2026). 8 timestamped rows → 7 distinct problems: single-feature decidability, no attack parameter variation, redundant r1–r3, one environment only, no declared IoT scenario, no attack provenance/validation, uncharacterised benign baseline. Full analysis + response plan: `Plan/THESIS3-PANEL-PLAN.md`.
- ⚠️ **Known leak (panel P1):** the 5 role-gated features are non-NaN ONLY for their attacker role — `ForwardingRatio`/`IngressEgressDelta`/`ConsistencyScore` for the blackhole attacker, `TunnelIntensity`/`TunnelBytes` for wormhole endpoints. So "is this column NaN?" is a **perfect label**. Combined with PDR 0.08-vs-0.94, the dataset is trivially separable — the panel's "then ML is unnecessary" objection is correct as of aug. 2026.
- ⚠️ **Paper-scope conflict R-A:** paper §1.4.1 + abstract commit to a *"controlled indoor environment"*. The DLSU-campus decision deliberately relaxes that — must be amended in §1.4.1/abstract and logged in `thesis-deviate.md` as D-5, not slipped in.
- ⚠️ **Paper-scope conflict R-B:** paper §1.4.1 explicitly EXCLUDES *"grayhole, Sybil, or selective forwarding"* from the threat model. Partial/probabilistic drop rates ARE selective forwarding — so the obvious fix for the panel's "vary the attacks" comment collides with approved scope. Safest reading: the panel asked for different **attacker positions**, not different drop rates. Adviser decides (plan §7 R-B).
- ✅ **Already have a pre-registered attack signature (panel P6):** paper **§3.4.4 + Tables 3.4/3.5** state the expected observables for blackhole and wormhole, written at proposal time before any capture. Quote as-published; NEVER edit them to match results. §3.3.1.1/§3.3.2.1 hold the theory citations.
- **Attack-validation framing (panel P6):** blackhole/wormhole are defined by adversary BEHAVIOUR, not protocol — so LEACH/AODV/RPL datasets are valid comparison points and sources need NOT be ESP32-specific. Validate by *definitional conformance* (criteria from Karlof & Wagner / Hu-Perrig-Johnson vs. what we implement, failures declared), then match signature SHAPE not absolute values. Tables drafted in plan §5.1.
- Two conformance gaps to declare, not hide: (a) our blackhole is a **placed relay**, it does not *attract* traffic by false route advertisement — hence the paper's name "Forwarding Suppression (Blackhole)"; (b) our wormhole produces duplicate arrivals but whether parent selection re-forms around the fake link is unproven — hence "Topology Distortion (**Wormhole-Inspired**)". The paper's own functional naming (§4.2.1.2/4.2.1.3, Tables 4.6/4.7) already makes the narrower, defensible claim — lead with it.
- ✅ **§2.8 + Table 2.8 already survey existing wireless datasets** — extend that table for the dataset-comparison work, don't write a new section.
- ⚠️ **Known circularity (panel P6):** the blackhole attacker counts its OWN drops — the evidence the attack occurred comes from the node performing it. Needs an independent observer (sniffer node / monitor-mode adapter) or root-side accounting.
- Every attack/traffic parameter is a compile-time constant: drop rate 100% (`blackhole_victim.c:195`), `PROBE_INTERVAL_MS 1000`, `SAMPLING_INTERVAL_MS 100`, phases 60/300/180/120 s = 11 min (`mesh_config.h:129-138`), and `BLACKHOLE_ATTACKER_MAC` is a `#define` (`mesh_config.h:207`). `run.ps1` exposes topology/role but **no** attack-intensity flags → r1/r2/r3 differ only in RF noise, and attacker position can't change without re-flashing every victim board.
- I-017 recurring hazard: children left powered through the run's later phases overfill SPIFFS (~1.1 MB) and become unreadable on export → carry each child back UNPLUGGED; `board_check.py --port COMxx --wait 75` before a run (≥50% SPIFFS → wipe+flash first).
- ⚠️⚠️ **RECURRING RUN-KILLER — verify `BLACKHOLE_ATTACKER_MAC` before EVERY blackhole run**
  (`mesh_config.h:207`). Blackhole VICTIMS send `MESH_DATA_P2P` to that exact MAC
  (`victim_main.c:152`), so if it names a board not in the mesh, every probe is addressed to
  nobody: root logs **zero arrivals in ALL phases**, `arrivals.csv` is header-only, and BOTH
  primary features (PDR *and* ForwardingRatio) come out 100% NaN — the run is unusable and the
  failure is SILENT (boards look healthy, telemetry is full, probes_count climbs normally).
  Hit sep. 15 AND again sep. 16 (stale `0c:80` while attacker board was `1c:38`). Symptom→cause
  shortcut: all-NaN PDR + empty arrivals + root `probes_count` stuck at 0.
  **Why the wizard guard missed it:** `Confirm-BlackholeAttackerMac` (menu.ps1:201, also in
  run_wizard) runs only at BUILD/FLASH time — the MAC is compiled INTO the victims, so reusing an
  already-flashed build carries the stale value silently. Changing the attacker ALWAYS means
  re-flashing every victim. **Two guards added sep. 16:** (1) the attacker compares its own STA MAC
  to the compiled one at boot and prints a MISMATCH/abort banner (`blackhole_victim.c`);
  (2) `features.py`'s `load_arrivals` warns loudly when arrivals files exist but are all
  header-only, instead of silently returning None like a legitimately absent root log.
  Rejected as too risky pre-campaign: having the attacker announce its MAC over the mesh
  (untested protocol change days before 24 runs).
- ⚠️ WORMHOLE's equivalent run-killer is DIFFERENT — it has **no MAC at all** (the tunnel is a
  physical wired UART1 link between the two endpoint boards; `mesh_config.h:243` says so outright,
  and wormhole victims send plain TODS since the P2P-to-a-MAC path is `BLACKHOLE_VICTIM_TARGET`
  only). Its silent failure is a dead/mis-wired cable: TunnelIntensity/TunnelBytes/TunnelLatency
  come out empty while both boards look healthy. ⚠️ Node B CANNOT detect this — `uart_write_bytes()`
  succeeds into an unterminated line, so B's "Tunnelled" counter climbs regardless; only Node A can
  prove a frame crossed. Guard added sep. 16 on Node A: if `s_tunnel_received == 0` at terminate it
  prints a TUNNEL CARRIED NOTHING banner (check B-TX→A-RX + COMMON GROUND; `uart_link_test` is the
  bring-up project).

## User preferences
- (none recorded yet)

## Failed approaches — do not retry
- Passing `idf.py -D` flags as `@($spec.Flags)` — that is an array SUBEXPRESSION, not a splat, so both
  defines merge into ONE arg (`-DACTIVE_ATTACK="1 -DMESH_TOPOLOGY=2"` → build failure). Use a plain
  variable and `@flags`. `build_all_variants.ps1:47-53` documents the same gotcha.
- Spawning a build/flash window as plain `powershell.exe` — `idf.py`/`esptool.py` are POWERSHELL
  FUNCTIONS from `C:\Espressif\Initialize-Idf.ps1`, and functions don't survive into a child process
  (only env vars do). Dot-sourcing it with no `-IdfId` also fails silently: `idf-env config get
  --property python --idf-path <path>` returns the STRING "null", not an error. Fix in use:
  `Get-EspIdfActivation` reads the real Start Menu shortcut's `-IdfId` at runtime (never hardcode it —
  a reinstall changes it).
- Long `idf.py -B <dir>` build-directory names in this repo (e.g. `build_cc_verify`) — the workstation
  path is already deep, so object paths cross Windows' 250-char `CMAKE_OBJECT_PATH_MAX` and ninja
  fails inside the **bootloader** subproject, long after the app's own files compiled fine. The CMake
  warning names the path but the failure looks unrelated. Use short names (`bcc`, `cwa`, `bjs`).
- Non-ASCII characters (`⚠`, `—`, `…`) anywhere in a Python tool's **module docstring** when it is
  passed to `argparse` as `description` — the Windows console is cp1252, so `--help` dies with
  `UnicodeEncodeError` before printing anything. `tools/command_center.py` is deliberately ASCII-only
  and calls `sys.stdout.reconfigure(encoding="utf-8")` before `rich` draws (its box-drawing
  characters hit the same wall on the first repaint).
- Splitting recovered SPIFFS dumps on newlines after stripping page metadata — welds row tails to heads and fabricates data that passes a field regex. `recover_spiffs.py` now accepts only byte runs delimited by `\n` on both sides.
- `run_matrix.py --record` with hand-typed `--repeat` — silently re-recorded the wrong run. Use `--autorecord` (scans, validates, records; no flags to mistype).
- Powering the SD reader module's VCC from ESP32 3V3 — its onboard AMS1117-3.3 regulator drops ~1.1-1.3V,
  leaving the card below its ~2.7V minimum. Symptom: CMD0 succeeds (R1=0x01, card answers "idle") but
  ACMD41/OCR times out forever (0x107) — looks like a wiring fault but isn't. Use VIN/5V instead; the
  module's 74HC125 level-shifter runs off the regulated 3.3V rail regardless, so 5V-in never puts 5V on
  the ESP32's GPIOs for this specific module.
- sep. 16, 2026 — Matching a `printf` format specifier to `sdmmc_card_t`'s `real_freq_khz`/
  `max_freq_khz` declared type — it differs by ESP-IDF version (see CLAUDE.md bootstrap facts).
  `sd_status.c`'s boot-check `rep()` now casts explicitly (`(unsigned long)x` + `%lu`) instead.
