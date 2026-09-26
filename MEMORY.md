# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 27, 2026 (pm) — **ARCHIVE (wizard DATA [7] / `archive.ps1`) NOW ALSO MOVES `datasets/PCAP/` + `datasets/run_logs/`** (user: "include the
  pcap and run logs so all of the info will be there"). PCAP moves WHOLE (cell folders + `standalone/`, .pcap + .json + _fixed) to
  `archive/<date>_<label>/PCAP/`; run_logs moves to `.../run_logs/` EXCEPT `run_logs/_archive/` (the log viewer's own archive, stays).
  Emptied PCAP/run_logs subfolders are removed (writers recreate them). Wizard menu no longer says "nothing to archive" when only
  pcaps/logs are left, and shows an ALSO MOVES line. Archived pcaps stay git-ignored (`PCAP/` rule) = local to that laptop. Tested:
  parse, `-WhatIf` on real data, real move in a scratch sandbox. ⚠️ The wizard's Wireshark capture picker + run-log viewer only scan the
  LIVE folders - archived ones are reachable via "Another file". ⚠️ Leftover pcaps/logs from the 3 already-archived sep. 26-27 runs are
  still live; archiving now would lump them into ONE new folder - file them into their matching archive by timestamp instead.
- sep. 27, 2026 (Wireshark review + burst) — **02:05 blackhole/linear pcap = REAL LINEAR, attack WORKED** (user: "is it really linear / why no attack in the graph").
  Chain ROOT(B0:18) -> node2(20:38) -> node4(F4:18 = BLACKHOLE per mesh_config.h) -> node3(20:80, victim). Proven twice: `verify_topology.py`
  on the 4 telem CSVs (0 parent switches) AND pcap data frames (only 3 links, none skip a hop). ⚠️ `member_boards.json` still labels 20:38 as
  attacker - STALE (real one is F4:18); wizard option 9 reads mesh_config.h so it picked the right board. Logs: attacker recv 180 / fwd 0 /
  drop 180 in phase 1; root arrivals from node3 = 301 / 0 / 120 (base/attack/cool), node2 unaffected. Wireshark looked flat because (1) a
  02:18:11-30 spike (attacker AP ~8,300 RTS + 757 retries to node3 at teardown) sets the Y axis, (2) 1 probe/s/child so the dip is ~20 -> 9
  frames/10 s, (3) option 4 / "Attacker - all traffic" count beacons+ACKs. Zoom 0-680 s on the data-frame "Attacker -> parent" line.
  **BURST_COUNT 100 -> 300** (user: "add 200 more") in `mesh_config.h:545` + "300 probes" text in run_wizard/menu/run.ps1 + memory/run-scenarios;
  NOT compiled/flashed; burst size is not in the CSV (old 100-probe bursts not comparable). Stationary = 1 probe/s/child (~660/child/run);
  highload 250 ms; run length is set only by root timers (60/300/180/120; jitter + burst-baseline add time), never by send rate.
- sep. 27, 2026 — **Wireshark view menu (wizard WIRESHARK -> "Open a capture - pick a view"): DEFAULT SCOPE = ALL BOARDS OF THE RUN** (user:
  "my mesh boards" labels were wrong - the filters always covered every board check_pcap heard). New [2] **MY boards ( >)** submenu = the same
  7 views limited to one member's boards (`member_boards.json`, matched on first:last MAC byte; member = `my_member.txt`, asks via
  `Select-MyMember` if unset) + "Another member's boards instead". New "side by side" view = one I/O `sends` line per board (nickname).
  Views are keyed, not numbered (`Get-PcapScopedView` shared by both menus); BLACKHOLE/WORMHOLE main-menu only, unchanged. `$script:WsColors`
  6 -> 10. Tested with stubbed Show-Menu/Open-InWireshark on `esp32_sniffer_2026-09-26_233911.pcap`, every view; NOT opened in real Wireshark.
- sep. 27, 2026 — **ALL DATA MOVED UNDER `ESP32-Environment/datasets/`; CODE STAYED** (user: data + visuals were out of place).
  `tools/exports`->`datasets/exports`, `analysis/{baseline,blackhole,wormhole}` (CSV/PNG output only)->`datasets/analysis/`,
  `archive`->`datasets/archive`, `PCAP`->`datasets/PCAP`, `run_logs`->`datasets/run_logs`. `analysis/*.py` + requirements.txt + its .md
  stay in `analysis/` (callers pass full `-o` paths; `analyze.ps1` now has `$analysisCode` = scripts, `$analysisRoot` = output).
  Repointed paths + operator messages only, no logic: run_wizard/run/menu/analyze/archive.ps1, tools/ImportBatch.ps1, argparse defaults
  (export_logs, import_sdcard, run_matrix, verify_topology, validate_integrity, inventory_cells, sniff), slides/refresh_slide_numbers.py,
  .gitignore, .gitattributes, .vscode/settings.json, .last_import_batch.json. `push_data.py`: EXPORTS/ANALYSIS/LOGS + new ARCHIVE const,
  analysis depth rule >=5 -> >=6 (same cell-depth guard). Done as a SHA-256-verified COPY (375 files, 258.8 MB identical): auto mode
  blocked the move, so **the originals are still on disk until the user deletes them.** Verified: parse/py_compile, inventory output
  identical before/after, wizard Get-RunDirs/Get-RunLogRoot -> datasets/. NOT run: a real capture, push/pull against GitHub.
  ⚠️ Stage `.gitattributes` WITH the data (else CSV line endings change -> integrity hashes break). ⚠️ GitHub paths change on push:
  a teammate on the old push_data.py syncs the old folders - `git pull` the code first. **FILEMAP, guides and older entries here still
  say the OLD paths - the user will fix docs later; trust the code.**
- sep. 26, 2026 (late) — **Root phase banners print the wall-clock start time** (`root_main.c` `phase_banner()`, e.g. `@ 22:03:15 PHT`;
  "(est.)" when the clock is only the build-stamp estimate, `--:--:--` if unseeded). Console-only visual aid, never in a CSV (user). Compiled clean, not flashed.
- sep. 26, 2026 (night) — **21:11 home re-run vs 19:18 + 3 fixes (user: "did it get worse / more missing data?").** Same firmware
  + analysis code; raw data clean (no gaps, arrivals 100% outside the attack). Differences: (a) TREE CHANGED - root -> node4 -> node2
  ATTACKER -> node3 = 1 victim + 1 bystander (177 drops vs 359); linear order = join order, preset can't fix it (power attacker first).
  (b) Children were in BASELINE before the reflashed root started: the root board booted its OLD firmware before the wizard wiped it,
  ran a session to Phase 0 (always seq 13 = 12 PREPAREs + 1); children kept seq 13, so the new root's PREPAREs + Phase 0 (seq 1-13)
  failed the seq dedupe - only seq 14 (attack) got through. **FIX (firmware, needs REFLASH of EVERY board - wire format grew 17->21 B,
  mixed old/new boards won't hear each other's phases):** `phase_msg_t.session_id` = random per root boot; a listener seeing a new
  session resets seq and drops back to 255 (UNSET) (ignored once terminated). Root+child compiled OK, NOT hardware-tested. Maybe
  related to node3's "112 s ahead" on G402 sep. 25 (root rebooted there) - unverified. `preprocess.assign_segments`: a 255 AFTER a real
  phase = root restart -> everything before is pre_baseline (tested on a doctored copy of node3). (c) **Window counter deltas lost
  4-15% of counts**: delta was last-first of the window's own samples, dropping increments between windows (varies with probe-timer
  phase). Now `_first` = previous kept window's last (window START edge), delta = `_last - _first`; PDR/latency seq ranges tile.
  After: every counter 100% of raw in both runs; 21:11 attacker drops 151 -> 177/177, recv=0 attack windows 29 -> 3. (d) `eda.py`
  KDE only when every phase has >= 5 distinct values (21:11 FR plot was a 1e15 spike). Home cell regenerated + 3 gates: attack
  CONFIRMED, topology FAIL (real: node4 re-joined after the root reflash), integrity WARN (bystander keeps 50% arrivals). 19:18
  run re-analysed (M6-M8 only, no gates) in a scratch copy - archive untouched: single-feature PDR 0.999, FR 0.85. Both runs are r1 - rename one before pooling.
- sep. 26, 2026 (late) — **Wizard WIRESHARK category** (user: "choose an option and it opens Wireshark"). Sniffer entries 21/22/23 moved
  OUT of VERIFY into it + NEW 24 *Open a capture - pick a view* (overview / one board / mesh data / retries / joins+leaves / weak links /
  BLACKHOLE attacker->parent / WORMHOLE B vs A), 25 *Open the NEWEST capture* (overview), 26 *ESP32 sniffer + watch LIVE*. MACs come
  from the CAPTURE, never a table: `check_pcap.py --map-json` = nodes + uplinks (TA->RA) + root_guess (a parent that never beaconed is
  still listed); attacker from mesh_config.h. Launch = `Wireshark -r <f> -Y <filter>` with `WIRESHARK_CONFIG_DIR=%APPDATA%\Wireshark-ThesisMesh`
  (RSSI/TA/RA/Seq/Retry columns, filter buttons, `io_graphs` rewritten per view). NOT a `-C` profile: tested, `-C` becomes the laptop's
  "last used profile" (Bas's NSCOM3 Wireshark would open in it). Filter sets NEED COMMAS (`{a, b}`; `{a b}` rejected for MACs). Find-Wireshark
  + sniff.py now read the App Paths registry (Bas's install is under S:\Main Programs\ - the live prompt was silently hidden). tshark IS
  installed, just not on PATH. Verified: every view's filter via tshark on the 3 PCAP files, a real launch + I/O graph screenshot, Default profile unchanged. Item 26 not hardware-tested.
- sep. 26, 2026 (eve) — **blackhole·linear·home·stationary 19:18 run = GOOD, keep it** (the 17:19 run in the same folders was
  replaced; it was unusable: node2's file held 121 s with the root as parent, the sniffer sat paused 618 s). Tree all run:
  root -> node2 ATTACKER (F4:2D:C9:73:E6:18) -> node4 (…1C:38) -> node3 (…0C:80) = 2 victims, 0 bystanders. Every CSV's
  parent_mac/layer matches the root's dashboard; 3 children 7249 rows, phase edges on the same row. Attacker drop_count
  +359 in attack (180 s x 2 = 360), forward flat. Root arrivals: ONE seq gap per victim = the attack (node4 487->669,
  node3 464->644), baseline 301/301 + 294/294. ESP32 sniffer (`PCAP/standalone/esp32_sniffer_2026-09-26_191818.pcap`,
  0 loss) independently shows the attacker's 92-byte probe-forward frames to the root at 0 for 3 min. Node2 was off-mesh
  36 s in PRE-baseline (root reflash) - excluded rows. Home channel 11 has a foreign AP (88:66:9f:e9:be:00).
- sep. 26, 2026 (eve) — **LatencyHopRatio/TunnelLatency cross-clock join FIXED** (`features.py` `_arrival_sender_window`):
  arrivals were merged on `window_start` (root clock) onto the sender's windows (own clock) -> 63-window shift on the home
  run, cooldown latencies inside attack windows with 0 arrivals. Now placed by seq range like PDR (child: probes+retry;
  wormhole_b: probes). After the fix LatencyHopRatio scores 0.9987 single-feature: it only exists outside the attack (no
  arrival = no latency) - the SAME open structure as PDR's 0.9991, not a new leak. Home cell regenerated; G402 + other cells
  still carry the old values (re-run). thesis-deviate D-2 updated.
- sep. 26, 2026 (eve) — **Root post-export choice** (user request): wizard asks, when the root is on this laptop,
  [1] trim + M6-M8 (default) / [2] trim only / [3] export only -> run.ps1 `-Analyze` / NEW `-Trim` / `-Export`. run.ps1
  `-Analyze` now SKIPS M6-M8 (trim still runs) when the folder has no child `*_telem.csv` - SD workflow exported the root
  first and overwrote a full analysis with a root-only one (twice on sep. 26). Parse-checked + guard filter tested; not run on boards.
- sep. 26, 2026 (eve) — **OPERATOR HOLD (root waits for `GO`) was REVERTED ON PURPOSE by the user ("i reverted the code i didnt like").**
  Not lost, not a bug: `run.ps1 -Hold`, `wait_for_operator_go()`, `OPERATOR_HOLD` and the wizard "Hold the root for GO? [Y/n]" are
  gone from the tree. Do NOT rebuild or re-propose it unless asked; the roster gate still starts Phase 0 once children join.
- Reading notes (sep. 26): relay `drop_count` = deliberate drops AND failed forwards (probe_relay.c keeps recv = fwd + drop);
  SET_TIME gets "no answer" when the board still runs pre-SET_TIME firmware before the reflash - clock then comes from the SD anchor.
- sep. 26, 2026 (night) — **Sniffer keep prompt is now `[Y/n]`** (`Confirm-KeepCapture`): only explicit n/no DELETES the .pcap+.json (no
  restore, PCAP\ is git-ignored); Enter/y/anything else keeps. Supersedes the eve entry's in-run "None/ESP32/Mac after Proceed" (removed).
- sep. 26, 2026 (eve) — **ESP32 SNIFFER OVER USB (no SD, no Mac) + wizard asks "packet capture?" every run** (user: the Mac owner
  is not always there; SD pins stay the data logger's). `sniffer_node/` = a SPARE board, `WIFI_MODE_NULL` + promiscuous on
  `MESH_CHANNEL` (read from mesh_config.h) at 20 MHz — passive, never transmits. Streams checksummed binary records on UART0 at
  **921600** (boot text at 115200 is skipped by checksum; `idf.py monitor` shows garbage on it BY DESIGN). `tools/sniff.py` ->
  radiotap `.pcap` + `.json` (USB loss = rec_seq gaps, board ring drops, reboots — quote them with any figure). Snap mgmt 256 / data 64.
  Wizard: after "Proceed?" -> None / ESP32 / Mac. ESP32: spare port (run's mesh ports refused), flash `build_sniffer_<port>`, sniff.py
  in its OWN window from BEFORE the first child, stopped by a `.stop` file in the run's `finally` (failed child too) + check_pcap with
  the boards' MACs. Mac: checklist + START/STOP prompts. Menu [23] = standalone, filed by cell (asks) or standalone\. Output `PCAP/<atk>/<topo>/<loc>/<scen>/`
  (git-ignored). Answers the P6 circularity (independent observer). ✅ **HARDWARE-TESTED sep. 26** (menu [23], COM9, 3 min 45 s):
  9430 frames, 3 mesh nodes, 2995 mesh DATA, usb loss 0, board drops 0 -> CP210x holds 921600 (if a .json ever shows USB loss, lower
  `SNIFF_BAUD` + sniff.py `BAUD` together). Then added: **P = pause/resume** (frames still read, not saved; each pause + frames skipped
  in the .json — the capture has gaps there), **keep/delete prompt** after check_pcap (default keep; 'd' removes .pcap/.json/_fixed —
  no restore, PCAP\ is git-ignored), Mac checklist shows Channel/Width as coloured chips. scapy pads radiotap MCS to 2 (spec 1) -> noise field.
- sep. 26, 2026 — **RETRY RATE = 0 IS A RESULT, NOT A BUG (G402 5 pm run traced raw -> validator).** Raw `retry_count`
  (= failed `esp_mesh_send()`, D-15) is non-zero only OUTSIDE the experiment: node5 24 fails at t -389..-366 s (root boot 1233
  dead, nothing to send to), node3 12 (unlabelled, desynced), node7 a constant 9 from before logging. 0 failures in baseline/attack/cooldown
  on every board = paper 3.3.1.2 / EXPECTED-RESULTS 6a pre-registered miss (1 probe/s + 1 s windows: RetryRate is only 0 or ~1).
  FIXED around it: `leakage.retry_count_is_overloaded()` - RetryRate was STILL on the leak
  list with the pre-F3 reason, so correlation/PCA had NO MAC-layer feature; now excluded only if `drop_count` is absent
  (v1) or a `wormhole_b` is present (Node B still writes its tunnel count there). `eda.py`: correlation uses LABELLED
  windows only (was all rows incl. pre-baseline) and writes `_baseline`/`_attack` views (paper 4.2.6 "consistency during
  baseline and its breakdown during manipulation"); constant features named; one colour per node in timeseries; verify_attack footnote.
  KEPT on purpose: timeseries extra panels (paper 4.2.6 says "e.g."; FR_5w + RootArrivals are display-only, never in stats/corr/PCA);
  Eq 4.4 epsilon (0 attempts -> RetryRate 0, not NaN). PAPER TODO: report RetryRate as Table 3.4 miss; analyze.ps1 dies if its output is redirected (PS5.1 stderr).
- sep. 25, 2026 — **WHY IMPORTS SHOW TINY "STILL RUNNING" FILES (recurring since sep. 24): the board REBOOTED.** ONE USB port (power+data):
  powerbank->laptop, or the idf.py monitor->export handoff (toggles reset), power-cycles it; old firmware then moved the run's CSVs into
  `_archive/` at boot (LIST_SD + importer skip it) and opened a ~1 KB phase-255 file. After a power cut "started" = LAST SET_TIME anchor.
  **FIXED IN FIRMWARE (team decision, NEEDS REFLASH + one hardware test):** no archiving at boot (ARCHIVE_SD only), and
  `LOG_ONLY_DURING_RUN 1` = no rows until the root's PREPARE (sent every 5 s in stabilise + roster wait; rows stay phase 255 =
  paper's "Baseline Stabilization" kept) or phase 0-3; TERMINATE never opens it. Late joiner -> verify_topology NOT MEASURED.
  User chose: wizard never shows `_archive/`. Dashboard is NOT hardcoded (per-board heartbeat); "ALL n DONE" ignores evicted boards.
  Host: END_RUN reply matched anywhere in a line (old "predates END_RUN" msg was false); USB "already imported" = node+repeat only.
- sep. 25, 2026 — **10 Hz sampling + 1 s windows are PANEL/ADVISER-MANDATED — never "restore" 1 Hz / 5 s** (D-1/D-9 "to restore
  literally" notes are history, not a to-do). Only the paper text (Tables 4.4/4.10, §4.2.4.1) is behind and must be amended.
- sep. 25, 2026 — **ROSTER GATE + RESET REASON (firmware, needs reflash; a safeguard, NOT a fix for the G402 run).** Root waits after stabilise until `EXPECTED_CHILDREN` (routing table
  size - 1) are in the mesh for 5 s; `run.ps1 -ExpectedChildren` (always passed on root, 0 = off; wizard = local children + remote count it asks
  for on multi-laptop runs - plain remote children are NOT in the roster). `START_ANYWAY` on serial releases it. Every board writes its reset
  reason + `Brownout/Crash resets (total)` to status_*.txt and an 11th `reset_reason` column to runs.csv (importer reads it positionally).
- sep. 24, 2026 — **Basti's laptop git identity is `xMiguelCarlosx`** — commits "by Miguel" from this clone are
  the user (VS Code auto-sync also runs `pull --autostash` mid-session). `PCAP/` + `*.pcap` git-ignored: a 120 MB
  Mac capture exceeds GitHub's 100 MB cap and blocked every push until removed from history.
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
