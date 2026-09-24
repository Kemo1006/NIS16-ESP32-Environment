# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 24, 2026 — **`run_wizard.ps1` multi-laptop roster: "N boards need ports" warning was WRONG whenever the roster
  is split** (step 6 always added +1 for root even after the operator had just said root is on ANOTHER laptop — said
  "5 boards need ports" right after a "root not here" answer). Fixed: that warning only fires when NOT multi-laptop
  (root/children are only sorted into local-vs-remote per-board, in step 7's `Select-PortOrRemote`, which already
  handles it correctly). Also added 3 clarifying banners (root-remote confirmation, child-count multi-laptop example,
  one-time "you'll be asked per board" notice before step 7) — the child COUNT is always the FULL experiment across
  every laptop, never just this one's; per-board "is it here?" is what actually sorts local from remote.
- sep. 23, 2026 — ⛔→✅ **`MESH_FORCE_HT20` first version BROKE mesh formation; FIXED + HARDWARE-VERIFIED same day.**
  Broken run: 0 nodes joined in 11 min (root `NODE COUNT` 1, children `AP:0`). Cause: `apply_rf_width()`
  forced 20 MHz AFTER `esp_wifi_start()` (no-op: STA iface not up, stayed 40 MHz) and AFTER `esp_mesh_start()`
  (hit the scan/AP as they came up; child scan aborted `SCAN_DONE status:fail`). Fix (`mesh_setup.c`):
  `esp_wifi_set_mode(WIFI_MODE_APSTA)` + force HT20 BEFORE `esp_wifi_start()`; nothing after mesh start;
  CONNECTED handlers still re-check (`only_if_ht40`). **Verified on 4 boards, wizard order (root parked,
  children searching ~45 s alone):** all joined, chain root→attacker→node4→node2, `NODE COUNT 4` stable
  3 min, every board `STA 20 MHz, AP 20 MHz` from boot, no `forced to 20 MHz` corrections, phase 0 reached
  all children. ⚠️ Don't move the width call after `esp_wifi_start()` again. (`Root: NO` in the root's
  "Mesh connected" line is PRE-EXISTING cosmetic: routerless root never gets PARENT_CONNECTED.)
- sep. 23, 2026 — **`MESH_FORCE_HT20 1` (mesh_config.h): all boards now run 20 MHz, not the ESP32-default HT40.** Why: the M1 Mac
  Sniffer offers 20 MHz ONLY and can't decode 40 MHz data (real capture: beacons fine, root 0 / child 3 data frames). `apply_rf_width()`
  in mesh_setup.c sets it at wifi/mesh start and re-checks on connect. ⚠️ HT40 captures (all before this) ≠ HT20 — label, don't pool. SD report [6] now prints 'RF width: ...'. CSV schema + analysis untouched (verifier is same-run relative; no absolute RSSI cut-offs). Builds clean; NOT hardware-verified.
- sep. 23, 2026 — **`tools/check_pcap.py` + wizard "Check a Mac sniffer capture file"** (stdlib, pcap+pcapng): finds mesh nodes
  by behaviour — mesh beacons have a HIDDEN SSID (not `ESPM_*`) + scrambled IE, so node = hidden-SSID beacon whose MAC−1 also transmits.
  Verified on the real 126 MB M1 capture (sep. 23, `Downloads\Jose's MacBook Air_ch11_...pcap`): exactly 4 boards, 1848 mesh DATA frames, root sent 0 → likely 20 MHz width missed HT40 data.
- sep. 23, 2026 — **`run.ps1` now flashes and monitors as TWO calls; a failed flash retries once at `-b 115200`, then `exit 1`
  before export.** Why: COM4 hit `Failed to leave compressed flash mode (C800)` (USB serial glitch) and the old combined
  `flash monitor` fell through into exporting a freshly-erased board. ⚠️ Mesh runs at **HT40 (log: `channel 11, 40D`)** — Mac Sniffer width may need 40 MHz for data frames.
- sep. 23, 2026 — **MAC WIRELESS DIAGNOSTICS SNIFFER gave a 0-BYTE file (M1, full run).** Likely cause: the
  guide said "turn Wi-Fi OFF" (true for Wireshark monitor mode only) — the Sniffer needs Wi-Fi ON but DISCONNECTED.
  New wizard item **MacBook sniffer test** (`Invoke-MacSnifferTest`, ~2 min, no attack; listens to root serial to prove the air had traffic). ✅ sep. 23: short test PASSED (packets seen); full-run capture still unverified.
- sep. 23, 2026 — **Tree positions are NOT hardcoded**: each node self-reports its parent MAC + role in its heartbeat;
  the root links them. Early prints show a PARTIAL tree (nodes report ~1 s apart) → a FALSE `NO NODE IS DOWNSTREAM` error.
  Fixed in `mesh_setup.c`: exposure verdict waits until heartbeat entries >= `esp_mesh_get_routing_table_size()`.
  ⚠️ sep. 24: a `NO NODE IS DOWNSTREAM` with ALL nodes reported (`REACHABLE` = `NODE COUNT`) is REAL, not this bug — LINEAR
  = 1 child/node, so chain order = JOIN order (+RSSI). Attacker must sit at `H01`: place it nearest the root, reset victims to rejoin.
- sep. 23, 2026 — **BOARD DATES ARE NOW PHILIPPINE TIME (PHT, UTC+8)** — user's choice. `SD_CLOCK_TZ "PHT-8"` in
  `mesh_config.h`, set in `sd_status_seed_clock()`; stamps use `localtime_r`. Epoch (clock.txt/SET_TIME) stays true UTC.
  ALSO FIXED: the build stamp (PH wall clock) was read as UTC → 8 h in the future → every SET_TIME anchor lost to it
  (`card anchor is older than the build stamp`), so NO capture ever got a real date. Building outside UTC+8 breaks this.
- sep. 23, 2026 — ⛔ **STALE-ROOT TERMINATE killed a run** (root table showed only itself). Root is flashed LAST, so
  the OLD root keeps running; its TERMINATE (`phase_id=4 root_ts=667 s`) is accepted by fresh children (seq starts at 0).
  Fix: `run_wizard.ps1` PARKS the root in its ROM bootloader (`esptool --after no_reset`, verified) before the first child, and
  WAKES it (hard reset + 10 s) just before its run.ps1 call. NOT an early erase: that would break run.ps1's SET_TIME (real clock).
- sep. 23, 2026 — ⚠️ **`WIRESHARK-GUIDE.md` had ROOT and a CHILD SWAPPED** — listed `b0:cb:d8:f3:32:18` as
  ROOT; the real root is `70:4b:ca:25:b7:68` and `b0:cb…18` is the UPSTREAM child, so every "root" filter
  pointed at a child. Fixed + a one-liner to re-derive. Filter 4 is **attacker → its PARENT**, not "→ root".
  `simple_sniffer` DOES exist in 5.5.4. Detail: ARCHIVE.md.
- sep. 23, 2026 — ⚠️ **`exposure.py` MUST use the ATTACK-WINDOW parent, not the whole-run mode.** node2 sat
  BELOW the attacker for its entire 671-window pre-baseline, then re-parented to the root. Whole-run mode is
  dominated by those rows and returns the ATTACKER as its parent (node2/attacker even look like a 2-cycle) —
  labelling a node whose PDR was 1.000 as `downstream`. **Never simplify `_dominant_parent()` to a plain
  mode.** Detail: ARCHIVE.md.
- sep. 23, 2026 — **ROLE-GATE COVERAGE GUARD** (`features._warn_on_missing_attack_role`): manipulation
  features are gated on `node_role == "<attacker>"` behind `if mask.any()`, so a ZERO-row gate computes
  nothing and SAYS nothing — `ForwardingRatio` (PRIMARY) silently all-NaN. Now warns, naming roles present.
  Detail: ARCHIVE.md.
- sep. 23, 2026 — **AUDIT of groupmate `fac59c5`/`13b607c` (LAYER-HOP-MAC explainer): every load-bearing
  number FACT-CHECKED and CORRECT** — `MESH_ROOT_LAYER (1)` (re-verified in 5.5.4), `layer -1 → NaN`, SoftAP
  = STA+1 on all 4 values, attacker `recv 180/fwd 0/drop 180`, arrivals `301→0→121` vs `300→180→121`.
  No errors. Also: baseline FR is genuinely n=600 sd=0.000000 (the lone `FR>1` is a pre_baseline queue
  flush, EXCLUDED). Detail: ARCHIVE.md.
- sep. 23, 2026 — **PANEL EVIDENCE for hop/`parent_mac` is ESPRESSIF'S OWN HEADER — cite it, not our code:**
  `#define MESH_ROOT_LAYER (1)` (`esp_mesh.h`, IDF v5.3.5) + the IDF MAC table ("Wi-Fi SoftAP: base_mac, +1 to
  the last octet") answer both "why hop = layer−1" and "why `parent_mac` matches no `node_id`" (SoftAP vs STA).
  Plain-language version (analogies, panel script, no code-reading required) written to
  `docs/2026-09-23_LAYER-HOP-MAC-EXPLAINER.md` — companion to `REVIEWER-QUESTIONS.md` §3/§7, not a replacement.
- sep. 23, 2026 — **THE ROOT NAMES THE VICTIMS LIVE, DURING THE RUN** (`mesh_setup.c` EXPOSURE block):
  ATTACKER / VICTIM / "not in the attack path" per node, and **errors when NO node is downstream** — catches
  bad attacker placement BEFORE burning an 11-minute run. Console role `VICTIM`→`CHILD` (enum VALUE is on the
  wire, unchanged). `verify_topology.py` gained an EXPOSURE column. Detail: ARCHIVE.md.
- sep. 23, 2026 — **PHASE-SCHEDULE MISMATCH IS NO LONGER SILENT.** Host tools MEASURE phase durations from
  `phase_id` transitions — warn SHORT (preprocess slices baseline BACKWARDS, so a short firmware baseline
  labels formation noise BENIGN), note LONG (`jitter`). `--phase-durations` overrides. Detail: ARCHIVE.md.
- sep. 23, 2026 — **`exposure` COLUMN: who the attack could actually reach** (`analysis/exposure.py`):
  `root`/`attacker`/`downstream` (**the REAL victims**)/`upstream`/`no_attacker`/`unknown`. Verified:
  `downstream` → attack PDR **0.0000**, `upstream` → **1.0000**. ⚠️ **In `leakage.py` METADATA_COLUMNS**.
  Detail: ARCHIVE.md.
- sep. 23, 2026 — **FIRMWARE ROLE `victim`→`child`.** ⚠️ `preprocess.py`'s `ROLE_ALIASES` folds BOTH
  spellings to canonical `child` at the ONE place `node_role` is made, so old captures still work;
  `features.py` gates on `CHILD_ROLE`, deliberately NOT both. Verified: only `node_role` changed, PDR
  unchanged (it sits behind the gate, so that IS the proof). ⚠️ **REFLASH.** Detail: ARCHIVE.md.
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
- sep. 22, 2026 — **DATA SYNC follows your CURRENT BRANCH; pushes ANALYSIS + EDA** (`--area analysis`).
  ⚠️ **Two bugs it exposed — the push SILENTLY did nothing:** the private clone carries the same
  `.gitignore` (needs `git add -f`), and "already on GitHub?" read the clone's WORKING TREE, so leftovers
  from the failed push made every later run claim "identical" forever. **Verify against the REMOTE
  (`git ls-tree origin/<branch>`), never the tool's summary.** Detail: ARCHIVE.md.
- sep. 23, 2026 — **`analysis/eda.py` plot readability overhaul + new `analysis/column_legend.py`.**
  Analysis-only, no reflash, Basti's clone (not `A:\Angelo\...`). **UNCOMMITTED.** **Bug fixed:** phase
  shading compared raw `Label` (NaN on unlabelled rows), stacking hundreds into one red block that read as
  the attack; now compares `segment`-derived names, and PCA/t-SNE drop unlabelled windows too — moved
  `blackhole/linear/home`'s PCA variance 30.5/23.0%→39.1/28.0%. ⚠️ Heatmap upper-triangle masking was tried
  and REJECTED — don't reintroduce. `column_legend.py`'s `_L` dict is now the single source of column meanings.
- sep. 22, 2026 — **CAPTURE DATES ARE REAL: the board takes its clock from the laptop (`SET_TIME`).** The old
  date was the link-time build stamp, identical on every boot of one flash. `/sdcard/clock.txt` anchor applied
  **after mount, before the folder tree** (that ordering is what makes "Date modified" true). Detail: ARCHIVE.md.
- sep. 22, 2026 — `status_NODE_<mac>.txt`/`runs.csv`/`location.txt`/`clock.txt` roles + why `DELETE_SD_FILE`
  only accepts `*_telem.csv`/`*_arrivals.csv` — full detail ARCHIVE.md.
- sep. 24, 2026 — **CAMPAIGN CHECKLIST: LIVE vs ARCHIVE, and `[x]` needs ANALYSIS** (`inventory_cells.py --scope`,
  wizard option asks). User REVERSED sep. 22's "archives count by design": archiving now takes a run OFF the live
  checklist. `[x]` = run in `tools/exports/` COMPLETE (M4/M5) + `analysis/<cell>/feature_table.csv` newer than the
  capture; else `[~]` naming the fix ("run analyze.ps1" vs "RE-CAPTURE"). Archive view checks `archive/<x>/analysis/`
  (git-ignored there → a fresh clone shows archives "not analysed"), dedupes copies. Summary/`--plan` count live only.
  **RANDOMISED PLAN:** each (location, topology, attack) draws 4 of the 6 `run.ps1` scenarios, balanced (5-6 uses each per
  location, bh≠wh per topology), saved ONCE in `tools/campaign_plan.json` (seed recorded; `--reshuffle` only pre-campaign). Slot order = run order. Benign row only where burst drawn.
- sep. 24, 2026 — **SCENARIO `none` RENAMED `stationary` EVERYWHERE + it gets a REAL folder** (`<loc>/stationary/`). `none` = accepted
  alias (canon_scenario / ConvertTo-Scenario, one per script). Pre-rename flat captures still read as stationary (fallbacks in
  Get-RunDirs/cell_dir/analyze.ps1). `-Attack none` (baseline) UNCHANGED. Also fixed: `jitter` missing from export_logs/run_matrix/analyze.ps1 → every jitter export failed. 20 py + 19 PS checks + root/child build pass.
- sep. 22, 2026 — **WIZARD SMART ARCHIVE FRONT END** (`Invoke-ArchiveMenu`): per-cell tables, byte-identical
  duplicate detection across every `archive/*/`, COMPLETE-run warning, `-WhatIf`. ⚠️ **`archive.ps1` MOVES
  data, so git shows STAGED DELETIONS under `tools/exports/` — check `archive/` BEFORE `git checkout`-ing
  them back; doing that once recreated 9 files already safely archived.** Detail: ARCHIVE.md.
- sep. 22, 2026 — **FIXED: wizard [15] campaign checklist CRASHED at the end** — `run_wizard.ps1:2232`
  called `Read-YesNo`, which is defined ONLY in `menu.ps1` and never dot-sourced here, so it threw
  `CommandNotFoundException` AFTER printing the whole checklist. Now uses this file's own `Read-Line`
  idiom. Swept for the same class: `Get-BuildDirSpec`/`Show-MainMenu` appear in run_wizard.ps1 but only
  inside COMMENTS — `Read-YesNo` was the one real cross-script call.
- ⚠️ **PS 5.1 promotes a native command's FIRST STDERR LINE to a TERMINATING error** under
  `$ErrorActionPreference='Stop'` — a tool writing a progress bar to stderr kills its caller with an EMPTY
  exception message. **Grep every `& python ... 2>&1` before shipping.** Detail: ARCHIVE.md.
- ⛔⛔ **PLUG BOARDS DIRECT INTO THE LAPTOP — NEVER THE DOCK OR A HUB.** Win11 BSOD'd twice
  (`ATTEMPTED_SWITCH_FROM_DPC` 0xB8) during USB board I/O — HOST DRIVER fault, not firmware. Every CP210x
  sat 2-3 hubs deep behind the Dell D6000. USB selective suspend now off. Detail: ARCHIVE.md.
- **Git repo root is this whole `Unified/` folder** (code, docs, `Paper/`, `ESP32-Environment/` all inside it),
  NOT `ESP32-Environment/` alone — branch `Unified`, remote `origin` =
  `https://github.com/Kemo1006/NIS16-ESP32-Environment`. GitHub IS the laptop-to-laptop transport: a `git pull`
  elsewhere gets the same MEMORY.md/STATUS.md/code. (Corrected sep. 17, 2026; was stale before that.)
- Thesis: DLSU CCS, CTTHES2/THES3. Proponents: Calpoporo, Carlos, Ong, Reinante. Adviser: Cu, Gregory G.
- Toolchain: ESP-IDF **v5.3.5** (bundles Python 3.11 + compiler); boards enumerate as "Silicon Labs CP210x USB to UART Bridge"; Windows reassigns COM numbers every plug — always re-check.
- **THESIS 3 DRIVER — `Paper/Improvements.pdf`** (CTTHES2 panel comments, ~aug. 2026). 8 timestamped rows
  → 7 problems: single-feature decidability, no attack parameter variation, redundant r1–r3, one
  environment, no declared IoT scenario, no attack provenance, uncharacterised benign baseline. Plan:
  `Plan/THESIS3-PANEL-PLAN.md`. Attack-provenance answer is DONE: `docs/ATTACK-VALIDATION.md`.
- ⚠️ **Known leak (panel P1)** — role-gated features made "is this NaN?" a perfect label.
  ✅ **Root cause removed by C7 Option 1**; `leakage.py` now decides per dataset. ⚠️ PDR's 0.9987
  single-feature score is a SEPARATE problem and still open (see the sep. 20 entry).
- **Attack-validation framing (panel P6):** validate by *definitional conformance* (canonical criteria vs
  what we implement, failures declared), matching signature SHAPE not absolute values — so LEACH/AODV/RPL
  sources are valid and need not be ESP32-specific. **Now written up in `docs/ATTACK-VALIDATION.md`.**
- ⚠️ **Known circularity (panel P6):** the blackhole attacker counts its OWN drops — the evidence the attack occurred comes from the node performing it. Needs an independent observer (sniffer node / monitor-mode adapter) or root-side accounting.
- Attack/traffic parameters are compile-time constants: drop rate 100% (`blackhole_victim.c`), `PROBE_INTERVAL_MS 1000`, `SAMPLING_INTERVAL_MS 100`, phases 60/300/180/120 s = 11 min (`mesh_config.h`). `run.ps1` exposes topology/role but **no attack-intensity flags**, so r1/r2/r3 still differ only in RF noise — the panel's 12:45-16:00 objection, unanswered. ✅ **Attacker POSITION is the one exception since F2**: it is a runtime NVS value now, no re-flash. Full pre-F2 text in ARCHIVE.md.
- I-017 recurring hazard: children left powered through a run's later phases overfill SPIFFS (~1.1 MB) and
  become unreadable on export → carry each child back UNPLUGGED; `board_check.py --port COMxx --wait 75`
  before a run (≥50% SPIFFS → wipe+flash first).
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
  silently. ⚠️ **`export.ps1` ALSO fails, LOOKING LIKE "ESP-IDF is not installed"** — it actually hunts
  `idf5.5_py3.12_env` (wrong; real is `...py3.11_env`). Check `idf-env.exe config get` first. ARCHIVE.md.
- Long `idf.py -B <dir>` names — deep paths pass Windows `MAX_PATH`; ninja fails in the **bootloader**
  subproject long after the app compiled, so it looks unrelated. Fixed by short per-variant `Bld` names
  (`bcr`,`bcba`,…) + a preflight warning. ⚠️ **Don't rename them back.** Detail: ARCHIVE.md.
- Non-ASCII in a Python tool's **module docstring** passed to `argparse(description=)` — cp1252 console ⇒
  `--help` dies with `UnicodeEncodeError`. Keep them ASCII; `sys.stdout.reconfigure(encoding="utf-8")` first.
- SD reader module VCC/format-specifier wiring & build gotchas — both fixed in code; full text ARCHIVE.md.
