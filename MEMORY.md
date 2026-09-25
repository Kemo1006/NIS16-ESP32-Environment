# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 25, 2026 — **D-15 + DATA-DICTIONARY §2 rewrite.** `retry_count`/`tx_count` are APP-LAYER counters (no Wi-Fi driver stats read
  anywhere); paper Table 4.5 calls them MAC stats - re-describe in the paper, no re-capture. ⚠️ Wormhole Node B still writes its TUNNEL
  count into `retry_count` (Tunnel* features read it) - the one overload F3 did not remove. `leakage.py` reason TEXT is pre-C7 (code is fine).
- sep. 25, 2026 — **10 Hz sampling + 1 s windows are PANEL/ADVISER-MANDATED — never "restore" 1 Hz / 5 s** (D-1/D-9 "to restore
  literally" notes are history, not a to-do). Only the paper text (Tables 4.4/4.10, §4.2.4.1) is behind and must be amended.
- sep. 25, 2026 — **WIZARD: a preset board with NO port was silently treated as "on another laptop".** Angelo's G402
  run showed ROOT under "not plugged in" (blank label/COM), then "Boards on ANOTHER laptop", "nothing to flash here" -
  while [12] Identify read it fine on COM3. Cause: that laptop's preset file has ROOT with `Port: ""` (GitHub's
  `presets/Cal/...g402.json` is fine: node1/COM20/MAC - so `git pull` or re-save it). Port-less boards skipped BOTH the MAC
  match and the re-pick. Fix: preset path now asks per port-less board "plugged into THIS laptop? [y/N]" -> port picker.
  Also: the preset path's location.txt check ran on the preset's SAVED ports (before drift fix) and printed "All boards
  already report" after checking ZERO boards - it now runs once after the port fix and says UNVERIFIED if none read.
- sep. 25, 2026 — **ROSTER GATE + RESET REASON (firmware, needs reflash; a safeguard, NOT a fix for the G402 run).** Root waits after stabilise until `EXPECTED_CHILDREN` (routing table
  size - 1) are in the mesh for 5 s; `run.ps1 -ExpectedChildren` (always passed on root, 0 = off; wizard = local children + remote count it asks
  for on multi-laptop runs - plain remote children are NOT in the roster). `START_ANYWAY` on serial releases it. Every board writes its reset
  reason + `Brownout/Crash resets (total)` to status_*.txt and an 11th `reset_reason` column to runs.csv (importer reads it positionally).
- sep. 25, 2026 — **ABORTED G402 files were NOT a power cut (first diagnosis WRONG, corrected same day).** Root arrivals show all 6 children
  sent probes through the whole run; the phase-255 files are LATER BOOTS. csv_logger_init archives the previous boot's files into `_archive/` on
  every boot and import_sdcard.py skips `_archive/` - so one restart after a run hides the real file. Tie children to the run by seq_num, not
  file times. validator FAIL + preprocess skip for no-experiment files stay (still correct); preprocess now WARNs when it keeps an older
  data file over a newer empty one (may be another session - node8's 13:41 file). OPEN: importer has no way to read `_archive/`.
- sep. 25, 2026 — **RUN LOGS: filed by run, viewable start-to-end, syncable.** Wizard saves to `run_logs/<attack>/<topology>/<location>/<scenario>/`
  (`Get-RunLogDir`; old flat logs list as NOT FILED); viewer pages the whole run, keep/archive (`run_logs/_archive/`, never pushed)/delete/push.
  `push_data.py --area logs`: `*.log` is ignored by the THESIS3 root .gitignore, so logs are listed like analysis (no staging). Data-sync submenu grouped. Scripted-stdin tested, NOT pushed live.
- sep. 25, 2026 — **DATA SYNC DELETE / RESTORE** (`push_data.py delete|restore --area X`, wizard Data sync [9]/[10]): a delete is a normal
  commit, so history keeps it and restore puts back the exact bytes. Only files GitHub HAS can be deleted (keeps it undoable). Push SKIPS a
  file deleted on GitHub if local bytes match a past version (else it would undo the delete); pull/push OFFER (never auto, even --yes) to
  remove such local copies; differing copies always kept. Ledgers + archive/ moves excluded. Sim-tested on a local bare repo, not real GitHub.
- sep. 24, 2026 — **STILL RUNNING / ABORTED root cause: a child misses TERMINATE** (root sends it P2P to every
  node in its routing table, 5 repeats; a child mid-reparent isn't in the table). Its SD mirror stays open →
  STILL RUNNING over USB, ABORTED once the card is pulled. **NOT HT20.** 4 layers now: (1) cooldown watchdog in
  `phase_listener_wait_for_terminate()` — no TERMINATE 180 s into cooldown → ends locally, manifest `term_timeout`
  +`clean` (PUSHED `4144d30`); (2) root re-sends TERMINATE every 5 s for 60 s (`TERMINATE_RESEND_S`); (3) serial
  `END_RUN` (`export_logs.py --end-run`, offered by the wizard on a STILL RUNNING file over USB): in cooldown →
  `manual_end`+`clean`; before cooldown → `manual_end` only (stays ABORTED — honest, cut short); (4) dashboard
  below. (2)+(3) pushed `d122033`/`489709a`, build-verified root+child, NOT hardware-tested. Importer ignores
  unknown manifest events; run numbers count distinct boots, so extra rows are safe. A card pulled mid-run
  is still ABORTED — correct, not a bug.
- sep. 24, 2026 — **Root dashboard EXPORT column + `EXPORT :` line** ("ALL n BOARDS DONE - SAFE TO EXPORT").
  Uses the spare heartbeat `export_status` = `EXPORT_STATUS_LOG_CLOSED` (0x04) once `csv_logger_is_closed()`;
  children send 3 final beats 1 s apart then go quiet; root keeps LOG_CLOSED rows (no stale eviction) and its
  listener keeps running after TERMINATE (`phase_listener_keep_running_after_terminate`), ignoring late probes.
  Committed+pushed `5f4443b`. Needs a REFLASH of every board; old firmware stays "not yet".
- sep. 24, 2026 — **Xtensa `uint32_t` is `long unsigned int`**: `%u` on `PHASE_*_S + jit_*` broke the root build
  under `-Werror`. Cast to `(unsigned)` like `sd_status.c` (`cd7c212`).
- sep. 24, 2026 — **Basti's laptop git identity is `xMiguelCarlosx`** — commits "by Miguel" from this clone are
  the user (VS Code auto-sync also runs `pull --autostash` mid-session). `PCAP/` + `*.pcap` git-ignored: a 120 MB
  Mac capture exceeds GitHub's 100 MB cap and blocked every push until removed from history.
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
- ⚠️ **PS 5.1 promotes a native command's FIRST STDERR LINE to a TERMINATING error** under
  `$ErrorActionPreference='Stop'` — a tool writing a progress bar to stderr kills its caller with an EMPTY
  exception message. **Grep every `& python ... 2>&1` before shipping.** Detail: ARCHIVE.md.
- ⛔⛔ **PLUG BOARDS DIRECT INTO THE LAPTOP — NEVER THE DOCK OR A HUB.** Win11 BSOD'd twice
  (`ATTEMPTED_SWITCH_FROM_DPC` 0xB8) during USB board I/O — HOST DRIVER fault, not firmware. Every CP210x
  sat 2-3 hubs deep behind the Dell D6000. USB selective suspend now off. Detail: ARCHIVE.md.
- **Git repo root is this whole folder** (`THESIS3/` on Basti's laptop: `OneDrive\Documents\Thesis\THESIS3`;
  code, docs, `Paper/`, `ESP32-Environment/` all inside it), NOT `ESP32-Environment/` alone — branch **`THESIS3`**
  (was `Unified` before sep. 2026), remote `origin` =
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
  ✅ Works on Basti's laptop (sep. 24): `$env:IDF_PYTHON_ENV_PATH="C:\Espressif\python_env\idf5.3_py3.11_env"`
  then `. C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1`. Build into `-B $env:LOCALAPPDATA\...` and restore
  `root_node/sdkconfig`, `child_node/sdkconfig`, `root_node/dependencies.lock` afterwards (the build rewrites them).
- Long `idf.py -B <dir>` names — deep paths pass Windows `MAX_PATH`; ninja fails in the **bootloader**
  subproject long after the app compiled, so it looks unrelated. Fixed by short per-variant `Bld` names
  (`bcr`,`bcba`,…) + a preflight warning. ⚠️ **Don't rename them back.** Detail: ARCHIVE.md.
- Non-ASCII in a Python tool's **module docstring** passed to `argparse(description=)` — cp1252 console ⇒
  `--help` dies with `UnicodeEncodeError`. Keep them ASCII; `sys.stdout.reconfigure(encoding="utf-8")` first.
- SD reader module VCC/format-specifier wiring & build gotchas — both fixed in code; full text ARCHIVE.md.
