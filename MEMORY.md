# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 22, 2026 — **CAPTURE DATES ARE REAL NOW: the board takes its clock from the laptop (`SET_TIME`).**
  The picker's date was never a run date — it was `sd_status_build_stamp()` (LINK-time `__DATE__`), identical on
  every boot of one flash: that is why deleting CSVs and re-running still showed `09/22 15:45`. No RTC, no NTP
  ⇒ only a host can supply one. New `SET_TIME=<epoch>`/`GET_TIME`: `settimeofday()` + save to `/sdcard/clock.txt`;
  `sd_status_apply_clock_anchor()` reads it next boot **after mount, before the folder tree** — that ordering is
  what makes Explorer's "Date modified" true (FatFs `get_fattime()` reads `time(NULL)`). FORWARD-only, so a stale
  card can't rewind a fresh time. `_push_host_time()` sends UTC on **every** `_open_port()`; `run.ps1 --set-time`
  runs **before** the erase/flash (erased board can't answer; a fresh build stamp would beat an older anchor and
  make the first post-flash run an estimate). `runs.csv` += `started`,`clock_src` (**appended last**; 7/8/10-col
  headers parse via `_manifest_when()`, 6 cases tested). Picker shows `started`, `~` = `clock_src=build` (EST). **All 6 variants `-Clean` build verified: 0 warnings, 0 errors.** ⚠️ **NEEDS REFLASH.**
- sep. 22, 2026 — **`status_NODE_<mac>.txt` is rewritten every boot and holds `Boot count:`, which IS the boot
  counter** — deleting it resets `b<n>` to 1. It is NOT what the picker dates files from (that is `runs.csv`,
  also the run-number + USB row-count/abort source). `DELETE_SD_FILE` accepts only `*_telem.csv`/`*_arrivals.csv`,
  so it, `runs.csv`, `location.txt` and `clock.txt` are all undeletable by design.
- sep. 22, 2026 — **CAMPAIGN CHECKLIST IS NOW A SCANNER, not a tick-box** (`inventory_cells.py`,
  `report_checklist()` rewritten; `report_plan()` and `--repeats N` untouched and re-verified).
  (1) **THREE states: `[x]` complete / `[~]` data captured but INCOMPLETE / `[ ]` nothing ever.** Before,
  "never attempted" and "attempted 5x, always just short" both rendered `[ ]`, hiding every hour spent.
  Only `[x]` counts toward M4. (2) **WHERE THE TICKED CELLS COME FROM** — each `[x]` names its source
  folder. This answers the recurring "all the data is in archive, why is it still checked?": the scan
  covers `tools/exports/` AND `archive/*/exports/` **by design** — archiving must not cost milestone
  credit. (3) **DOUBLE-COUNT DETECTOR** — same (cell, repeat, children, arrivals_rows) from 2+ sources.
  On first run it immediately flagged this session's own G402 duplicate across `2026-09-22_incomplete`
  + `_test`. (4) **CLOSEST TO DONE** — near-misses ranked by worst coverage %, each with its one-line
  blocker, so the next action is obvious (`home` 93.7% vs the 95% floor sits at the top).
  ⚠️ Column widths are computed FROM THE DATA — pre-redesign archives carry legacy folder names like
  `partial_mesh_topology` that shear a fixed-width table.
- sep. 22, 2026 — **WIZARD NOW HAS A SMART ARCHIVE FRONT END (`Invoke-ArchiveMenu`, DATA group).** The MOVE
  still lives in `archive.ps1` — one implementation — but the wizard adds the judgement it cannot make:
  (1) a per-CELL table with file count/size and **whether a root + arrivals file is present**;
  (2) **BYTE-IDENTICAL DUPLICATE DETECTION against every `archive/*/`** (name-match first, hash only
  collisions; `run_ledger.csv` skipped — regenerated header-only, would always false-positive);
  (3) a COMPLETE-run warning via `inventory_cells.py`; (4) a content-derived label suggestion;
  (5) preview-only (`-WhatIf`) / archive-now / list duplicates / cancel.
  ⚠️ **WHY (2) MATTERS — this session's own mistake:** `archive.ps1` MOVES data out of `tools/exports/`,
  which leaves the git-tracked paths as STAGED DELETIONS. Those deletions were read as data loss and
  `git checkout`-restored — recreating 9 G402 files that were already safe in
  `archive/2026-09-22_incomplete/`. Result: the SAME capture in two archives and `runs found` 36→37.
  **A staged deletion under `tools/exports/` usually means archive.ps1 moved it — check `archive/` BEFORE
  restoring with git.** The new detector was tested against exactly that duplicate and flagged all 9.
- sep. 22, 2026 — **`verify_attack.py` NOW PRINTS PER-NODE PDR under the pooled row — use THAT in the paper.**
  Pooled PDR averages nodes the attack never touched with nodes it annihilated, so it describes NO actual
  node. On blackhole/linear/home r1: pooled 0.514 = mean of victim H01 **1.0000** (upstream of the
  attacker, never transits it) and victim H03 **0.0137** (downstream, near-total loss) — a ~37x
  understatement of the real effect, and the pooled value moves run-to-run purely with where the attacker
  lands. The pooled row STAYS (the 3-sigma test consumes it); the split prints underneath, and a victim
  above the attacker is called out explicitly. ⚠️ Uses the PRE-`block_aggregate` frame (`df_nodes`) —
  `verify()` rebinds `df` to the pooled frame, which drops `node_role`/`hop` (first attempt printed `?`/`-`).
- sep. 22, 2026 — **FIXED: wizard [15] campaign checklist CRASHED at the end** — `run_wizard.ps1:2232`
  called `Read-YesNo`, which is defined ONLY in `menu.ps1` and never dot-sourced here, so it threw
  `CommandNotFoundException` AFTER printing the whole checklist. Now uses this file's own `Read-Line`
  idiom. Swept for the same class: `Get-BuildDirSpec`/`Show-MainMenu` appear in run_wizard.ps1 but only
  inside COMMENTS — `Read-YesNo` was the one real cross-script call.
- sep. 22, 2026 — **`build_all_variants.ps1` HARDENED + the 2 wormhole warnings FIXED.** New `-Clean`
  switch wipes every build dir first; a warm run now REFUSES to print "ALL VARIANTS BUILD CLEAN" and
  instead names the variants that reused cached objects. **Use `-Clean` for any M1 criterion-1 evidence.**
  Dead `mesh_data_t root_data`/`mdata` descriptors deleted from `wormhole_victim.c` (pre-C7 leftovers;
  both tasks send via `probe_relay_send_own()` — call sites traced, no behavioural change).
- sep. 22, 2026 — **NEW SCENARIO `jitter` (TRAFFIC_PROFILE=3) — ROOT ONLY, ADDITIVE ONLY.** The root draws a
  fresh random EXTENSION per boot for the baseline (0..`JITTER_BASELINE_MAX_S`=45s) and attack
  (0..`JITTER_ATTACK_MAX_S`=30s) windows via `esp_random()`, so phase transitions land at a different
  wall-clock offset every run. **WHY:** every run used the identical schedule (60/300/180/120), so
  `leakage.py` lists `window_start` as METADATA — elapsed time alone scored **0.857** against the label
  without looking at the network. That is the panel's 12:45-16:00 "runs are all identical" objection, and
  `eda.py`'s survivors warning names attack-parameter variation as THE fix (not feature exclusion).
  ⛔⛔ **NEVER MAKE THE JITTER SUBTRACTIVE.** `preprocess.py` resolves real baseline as "the LAST
  `PHASE_BASELINE_S` of phase 0", anchored backwards from each node's phase-0 exit. A baseline SHORTER
  than 300s would make that slice reach past the real baseline's start and pull mesh-formation noise into
  the benign class — wrong, and still plausible-looking. Additive keeps every existing host rule correct
  with ZERO analysis-side change. Not in the CSV and doesn't need to be: real durations are recoverable
  from any node's phase_id transition timestamps. Root-only because only the root schedules phases — a
  jitter child binary would be byte-identical to a plain one. Wired into `run.ps1`, `run_wizard.ps1` and
  `menu.ps1` (scenario lists + build-dir suffix + flag mapping all kept in sync).
- sep. 22, 2026 — **FIRST CLEAN r1 CAPTURE VERIFIED end-to-end (blackhole/linear/home) — attack CONFIRMED.**
  Chain: ROOT(H00)-victim1(H01, direct child of root)-ATTACKER(H02)-victim2(H03). `verify_attack.py`:
  **BLACKHOLE CONFIRMED**, ForwardingRatio 1.000→0.026, PDR 1.000→0.514. Phase 0 clean (300.4s on all 4
  boards) — **NOT luck: F1 (sep. 20) already fixed this**, recording `PHASE_ID_UNSET=255` before any
  broadcast is heard instead of mislabelling it phase 0; `preprocess.py` excludes 255 as `pre_baseline`.
  ⚠️️ **FINDING: aggregate PDR (0.514) HIDES a near-total per-victim split** — victim1 (upstream of
  attacker, direct root child) stayed at PDR=1.000 through the ENTIRE attack window (untouched); victim2
  (downstream) crashed to PDR=0.0137 (near-total). Pooling both into one PDR number is the exact positional
  effect flagged today in blackhole_victim.c's header — now proven on real data. **Report PDR per-node-
  relative-to-attacker in the write-up, not pooled.** ✅ **Checked, NOT a gap: `leakage.py`'s survivors
  warning (eda.py:993) ALREADY catches ForwardingRatio/ConsistencyScore at 99.9% accuracy on this exact
  run** (`lift_over_majority` 0.30 > the 0.15 print threshold) — confirmed by direct call, not just reading
  the CSV. **Deliberately NOT auto-excluded**: the code's own documented reasoning is that a fixed-schedule
  attack window is separable BY CONSTRUCTION in any single run, so excluding by accuracy alone would hide
  real signal along with the leak. Its stated fix is attack-PARAMETER VARIATION across repeats (panel
  12:45-16:00), not a code change — no `leakage.py` edit needed or made.
- sep. 22, 2026 — **CONSOLE SAYS `HOP`, NOT `LAYER` (adviser) + the blackhole's position is now GUARDED.**
  "Layer" reads as an OSI layer; this is a mesh TREE depth (the mesh runs BELOW IP). Renamed across the root
  dashboard + `topology_graph.c`'s star reason. ⚠️ **Off-by-one is deliberate — ESP-WIFI-MESH numbers the
  ROOT layer 1, so hop = layer-1 and the ROOT IS H00**, matching `preprocess.py:768`'s `hop` (D-11); the
  console now agrees with the dataset. `fmt_layer()` deleted → `fmt_hop()`. **The raw firmware CSV still
  writes `layer`**; renaming that column is a schema change hitting every script + every existing capture —
  NOT done, ask first. Also: `blackhole_victim.c`'s header described the PRE-C7 model and contradicted its
  own code — rewritten. New **leaf/off-path guards** (a blackhole with nothing under it drops nothing and
  the capture still passes EVERY check): attacker warns after 10 s of attack-phase at recv=0
  (`LEAF_WARN_AFTER_MS`); the ROOT dashboard, which alone sees the whole tree, shouts before the window
  opens. New `TOPOLOGY TREE` block prints BELOW the existing tables — nothing previously printed changed.
  ✅ **6/6 variants BUILD CLEAN on ESP-IDF 5.5.4**, 0 warnings. **REFLASH ALL.** ❌ **DECLINED: hex
  `I (622272)` timestamp** — ESP-IDF's standard prefix, not ours; hex-ing it IS "we invented our own format".
- sep. 22, 2026 — ⚠️ **PS 5.1 PROMOTES A NATIVE COMMAND'S FIRST STDERR LINE TO A TERMINATING ERROR**
  under `$ErrorActionPreference='Stop'` — so a tool that writes a progress bar to stderr (`export_logs.py`)
  kills its PowerShell caller with an EMPTY exception message. Both `run_wizard.ps1` import calls now wrap
  in `'Continue'` + `finally` restore. **Grep every `& python ... 2>&1` before shipping.** ⚠️ Editing
  `run_wizard.ps1` does NOT affect an ALREADY-RUNNING wizard — exit [17] and relaunch. Detail: ARCHIVE.md.

## Durable facts & constraints
- sep. 22, 2026 — ⚠️⚠️ **PLUG BOARDS DIRECT INTO THE LAPTOP — NEVER THE DOCK OR ANY HUB.** Win11 26200
  hard-crashed 2x (BSOD `ATTEMPTED_SWITCH_FROM_DPC` 0xB8) during export / `DELETE_SD_FILE` / `SET_LOCATION`.
  HOST DRIVER fault, **not the firmware or scripts** — nothing an ESP sends over a COM port can crash Windows.
  Confirmed by the PnP parent chain: every CP210x sat 2-3 Genesys hubs deep behind the Dell D6000 dock,
  sharing one Intel root port with its DisplayLink video chip. USB selective suspend now off (AC+DC); still to
  do: update CP210x + DisplayLink drivers. Dumps in `C:\Windows\Minidump`. Detail: ARCHIVE.md.
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
- ⚠️ **WORMHOLE's run-killer: the tunnel is a WIRED UART link, so its silent failure is a dead cable**
  (Tunnel* features empty, both boards look healthy). ⚠️ **Node B CANNOT detect it** —
  `uart_write_bytes()` succeeds into an unterminated line; only Node A can prove a frame crossed.
  Guard on A: `s_tunnel_received == 0` at terminate prints a TUNNEL CARRIED NOTHING banner.

## Failed approaches — do not retry
- Passing `idf.py -D` flags as `@($spec.Flags)` — that is an array SUBEXPRESSION, not a splat, so both
  defines merge into ONE arg (`-DACTIVE_ATTACK="1 -DMESH_TOPOLOGY=2"` → build failure). Use a plain
  variable and `@flags`. `build_all_variants.ps1:47-53` documents the same gotcha.
- Spawning a build/flash window as plain `powershell.exe` — `idf.py`/`esptool.py` are POWERSHELL
  FUNCTIONS from `C:\Espressif\Initialize-Idf.ps1`, and functions don't survive into a child process.
  Dot-sourcing with no `-IdfId` also fails silently (`idf-env config get` returns the STRING "null").
  Fix in use: `Get-EspIdfActivation` reads the real Start Menu shortcut's `-IdfId` at runtime.
  ⚠️ **sep. 22, 2026 — `export.ps1` ALSO fails here and LOOKS LIKE "ESP-IDF is not installed". It is.**
  `activate.py` derives the venv name from whichever `python` is first on PATH (3.12 on Angelo's box), then
  reports `idf5.5_py3.12_env ... not found`. The real venv is **`idf5.5_py3.11_env`**. Never conclude IDF is
  absent from an `export.ps1` failure — check `C:\Espressif\idf-env.exe config get` first. Working line:
  `. C:\Espressif\Initialize-Idf.ps1 -IdfId esp-idf-20ee62e792ea89630ac6a777ab3ebc57` (**this laptop = v5.5.4**).
- Long `idf.py -B <dir>` names — deep paths pass Windows `MAX_PATH`; ninja fails in the **bootloader**
  subproject long after the app compiled, so it looks unrelated. Fixed by short per-variant `Bld` names
  (`bcr`,`bcba`,…) + a preflight warning. ⚠️ **Don't rename them back.** Detail: ARCHIVE.md.
- Non-ASCII in a Python tool's **module docstring** passed to `argparse(description=)` — cp1252 console ⇒
  `--help` dies with `UnicodeEncodeError`. Keep them ASCII; `sys.stdout.reconfigure(encoding="utf-8")` first.
- Powering the SD reader module's VCC from ESP32 3V3 — its onboard AMS1117-3.3 drops ~1.1-1.3V, leaving the
  card below its ~2.7V minimum. Symptom: CMD0 succeeds (R1=0x01) but ACMD41/OCR times out forever (0x107) —
  looks like wiring but isn't. Use VIN/5V; the module's 74HC125 level-shifter never puts 5V on ESP32 GPIOs.
- sep. 16, 2026 — Matching a `printf` format specifier to `sdmmc_card_t`'s `real_freq_khz`/
  `max_freq_khz` declared type — it differs by ESP-IDF version (see CLAUDE.md bootstrap facts).
  `sd_status.c`'s boot-check `rep()` now casts explicitly (`(unsigned long)x` + `%lu`) instead.
