# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 21, 2026 — **C7 OPTION 1 SHIPPED (D-12): every node relays hop-by-hop at the app layer.**
  Shared `probe_relay.{h,c}`; victims send to their PARENT (`MESH_DATA_P2P`); **the attacker runs the
  SAME relay and differs by ONE boolean callback**. ⚠️ **This IMPLEMENTS the paper** (§3.1.3.2
  mandates it; Table 4.2 already specified the counters) — **the old TODS behaviour was the
  deviation**. ⛔ **CONFLICTS WITH THE SIGNED MILESTONE FORM; adviser sign-off required** — every
  milestone CRITERION still passes, only the mechanism changed. Fixes panel 2:40-4:50 at the root.
  ⚠️ **Pre-C7 and post-C7 captures are NOT comparable.** Full rationale + the conflict: D-12.
- sep. 21, 2026 — ⚠️ **TRAP THAT WOULD HAVE SILENTLY KILLED EVERY WORMHOLE RUN.** The relay first
  forwarded only `PROBE_MAGIC`; Node A's duplicate carries `PROBE_MAGIC_WORMHOLE`, so every
  intermediate relay would have dropped it and wormhole runs would have looked clean. Both magics now
  relay. **Any future change to the relay's accept-filter must re-check this.**
- sep. 21, 2026 — **`leakage.py` is DATASET-AWARE, not hardcoded.** `relay_features_are_gated(df)`
  counts how many `node_role`s carry each relay column: pre-C7 (1 role) excludes, post-C7 (>=2)
  re-admits. Both generations coexist for months. Before/after score = deliverable E2.
- sep. 21, 2026 — **A stale `BLACKHOLE_ATTACKER_MAC` is NO LONGER a run-killer** — bookkeeping only.
  The old "RUN WILL BE EMPTY / ZERO arrivals" alarms are now FALSE and would cause good captures to
  be aborted; downgraded in `menu.ps1` + the attacker boot banner. Dead `BLACKHOLE_VICTIM_TARGET`
  removed. ⚠️ `BLACKHOLE_ROLE` is still REQUIRED — it selects which source file builds.
- sep. 21, 2026 — **`layer` → `hop` (D-11).** New `hop` column (root = 0); `LayerChangeCount` →
  **`HopChangeCount`**; raw `layer` kept. ⚠️ **Off-by-one is the point** — Espressif numbers the root
  layer 1, so a plain rename would read "the root is 1 hop from itself"; `layer == -1` → NaN, never
  -2. Feature VALUES unchanged (offset-invariant); verified zero shared values moved over 7704 rows.
  Dated `2026-07-*` issue logs keep the old name deliberately: historical record.
- sep. 21, 2026 — **Smart trimmer**: `trim_run.py` scores boot sessions on PHASE PROGRESSION, not
  length. Old rule kept a long idle/export session over a short or aborted real run. Proven: 400-row
  real run (+102.6) beat a 3000-row idle session (-146.5). Warns when two sessions look real, or none.
- sep. 21, 2026 — **`verify_topology.py --structure`** rebuilds the parent/child table from CSVs (also
  in `run_wizard.ps1` → VERIFY); works on ARCHIVED runs, unlike the serial banner. ⚠️ **`node_id` is
  the STA MAC but `parent_mac` is the parent's SoftAP BSSID = STA + 1** — joining them directly
  matches NOTHING and looks like a disconnected mesh. Confirmed on all 7 non-root nodes.
- sep. 21, 2026 — **`docs/REVIEWER-QUESTIONS.md`** answers every adviser/panel side comment against
  verified source. Key: the MAC is `esp_read_mac(ESP_MAC_WIFI_STA)`, an **eFuse read** — the CP210x
  USB bridge has no MAC at all; RSSI is read from the driver; PDR/LatencyHopRatio NaN during the
  attack are **results, not gaps**.
- sep. 20, 2026 — ⚠️ **CORRECTION: "only ONE cell has data" and "ZERO wormhole captures exist" were BOTH
  WRONG** (recorded in STATUS+MEMORY, and I repeated them). `tools/inventory_cells.py` scans live **and
  archived** exports: **18 runs, 8 COMPLETE, 5 attack×topology cells (all with a complete run), 2
  locations (G402+home)**; wormhole linear r2/r3, star r1/r2/r3, partial_mesh r1 all exist. **Cause:
  `archive.ps1` MOVES captures out of `tools/exports/`, and every tool only looked there.** ⚠️ Team call:
  those 6 wormhole runs are pre-restart (schema v1) — mechanically complete; whether they count is yours.
- sep. 20, 2026 — **TELEMETRY IS SCHEMA v2 (14 cols) — EVERY BOARD MUST BE RE-FLASHED.** F3 appends
  `recv_count,forward_count,drop_count`; v1's 11 unchanged; `validate_integrity.py` accepts BOTH.
  Point: `retry_count` means ONE thing on every role again (it used to carry the attacker's DROP
  count). ⚠️ **The ROOT reports 0/0/0, NOT its arrival count** — recv>0 with forward=0 would score
  the root ForwardingRatio 0.0, making the node that MEASURES the attack read as the one committing
  it. Full rationale: `csv_logger.h` F3 block + `root_main.c`.
- sep. 20, 2026 — **⚠️ `PDR` ALONE SCORES 0.9987 vs a 0.7031 majority** (`analysis/leakage.py`, G402) ⇒
  **excluding leaking features does NOT answer the panel's 2:40-4:50 objection.** PDR is not leakage — it
  is the real, independently-observed effect — but a **100% drop rate in a fixed 180 s window is separable
  by construction.** Only attack-parameter variation fixes it, which collides with R-B (§1.4.1 excludes
  selective forwarding). **Adviser decides.** `eda.py` prints this every pass.
- sep. 20, 2026 — ⛔ **C7 OPTION 1 — APPROVED BY THE USER sep. 20, NOT YET IMPLEMENTED.** F3 killed the
  retry_count overload but not the ROLE GATE: honest nodes send TODS, so recv=0 and ForwardingRatio stays
  attacker-only. Option 1 = every node relays to its parent explicitly (P2P to `mesh_setup_get_parent_mac()`,
  always upward so no loops); it also makes attacker POSITION topologically meaningful and makes
  `BLACKHOLE_ATTACKER_MAC` targeting obsolete. Cost ('existing runs non-comparable') is lowest NOW.
- sep. 20, 2026 — **F1 `PHASE_ID_UNSET`/`GT_LABEL_UNSET` = 255.** A node that has not heard a broadcast
  RECORDS that instead of claiming baseline. ⚠️ **Host handling is NOT optional**: 255 is non-zero, so the
  phase-exit anchor would otherwise treat a node's FIRST window as its exit. Handled in
  `preprocess.assign_segments()` + `validate_integrity.PHASE_TO_LABEL`; `analysis/test_segments.py` proves
  **v1 and v2 give IDENTICAL segments**. Run `python test_segments.py` (no pytest here). Why: mesh_config.h.
- sep. 20, 2026 — **F2: attacker MAC is a RUNTIME value** (NVS, compiled constant as fallback);
  `export_logs.py --set/--get/--clear-attacker-mac`; takes effect on the NEXT boot. ⚠️ Since C7
  Option 1 this is **bookkeeping only** — victims no longer target the attacker by MAC at all.
- sep. 20, 2026 — **P5 `analysis/leakage.py`** = C7 Option 3 (exclude role-gated features from model
  inputs, with a written reason per column). **Superseded in part by C7 Option 1** — see the sep. 21
  dataset-aware entry above; full original text in ARCHIVE.md.
- sep. 20, 2026 — `analyze.ps1 -Verify` runs **three exit-code-checked gates** (integrity → topology →
  attack); a NOT-CONFIRMED after a failed gate reads **INCONCLUSIVE, not a negative result**.
- sep. 20, 2026 — `member_boards.json` had **child_8/child_10 transposed** (child_8 listed B4:90, actually
  70:68). Corrected against the boards' own telemetry — the export filename carries the nickname the board
  reports for itself and column 2 its MAC, so the boards are ground truth. Every other entry verified.
- sep. 20, 2026 — **`docs/DATA-DICTIONARY.md` written** — per-role meaning of every column, **no column
  holds an 802.11 MAC retry**, RSSI-is-per-link, root-is-layer-1. **Read it before writing schema text.**
- sep. 20, 2026 — **TESTBED SCENARIO IS EVIDENCE-BACKED; sources ALREADY in our bibliography.**
  **Khan et al. (2022), Sustainability 14(24):16630** — its ESP32+ESP-MESH air-quality nodes sit "at a
  different location on a COLLEGE CAMPUS". Cite: 120 s reporting interval; baseline PDR >97%, loss
  <1.8% — our corrected 0.998±0.025 lands INSIDE their range (a validation result). Karlof & Wagner
  (2003) = the "target deployment" cite. ⇒ **The gap is a measured floor plan + a declared traffic
  profile, NOT literature.** ⚠️ Zhukabayeva's "4-storey office building" detail is unverified.
- sep. 20, 2026 — **"Realistic data" resolved (panel 9:10-12:00).** Every dependent variable is
  network-layer and none depends on payload bytes ⇒ network behaviour MUST be real (it is); sensor
  VALUES may be synthetic; placement/RF context must be real AND RECORDED (the actual gap). The paper
  needs ONE paragraph stating measured vs generated. ⚠️ Do NOT slow the probe to 120 s — PDR
  resolution is probes-per-window; keep 1 Hz as the declared measurement instrument.
- sep. 20, 2026 — **P1/P2/P3 (analysis fixes) applied + verified — full entry in ARCHIVE.md.**
  Sigma is still 3; `BASELINE_FLOOR` was RAISED 0.50→0.90. Rationale lives in each code comment.
- sep. 20, 2026 — **SCOPE SETTLED by the user: "TinyTrust / Collaborative TinyML IDS" is DROPPED** — it came
  from an externally-suggested (ChatGPT) prompt template, not the adviser or panel. The thesis is and stays
  *Cross-Layer Dataset Design and Exploratory Analysis of ESP32-Based ESP-WIFI-MESH Network*, which does NOT
  implement an IDS and excludes Sybil (§1.4.1). Risk R1 CLOSED. Two attacks only: blackhole + wormhole.
  ⚠️ The user's prompt template still says "our thesis is focused on intrusion detection" — template
  residue, do not act on it.
- sep. 20, 2026 — **Five pre-fix diagnostics in ARCHIVE.md.** Still load-bearing: (a) ⚠️ **re-run
  M6→M7 on ANY cell analysed before sep. 20** (WINDOW_SECONDS bug hit every table since D-9);
  (b) **quotable proof the blackhole worked** — root arrivals **6.07/s → 0/s → 6.01/s**, attacker
  forwarded 2605/2600 baseline vs **1/1020** attack; (c) **Table 3.4's predicted victim-retransmission
  increase is a pre-registered MISS — REPORT it, do NOT edit the table** (§3.3.1.2 explains why).
- sep. 20, 2026 — Scope evidence: "TinyTrust"/"TinyML"/"intrusion detection system" appear ZERO times in the
  approved proposal or this repo (grep); the abstract says "Rather than implementing a real-time IDS".
- sep. 20, 2026 — **Attacker placement is not topological.** Valid chain of 8, but the attacker sits at
  **layer 7 of 8** — ONE victim downstream, five UPSTREAM, so those five send probes DOWN the chain and it
  relays them back UP. The attack works; the traffic pattern is not one a real forwarding adversary produces.
  The panel's "deployment appears random", made concrete. F2 (done) makes moving it cheap; **C7 Option 1 is
  what would make position actually mean something.**
- sep. 20, 2026 — Audit report Rev 3: https://claude.ai/artifact/RGB3RTXvfK7yzK9erEFNzE · the sep. 18 tooling batch + the sep. 16 root-as-blackhole-attacker proposal are in ARCHIVE.md; live threads carried in STATUS.md.

## Durable facts & constraints
- **Git repo root is this whole `Unified/` folder** (code, docs, `Paper/`, `ESP32-Environment/` all inside it),
  NOT `ESP32-Environment/` alone — branch `Unified`, remote `origin` =
  `https://github.com/Kemo1006/NIS16-ESP32-Environment`. GitHub IS the laptop-to-laptop transport: a `git pull`
  elsewhere gets the same MEMORY.md/STATUS.md/code. (Corrected sep. 17, 2026; was stale before that.)
- Thesis: DLSU CCS, CTTHES2/THES3. Proponents: Calpoporo, Carlos, Ong, Reinante. Adviser: Cu, Gregory G.
- Toolchain: ESP-IDF **v5.3.5** (bundles Python 3.11 + compiler); boards enumerate as "Silicon Labs CP210x USB to UART Bridge"; Windows reassigns COM numbers every plug — always re-check.
- Mesh identity is shared across every board: `MESH_ID {0xAB,0xCD,0xEF,0x01,0x23,0x45}`, `MESH_PASSWORD "MeshSecure2026!"` in `components/mesh_common/include/mesh_config.h` — never change between flashing root and victims.
- The FOLDER you build from decides the role, not the COM port: `root_node/` → root, `child_node/` → victim.
- Blackhole signature (M2): attack-window PDR ~0.08 vs 0.94 benign, ForwardingRatio ~0.02, root logs zero arrivals. Wormhole signature: duplicated `(src_mac, seq_num)` arrivals (×2 on the tunnelled node).
- **aug. 29, 2026 — honest nodes cannot observe their own forwarding** (MESH_DATA_TODS => the stack
  relayed below the app layer). ✅ **SOLVED sep. 21 by C7 Option 1 (D-12)** — every node now relays
  explicitly and reports real recv/forward/drop. Kept for the why; full text in ARCHIVE.md.
- Feature coverage is run-type-dependent: baseline 10/16, blackhole 13/16, wormhole 13/16, **combined matrix 16/16**. "No feature uniformly NaN" is a claim about the assembled dataset, not any single run.
- **THESIS 3 DRIVER — `Paper/Improvements.pdf`** (CTTHES2 panel comments, ~aug. 2026). 8 timestamped rows
  → 7 problems: single-feature decidability, no attack parameter variation, redundant r1–r3, one
  environment, no declared IoT scenario, no attack provenance, uncharacterised benign baseline. Plan:
  `Plan/THESIS3-PANEL-PLAN.md`. Attack-provenance answer is DONE: `docs/ATTACK-VALIDATION.md`.
- ⚠️ **Known leak (panel P1)** — role-gated features made "is this NaN?" a perfect label.
  ✅ **Root cause removed by C7 Option 1**; `leakage.py` now decides per dataset. ⚠️ PDR's 0.9987
  single-feature score is a SEPARATE problem and still open (see the sep. 20 entry).
- ⚠️ **Paper-scope conflict R-A:** paper §1.4.1 + abstract commit to a *"controlled indoor environment"*. The DLSU-campus decision deliberately relaxes that — must be amended in §1.4.1/abstract and logged in `thesis-deviate.md` as D-5, not slipped in.
- ⚠️ **Paper-scope conflict R-B:** paper §1.4.1 explicitly EXCLUDES *"grayhole, Sybil, or selective forwarding"* from the threat model. Partial/probabilistic drop rates ARE selective forwarding — so the obvious fix for the panel's "vary the attacks" comment collides with approved scope. Safest reading: the panel asked for different **attacker positions**, not different drop rates. Adviser decides (plan §7 R-B).
- ✅ **Already have a pre-registered attack signature (panel P6):** paper **§3.4.4 + Tables 3.4/3.5** state the expected observables for blackhole and wormhole, written at proposal time before any capture. Quote as-published; NEVER edit them to match results. §3.3.1.1/§3.3.2.1 hold the theory citations.
- **Attack-validation framing (panel P6):** validate by *definitional conformance* (canonical criteria vs
  what we implement, failures declared), matching signature SHAPE not absolute values — so LEACH/AODV/RPL
  sources are valid and need not be ESP32-specific. **Now written up in `docs/ATTACK-VALIDATION.md`.**
- **Two conformance gaps, both now MEASURED and written up** in `docs/ATTACK-VALIDATION.md`: (a) the
  blackhole is a *placed* relay — it does not ATTRACT traffic by false route advertisement; (b) the
  wormhole duplicates arrivals but does **NOT** re-form parent selection (0 switches, r2 and r3). The
  paper's own functional naming (§4.2.1.2/4.2.1.3, Tables 4.6/4.7) already makes the defensible claim.
- ✅ **§2.8 + Table 2.8 already survey existing wireless datasets** — extend that table for the dataset-comparison work, don't write a new section.
- ⚠️ **Known circularity (panel P6):** the blackhole attacker counts its OWN drops — the evidence the attack occurred comes from the node performing it. Needs an independent observer (sniffer node / monitor-mode adapter) or root-side accounting.
- Attack/traffic parameters are compile-time constants: drop rate 100% (`blackhole_victim.c`), `PROBE_INTERVAL_MS 1000`, `SAMPLING_INTERVAL_MS 100`, phases 60/300/180/120 s = 11 min (`mesh_config.h`). `run.ps1` exposes topology/role but **no attack-intensity flags**, so r1/r2/r3 still differ only in RF noise — the panel's 12:45-16:00 objection, unanswered. ✅ **Attacker POSITION is the one exception since F2**: it is a runtime NVS value now, no re-flash. Full pre-F2 text in ARCHIVE.md.
- I-017 recurring hazard: children left powered through a run's later phases overfill SPIFFS (~1.1 MB) and
  become unreadable on export → carry each child back UNPLUGGED; `board_check.py --port COMxx --wait 75`
  before a run (≥50% SPIFFS → wipe+flash first).
- ✅ **The old "verify the attacker MAC before EVERY blackhole run" run-killer is RETIRED** by C7
  Option 1 — victims no longer address the attacker by MAC, so a stale value is bookkeeping only.
  Its symptom (all-NaN PDR + empty arrivals + root probes_count stuck at 0) can now only mean
  something else, so do NOT reach for that diagnosis first. Full historical entry in ARCHIVE.md.
- ⚠️⚠️ **RECURRING ROOT BOOT-LOOP — check the root's power BEFORE every capture.** Symptom: boot count
  climbing every ~2 s, `rst:0x3 (SW_RESET)`, UART garbled mid-line, always as the radio powers up. Cause:
  **power brownout, not firmware** — the ROOT runs softAP+STA (a child runs STA only) and its brownout
  detector sits at the most sensitive default. Fix: root DIRECTLY into a laptop USB port, never a shared
  hub; known-good short cable. RULED OUT: the `MESH_STACK_MAX_LAYER_CHAIN` change. If a CHILD loops too,
  it's the shared supply, not root dual-radio draw. Full diagnosis in ARCHIVE.md.
- ⚠️ **WORMHOLE's run-killer is DIFFERENT — it has NO MAC at all**: the tunnel is a physical wired UART1
  link between the two endpoint boards, so its silent failure is a dead/mis-wired cable (Tunnel* features
  empty, both boards look healthy). ⚠️ **Node B CANNOT detect this** — `uart_write_bytes()` succeeds into
  an unterminated line, so B's counter climbs regardless; only Node A can prove a frame crossed. Guard on
  Node A: `s_tunnel_received == 0` at terminate prints a TUNNEL CARRIED NOTHING banner (check B-TX→A-RX +
  COMMON GROUND; `uart_link_test` is the bring-up project).


## Failed approaches — do not retry
- Passing `idf.py -D` flags as `@($spec.Flags)` — that is an array SUBEXPRESSION, not a splat, so both
  defines merge into ONE arg (`-DACTIVE_ATTACK="1 -DMESH_TOPOLOGY=2"` → build failure). Use a plain
  variable and `@flags`. `build_all_variants.ps1:47-53` documents the same gotcha.
- Spawning a build/flash window as plain `powershell.exe` — `idf.py`/`esptool.py` are POWERSHELL
  FUNCTIONS from `C:\Espressif\Initialize-Idf.ps1`, and functions don't survive into a child process.
  Dot-sourcing with no `-IdfId` also fails silently (`idf-env config get` returns the STRING "null").
  Fix in use: `Get-EspIdfActivation` reads the real Start Menu shortcut's `-IdfId` at runtime.
- Long `idf.py -B <dir>` build-directory names in this repo (e.g. `build_cc_verify`) — the workstation path is
  already deep, so object paths cross Windows' `MAX_PATH`/`CMAKE_OBJECT_PATH_MAX` and ninja fails inside the
  **bootloader** subproject, long after the app's own files compiled fine; the failure looks unrelated.
  ⚠️ Worse on a machine with a longer username (measured 265 chars on Angelo Calpoporo's, sep. 17).
  ✅ **Mitigation CONFIRMED WORKING sep. 20** on that same machine: short `-B` names build all 6 variants
  clean (`bh1`,`bv1`,`wa1`,`wb1`,`rb1`,`rn1`). Unapplied alternative: `LongPathsEnabled=1` (needs admin).
- Non-ASCII characters (`⚠`, `—`, `…`) in a Python tool's **module docstring** when it is passed to `argparse`
  as `description` — the Windows console is cp1252, so `--help` dies with `UnicodeEncodeError` before printing
  anything. `tools/command_center.py` is deliberately ASCII-only and calls
  `sys.stdout.reconfigure(encoding="utf-8")` before `rich` draws.
- Splitting recovered SPIFFS dumps on newlines after stripping page metadata — welds row tails to heads and fabricates data that passes a field regex. `recover_spiffs.py` now accepts only byte runs delimited by `
` on both sides.
` on both sides.
- `run_matrix.py --record` with hand-typed `--repeat` — silently re-recorded the wrong run. Use `--autorecord` (scans, validates, records; no flags to mistype).
- Powering the SD reader module's VCC from ESP32 3V3 — its onboard AMS1117-3.3 drops ~1.1-1.3V, leaving the
  card below its ~2.7V minimum. Symptom: CMD0 succeeds (R1=0x01) but ACMD41/OCR times out forever (0x107) —
  looks like wiring but isn't. Use VIN/5V; the module's 74HC125 level-shifter never puts 5V on ESP32 GPIOs.
- sep. 16, 2026 — Matching a `printf` format specifier to `sdmmc_card_t`'s `real_freq_khz`/
  `max_freq_khz` declared type — it differs by ESP-IDF version (see CLAUDE.md bootstrap facts).
  `sd_status.c`'s boot-check `rep()` now casts explicitly (`(unsigned long)x` + `%lu`) instead.
