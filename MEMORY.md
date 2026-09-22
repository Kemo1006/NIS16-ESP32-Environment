# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 23, 2026 — **THE PHASE SCHEDULE IS DECLARED TWICE AND NOTHING CHECKED THEY AGREE — now it does.**
  `mesh_config.h`'s `PHASE_*_S` are overridable at build time (`-DPHASE_BASELINE_S=180`) but `preprocess.py`
  and `validate_integrity.py` carry their own copies. Damage is silent and ONE-DIRECTIONAL: `preprocess.py`
  slices baseline BACKWARDS from the phase-0 exit, so a firmware baseline SHORTER than the host assumes
  reaches past the real start and labels mesh-formation noise BENIGN. Both now MEASURE real durations from
  `phase_id` transitions: warn on SHORT, note LONG (normal — `jitter` extends phases), `--phase-durations`
  declares a different schedule, `preprocess.py` reports `short_baseline` per node. Verified with a wrong
  nominal (`0=600`): silent when they agree, loud when not. **Still duplicated — but never silent now.**
- sep. 23, 2026 — **"VICTIM" IS DERIVED FROM THE TOPOLOGY, not the firmware role** (`analysis/exposure.py`).
  New `exposure` column per node per run: `root`/`attacker`/`downstream` (**the REAL victims**)/`upstream`
  (present, unreachable by the attack)/`no_attacker`/`unknown` (chain unresolved — never folded into another
  value). Resolved from `parent_mac` (parent's SoftAP BSSID = STA+1), preferring the parent held DURING the
  attack window, with a cycle guard. Verified: `downstream` → attack PDR **0.0000**, `upstream` → **1.0000**.
  `verify_attack.py` prints "built as" vs "exposure" and names only downstream nodes VICTIM.
  ⚠️ **In `leakage.py` METADATA_COLUMNS** — in an attack window "downstream" is nearly the label.
- sep. 23, 2026 — **FIRMWARE ROLE RENAMED `victim`→`child` (Change B, DONE).** `victim_main.c` writes `child`;
  a plain child is only a VICTIM if the attacker sits between it and the root, which `exposure` now says.
  ⚠️ **The compat map is what makes this safe:** `preprocess.py`'s `ROLE_ALIASES` folds BOTH spellings to the
  canonical `child` at the ONE place `node_role` is produced, so pre-2026-09-23 captures (which say `victim`
  forever) keep working. `features.py` gates on `CHILD_ROLE`, deliberately NOT on both spellings — accepting
  both there would hide a canonicalisation that had stopped running. **Verified by regenerating
  feature_table.csv and diffing: shape identical (3502x66), `node_role` the ONLY column that changed, PDR
  non-null 1318 and sum 1074.0 unchanged.** ⚠️ **NEEDS REFLASH** before the next capture.
- sep. 23, 2026 — **DE-HARDCODED the machine-specific paths.** `Get-EspMac.ps1` pinned `esp-idf-v5.3.5` +
  `idf5.3_py3.11_env` — **dead on a 5.5.4 laptop, symptom just "no MAC"**. It and `board_check.py` now discover
  via `IDF_PATH`/`IDF_TOOLS_PATH`, then glob `<SystemDrive>\Espressif` newest-first. `C:\Python314\python.exe`
  in all 3 menus → the `py` launcher. `board_check.py`'s MAC→label table is overridable by
  `presets/boards.json` (`--roster`) so a new board needs no code edit — NOT the per-run presets, which
  disagree by design. Detail: ARCHIVE.md.
- sep. 23, 2026 — **TIMESERIES PLOTS WERE MISALIGNED — fixed.** `window_start` is each node's OWN clock from
  ITS boot and boards are flashed one at a time (phase 0 began 60s in on the root, **670s on node2** — why its
  baseline "starts at 600s"; harmless, phase 255 is dropped). Bands came from whichever node sorted first.
  `_align_to_baseline()` re-bases on each node's phase-0 entry; **anchor on the RAW `segment` column, not
  `_phase_names()`** (returns "Baseline", never matches). Also `_extract_run_id()` expected the OLD filename,
  so the overlay never existed. ⚠️ **BOTH views are written and BOTH are wanted** (per-run overlay AND one per
  capture file) — per-run alone silently dropped plots the team uses. Detail: ARCHIVE.md.
- sep. 23, 2026 — **KEEP `RetryRate` in the blackhole signature; the stale comment was the only problem.**
  Its removal condition ("once retry_count means MAC-layer failure on every role") IS met — verified in
  `blackhole_victim.c:378-386`, F3 moved deliberate drops to `drop_count`. But that killed the LEAK, which is
  the argument for KEEPING it: the FAIL is now an honest clean negative, and Table 3.4's pre-registered
  prediction missing is a result to REPORT, not to delete. Dropping it would read as hiding a failed prediction.
- sep. 22, 2026 — **`vTaskDelay`→`xTaskDelayUntil` IN ALL 4 TELEMETRY LOOPS — THE M5 COVERAGE BLOCKER'S ROOT
  CAUSE.** They slept 100ms AFTER the body, so the real period was body+100ms; with `CONFIG_FREERTOS_HZ=100`
  (10ms tick) any non-zero body cost a whole tick. Root measured **110.0ms = 9.09Hz → 93.6%** vs the 10Hz the
  validator assumes — **with ZERO gaps** (longest interval 0.36s). Nothing was lost; no node with a >0ms body
  could ever have passed. Fixed in `root_main.c`, `blackhole_victim.c`, `victim_main.c`, `wormhole_victim.c`;
  **6/6 `-Clean` build verified, 0 warnings.** ⚠️ **Re-measure coverage after the reflash before M5 is done.**
- sep. 22, 2026 — ⚠️ **M3 CONVERGENCE FAILS on the sep. 22 home run.** node2 (`B0CBD8F33218`, hop 1) took
  **607.1s** to converge, 3 parent_switches, 6 layer_changes (others 0-31s / 0) — explains its 647s of
  phase-255 idle, its 11906-row file and likely its ~8.6Hz attack/cooldown cadence. `verify_topology.py`:
  "Converged within 60s: NO". Structure itself is CORRECT linear H00-H03. Run it with `--dir tools/exports`
  (the exports ROOT, not a leaf cell).
- sep. 22, 2026 — **`validate_integrity.py`: WARN separates LOST DATA from SLOW CADENCE; derived dirs skipped.**
  It said "node was dropping samples" for pure cadence drift. Now reports median interval + gaps-vs-own-cadence
  and names which. `_find_csvs()` prunes `trimmed/`,`_archive/`,`archive/` (`--include-derived` restores):
  trimmed output is **byte-identical to raw when a capture holds ONE boot session — the HEALTHY case** (all 5
  live captures verified: 1 session, 0 regressions). **`trimmed/` is correct — do not delete or "fix" it.**
- sep. 22, 2026 — **DATA SYNC: follows your CURRENT BRANCH, and pushes ANALYSIS + EDA** (`push_data.py`
  `--area analysis`). `--branch` was hardcoded `"Unified"`. ⚠️ **TWO BUGS IT EXPOSED — the push SILENTLY did
  nothing:** the private clone carries the same `.gitignore`, so `git add` skipped every analysis path without
  a word (needs `-f`); and "already on GitHub?" was answered from the clone's WORKING TREE, so leftovers from
  the failed push made every later run say "already on GitHub, identical" forever. **Verify a push against the
  REMOTE (`git ls-tree origin/<branch>`), never the tool's own summary.** Full detail: ARCHIVE.md.
- sep. 23, 2026 — **`analysis/eda.py` plot readability overhaul + new `analysis/column_legend.py`.**
  Analysis-only, no reflash, Basti's clone (not `A:\Angelo\...`). **UNCOMMITTED.** **Bug fixed:** phase
  shading compared raw `Label` (NaN on unlabelled rows), stacking hundreds into one red block that read as
  the attack; now compares `segment`-derived names, and PCA/t-SNE drop unlabelled windows too — moved
  `blackhole/linear/home`'s PCA variance 30.5/23.0%→39.1/28.0% (the exclusion, not new data). ⚠️ Masking
  the heatmap's upper triangle was tried and REJECTED by the user — don't reintroduce. `column_legend.py`'s
  `_L` dict is now the single source of column meanings (checked vs `docs/DATA-DICTIONARY.md` + firmware).
- sep. 22, 2026 — **CAPTURE DATES ARE REAL: the board takes its clock from the laptop (`SET_TIME`).** The
  picker's date was `sd_status_build_stamp()` (link-time `__DATE__`), identical on every boot of one flash —
  why deleting CSVs and re-running still showed the same date. No RTC, no NTP ⇒ only a host can supply one.
  `SET_TIME`/`GET_TIME` + `/sdcard/clock.txt`; the anchor is applied **after mount, before the folder tree**,
  which is what makes Explorer's "Date modified" true. FORWARD-only. `runs.csv` += `started`,`clock_src`.
  ⚠️ **NEEDS REFLASH.** Full detail: ARCHIVE.md.
- sep. 22, 2026 — `status_NODE_<mac>.txt`/`runs.csv`/`location.txt`/`clock.txt` roles + why `DELETE_SD_FILE`
  only accepts `*_telem.csv`/`*_arrivals.csv` — full detail ARCHIVE.md.
- sep. 22, 2026 — **CAMPAIGN CHECKLIST IS A SCANNER** (`inventory_cells.py`): `[x]` complete / `[~]` captured
  but INCOMPLETE / `[ ]` never — only `[x]` counts toward M4. Scans `tools/exports/` AND `archive/*/exports/`
  **by design** (archiving must not cost milestone credit); flags double-counted cells. Detail: ARCHIVE.md.
- sep. 22, 2026 — **WIZARD SMART ARCHIVE FRONT END** (`Invoke-ArchiveMenu`): per-cell tables, byte-identical
  duplicate detection across every `archive/*/`, COMPLETE-run warning, `-WhatIf`. ⚠️ **`archive.ps1` MOVES
  data, so git shows STAGED DELETIONS under `tools/exports/` — check `archive/` BEFORE `git checkout`-ing
  them back; doing that once recreated 9 files already safely archived.** Detail: ARCHIVE.md.
- sep. 22, 2026 — **`verify_attack.py` PRINTS PER-NODE PDR under the pooled row.** The pooled value averages
  an untouched upstream node with an annihilated downstream one and describes NOBODY — quote the per-node
  split in the write-up. Superseded in part by the `exposure` column (above). Detail: ARCHIVE.md.
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
- sep. 22, 2026 — **SCENARIO `jitter` (TRAFFIC_PROFILE=3) — ROOT ONLY, ADDITIVE ONLY.** Random per-boot
  EXTENSION to baseline/attack windows so phases don't land at the same offset every run (elapsed time alone
  scored 0.857 against the label). ⛔ **NEVER SUBTRACTIVE** — a shorter baseline pulls mesh-formation noise
  into the benign class. Full rationale: ARCHIVE.md.
- sep. 22, 2026 — **FIRST CLEAN r1 CAPTURE VERIFIED (blackhole/linear/home) — attack CONFIRMED.**
  ForwardingRatio 1.000→0.026, PDR 1.000→0.514. ⚠️ **Aggregate PDR HIDES a positional split:** the victim
  UPSTREAM of the attacker stayed at PDR=1.000 throughout; the downstream one fell to 0.0137. Pooling
  describes no real node — **report PDR PER NODE relative to the attacker.** ✅ NOT a gap: `leakage.py`'s
  survivors warning already catches ForwardingRatio/ConsistencyScore; the documented fix is attack-PARAMETER
  VARIATION across repeats, not a code change. Full detail: ARCHIVE.md.
- sep. 22, 2026 — **CONSOLE SAYS `HOP`, NOT `LAYER` (adviser); root = H00.** ESP-MESH `layer` is 1-based, so
  the console now prints hop = layer-1 and agrees with the paper. Blackhole header rewritten to the C7
  positional model; leaf/off-path guards added; `TOPOLOGY TREE` block added. Full detail: ARCHIVE.md.
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
- Spawning a build/flash window as plain `powershell.exe` — `idf.py`/`esptool.py` are POWERSHELL FUNCTIONS
  from `Initialize-Idf.ps1` and don't survive into a child process; dot-sourcing without `-IdfId` fails
  silently. ⚠️ **`export.ps1` ALSO fails and LOOKS LIKE "ESP-IDF is not installed" — it is not:** it builds
  the venv name from whichever `python` is first on PATH (3.12) and hunts `idf5.5_py3.12_env`; the real one
  is `idf5.5_py3.11_env`. Check `idf-env.exe config get` before concluding anything. Detail: ARCHIVE.md.
- Long `idf.py -B <dir>` names — deep paths pass Windows `MAX_PATH`; ninja fails in the **bootloader**
  subproject long after the app compiled, so it looks unrelated. Fixed by short per-variant `Bld` names
  (`bcr`,`bcba`,…) + a preflight warning. ⚠️ **Don't rename them back.** Detail: ARCHIVE.md.
- Non-ASCII in a Python tool's **module docstring** passed to `argparse(description=)` — cp1252 console ⇒
  `--help` dies with `UnicodeEncodeError`. Keep them ASCII; `sys.stdout.reconfigure(encoding="utf-8")` first.
- SD reader module VCC/format-specifier wiring & build gotchas — both fixed in code; full text ARCHIVE.md.
