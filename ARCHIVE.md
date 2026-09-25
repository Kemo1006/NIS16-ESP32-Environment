# Archive — completed-work log

<!-- Append-only filing cabinet, no line limit. Entries roll in from STATUS.md and
     MEMORY.md when those hit their caps. NEVER read, parse, or scan this file unless
     the user explicitly asks — it exists so the active files can stay small. -->

<!-- Format: - mmm. dd, yyyy — <what was completed / retired fact> -->

- jul. 26, 2026 — Initialized this workstation from the template (CLAUDE/AGENTS/STATUS/MEMORY/FILEMAP at Thesis_workstation root, routing into the repo + Paper).
- jul. 26, 2026 — `linear·blackhole` row completed (r1–r3); `linear·wormhole·r1` captured, tunnel worked first attempt. Four tool bugs fixed (3 silent); `recover_spiffs.py` + `run_matrix.py --autorecord` added.
- jul. 27, 2026 — Thesis 2 presented. Defense materials (DEFENSE-SCRIPT ×4, DEFENSE-PREP ×3, TERMS-GLOSSARY.md) written, used, and retired to `0_Resources/archive/` on aug. 06, 2026.
- jul. 26, 2026 — Recovered LatencyHopRatio + TunnelLatency without re-capture; wrote `thesis-deviate.md`.
- jul. 27, 2026 — M4 matrix reached 16 of 24 (linear + star complete both attacks; tree/partial blackhole r1).
- aug. 06, 2026 — Read `Paper/Improvements.pdf` + the approved paper; wrote `Plan/THESIS3-PANEL-PLAN.md` (7 problems → code evidence → 5 workstreams → non-code needs → source list). Scenario settled. Found scope conflicts R-A/R-B and the pre-registered signature in paper §3.4.4. Created `Plan/`; archived Thesis 2 defense docs to `0_Resources/archive/`.
- sep. 12, 2026 — SD-card reader bring-up PASSED in `sd_card_test/` (adviser-requested, standalone sandbox): fixed `ESP_ERR_TIMEOUT`/underpowered card (VCC → VIN/5V, not 3V3) and `ESP_ERR_INVALID_CRC` (capped `host.max_freq_khz = 4000`). Then hit and fixed a stack-overflow crash (`static char report[2048]` had been a local in `app_main`, overflowing its ~3.5KB task stack and corrupting memory 2+ layers away from the real cause).
- sep. 15, 2026 — `run_wizard.ps1`: `b`/`back` through the manual capture flow; fixed a multi-laptop crash when a board marked remote had no COM port.
- (pre-redesign) Old 16-run dataset scale: an 11-min run ≈ 790 windows (1 Hz analysis, 5 s windows, 6 boards); 16 runs ≈ 12.6k windows ("10k dataset"). Benign class was thin: `tools/exports/baseline/` held linear·r1 only — 1 benign run against 15 attack runs. Superseded sep. 2026 by the panel-mandated redesign (`ESP32-Environment/memory/panel-change-2026-09.md`) — all these runs are being redone/archived.
- sep. 2026 — SD card reader hardware track: 8 physical boards (4× 38-pin "G.." + 4× 30-pin "D.." labels, mixed/paired by topology). SPI wiring identical GPIO numbers on both: SCK=18, MOSI=23, MISO=19, CS=5 (free choice), any GND. Avoid GPIO16/17 (wormhole UART tunnel) and, on the 38-pin board only, GPIO6-11 (wired to internal boot flash). Standalone bring-up: `NIS16-ESP32-Environment-semi-final/sd_card_test/`.
- sep. 12, 2026 — RESOLVED the `fopen(..., "w")` returns-NULL bug in `sd_card_test.c`: `CONFIG_FATFS_LFN_NONE=y` (default) only accepts 8.3 short filenames; `sd_card_status_testfile.tmp`/`sd_card_status.txt` both exceed that → `FR_INVALID_NAME` → `errno 22 EINVAL`. NOT filesystem corruption — a PC reformat to FAT32 was tried first and did NOT fix it, ruling that theory out before errno/strerror logging found the real cause. Fix: `CONFIG_FATFS_LFN_HEAP=y` in both `sdkconfig` AND `sdkconfig.defaults`. Same fix later needed in `root_node`/`child_node` for `sd_status.c`'s longer folder names (`partial_mesh_topology`, `DLSU_Library`).
- sep. 12, 2026 — Root cause of the "`fopen(..., \"w\")` returns NULL" bug found: `CONFIG_FATFS_LFN_NONE=y` (8.3 short filenames only) rejected long names with `EINVAL`. Fixed via `CONFIG_FATFS_LFN_HEAP=y`. See MEMORY.md for the full writeup and what shipped on top of it.
- jul. 26, 2026 — Workstation anchor placed at the workstation root, not inside the git repo, so it could route to both the code repo and `Paper/` without committing workstation docs into the ESP32 repo. Capture rate set to 10 Hz (analysis downsamples to the spec's 1 Hz) so ~30% loss still fills every window.
- ~jul. 2026 — LatencyHopRatio = relative one-way delay, TunnelLatency = duplicate-arrival divergence (D-2/D-3): no response leg / tunnel is one-way, and the unsynchronised-clock offset cancels under subtraction, so neither needed a firmware change or re-capture. Raw captures in `tools/exports/` are tracked in git (~6 MB) as the thesis's primary evidence; `_archive/`/`trimmed/`/`manifest.json` stay ignored.
- aug. 06, 2026 — THES3 deployment scenario decided (group): smart campus / environmental-building monitoring, sited at DLSU Manila — grounded in the paper's own §1.1/§1.5, needs no scale-down claim, and makes the 4 topologies physical (corridor→linear, room/lobby→star, multi-floor→tree, atrium→partial). Full reasoning: `Plan/THESIS3-PANEL-PLAN.md` §6 Q1. All THES3 planning/brainstorm consolidated into `Plan/` (indexed by `Plan/INDEX.md`) rather than scattered at workstation root.
- sep. 14, 2026 — `combined` tree BUILT (rolled from MEMORY.md sep. 15, 2026): merged `../CC/` (SD-card logging, `run_wizard.ps1`, presets) with `../NIS16-ESP32-Environment/` (`menu.ps1`, dated `docs/`, `tools/verify_attack.py`) into a full workstation wrapper with fresh git history in `ESP32-Environment/` (file-level merge, not `git merge` — the sources share a GitHub origin but not commit history). Both sources left untouched as frozen references. Command Center REMOVED not disabled (`heartbeat.[ch]` deleted, every `CONFIG_USE_COMMAND_CENTER`/CMake toggle/`-CommandCenter` gone); `node_identity.[ch]`/`mesh_messages.h` KEPT — capture depends on them. `verify_attack.py` (3-sigma, Zhukabayeva 2025 + Airehrour 2018) ported unchanged and verified CONFIRMED/exit 0 against a real blackhole capture. `docs/` rebuilt around the `2026-09-14_*` set, CC's older guides → `docs/_archive/`, ported docs corrected for NIS16-only facts (SD was "PLANNED" there, real here; their export paths used `<topology>_topology` with no `<location>`). `analysis/ANALYSIS-Commands.md`'s command matrix still uses old paths — pre-existing CC debt, never fixed. Superseded sep. 15, 2026 when `combined` was hardware-validated and became the working tree.
- sep. 14, 2026 — `menu.ps1` "Run MULTIPLE boards in parallel" BUILT (rolled from MEMORY.md sep. 15, 2026): one ESP-IDF window per board, sequential pre-build so N boards don't cold-compile at once, per-board hardware-safety confirm (no blind apply-to-all). `$boards` is reordered children-first/root-last immediately after the add-board loop REGARDLESS of pick order, so plan table/confirm/pre-build/spawn all read one ordered list and picking the root first never needs a restart. `Get-PortKind`/`Get-PortList` COM-classification ported from `run_wizard.ps1` (its interactive flow makes dot-sourcing impossible) so Bluetooth/non-ESP32 ports are never offered. Same day, build output for `run.ps1`/`run_wizard.ps1`/`menu.ps1` moved off the OneDrive-synced repo to `%LOCALAPPDATA%\esp32_builds\<tag>\` — the sync/Defender tax applied to every build, not just the first. Two gotchas found and fixed on the way (the `@($spec.Flags)` non-splat and the plain-`powershell.exe` spawn) are kept in MEMORY.md's "Failed approaches".
- sep. 12, 2026 — SD card status-report tree shipped in the REAL firmware (not just `sd_card_test/`), folder names mirroring `export_logs.py`'s topology-dir scheme so the SD tree and `exports/` tree stay structurally identical. The four location names (`home`/`G402`/`DLSU_Library`/`Goks`) were the first written definition of the `environment` field `Plan/THESIS3-MEMBER-HOWTO.md` had flagged as owned-but-undefined; threaded through `export_logs.py --location`, `run_matrix.py --location`, `run.ps1 -Location`. `run_ledger.csv`'s 14 pre-existing rows backfilled `location=unrecorded` rather than guessed (backup: `run_ledger.csv.bak-pre-location`).
- sep. 13, 2026 — BUILT: distinct `MESH CONNECTED: N node(s)` log banner in the shared `components/mesh_common/src/mesh_setup.c` (both CC/CC_JSON) — fires on parent-connect, child-connect/disconnect, and routing-table add/remove, reusing the already-called `esp_mesh_get_routing_table_size()`. NOT `CONFIG_USE_COMMAND_CENTER` — adds zero mesh traffic. Verified via 2 clean `-Wall -Wextra -Werror` builds (baseline + blackhole-victim).
- sep. 13, 2026 — FIXED (hardware-tested), all in `run_wizard.ps1`: args were passed as `@($array)` (binds POSITIONALLY), crashing every real run into `-Port` — switched to an ordered-hashtable splat (binds by name); `$Repeat`/`$repeat` silently collided (PS names are case-insensitive) so `-Preset ... -Repeat 2` was quietly ignored; the blackhole-MAC-mismatch prompt showed `a)/b)` info bullets right before an unrelated `[y/N]` prompt, so typing `a`/`b` read as "no" and aborted every time — replaced with a real menu whose option 1 auto-patches the header.
- sep. 13, 2026 — FOUND: `Get-Content -Raw` misdetects `mesh_config.h`'s no-BOM UTF-8 encoding on Windows PowerShell 5.1, corrupting every non-ASCII byte (the header's em-dash comments) on write-back. Caught via a before/after diff against a COPY, before it touched the real file. Fix: `[System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))`.
- sep. 17, 2026 — `menu.ps1`'s multi-board flow gained run_wizard's pre-flash summary box; both front-ends' plan tables now show each board's MAC.
- sep. 18, 2026 — BUILT (`run_wizard.ps1`/`menu.ps1`, uncommitted at the time): (1) **Main-menu declutter** — the
  3 member-board-list entries (edit table / open json / snapshots) collapsed into one submenu in
  BOTH launchers (`Show-Menu -AllowBack` in run_wizard, `Read-Choice -AllowBack` in menu.ps1), freeing
  2 main-menu slots each; numbering renumbered accordingly. (2) **SD-import picker delete** —
  `Select-CardFiles`'s "Import which?" prompt gained `d1,3`/`d1-2` to delete those numbered files
  straight off the card (a real `Remove-Item`, red PERMANENT warning + `[y/N]`), separate from the
  existing post-import `--delete-source` (still only fires after a verified copy) — for clearing
  junk/ABORTED entries the operator never intends to import. (3) **Per-member preset folders** — the
  root problem: a preset's filename already spells the experiment cell (topology-attack-scenario-
  location), so two members' preset for the same cell collided on name, and there was no way to tell
  whose boards a saved preset described without opening it. Presets now file under
  `presets\<Member>\<cell>.json` (`presets\Bas\`, `presets\Cal\`, `presets\Kyle\` created, empty
  until first save — git won't track empty dirs). `Get-PresetFiles` recurses and tags each file's
  `.Owner` from its folder; `Save-Preset` gained an `-Owner` param (also written into the JSON itself
  as an `owner` field, so a copied-out file still says whose it is — omitted `-Owner` keeps whatever
  the file/folder already had, so a re-save never blanks it). New `Find-PresetOwnerByMac` guesses the
  owner from the roster's MACs against `member_boards.json`; `my_member.txt` (new, via
  `Get-MyMember`/`Select-MyMember`, exposed as a 4th member-board submenu item) remembers "whose
  laptop is this" as the fallback. The save flow now asks "Whose boards is this preset for?"
  (pre-answered by MAC, then by `my_member.txt`) BEFORE the filename prompt — this is what makes
  saving an absent member's preset while yours already has the same cell name work without a manual
  rename. The load picker (`Show-Menu` gained an optional `-GroupHeaders` hashtable, purely visual —
  numbering stays one sequential run so a heading can never shift what "[3]" means) groups YOURS
  first, then every other member with boards filed, then UNFILED last. Preset detail screen gained a
  `Boards of: <member>` line (green if it's you) and a new "File this preset under a member" action
  (one file at a time, no bulk auto-move — a wrong guess would misattribute someone's boards). The
  SD-import "several presets match" pickers (both launchers) now show the owner per line, since same-
  cell presets now share a filename; `menu.ps1`'s scan was non-recursive and would have silently
  fallen back to raw `victim_NODE_<MAC>` naming on every import once presets moved into folders —
  fixed to `-Recurse`. The pre-existing `presets\linear-blackhole-none-g402.json` git conflict was
  RESOLVED sep. 18, 2026 when pushing to origin (see MEMORY.md "sep. 17 conflict" note): the flat path
  was superseded by `presets\Bas\linear-blackhole-none-g402.json` and removed. Tested: 21 PS-unit
  checks (owner detection, folder recursion, same-filename coexistence, Save-Preset owner precedence,
  grouping order) + scripted-stdin runs of both launchers' startup and submenu. NOT hardware-tested
  (no board touched by any of this). PS 5.1 trap hit and fixed: `[ordered]@{}` has `.Contains()` but
  no `.ContainsKey()` — see the global `powershell_menu_script_traps` memory (not this file).
- sep. 17, 2026 — FIXED + PUSHED (`a4f87b4`, `origin/Unified`): "Run analysis only" (both wizards)
  always read the RAW export, ignoring `trimmed\` entirely — new `Select-AnalysisInput` (mirrored in
  both files) now defaults to `trimmed\` when present, blocks (default: cancel) on a stale/incomplete
  trim missing raw files, and blocks (default: cancel) when a run's ROOT has no `*_arrivals.csv` —
  PDR/LatencyHopRatio/TunnelLatency would otherwise come out silently NaN with no warning. Verified
  against synthetic folders (up-to-date/stale trim, missing arrivals) plus the real
  `blackhole/linear/G402` export. Also in this push: `csv_logger.c`'s arrivals SD-mirror flush reused
  the TELEMETRY row counter (which resets on its own cadence), so arrivals almost never flushed
  mid-run — a root losing power before `csv_logger_close()` could lose most of its arrivals despite
  telemetry surviving; gave arrivals their own counter. NOT build-tested at the time (`idf5.3_py3.14_env`
  broken) — reviewed line-by-line; confirmed BUILD-CLEAN sep. 18, 2026 alongside the DELETE_SD_PATH
  work below (child + root both compiled), still not hardware/flash-tested. Also fixed: Windows
  PowerShell 5.1's `ConvertFrom-Json` does not enumerate a top-level JSON array, so a 2+ file SD card
  crashed the import picker with `Cannot convert System.Object[] to System.Int32` (reported as a
  teammate's crash; the catch block's "is python on PATH?" hint was a red herring, not the cause) —
  fixed with `| ForEach-Object { $_ }` in `Get-CardFileList`/`Import-OneSdCard`; reproduced live in
  PS 5.1 before shipping the fix.
- sep. 17, 2026 — DIAGNOSED: `blackhole/linear/G402`'s exported "root" file (MAC `2805A532D7B4`)
  isn't this run's actual root — every victim's `parent_mac` traces to `B0CBD8F33218` (the preset's
  real root), whose SD card/arrivals were never imported. Distinct from the known stale-
  `BLACKHOLE_ATTACKER_MAC` failure (no arrivals file exists at all here, vs. header-only there) — same
  "PDR NaN" symptom, different cause. Fix: import `B0CBD8F33218`'s card, remove the stray
  `2805A532D7B4` file from the export + `trimmed\`, re-trim, re-analyze. Carried forward as STATUS.md
  "REDO blackhole/linear/G402" until actually redone.
- sep. 17, 2026 — BUILT in both wizards: "Trim exported CSVs only" is its OWN DATA menu option now
  (`run_wizard.ps1` Idx 10 `Invoke-TrimOnly`, `menu.ps1` Action 11), not folded into "Run analysis
  only" — that action's M6->M8 pipeline runs off the raw export with no trim step (it never had one).
  Both shell out to the EXISTING `tools\trim_run.py --apply` (never `--in-place`), which already
  writes to a `trimmed\` subfolder and leaves the raw export untouched by its own design. Also:
  `run_wizard.ps1`'s manual-flow child-count prompt now accepts `0` for a root-only capture (was
  `-ge 1`) — downstream code already handled an empty roster gracefully. Not hardware-tested.
- sep. 17, 2026 — **`run_wizard.ps1`**: add/remove node, save-back-to-preset, no-preset mode, 3
  live-run fixes (missing `Mac` crash, forced blackhole attacker, "Type 1-1"). Full detail: MEMORY.md.
  Rolled from STATUS.md "Recently done" sep. 17, 2026.
- sep. 16, 2026 — PROPOSED, NOT BUILT (team decides first): root-as-blackhole-attacker, STAR ONLY —
  thesis fig 4.17 shows ROOT as the attacker in star, since every child connects directly to root so
  no child-relay position exists there (tree/linear/partial keep a child attacker; wormhole
  unchanged). Design sketch: `ROOT_BLACKHOLE_ATTACKER` flag + a drop branch in `root_main.c`'s
  `probe_data_cb`, root's telemetry role string swapped to `"blackhole"` so `features.py` needs ZERO
  changes; children need no firmware change. Biggest trap: pass `-DestAttack blackhole` for folder
  placement but NOT `BlackholeRole=victim` (that compiles in P2P-to-attacker-MAC addressing, wrong
  here); the MAC pre-flight does not apply and must be SKIPPED, not extended. Full plan (read before
  building): `.claude\plans\mutable-honking-spindle.md`, under the Basti user profile. Rolled from
  MEMORY.md sep. 17, 2026 (still not built as of the roll).
- TERMS-GLOSSARY.md (archived aug. 06 with the Thesis 2 defense docs) may still be live reference for
  THES3 writing (paper Tables 4.11/4.12 vocabulary) — pull it back to root if so. Rolled from
  MEMORY.md sep. 17, 2026.
- sep. 17, 2026 — BUILT: **capture provenance** — answering "is this card's data from the firmware I
  flashed today, or left over from a run I interrupted and forgot?" An ESP32 has no RTC (boots at
  1970) and mobility/powercycle deliberately power-cycle boards, so no clock or sync-on-connect
  scheme survives; an RTC module was considered and rejected by the user. Instead every image
  carries a BUILD STAMP: `sd_status_build_stamp()` (`sd_status.c`) reads `esp_app_desc_t`
  .date/.time — written at LINK time, so right on every incremental build and identical on every
  boot of one flash — normalised to "YYYY-MM-DD HH:MM:SS". Deliberately NOT raw
  `__DATE__`/`__TIME__` in a source file: those update only when THAT file recompiles, so an
  incremental build would report a stale date. It never touches capture CSV rows (user's constraint
  — the dataset format is fixed): it goes to a new `built` column on `runs.csv` (`csv_logger.c`,
  appended LAST so a card whose manifest was started by older firmware keeps its 7-column header and
  `import_sdcard.py` recovers the 8th field positionally from DictReader's restkey) and a "Firmware
  built:" line in `status_<node>.txt`. Needs `esp_app_format` in `mesh_common/CMakeLists.txt`. A
  build stamp is NOT a capture time — one flash's boots all share it, so pair it with the per-folder
  boot counter to order within a flash. `import_sdcard.py` gained `--list-json` (each file +
  stamp/rows/clean/already-imported; stdout JSON only, warnings to stderr) and `--files`
  (card-relative paths — the per-FILE counterpart to `--boots`); option [3] in BOTH wizards now
  shows a numbered picker built from it, `MM / DD / YYYY HH:MM | filename`, newest build first.
  Firmware NOT compiled as of this write (no ESP-IDF in the shell); Python + both pickers were tested
  on a synthetic card (new / old-7-col / no-manifest / aborted) and a full list→pick→import round trip.
- sep. 17, 2026 — Heartbeat: instant disconnect reporting, `mesh_setup.c` (full writeup in MEMORY.md's Decisions section as of this roll).
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
- sep. 17, 2026 — FIXED + BUILT: nav/UX overhaul, `run_wizard.ps1` + `menu.ps1` (kept in sync). Both
  gained `m` (jump to main menu, replaces Ctrl+C) on every prompt via shared `Read-Line`→throw,
  caught once at the outer loop; self-disables past the final confirm (`$script:NavLocked`) so it
  can't abandon a half-flashed roster. Wizard also: `b` (back) at ports/roster steps; root-here
  toggle (skips the full multi-laptop split just to mark root remote); blackhole/wormhole menus
  gained "attacker/tunnel is on ANOTHER laptop" — the only prior path nominated a LOCAL board,
  reading its MAC and overwriting `mesh_config.h` wrongly; `Select-Port` now hides a port an earlier
  board already claimed (manual entry still allows deliberate swap-mode reuse). `menu.ps1` was
  one-shot (ran one action, exited); now loops back to its main menu, grouped by category
  (CAPTURE/DATA/MAINTENANCE/VERIFY); `b`-plumbing added but not yet wired into its flows. Verified
  via `-DryRun` replay (wizard) / declined-confirm replay (menu.ps1, no dry-run switch exists).
  **Cont'd same day:** both scripts' category menus now show sequential 1-9 on screen (a new
  `$order`/`$display` lookup translates back to the real action/modeIdx, which used to leak gaps
  like DATA showing 1/5/8); added `cls` beside `m` (same `Read-Line` choke point, no Ctrl+C
  needed either). `menu.ps1` gained the wizard's identify-a-port/-ALL (`board_check.py`, cached
  in `$script:IdentifiedPorts`) and its `Test-PortSafeToTouch` gate — BLOCKED (non-ESP32) ports
  now hidden from every `menu.ps1` port picker, UNKNOWN needs the port name typed back to
  confirm. `b`-back STILL not wired into any `menu.ps1` flow — needs the same `$step`-machine
  treatment as the wizard (user-approved; only the multi-board flow was scoped before the
  session moved to other requests).
  **Cont'd same day (bug fix):** `cls` was leaving a BLANK screen — `Read-Line`'s handler did
  `Clear-Host; continue`, but every numbered menu (`Show-Menu`, `Show-CaptureWizardMenu` in
  run_wizard; `Read-Choice`, `Show-MainMenu` in menu.ps1) prints its title/options ONCE, above
  the prompt loop, so Clear-Host wiped them with nothing to put them back. Fix: `Read-Line` now
  takes an optional `-Redraw` scriptblock; those four functions capture their own
  print-title/options code as `$draw`, run it once up front, and pass `-Redraw $draw` so `cls`
  replays it after clearing. Other one-off `Read-Line` prompts (port pickers, y/n confirms) were
  NOT touched — lower priority, they only lose a line or two of context, not the whole menu.
  **Cont'd same day (feature):** `menu.ps1`'s multi-board flow gained run_wizard's boxed pre-flash
  summary (header + "Order (root is always last)" table + Exports/Analysis footer), replacing its
  bare `Plan:` list (no Repeat/swap-mode lines - menu.ps1 has neither concept). Both front-ends'
  Order tables now show each board's MAC via a new `Resolve-BoardMac`: prefers a preset's recorded
  MAC / the `Invoke-Identify` cache / (blackhole attacker) the MAC `Confirm-BlackholeAttackerMac`
  already read, else reads the chip live (harmless - the board is about to be flashed anyway),
  skipped under wizard's `-SkipMacCheck`/`-DryRun` (shows `(unread)`). Useful against the
  `BLACKHOLE_ATTACKER_MAC` mismatch bug above: the targeted MAC is now on the confirm screen itself.
- sep. 13, 2026 — DECIDED (user): build BOTH Command Center dashboard variants in parallel workstations — Variant A (on-device ASCII) in `Thesis_workstation_CC`, Variant B (root emits JSON + `tools/command_center.py` with `rich`) in `Thesis_workstation_CC_JSON`. WHY: the deciding factor between them is COM-port exclusivity (`run.ps1` ends in `idf.py ... flash monitor`, which holds the root's port for the whole run, so Variant B needs `-NoMonitor` or a second connection), and that is easier to judge on hardware than on paper. Build order is copy-then-fork: the shared core was written once in A and copied verbatim to B, which diverges at exactly one function in `root_main.c`. Verified byte-identical afterwards (`diff -rq`) — children are interchangeable, so switching dashboards reflashes the ROOT only. Superseded for `combined`: Command Center was REMOVED entirely from this merge (see sep. 14 BUILT entry in MEMORY.md); this decision stays live only for the standalone CC/CC_JSON workstations.
- sep. 12, 2026 — DECIDED: `ATTACK-MECHANICS.md`, `OUTPUT-VERIFICATION.md`, `NODE-INVENTORY.md`, and `linear_topology_blackhole.png/.svg` moved from workstation root into `Resources/reference/` and `Resources/figures/` (root was getting cluttered; NOT moved into `0_Resources/`, which is cross-workstation only). `Resources/INDEX.md` documents each subfolder.
- aug. 06, 2026 — DECIDED: Thesis 2 defense docs (4 DEFENSE-SCRIPT*, 3 DEFENSE-PREP*, TERMS-GLOSSARY.md) archived to `0_Resources/archive/` — the defense is delivered. `ATTACK-MECHANICS.md`, `OUTPUT-VERIFICATION.md`, `NODE-INVENTORY.md` stayed at root at the time (superseded by the sep. 12 move above).
- sep. 14, 2026 — `combined` workstation built: CC firmware+tooling base, Command Center removed, NIS16's `menu.ps1` + `verify_attack.py` + dated docs ported/corrected.
- sep. 13, 2026 — Command Center design decisions, rolled from MEMORY.md sep. 15 (all now moot in `combined` — CC was removed entirely in the sep. 14 merge; kept for the standalone CC/CC_JSON workstations' own history): (1) scope was dashboard-only, unified-binary dispatch DEFERRED since `child_node/main/CMakeLists.txt` picks one of three separate `victim_main.c`/`blackhole_victim.c`/`wormhole_victim.c` `app_main()`s at CMake configure time, not via an `#ifdef` chain — role stays a build flag, only the nickname was runtime-resolved. (2) Every CC packet led with its own `uint32_t magic` (`HEARTBEAT_MSG_MAGIC`/`COMMAND_MSG_MAGIC`), not a 1-byte `msg_type`, because `phase_listener_set_data_cb()`'s single callback slot made a lone `msg_type` byte indistinguishable from `PROBE_MAGIC`'s first byte. (3) Heartbeats were DEMO-ONLY: `CONFIG_USE_COMMAND_CENTER` defaulted to 0 and compiled the heartbeat/dashboard OUT of the binary (not a runtime skip), because a 3s heartbeat from every node adds MAC contention and moves RetryRate/PDR/latency, making an enabled-heartbeat run incomparable to the existing 16.
- sep. 13, 2026 — DECIDED (user): relocate `Thesis_workstation_{CC,CC_JSON,SDCard}` from `S:\My Work\Business\Claude\Workstations\` to `C:\Users\Basti\OneDrive\Documents\Thesis\{CC,CC_JSON,SDCard}`; inner repo renamed `NIS16-ESP32-Environment-semi-final` → `ESP32-Environment`. WHY: shorter absolute path compiles faster. User declined updating the workstation `.md` docs to match — their embedded paths/old repo name are now stale by design; verify against `run.ps1`/`export_logs.py` source, not the docs.
- sep. 13, 2026 — FOUND (doc drift, 3 items, all `run.ps1`/`export_logs.py` vs the workstation docs): (1) `-Location`/`--location` is mandatory whenever `-Export`/`-Analyze`/`-Clean` is used (hard-throws otherwise) but every `ATTACKS-Commands.md` copy-paste block omits it. (2) real export path is `tools\exports\<attack>\<topology>\<Location>\` (e.g. `linear`, not `linear_topology` as `LINEAR-RUNBOOK.md` claims — that folder doesn't exist). (3) `run.ps1` never checks `$LASTEXITCODE` after its own `idf.py ... flash monitor` call — a failed flash silently falls through into the export logic instead of aborting.
- sep. 13, 2026 — BUILT: `ESP32-Environment\run_wizard.ps1` (new file, both CC/CC_JSON, kept byte-identical) — numbered-menu front-end for `run.ps1` covering attack/topology/location/repeat/roster, auto-detects shared-vs-separate COM ports, verifies the blackhole attacker's live MAC against `mesh_config.h` (offers to auto-patch + force clean rebuild on mismatch), and saves/replays a roster as a JSON preset for r1/r2/r3.
- sep. 13, 2026 — DECIDED: `/sdcard/node_config.txt` may override the **nickname but NOT the role**. A `role=` line is logged as a warning and ignored. WHY: behaviour comes from the build flags, so honouring a stale card would make the dashboard display something false to the panel. Revisit only if the unified binary is ever built. `node_identity_resolve()` takes the role as a parameter because `mesh_common` cannot see `ACTIVE_ATTACK` — it is scoped to the app components.
- sep. 13, 2026 — DECIDED: `csv_logger_export_in_progress()` latches true on the first export and is never cleared, deliberately mirroring the `esp_log_level_set("*", ESP_LOG_NONE)` that file already never restores. WHY: `esp_log_level_set` gates `ESP_LOGx` but NOT `printf`, which both dashboards use — an unguarded repaint mid-export re-creates I-001 ("never saw END_OF_FILE"). Latching makes the check race-free (false→true only). Cost, accepted: a board's dashboard goes quiet after its first export until reboot; the export is the last step of a run, so nothing is lost.
- sep. 13, 2026 — FINDING: the "blackhole isolates downstream victims from root broadcasts" premise behind the proposed force-export fallback timer is FALSE, so that timer was dropped from the plan. `blackhole_victim.c:204-208` drops only at the application layer and `attacker_recv_cb` filters on `pkt->magic != PROBE_MAGIC`, so it only ever sees probes victims explicitly unicast to its MAC; descendant transit traffic is forwarded by the mesh stack below `esp_mesh_recv()`. Confirmed in captured data: in `blackhole/linear/r2` the attacker is layer 2 and victims at layers 3/4/5/6 all logged `0,0 → 1,1 → 3,0` within 1-2 samples. `BLACKHOLE-SETUP.md:130-132` says the same.
- sep. 15, 2026 — REWROTE `tools/verify_topology.py` to be interactive by default: bare
  `python tools\verify_topology.py` now only asks topology + location (menus auto-populated
  from what's actually captured — an empty topology never appears), then auto-discovers
  every (attack, repeat) combo for that topology+location and reports on all of them, no
  further prompts. WHY IT WAS BROKEN: `resolve_files()` did a flat, non-recursive
  `glob.glob()` against `tools/exports/`, but real captures nest as `exports/<attack>/
  <topology>/<location>/...` — every invocation, any flags, found zero files. Also fixed a
  latent `--topology partial` bug: the exports folder is actually `partial_mesh`, not
  `partial` (new `topology_dirname()` mapping, used by both modes).
  ⚠️ TWO REVERT PATHS, not the same target: (1) any explicit flag (`--topology`/
  `--attack`/`--repeat`/`--location`/`--files`) already bypasses interactive mode and runs
  the fixed, deterministic path today — no revert needed for scripted use. (2) `git checkout
  HEAD -- tools/verify_topology.py` restores the literal pre-session file byte-for-byte
  (repo's only commit, `74aee68`, this file untouched since) without touching any other
  uncommitted work in the repo — but that ALSO brings back the non-recursive-glob bug
  (finds nothing), since HEAD predates every fix, not just the interactive layer. To keep
  the bugfixes and only drop the interactive prompt, edit the CURRENT file instead: delete
  `interactive_run()` + `discover_topologies/locations/groups()` + `prompt_choice()` + the
  `interactive = (...)` branch in `main()`.
- sep. 15, 2026 — BUILT: ingestion guard `_reject_unimported_card_files()` + `_RAW_CARD_RE` in
  `analysis/preprocess.py` — refuses raw card-shaped names (`<role>_NODE_<MAC>[_r<N>]_b<boot>_<kind>.csv`;
  the `_b<boot>_` segment is the giveaway) BEFORE the glob, listing them in the quality report. ⚠️ Refuses
  ONLY that shape, NOT everything failing `_CAPTURE_RE` — `generate_fake_data.py` fixtures
  (`NODE_ROOT01_RUN_001_telem.csv`) are non-canonical too and must keep loading; do not "tighten" to blanket
  strictness. Covers both front-ends + manual runs (`features.py` imports `run_pipeline` from `preprocess`).
- sep. 15, 2026 — Rolled from STATUS.md "Recently done" (fuller versions of all three live on in MEMORY.md's Decisions until that file's own cap rolls them here too): SD card housekeeping (`combine_all.py` location-blind glob fix + `ARCHIVE_SD`); caught+fixed a golden-rule-#2 violation (root's `-Analyze` fired before children finished exporting, manually re-ran M6→M7→M8); `menu.ps1` "Run MULTIPLE boards in parallel" hardware-validated.
- sep. 15, 2026 — HARDWARE-VALIDATED `combined`: first successful board flash from this tree. 3-board blackhole/linear/home run via `menu.ps1`'s multi-board option (COM20=root/node5 `b0:cb:d8:f3:32:18`, COM25=node3 `70:4b:ca:25:b7:68`, COM26=node6 `f4:2d:c9:73:e6:18`) completed all 4 phases + export. FOUND: `BLACKHOLE_ATTACKER_MAC` (`mesh_config.h:207`, `20:50:0d:e7:0c:80`) matches NO board in `board_check.py`'s own roster — user confirmed patching to node5's real MAC at the time. FOUND+FIXED: root's `-Analyze` fired before children COM25/COM26 finished exporting (golden rule #2 violation), so M6/M7/M8 ran on an incomplete folder; manually re-ran all three once every export existed (15 files, 1720 windows, 3 nodes). Board/MAC assignments here are SUPERSEDED — by sep. 16 the same MAC (`f4:2d:c9:73:e6:18`) belonged to a different node (node2/attacker per the current preset); do not treat this entry's node numbers as current.
- sep. 15, 2026 — BUILT (UX later superseded sep. 16 — see MEMORY.md's current Decisions entry): SD-card import in BOTH front-ends, both shelling out to the same `import_sdcard.py` so they can't drift — `run_wizard.ps1` main menu (detects card drives by testing each drive root for `baseline`/`blackhole`/`wormhole`; bulk "import ALL", dry-run preview then confirm, repeat/roster/delete-source/boot-filter asked as separate prompts each pull) and `menu.ps1` option 7 (**Quit moved 7→8**). The underlying `import_sdcard.py --roster`/`--delete-source` flags this describes are still current; only the prompt flow changed.
- sep. 13, 2026 — Rolled from MEMORY.md Decisions (room for sep. 16 entries): OPEN
  (user-requested, not built): `run_wizard.ps1` needs a per-node selective clean option instead
  of `-CleanBuild`'s all-or-nothing wipe of both `child_node\build_*` and `root_node\build_*` —
  motivated by wanting variable attacker counts (e.g. 2 blackhole attackers out of 10 nodes),
  which the wizard's roster picker currently hard-blocks (enforces exactly one attacker).
- sep. 16, 2026 — Rolled from STATUS.md "Recently done" (room for the pre-restart archive entry):
  Scenario v1 shipped (`-Scenario`/`-ScenarioTarget`) — full details live on in MEMORY.md's Decisions.
- sep. 16, 2026 — Rolled from MEMORY.md Decisions (superseded — multi-laptop capture-split mode
  was later REMOVED entirely from `run_wizard.ps1`, not merely disabled; see FILEMAP.md "What this
  workstation is"). Kept only for historical record of what it used to do:
  - sep. 15, 2026 — BUILT: `b`/`back` through `run_wizard.ps1`'s manual capture flow, one step per
    press; that straight-line section became a `:flow`-labelled step machine (0-8), and
    `Show-Menu -AllowBack` / `Read-RepeatNumber -AllowBack` returned **-1** as the go-back
    sentinel. Also fixed a crash ("Key cannot be null") building the role menu in MULTI-LAPTOP
    mode — `$script:IdentifiedPorts.ContainsKey($_.Port)` where a board marked "not on this
    laptop" had `Port = $null` by design.
  - sep. 15, 2026 — `run_wizard.ps1`: opt-in multi-laptop split mode (e.g. Laptop A runs root +
    some children, Laptop B runs the attacker + others). Answered the FULL roster on every laptop,
    marked which boards were physically here; remote boards got a hand-off summary, never
    flashed/saved locally. Attacker could be remote, so blackhole pre-flight gained a
    manual-MAC-entry branch (validated vs `mesh_config.h`) instead of reading it over serial.
    Preset `RootCount` relaxed "exactly one" -> "at most one" for a laptop's own rootless roster.
- sep. 13, 2026 — Rolled from MEMORY.md Decisions (room for sep. 16 entries; still genuinely
  unconfirmed, not resolved — re-open in MEMORY.md if it resurfaces): OPEN (user-reported,
  unconfirmed): SD card reported as "doesn't even exist" / not writing data, stated right after a
  live test run whose OWN monitor output showed the card mounting successfully (`Name: ASTC,
  SDHC/SDXC, 3728 MB`) with only `location.txt` missing. Contradiction unresolved — could mean no
  files land on the card post-run, or the physical card fails when inspected separately. Reproduce
  before attempting a fix.
- sep. 15, 2026 — Rolled from MEMORY.md Decisions (room for sep. 16 entries): `menu.ps1`: ported
  `run_wizard.ps1`'s phase-duration estimate (`Get-PhaseDurations`/`Format-Duration`, read live
  from `mesh_config.h`'s `PHASE_*_S` constants, flagged as a hardcoded fallback rather than
  silently presented as fact if that header can't be read) into both the single-board and
  multi-board run flows — shows build/flash time (warm ~2min / cold ~4min, detected via the
  existing build-dir check) plus the root's phase total and a "finishing around HH:mm" line.
- sep. 16, 2026 — Rolled from STATUS.md "Recently done" (room for sep. 16's analyze.ps1 entry):
  Fixed the scenario `none`-folder bug across all 5 path-builders; re-verified end-to-end. Added
  `run_wizard.ps1` "Verify a run" menu option; redesigned SD-card import UX in both front-ends.
- sep. 15, 2026 — Rolled from MEMORY.md Decisions (room for sep. 16 entries): `menu.ps1`: rewrote
  "Identify a board" to read MULTIPLE boards' MAC/node number at once (ported
  `Select-MultiplePorts` from `run_wizard.ps1` — 'all' or a comma-list, BLOCKED ports never listed,
  an UNKNOWN port needs its name typed back to confirm before it's touched), then cross-checks
  every MAC just read against the compiled `BLACKHOLE_ATTACKER_MAC` and offers to auto-fix
  `mesh_config.h` if none of the boards read matches it.
- sep. 15, 2026 — Rolled from MEMORY.md Decisions: BUILT: `import_sdcard.py --delete-source` —
  removes a card file only after VERIFYING its bytes match what was written to the local export
  (not just "the copy succeeded") — protects against a partial/corrupt copy silently deleting the
  only remaining source.
- sep. 15, 2026 — Rolled from MEMORY.md Decisions (room for sep. 16 entries): BUILT:
  `import_sdcard.py --roster <preset.json>` (MAC -> Label/Role from a `run_wizard.ps1` preset) so a
  card import is named EXACTLY like a USB export — `child_node2_linear_blackhole_r1_<date>_<time>_
  telem.csv`, not `victim_NODE_<MAC>_...` — and every board in one pass shares the single
  `--repeat`. Gotcha: an unmatched MAC falls back to card naming SILENTLY (no warning yet).
- sep. 16, 2026 — Rolled from STATUS.md "Recently done" (room for sep. 16's analyze.ps1 fix +
  data-quality entries): Root-as-blackhole-attacker (star topology only) researched + designed
  (not built); plan saved, team decides next. Full details live on in MEMORY.md's Decisions.
- sep. 15, 2026 — Rolled from MEMORY.md Decisions (room for sep. 16's PDR fix entries): FIXED:
  `analysis/combine_all.py` (M8 aggregator) globbed a fixed `<attack>/<topology>/feature_table.csv`
  depth from before `<location>` existed, so every run captured under a `<location>` folder
  (everything since sep. 12) was silently invisible to `combined_all.csv` — `blackhole/linear/home`
  (396 rows) was missing; only pre-location legacy runs got in. Now walks `**/feature_table.csv`
  recursively, backfilling `unrecorded` for legacy captures. Per-run M6/M7/M8 were unaffected —
  only aggregation was blind.
- sep. 15, 2026 — Rolled from MEMORY.md Decisions: BUILT + sep. 16 HARDWARE-VERIFIED: `ARCHIVE_SD`
  — on-device serial command (archive, never delete) that moves a run's own SD-mirror CSVs into
  `<run_dir>/_archive/` right after a confirmed USB download, instead of waiting for the next
  boot's sweep. Confirmed working live: the `blackhole/linear/G402/mobility/_archive/` folder from
  sep. 16's captures.

- sep. 16, 2026 — Rolled from MEMORY.md Decisions (RESOLVED: the corrected folder rule
  — scenario folder ONLY for a real scenario, `none` gets none — is now stated directly in the
  run-scenarios-v1 entry, so this conflict flag is redundant):
  - sep. 16, 2026 — ⚠️ FLAGS A CONFLICT with the scenario entry directly below: it claims the scenario folder
    must be ALWAYS present incl. `none`, and skipping it "breaks `-Analyze` for every ordinary run." Found the
    OPPOSITE true and fixed it: `none` (no-scenario, default) was nested as a REAL `.../none/` folder in FOUR of
    five path-builders — `export_logs.py _subdir_for()`, `run_wizard.ps1 Get-RunDirs`, `run.ps1`'s `-Analyze`
    block, `run_matrix.py cell_dir()` — though each file's OWN comment says the opposite ("none... unchanged
    from before this feature existed"); also loosened `verify_topology.py`'s explicit `--scenario none` case.
    User spotted `analysis/blackhole/linear/home/none/` unprompted and called it a bug. Fixed all 5; migrated
    tonight's stranded r1 capture back to the flat path. Entry below left UNEDITED (flag, don't overwrite) —
    treat its folder-layout claim as WRONG until re-confirmed on real hardware.

- sep. 16, 2026 — Rolled from MEMORY.md Decisions (shipped and stable; the wizard UX is
  self-evident from using the tool):
  - sep. 16, 2026 — BUILT: SD-import wizard UX cut from 6+ prompts to 2 in both front-ends
    (`run_wizard.ps1 Invoke-ImportSdCard`, `menu.ps1` option 7): asks attack/topology/(scenario)/
    location + repeat, then auto-matches the roster preset and auto-picks the card drive when exactly
    one looks like a card; `--delete-source` + import-everything are always-on defaults now.
    `run_wizard.ps1` also gained a "Verify a run" menu option (`Invoke-VerifyRun`).
- sep. 15, 2026 — Rolled from MEMORY.md Decisions (root-caused, guards added, no longer live risk):
  ⚠️ ROOT-CAUSED a FALSE `BLACKHOLE CONFIRMED` (ForwardingRatio 0.995→0.000, z=-19.6): the
  `feature_table.csv` pooled THREE UNRELATED SESSIONS in one leaf — the real root export
  (`..._r2_20260915_211307_...`) plus two RAW SD-card files copied in by hand
  (`victim_NODE_20500DE70C80_r21_b22`, `..._F42DC973E618_r26_b28`). THE FACT: an ON-CARD `r<N>` is
  that board's own on-device run counter (times IT logged to THAT card), NOT the campaign repeat. A
  card mirrors the same `<attack>/<topology>/<location>/` tree as `exports/`, so dragging a card's
  folder over the exports folder merges raw captures into a leaf where they still end in
  `_telem.csv` and get globbed in silently; only `import_sdcard.py --repeat` restamps them to one
  campaign number. `verify_topology.py` had already flagged both orphans ("No root node identified"/
  "Unresolved parents") — that was the tell.
- sep. 16, 2026 — Rolled from STATUS.md Recently done + MEMORY.md: `analyze.ps1` gained a menu;
  archived twice (`pre-restart`, `mobility-run`) and reset the scaffold. REWROTE
  `analysis/ANALYSIS-Commands.md` (was badly stale: `star_topology` naming, no `<location>`/
  `<scenario>` layers, no tooling) — now leads with `analyze.ps1`, covers trimming (+ the
  stale-`trimmed/` gotcha), manual M6→M7→M8, `verify_attack.py` PASS/FAIL/SKIP reading (a FAIL
  usually means a noisy baseline, not broken code), and a "looks like an error but isn't" section
  (PS 5.1 red numpy-stderr; by-design NaN columns). All 13 paths link-checked.
- sep. 16, 2026 — Rolled from STATUS.md Recently done: analysis grid 1Hz→10Hz + window 5s→1s
  (**D-9**, 577→2,894 rows/run); attack/topology/location/scenario now columns on every row
  (**D-10**, fixes `combine_all` pooling scenarios). Full detail: MEMORY.md.
- sep. 17, 2026 — Rolled from MEMORY.md Decisions (shipped and stable): BUILT
  `ESP32-Environment/archive.ps1`, automating the archiving convention: one dated+labelled folder
  per run under `archive/<date>_<label>/`, each with an auto-written README giving the reason.
  MOVES (never copies/deletes) all captures + analysis output preserving the
  attack/topology/location/scenario layout, then resets the `.gitkeep` scaffold (3 attacks × 4
  topologies) + header-only ledger. Keeps `analysis/*.py|md|txt` and every `.gitkeep`. `-WhatIf`
  previews; `-Label`/`-Reason`/`-Force` script it; refuses to run on an empty tree (a lone
  header-only ledger doesn't count as data); auto-suffixes `-2` rather than overwrite an existing
  archive. ⚠️ Git-Bash `mv` gives "Permission denied" on these dirs — the script uses `Move-Item`.
  ⚠️ **PS 5.1 `Out-File -Encoding utf8` writes a BOM.** That silently broke `run_ledger.csv`:
  `run_matrix.py` reads it with plain `encoding="utf-8"` + `csv.DictReader`, which does NOT strip a
  BOM, so field 1 became `﻿` + `topology` and every `row["topology"]` would fail (pandas hides
  this — it strips BOMs, so test with csv.DictReader). Use `-Encoding ascii`, or
  `[System.IO.File]::WriteAllText(..., New-Object System.Text.UTF8Encoding $false)` when the text
  may be non-ASCII.
- sep. 17, 2026 — Rolled from STATUS.md Recently done: **FIXED PDR** (it WAS a code bug — corrects
  an earlier "not a code bug" note) — per-window attribution replaces the run-wide coverage gate,
  so `PDR==0` can finally be recorded (was 0 of 446 rows); also killed a `0/(0+EPSILON)`
  false-zero. thesis-deviate **D-8**. Full detail: MEMORY.md.
- sep. 17, 2026 — Rolled from STATUS.md Recently done: **Wizard/menu nav overhaul, cont'd**
  (`run_wizard.ps1` + `menu.ps1`, kept in sync) — `cls` clears the terminal (no Ctrl+C); both main
  menus number 1-9 sequentially regardless of category; `menu.ps1` gained the wizard's
  identify-a-port/-ALL + MAC tagging and now hides non-ESP32 (BLOCKED) ports everywhere, gating
  UNKNOWN behind a typed confirm. Full detail: MEMORY.md.
- sep. 17, 2026 — Rolled from MEMORY.md Decisions (shipped and stable): BUILT
  `ESP32-Environment/analyze.ps1` — the analysis+validation front door (trim→M6→M7→M8→verify) on
  captured data. No args = `menu.ps1`-style menu, runs pickable from a numbered list; `-List` shows
  combos + row counts + running total; `-All`, `-Verify`, `-SkipTrim` for scripting. Finds captures
  at ANY folder depth (a v1 bug checked only one level and silently missed every `-Scenario`-tagged
  capture). Docs: `analysis/ANALYSIS-Commands.md`. ⚠️ `trim_run.py` does NOT clear `trimmed/` before
  re-trimming, so stale files from a prior partial run get loaded by every analysis tool — it warns
  `[!] N STALE file(s)`; menu [6] clears it.
- sep. 16, 2026 — Rolled from MEMORY.md Decisions (cap overflow): ⚠️ CAPTURE QUALITY, unresolved:
  `blackhole/linear/G402/mobility` — 3 of 4 victims probed all run but root logged nothing from them
  in ANY phase (`B4BFE932FE90` changed layer 4→5 mid-run; `2805A532D7B4` at layer 6). NOT the MAC bug
  (that run's attacker `0c:80` DID match the then-configured MAC, one victim got through) — suspected
  mobility-disrupted TODS relay, still untested since the 15:36 re-run was itself voided by the MAC
  bug. `home/mobility` also exported ONLY root's CSVs — check `-Location`/`-Scenario` match on every
  board before export.
- sep. 16, 2026 — Rolled from MEMORY.md Decisions (cap overflow, shipped): BUILT run scenarios v1
  (`none|burst|highload|mobility|powercycle`) in run.ps1 (`-Scenario`/`-ScenarioTarget`), both
  front-ends, presets, `run_matrix.py`, `verify_topology.py`, the Python export chain — the panel's
  "real-world variation" ask. Build flag `-DTRAFFIC_PROFILE=1` burst / `=2` highload; `none` passes NO
  flag, so its compile line and build dir stay byte-identical to pre-scenario. Who gets it: burst →
  root + the ONE `-ScenarioTarget` child; highload → every child; mobility/powercycle → nobody
  (human-performed, label-only). Burst fires `BURST_COUNT`(100) probes `BURST_OFFSET_S`(60) into the
  attack-length window, and on a BASELINE run the root holds a matching extra window so a legit burst
  and a burst-under-attack form a matched pair. ⚠️ Export-folder rule: the scenario folder is added
  ONLY for a real scenario — `none` gets NO extra folder. Build-dir suffix `_burst`/`_highload` is a
  SEPARATE concern (firmware variant, not export path). ⚠️ Verified only without hardware attached —
  NOT bench-tested on real boards as of this roll.
- sep. 17, 2026 — Rolled from MEMORY.md Decisions (cap overflow, shipped): BUILT "edit a specific
  node" on the pre-flash plan summary, both `menu.ps1` and `run_wizard.ps1` (independent
  implementations — the two scripts' board/roster models differ, kept in sync in spirit only). After
  the Attack/Topology/"Order (root is always last)" box, the operator can edit one node's
  port/label/toggles (Wipe/Flash/Export+Location/Clean in `menu.ps1`) and attack sub-role (blackhole
  attacker/victim, wormhole A/B — reassigns ALL peers together in `run_wizard.ps1` to keep "exactly
  one attacker"/"exactly one A and one B" true; `menu.ps1` edits just the one board's field, matching
  its existing warn-only philosophy); change which node is ROOT (promotes one, demotes the other,
  re-sorts children-first-root-last, and in `run_wizard.ps1` re-triggers the attack-sub-role picker
  for the new child set); or change the run's TOPOLOGY (global, rebuilds every board's command line).
  Every change reprints the plan (and, in `menu.ps1`, re-runs the sanity warnings incl.
  `Confirm-BlackholeAttackerMac`) before the per-board CONFIRM loop / "Proceed?" runs — no blind
  apply-to-all. Extended sep. 17 in `run_wizard.ps1` only (add/remove node, no-preset mode) — see
  MEMORY.md for the current state of that feature.
- sep. 16, 2026 — Rolled from MEMORY.md Decisions (cap overflow, shipped): FIXED `features.py`'s PDR
  attributability (thesis-deviate **D-8**), superseding an earlier "NaN logic is correct" claim — it
  was NOT. PDR gated attributability on a run-wide `covered_macs` set, so a victim the root never
  logged ANYTHING for got NaN in every window — exactly the node a blackhole hits hardest.
  Consequence: `PDR == 0` occurred in **0 of 446 rows**; the feature could never record the value it
  exists to detect. Now gated per-window on evidence: node transmitted (`probes_count_delta > 0`)
  AND was associated (`layer > 0`, parent_mac non-zero) AND the window is inside the root's
  arrival-logging span (that last one replaces the old safety against a never-pulled root CSV). Also
  fixed a latent FALSE-POSITIVE: `0/(0+EPSILON)` returned a literal `0.0` for windows where a node
  sent nothing — a fabricated blackhole signature. Before→after on `G402/mobility`: PDR non-null
  41→238, `PDR==0` 0→201, NaN 405→208; victim PDR by phase now baseline 0.217 → attack 0.000 →
  cooldown 0.750. `verify_attack.py` still says NOT CONFIRMED there (that capture's own baseline is
  degraded, 0.164±0.372) — i.e. it surfaces the signature WITHOUT fabricating one. Remaining NaN is
  correct, not a gap: root never originates probes (PDR undefined for it).
- sep. 17, 2026 — Rolled from MEMORY.md Decisions (cap overflow; superseded by the two
  heartbeat follow-up entries that remain in MEMORY.md, which describe current behaviour).
  Original entry:
  - sep. 17, 2026 — DECIDED + BUILT: Command Center's heartbeat/node-table feature is back,
    **on purpose, reversing the sep. 14, 2026 "removed, not merely disabled" merge decision**
    (see ARCHIVE.md and the sep. 13 BUILT entry below for what it replaced). Trigger: needed a live
    per-node MAC/layer view to verify connected boards are actually following the built topology
    (STAR/TREE/LINEAR/PARTIAL), which the existing zero-traffic `MESH CONNECTED: N node(s)` banner
    (sep. 13, still in place) cannot show — ESP-MESH's routing-table API gives MACs but no per-node
    layer. Implementation lives INSIDE `components/mesh_common/{mesh_setup.c,mesh_setup.h}` —
    deliberately NOT a separate `heartbeat.[ch]` file (user's explicit call, sep. 17). Every node
    (root included) sends a `node_heartbeat_pkt_t` (`mesh_messages.h` — wire format was already
    defined, unused, kept only for `node_identity`/capture per the sep. 14 removal note) to root every
    `HEARTBEAT_INTERVAL_MS` (2000 ms); root aggregates the latest row per MAC and reprints the table
    (LYR/MAC/ROLE/NICKNAME/RSSI/PHASE/AGE_S, sorted by layer) under the `MESH_SETUP` log tag whenever
    a node's layer/role/nickname changes. Public API: `heartbeat_start()` (every node, after
    `phase_listener_start()`) / `heartbeat_table_init()` + `heartbeat_ingest()` (root only, demuxed
    inside the existing `probe_data_cb` single-packet-dispatcher — no second `esp_mesh_recv()` reader).
    ⚠️ **Knowingly reintroduces periodic mesh traffic** on the exact network this testbed measures
    (PDR/latency/RSSI) — the sep. 13 banner's whole point was avoiding that. At `HEARTBEAT_INTERVAL_MS
    = 2000` and `PROBE_INTERVAL_MS = 1000`, heartbeat volume is small relative to probe traffic, but
    this was NOT benchmarked against a clean capture before being merged — if PDR/latency numbers
    look off after this change, check whether heartbeat traffic is a contributing cause before
    trusting the data. NOT build-tested (no ESP-IDF environment in the session's shell) — first build
    must go through the normal `run.ps1`/wizard flow before a real capture. FILEMAP.md updated to match.

## Rolled from MEMORY.md — sep. 18, 2026 (heartbeat fixes, sep. 17)
- sep. 17, 2026 — ADDED instant disconnect reporting on top of the stale-eviction fix below, in
  response to "can the heartbeat print instantly on disconnect instead of waiting on the stale
  timer": (1) `MESH_EVENT_CHILD_DISCONNECTED` — the one mesh event that names a specific MAC — now
  calls a new `heartbeat_mark_offline(mac)` which evicts that row and reprints immediately, instead
  of waiting up to `HEARTBEAT_STALE_MS` (21 s) for the age sweep to notice. Only fires anything on
  the root (`s_table_ready` guard) — same as every other root-only table op. (2)
  `MESH_EVENT_ROUTING_TABLE_REMOVE` — fires for a multi-hop node dropping off deeper in the tree,
  which `CHILD_DISCONNECTED` does NOT catch (that event only names the root's own direct children) —
  now forces an immediate `heartbeat_table_print()` instead of waiting up to
  `HEARTBEAT_TABLE_REPRINT_MS` (14 s) more for the periodic reprint. ⚠️ This does NOT shrink the 21 s
  staleness floor itself for a multi-hop node — `ROUTING_TABLE_REMOVE` carries no MAC, so it can only
  force an early PRINT of whatever the stale sweep already knows, not an early EVICT. True instant
  detection (<1 heartbeat interval) is only possible for the root's direct children; a deeper node's
  disconnect is still bounded below by three missed heartbeats, which is what tells a real drop apart
  from one lost frame. Required moving `s_table_ready` up into the file's top module-private-state
  block (was declared down in the heartbeat section) plus two early forward declarations
  (`heartbeat_table_print`, new `heartbeat_mark_offline`), so `mesh_event_handler` — defined earlier
  in the file — can reach them. Same file as everything else here: `mesh_setup.c`. Not build-tested
  (attempted locally: this machine's `idf5.3_py3.14_env` Python venv is broken/missing —
  `idf_tools.py install-python-env` needed, unrelated to this change) — same caveat as the entry below.
- sep. 17, 2026 — FIXED three heartbeat gaps, all found via live hardware logs across this session
  (follows the original BUILT entry, now in ARCHIVE.md): (1) the table only reprinted on
  layer/role/nickname change, so a plain disconnect/reconnect showed nothing even though `AGE_S`
  tracked it correctly — added
  `HEARTBEAT_TABLE_REPRINT_MS`, a root-only unconditional timer reprint gated on a new
  `s_table_ready` flag (set by `heartbeat_table_init()`) instead of `mesh_setup_is_root()`, which is
  FALSE for this whole testbed's actual root (manual/fixed root, no router, never gets
  `MESH_EVENT_PARENT_CONNECTED` — confirmed from a boot log reading `Root: NO`; that flag's one other
  consumer, `heartbeat_task`'s parent-RSSI/send-direction check, was left alone since its TODS
  self-loopback works fine). Root also self-ingests its own heartbeat locally each tick so its row
  can't age out. (2) Change-triggered prints weren't resetting the periodic timer (uneven first gap)
  — both paths now share one `s_last_print_us`, reset on every print. (3) A disconnected node's row
  never left the table, only `AGE_S` climbed, so the printed node COUNT stayed wrong —
  `heartbeat_table_print()` now sweeps for entries idle past `HEARTBEAT_STALE_MS` (3× the send
  interval), logs `Node OFFLINE` with MAC+nickname, and evicts before printing. ⚠️
  `HEARTBEAT_TABLE_REPRINT_MS` rounds UP to the next multiple of `HEARTBEAT_INTERVAL_MS` (check rides
  the send loop) — keep it an exact multiple or the configured value won't match what's observed.
  Final values after user iteration: `HEARTBEAT_INTERVAL_MS` 7000, `HEARTBEAT_TABLE_REPRINT_MS`
  14000, `HEARTBEAT_STALE_MS` 21000 (auto-derived, 3×interval). Still NOT committed, NOT
  build-tested. Heartbeat is in `mesh_setup.c/.h`; ⚠️ it adds periodic mesh traffic to the very
  network this testbed measures — see the original BUILT entry in ARCHIVE.md before trusting PDR/
  latency numbers captured with it enabled.

## Rolled from STATUS.md "Recently done" — sep. 18, 2026
- sep. 17, 2026 — **"Trim exported CSVs only"** split into its own DATA menu option in both wizards
  (was missing entirely — "Run analysis only" never trimmed); `run_wizard.ps1` child-count prompt
  accepts `0` for a root-only capture. MEMORY.md.
- sep. 17, 2026 — **SD-card capture provenance**: build stamp → `runs.csv` `built` + status report;
  `import_sdcard.py --list-json`/`--files`; dated numbered file picker in both wizards. MEMORY.md.

## Rolled from STATUS.md "Recently done" — sep. 18, 2026 (2nd roll)
- sep. 17, 2026 — **Analysis pipeline hardening**, pushed `a4f87b4` (trimmed\ default, missing root
  arrivals blocks, arrivals-flush fix, PS5.1 import-picker crash). MEMORY.md.

## Rolled from MEMORY.md "Decisions" — sep. 18, 2026
- sep. 17, 2026 — BUILT in `run_wizard.ps1` only (`menu.ps1` still has just the edit-a-node step):
  "Adjust the plan?" gained ADD / REMOVE a node beside edit/topology; an edited preset now offers
  "save these changes back into <preset>" as its own prompt (separate from "save as a new preset",
  which still appears only for a from-scratch roster); and the mode menu gained "Run a capture
  without a preset", skipping the preset picker even when presets exist. Remove refuses to drop the
  ROOT (swap root first via that node's Role field) or to break "exactly one attacker". Three bugs
  the user then hit on a live run, all fixed: (1) MANUAL-flow boards never carried a `Mac` field
  (only preset-loaded ones did, via `ConvertTo-Roster`) while `Resolve-BoardMac` caches with
  `$Board.Mac = $mac` — a PSCustomObject cannot gain a property by assignment, so the confirm table
  threw AFTER every question was answered and AFTER the attacker-MAC gate had rewritten
  `mesh_config.h`; pre-existing, but the new no-preset option made it the default path. Every
  construction site now seeds `Mac = ''`, plus an `Add-Member -Force` fallback (as `Add-BoardMacs`
  always used). (2) the blackhole role menu FORCED one child to be the attacker — with a single
  child that was no choice at all, and it yielded an attacker with no victims, i.e. no attack
  signature; it now always offers "None of these - they are all VICTIMS", the single-laptop twin of
  the existing multi-laptop escape. (3) `Show-Menu` printed "Type 1-1" for a one-option menu and
  rejected Enter; it now says "Press Enter (or type 1)" and accepts it. NOT hardware-tested.

## Rolled from STATUS.md "Recently done" — sep. 18, 2026 (3rd roll)
- sep. 18, 2026 — **Wizard tooling session** (`run_wizard.ps1`/`menu.ps1`): member board list gained
  per-board scenario job (burst/mobility/powercycle, one holder each, shown as a tag) + named
  snapshots like presets (new `member_boards\` folder: save/look-at/load/delete); separately,
  run_wizard fixed burst-target and preset-scenario dead ends, and re-finds preset boards by MAC
  after USB moves. MEMORY.md.

## Rolled from MEMORY.md "Decisions" — sep. 18, 2026 (2nd roll)
- sep. 18, 2026 — BUILT: per-board **scenario job** (burst/mobility/powercycle - the set
  `Test-ScenarioNeedsTarget` flags in run_wizard.ps1; highload/none aren't per-board) on every add/
  edit in the guided editor, shown as a `<< BURST TARGET`-style tag; picking a job another board
  already holds asks to move it (mirrors run_wizard's ScenarioTarget uniqueness). Also BUILT: named
  **snapshots** — save the current list under an attack/topology/location name (like a preset) into
  a new `ESP32-Environment\member_boards\` folder, then look at or load one back later instead of
  retyping (per user request); loading OVERWRITES the live file after a table preview + `[y/N]`
  confirm. New "Save/load a named board-list snapshot" option (Idx 13/Action 14). Two real bugs
  caught by scripted testing before shipping: `return (if(){}else{})` is invalid PowerShell
  (statement keywords can't sit inside `()`) - would have crashed every "keep current" scenario
  answer; and the table renderer's column padding went negative (crash) when an early row's
  scenario tag made it wider than a later row's - fixed by reserving the widest tag's width across
  the whole column up front. Tested: 18 + 15 scripted-answer checks against own fixtures (not the
  live file, which keeps changing underneath) + both real launchers opened end to end.
- sep. 18, 2026 — FIXED in `run_wizard.ps1` (uncommitted): **presets were matched to boards by COM
  port only.** Moving boards to other USB sockets/a hub renumbers COM ports (they follow the socket),
  and the drift fix made you pick ports by hand and then BLANKED the preset's recorded MAC. Now: new
  `Get-LiveMacMap` + `Sync-RosterPortsByMac` read each plugged-in ESP32's MAC (reusing this session's
  identify cache) and move every preset board to the port holding its recorded MAC, with a [Y/n]
  preview; only unmatched boards go to the manual picker. Also catches two boards that TRADED COM
  numbers (previously silent — each would be flashed/labelled as the other). The picker's "Verify
  MACs now" used to overwrite a board's MAC with whatever board sat on its old port and offer to save
  it (corrupting the preset); it now reports whose board is there and offers the MAC re-match.
  Skipped under `-DryRun`/`-SkipMacCheck`. Matching logic tested with 14 fake-board cases in PS 5.1;
  NOT hardware-tested — load a preset with boards on different sockets before relying on it.
- sep. 18, 2026 — FIXED in `run_wizard.ps1` (uncommitted), from teammates' reports: (1) **no skip on
  burst** — the manual flow's scenario-target step (burst/mobility/powercycle) dead-ended with "go
  back" whenever no LOCAL child could carry it, even on a multi-laptop split (root-only laptop, or
  only attacker/wormhole boards here); it now records the target as on another laptop, like the
  blackhole/wormhole role menus already did. (2) **presets' scenario couldn't be changed** — "Adjust
  the plan before confirming?" gained "Change scenario for this run": clears the old target, re-asks
  for one with the same "on another laptop" escape (offered only when the roster already has remote
  boards). `menu.ps1` checked: has neither bug (per-board yes/no questions, missing target is only a
  warning; no presets). Parser clean, not hardware-tested.

## Rolled from STATUS.md "Recently done" — sep. 18, 2026 (4th roll)
- sep. 18, 2026 — **Main-menu declutter + SD-picker delete + per-member preset folders**
  (uncommitted; `run_wizard.ps1`, `menu.ps1`): the 3 member-board-list main-menu entries
  (edit / open json / snapshots) collapsed into one submenu in both launchers, freeing the main
  menu; the SD-card import file picker gained a `d1,3` command to delete files straight off the
  card (separate from the existing post-import `--delete-source`, which still only fires after a
  verified copy); presets split one folder per member (`presets\Bas\`, `presets\Cal\`,
  `presets\Kyle\` — empty until first save, git won't track them until then), with owner
  auto-detected from the roster's MACs against `member_boards.json`, a new `my_member.txt`
  ("whose laptop is this," set from the member-board submenu) breaking ties, and the picker
  showing YOURS first then every other member under its own heading — solves "which preset did I
  save for the absent member vs. mine" by construction. The pre-existing
  `presets\linear-blackhole-none-g402.json` unresolved merge conflict (still UU, see
  Blockers) was left untouched and still sits unfiled; resolving it is now also a precondition
  for filing THAT preset under an owner. MEMORY.md.

## Rolled from MEMORY.md - sep. 20, 2026 (sep. 18 tooling batch + sep. 16 attacker proposal)

- sep. 18, 2026 — **PUSHED** the whole day's sep. 18 tooling batch to `origin/Unified` (`1cf76e3`):
  topology graph, mesh layer-cap fix, CC heartbeat, per-member presets (full detail in ARCHIVE.md),
  run-log/SD-delete tooling, member board list. Resolved the sep. 17 index conflict on
  `presets\linear-blackhole-none-g402.json` by removing it (superseded by `presets\Bas\...json`,
  already staged) and merging in the 3 data-sync commits (`0a356df` etc.) pushed from a separate
  clean clone. Also merged `run.ps1`/`push_data.py` conflicts by keeping the newer local versions
  (menu already collapsed to one submenu; docstring already covering presets).
- sep. 18, 2026 — BUILT (`run.ps1` + `run_wizard.ps1`'s `Invoke-FirmwareSelfTest`, uncommitted):
  auto-detect + wipe a half-configured build dir. Symptom that triggered this: an interrupted
  `idf.py`/Ctrl+Break can leave `CMakeCache.txt`/`build.ninja` written but the generated
  `config\sdkconfig.h` without `CONFIG_IDF_TARGET_ESP32` — esp-idf's `soc_caps.h` then can't
  determine the ECO version and `sha_hal.c` fails with `SHA_TYPE`/`SHA1` undeclared, a plain rebuild
  just reusing the same broken tree forever. Same remedy as the existing wrong-repo-path self-heal in
  `run.ps1`: detect, `Remove-Item -Recurse -Force`, let it reconfigure. Scope explicitly limited to
  `run.ps1`/`run_wizard.ps1` per user request — `menu.ps1`'s own separate pre-build `idf.py` call
  still has NO self-heal of any kind.
- sep. 18, 2026 — BUILT (`tools\push_data.py` + `run_wizard.ps1`, uncommitted): data sync now
  actually covers saved presets, not just capture CSVs — `push_data.py`'s docstring had claimed
  presets support since it was written, but the code was 100% CSV-hardcoded. New `--area
  {exports,presets}` flag (default exports); presets area syncs `.json` under `presets\<owner>\`
  using the exact same byte-diff/conflict-keep-both/ledger-skip machinery, no new logic needed.
  Wizard menu gained "Upload my saved presets to GitHub" (`Invoke-DataSync -Area presets`), same
  push-then-auto-pull-back UX as the existing CSV push. `menu.ps1`'s separate, still-unmerged
  data-sync menu NOT touched — out of the user-specified scope both times this was requested.
- sep. 18, 2026 — BUILT (`run_wizard.ps1` + `mesh_common`, uncommitted), 4 items. (1) Run log:
  `[Y/n]` prompt before a capture, `Start-Transcript` over the board loop into new `run_logs\`, named
  like a preset + timestamp; DATA menu "View a saved run log" (`Invoke-ViewRunLog`). (2)
  `DELETE_SD_PATH=<attack>/<topology>/<location>` in `csv_logger.c` — PERMANENTLY deletes a card
  folder (e.g. `blackhole/linear/G402`), the ONE deliberate exception to this project's
  archive-never-delete rule, operator-requested only. Path must be `baseline|blackhole|wormhole` +
  `[A-Za-z0-9_-]` segments (blocks `..`, absolute paths); refuses (`ERROR:SD_PATH_IN_USE`) if the
  board is logging there now; command buffer widened 32→96B with an overflow guard (else a truncated
  path names the PARENT folder). Host: `export_logs.py --delete-sd-path`; wizard: MAINTENANCE "Delete
  a folder..." (`Invoke-DeleteSdFolder`), board→attack→topology/ALL→location/ALL→**`[y/N]`** (downgraded
  from type-DELETE per explicit user request — less friction, less guard on a permanent wipe; flagged
  not re-litigated). BUILD-CLEAN (child+root) sep. 18 — ⚠️ **NOT flashed/hardware-tested yet**. Found
  along the way: needed `#include <unistd.h>` for `rmdir`; the wizard's script-wide `Stop` turns any
  `python ... 2>&1` call's first stderr line into a thrown exception, dropping the rest of the output
  (`Continue` set locally in `Invoke-DeleteSdFolder`; `Get-SdLocation`/`Set-SdLocation` still have this
  latent bug). (3) `import_sdcard.py` no longer descends into `_archive\` (was re-importing archived
  runs) — verified on a fake card. (4) The 3 GitHub sync menu items (see `0a356df` below) merged into
  one DATA entry opening a submenu (`Invoke-DataSyncMenu`, "Back" default) — `run_wizard.ps1` only,
  `menu.ps1` untouched. ⚠️ Menu `Idx` numbers shift as this file is hand-edited concurrently elsewhere
  (OneDrive sync) — a stale-numbered scripted test this session hit "Test data sync" by accident,
  making a local `sync_test\`; confirmed nothing reached `origin/Unified`, folder deleted — re-derive
  live numbering before scripting wizard input.
- sep. 18, 2026 — BUILT + **PUSHED** (`0a356df`, `origin/Unified` — the day's only pushed work): **data-only
  GitHub sync**, `ESP32-Environment\tools\push_data.py` + one menu option each for push / pull / test
  (menu.ps1 Action 15/17/16, shared `Invoke-DataSync`; run_wizard's 3 merged into one submenu sep. 18,
  see today's entry above). Why: a `git pull --autostash` on a tree with uncommitted code wrecked this
  repo sep. 17 (conflicted preset + orphaned stash, still unresolved), and teammates capture DIFFERENT
  nodes of one run, so data must reach GitHub without anyone's half-done code. Safety: all git work happens
  in a private blob-filtered clone under `%LOCALAPPDATA%\nis16-data-sync` — your tree is never stashed/checked-out/merged/rebased; only
  `.csv` under `tools/exports/` (or `sync_test/`) can be staged, anything else ABORTS the commit; on
  rejection it rebuilds the commit on newest origin and retries (5×). Rules: unseen file → added; ledgers →
  unioned; identical or older-than-origin → skipped; same name + different bytes → BOTH kept, yours to
  `sync_conflicts/<computer>/` (no analysis scans it); already under `archive/` on GitHub → never re-pushed
  live. Pushed/pulled files are `git add`ed locally because a plain `git pull` REFUSES to overwrite an untracked
  file even when byte-identical (verified). `.gitattributes` gained `merge=union` for both ledgers. Tested:
  44-check two-laptop sim on a local bare repo (race retry, archive suppression, code untouched, `git pull`
  still works after) + 9-check pull-only sim + a cancelled GitHub dry run. NOT proven laptop-to-laptop yet — run "Test data sync" on two machines first.
- sep. 18, 2026 — BUILT (both wizards, uncommitted): **member board list** — a Cal / Bas / Kyle
  table (nickname | first:last MAC | colored role) atop both main menus, replacing the whiteboard.
  Data: `ESP32-Environment\member_boards.json` (member names FIXED in code); shared code
  `tools\Show-MemberBoards.ps1`. Three ways to edit: "Edit the member board list" (guided add/edit/
  remove, saves each change immediately, no BOM, never overwrites invalid JSON), "Open
  member_boards.json directly" (launches `$env:EDITOR`/`code`/notepad, non-blocking), and named
  snapshots (full detail rolled to ARCHIVE.md). ⚠️ The Idx/Action numbers this entry originally cited
  are STALE as of the sep. 18 main-menu-declutter entry above — all 3 now sit inside one submenu
  (run_wizard Idx 17, menu.ps1 Action 18), which also gained a 4th item ("Set whose laptop this is").
  Seeded from a whiteboard photo:
  Cal 20:38 attacker, 20:80 + F4:18 role `?`; Kyle 8/9/10/11 = B4:90/28:B4/70:C8/B4:80 children; Bas
  none. ⚠️ `70:C8`/`28:B4` hard to read in the photo — confirm. ⚠️ Someone hand-edited the file
  sep. 18 evening — Cal's `20:38 attacker` moved to Kyle as `child_8`, contradicting the user's
  earlier confirmation; not reverted, flagged for the team (STATUS.md Next step 2).
- ⚠️ Root-as-blackhole-attacker (STAR only) proposed sep. 16, NOT built — team decides first; full
  plan at `.claude\plans\mutable-honking-spindle.md` (Basti profile). Rolled to ARCHIVE.md for detail.


## sep. 20, 2026 — superseded pre-fix audit diagnostics (rolled from MEMORY.md)

- sep. 20, 2026 — Pre-fix leftovers still true: anchor on the PHASE EXIT (a root-boot cutoff is NOT
  sufficient), and `compute_forwarding_features` still has no guard on a physically impossible
  ForwardingRatio > 1, unlike `compute_pdr_features`' five guards.
- sep. 20, 2026 — `RSSI_Hop_Diff` also inherited the contamination; fixed by P1 + the rssi-0 blanking.

## sep. 20, 2026 — P1/P2/P3 applied + verified (rolled out of MEMORY.md sep. 20 to hold the 200-line cap)

Superseded as a *live* entry by the F1/F2/F3/P5 batch, but kept verbatim because it records the verification numbers for the analysis fixes.

- sep. 20, 2026 — **P1/P2/P3 APPLIED + VERIFIED (uncommitted). `verify_attack.py` → `BLACKHOLE CONFIRMED
  (2/2 primary exceed 3-sigma)`, exit 0.** 3 files, +295/−16; NO firmware, NO raw CSV, NO threshold lowered
  (sigma still 3; `BASELINE_FLOOR` RAISED 0.50→0.90). Each change carries its full rationale in a code
  comment — read those, not this entry, for the why.
  **P1 `preprocess.py`** — new `assign_segments()`: `segment` + `t_anchor_s` columns anchored on each node's
  **own first exit from phase 0** (the only clock-free cross-node event); phase 0 & t < −300 s →
  `pre_baseline`; non-real-phase segments get `window_label = NaN` (rows KEPT, nothing deleted). Also blanks
  `rssi_dbm == 0` (6446 rows, A1#7). ⚠️ anchor on the PHASE EXIT, not root boot — see below.
  **P2 `features.py`** — `from preprocess import WINDOW_SECONDS` (was a divergent literal 5).
  **P3 `verify_attack.py`** — new **INFEASIBLE** status (bounded feature whose max attainable |z| < sigma is
  excluded, never FAIL); `BASELINE_DISPERSION_CEILING` sd/mu > 0.15 → INVALID-BASE; `RATIO_OF_SUMS` for
  ForwardingRatio; killed the docstring's bogus "z = −6.10" (actual −2.55); rewrote the RetryRate note.
  **Verified:** FR −40.22 / PDR −39.38 / Consistency +38.88 / IngressEgress +48.51 all PASS · 4 features
  79.9% NaN → **0%** · eda.py PCA usable features **4 → 8** · segments 2945/2399/1414/946 ·
  **NEGATIVE CONTROL** (half the baseline relabelled attack) still NOT CONFIRMED z≈0 — not made permissive ·
  re-contaminating now gives **INCONCLUSIVE + "check for pre_baseline contamination"** (was the misleading
  "check the attacker setup") · 15/15 unit tests · byte-identical reruns (M6 determinism).

## sep. 20, 2026 — pre-fix diagnostics, rolled out of MEMORY.md to hold the 200-line cap

All five were SUPERSEDED by fixes applied the same day (P1/P2/P3, then F1/F2/F3/P5). Kept verbatim because they hold the measured numbers and the quotable evidence that the blackhole attack itself always worked — which the paper needs.

- sep. 20, 2026 — **M8 was silently running on 4 of 16 features** (eda.py drops columns until something
  runs; 0/7704 rows had a complete set). P2 lifted it to **8**. The other 5 need F3/F4 (3 relay features)
  and a wormhole capture (3 tunnel). M7's "no feature uniformly NaN" stays unmet until a wormhole run exists.
- sep. 20, 2026 — **Two existing tools already detect early-boot contamination — wire them as gates.**
  `validate_integrity.py`'s "phase 0 has 2.76–2.95x expected rows" WARN fires on exactly the 5 nodes that
  booted 491–551 s before the root; `verify_topology.py` returns "Converged within 60s: NO" for them.
  `analyze.ps1` calls `verify_attack.py` WITHOUT checking either exit code. D-2 records children-booted-
  before-root as ROUTINE (−194 s in July) ⇒ systemic ⇒ fix F1 in firmware, not the runbook.
- sep. 20, 2026 — **The blackhole ATTACK WAS ALWAYS FINE; `verify_attack.py` was the broken thing** (fixed
  above). Quotable evidence: root arrivals **6.07/s baseline → 0/s attack → 6.01/s cooldown** (99% recovery;
  `validate_integrity.py`'s own words: "total drop, the expected attack signature"); attacker forwarded
  2605/2600 baseline vs **1/1020** attack; ~182 contiguous missing seq per victim = `PHASE_ATTACK_S`. Cause
  of the false FAIL: root joined 100–551 s AFTER the victims (sep. 18 brownout) and `phase_listener.c:35`
  inits `s_gt_label = GT_LABEL_BASELINE`, so never-heard-a-broadcast looked like baseline — 2945/7704 (38%).
- sep. 20, 2026 — **SECOND BUG (FIXED by P2)**: `features.py` WINDOW_SECONDS 5 vs `preprocess.py` 1 — the
  merge on `window_start` matched only multiples of 5. Affected EVERY feature table built since D-9 ⇒
  **re-run M6→M7 on any cell analysed before sep. 20.**
- sep. 20, 2026 — **LEAKAGE measured (panel-P1).** (1) `RetryRate` on the ATTACKER row is the attack's own
  drop counter (`blackhole_victim.c` overloads `retry_count`): 0.0033 → **0.9991**, while victims go 0.0008
  → **0.0000**. The one feature that "PASSED" is the leak. ⇒ `SIGNATURES`' "victims retry" was wrong (now
  fixed), and paper **Table 3.4's "retransmission increase for victim nodes" is a pre-registered MISS** —
  REPORT it, do NOT edit the table; §3.3.1.2 already explains why (link-layer ACKs still succeed).
  (2) `ConsistencyScore` ≡ |ForwardingRatio−1| to 1.1e-16 and `IngressEgressDelta` = recv×|1−FR| ⇒ **3 of 16
  features are ONE measurement**; FR alone decides the attack at 0.9694 vs 0.7685 majority.
  (3) `combine_all.py:52-55` ships `attack_type` + `node_role` as plain-text label equivalents.
  (4) `window_start` alone scores 0.857 vs 0.817 (fixed phase timing). (5) ⚠️ the NaN mask is NOT a perfect
  label *within* a run (0.752 vs 0.817 majority — worse than guessing); it identifies RUN TYPE at
  dataset-assembly level. Fixes: F3 (dedicated recv/forward/drop counters) then F4 (un-gate), both need
  re-capture; P5 (modelling-column allowlist) is host-side.

## sep. 20, 2026 — full BLACKHOLE_ATTACKER_MAC run-killer entry (condensed in MEMORY.md after F2)

F2 (runtime attacker MAC via NVS) removes the 're-flash every victim' half of this hazard. The SYMPTOM and the detection shortcut are unchanged and stay live in MEMORY.md; the full incident history is here.

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

## sep. 20, 2026 — durable facts condensed in MEMORY.md after F2/F3/P5 (originals)

- Every attack/traffic parameter is a compile-time constant: drop rate 100% (`blackhole_victim.c:195`), `PROBE_INTERVAL_MS 1000`, `SAMPLING_INTERVAL_MS 100`, phases 60/300/180/120 s = 11 min (`mesh_config.h:129-138`), and `BLACKHOLE_ATTACKER_MAC` is a `#define` (`mesh_config.h:207`). `run.ps1` exposes topology/role but **no** attack-intensity flags → r1/r2/r3 differ only in RF noise, and attacker position can't change without re-flashing every victim board.
- ⚠️ **Known leak (panel P1):** the 5 role-gated features are non-NaN ONLY for their attacker role — `ForwardingRatio`/`IngressEgressDelta`/`ConsistencyScore` for the blackhole attacker, `TunnelIntensity`/`TunnelBytes` for wormhole endpoints. So "is this column NaN?" is a **perfect label**. Combined with PDR 0.08-vs-0.94, the dataset is trivially separable — the panel's "then ML is unnecessary" objection is correct as of aug. 2026.
- **aug. 29, 2026 — honest nodes cannot observe their own forwarding.** Victims send with `esp_mesh_send(NULL, ..., MESH_DATA_TODS)` (`victim_main.c:164`), so the mesh stack relays *below the app layer*; only the blackhole attacker sees transit packets, because victims address it explicitly (`victim_main.c:159`). The 11-column schema gives every node `probes_count`/`tx_count`/`retry_count`, but they mean "probes I originated" on a victim and "received/forwarded/dropped" on the attacker. ⇒ C7 (un-gate the relay features) is **not** a mask widening — there is no honest-relay data to un-gate. Three options in `Plan/THESIS3-MEMBER-HOWTO.md` §1 C7.

- sep. 20, 2026 — **F2: attacker MAC is a RUNTIME value** (`blackhole_target.c`, NVS `nis16`/`bh_mac`, compiled
  `BLACKHOLE_ATTACKER_MAC` as fallback). `export_logs.py --set/--get/--clear-attacker-mac`. **Takes effect on
  the NEXT boot — power-cycle the victim.** Makes "vary the attacker position" affordable: it used to cost a
  re-flash of every victim. Rejects all-zero/broadcast/multicast (those reproduce the silent failure).

- sep. 20, 2026 — **`docs/DATA-DICTIONARY.md` written**: per-role meaning of every column, **no column holds an
  802.11 MAC retry**, RSSI-is-per-link, root-is-layer-1. The cheap half of "rename honestly" — renaming costs
  a re-capture, writing down what they contain costs nothing. **Read before writing schema text in the paper.**

- sep. 20, 2026 — **P5 `analysis/leakage.py` is the ONE place deciding what a model may see**, with a written
  reason per exclusion (an undocumented exclusion list looks like cherry-picking). Out: FR/Consistency/IED
  (role-gated; Consistency ≡ |FR−1| to 1.1e-16, IED = recv×|1−FR| ⇒ 3 columns, ONE measurement), RetryRate,
  the 3 Tunnel features. This is **C7 Option 3** — no re-capture, no firmware risk. Writes `leakage_audit.csv`.

- sep. 20, 2026 — **F1 `PHASE_ID_UNSET`/`GT_LABEL_UNSET` = 255.** A node that has not heard a broadcast now
  RECORDS that instead of claiming baseline, so the sep. 18 failure (root 100–551 s late ⇒ 38% falsely
  baseline) cannot recur silently. ⚠️ **Host handling is NOT optional**: 255 is non-zero, so the phase-exit
  anchor would otherwise treat a node's FIRST window as its exit and shift every `t_anchor_s` — plausible and
  totally wrong. Handled in `preprocess.assign_segments()` + `validate_integrity.PHASE_TO_LABEL`. Verified by
  `analysis/test_segments.py` (20 checks): **v1 and v2 produce IDENTICAL segments.** No pytest here — run it
  directly: `python test_segments.py`.

- sep. 20, 2026 — `analyze.ps1 -Verify` now runs **three exit-code-checked gates** (integrity → topology →
  attack). It previously ran only `verify_attack.py` and ignored even that code. A NOT-CONFIRMED on a capture
  that failed an earlier gate is now **INCONCLUSIVE, not a negative result**.

- sep. 20, 2026 — **TELEMETRY IS SCHEMA v2 (14 cols) — EVERY BOARD MUST BE RE-FLASHED.** F3 appends
  `recv_count,forward_count,drop_count`; v1's 11 are unchanged and in place, and `validate_integrity.py`
  accepts BOTH widths (we cannot re-capture sep. 18). **Point of F3: `retry_count` means ONE thing on every
  role again** (failed sends). It used to carry the attacker's DROP count — why `RetryRate` went 0.0033→0.9991
  on that one board while victims went to 0.0000. Proof: on a synthetic v2 capture `RetryRate` now reads
  0.000→0.000 on the attacker while ForwardingRatio still gives BLACKHOLE CONFIRMED.
  Semantics on every role: recv = accepted FOR RELAY, forward = passed on, drop = accepted and not passed on.
  ⚠️ **The ROOT reports 0/0/0, NOT its arrival count** — recv>0 with forward=0 would score the root
  `ForwardingRatio = 0.0` every window, making the node that MEASURES the attack read as the one committing it.

- sep. 20, 2026 — **⚠️ `PDR` ALONE SCORES 0.9987 vs a 0.7031 majority** (`analysis/leakage.py`, G402). So
  **excluding leaking features does NOT answer the panel's 2:40-4:50 objection.** PDR is not leakage — it is
  the real, independently-observed effect — but a **100% drop rate in a fixed 180 s window is separable by
  construction**, and no feature choice repairs that. Only attack-parameter variation does, which collides with
  R-B (§1.4.1 excludes selective forwarding; a partial drop rate IS selective forwarding). **Adviser decides.**
  `eda.py` prints this on every pass so it cannot be forgotten.

- sep. 20, 2026 — ⛔ **THE ONE REMAINING DECISION IS C7 OPTION 1** (`Plan/THESIS3-MEMBER-HOWTO.md` §1 C7).
  F3 killed the retry_count OVERLOAD but not the ROLE GATE: honest nodes send TODS, so recv=0 and
  ForwardingRatio stays attacker-only. Option 1 = every node relays to its parent explicitly; it also makes
  attacker POSITION topologically meaningful. **Its stated cost ("existing runs become non-comparable") is
  near zero RIGHT NOW** — one cell exists and needs re-capture anyway — **and rises with every run captured.**

- sep. 20, 2026 — **Five pre-fix diagnostics are in ARCHIVE.md** (M8-on-4-of-16-features; the two tools that
  already detect early-boot contamination, now WIRED as gates; the WINDOW_SECONDS 5-vs-1 bug; the leakage
  measurements; the evidence the attack always worked). Still load-bearing:
  (a) ⚠️ **re-run M6→M7 on ANY cell analysed before sep. 20** — WINDOW_SECONDS hit every table built since D-9.
  (b) **Quotable proof the blackhole worked:** root arrivals **6.07/s baseline → 0/s attack → 6.01/s cooldown**
      (99% recovery); attacker forwarded 2605/2600 baseline vs **1/1020** attack; ~182 contiguous missing seq
      per victim = `PHASE_ATTACK_S`.
  (c) **Table 3.4's predicted victim-retransmission increase is a pre-registered MISS — REPORT it, do NOT edit
      the table** (§3.3.1.2 explains why: link-layer ACKs still succeed). A declared miss is a finding; a table
      edited to match results is misconduct.
  (d) `combine_all.py:52-55` ships `attack_type` + `node_role` as plain-text label equivalents — excluded by
      `leakage.py` METADATA_COLUMNS, but still present in the CSV.

- **THESIS 3 DRIVER — `Paper/Improvements.pdf`** (CTTHES2 panel comments, received ~aug. 2026). 8 timestamped rows → 7 distinct problems: single-feature decidability, no attack parameter variation, redundant r1–r3, one environment only, no declared IoT scenario, no attack provenance/validation, uncharacterised benign baseline. Full analysis + response plan: `Plan/THESIS3-PANEL-PLAN.md`.

- **Attack-validation framing (panel P6):** blackhole/wormhole are defined by adversary BEHAVIOUR, not protocol — so LEACH/AODV/RPL datasets are valid comparison points and sources need NOT be ESP32-specific. Validate by *definitional conformance* (criteria from Karlof & Wagner / Hu-Perrig-Johnson vs. what we implement, failures declared), then match signature SHAPE not absolute values. Tables drafted in plan §5.1.

- Two conformance gaps to declare, not hide: (a) our blackhole is a **placed relay**, it does not *attract* traffic by false route advertisement — hence the paper's name "Forwarding Suppression (Blackhole)"; (b) our wormhole produces duplicate arrivals but whether parent selection re-forms around the fake link is unproven — hence "Topology Distortion (**Wormhole-Inspired**)". The paper's own functional naming (§4.2.1.2/4.2.1.3, Tables 4.6/4.7) already makes the narrower, defensible claim — lead with it.

- sep. 20, 2026 — **TESTBED SCENARIO IS EVIDENCE-BACKED; the sources are ALREADY in our bibliography.**
  **Khan et al. (2022), Sustainability 14(24):16630** is not just our platform cite — its ESP32+ESP-MESH
  air-quality nodes sit **"at a different location on a COLLEGE CAMPUS"**. The campus environmental-
  monitoring scenario IS the published use case of our own protocol. Verified sep. 20 vs the MDPI record.
  Cite these numbers: **reporting interval every 2 minutes per node**; **baseline PDR > 97%, loss < 1.8%** —
  and note our corrected baseline **0.998±0.025 lands inside their range** (a validation result).
  Zhukabayeva 2025 (Technologies 13(8):348) = routing attacks on a smart-BUILDING environmental WSN + the
  3-sigma method. ⚠️ its "4-storey office building / linear topology" detail in
  `memory/resources-papers-assessment.md` came from a teammate's full-text read, NOT confirmable from the
  abstract — **re-verify against the PDF before publishing it.** Karlof & Wagner (2003) = the
  "target deployment" cite the panel asked for (damage scales with traffic aggregated at the attacker's
  position ⇒ near-sink/intermediate/edge is justified). ⇒ **The gap is NOT literature — it is (a) a measured
  floor plan per topology and (b) a declared traffic profile.** That fully answers panel 9:10-12:00.

- sep. 20, 2026 — **"Realistic data" resolved (panel 9:10-12:00).** Every dependent variable is
  network-layer (forwarded?, arrived?, RSSI, retries, hops) and **none depends on the payload bytes** — a
  blackhole drops a frame carrying a real 28.4 °C exactly as it drops a synthetic one. So: network
  behaviour **MUST be real** (it is); sensor VALUES **may be synthetic**; timing / payload size / message
  mix must be **realistic and cited** (Khan's 120 s); placement, distances, RF context must be **real AND
  RECORDED** (real but undocumented today — the actual gap). Simulating loss/RSSI/retries is what WOULD
  break validity, and we don't. The paper needs ONE paragraph stating what was measured vs generated — a
  stated synthesis is a methodology note, an unstated one is a finding against us.
  ⚠️ Do NOT naively slow the probe to 120 s: PDR resolution is probes-per-window and it would become
  unmeasurable. Keep the 1 Hz probe as the declared **measurement instrument** (like a ping sweep) and
  layer 120 s application telemetry on top as a second message type.

- ⚠️⚠️ **RECURRING ROOT BOOT-LOOP — check the root's power BEFORE every capture** (first diagnosed
  sep. 18, 2026, mid `blackhole/linear/G402`). Symptom: boot count climbing every ~2s in the SD env
  report, `rst:0x3 (SW_RESET)`, UART output garbled mid-line (abrupt uncontrolled reset, NOT a clean
  `esp_restart()` call anywhere in app code), always right as WiFi/mesh radio powers up (`sta +
  softAP` dual-radio start — the single highest current-draw moment of boot). Diagnosis: power
  brownout, not firmware — the ROOT runs BOTH softAP+STA (a child only runs STA, draws less), and
  `root_node/sdkconfig`'s brownout detector sits at its most sensitive default
  (`CONFIG_ESP32_BROWNOUT_DET_LVL_SEL_0`, ~2.7V trip). RULED OUT as the cause: the same-session
  `MESH_STACK_MAX_LAYER_CHAIN=1000` change — `mesh_setup.c:139`'s `esp_mesh_set_max_layer(1000)` call
  succeeds every time (its own log line prints cleanly right after it, before the crash point). Fix:
  root directly into a laptop USB port, never a hub shared with other boards; known-good short cable.
  If a CHILD loops too under the same setup, it's the shared power source, not root's dual-radio
  draw specifically — re-diagnose before assuming this same cause.

- ⚠️ WORMHOLE's equivalent run-killer is DIFFERENT — it has **no MAC at all** (the tunnel is a
  physical wired UART1 link between the two endpoint boards; `mesh_config.h:243` says so outright,
  and wormhole victims send plain TODS since the P2P-to-a-MAC path is `BLACKHOLE_VICTIM_TARGET`
  only). Its silent failure is a dead/mis-wired cable: TunnelIntensity/TunnelBytes/TunnelLatency
  come out empty while both boards look healthy. ⚠️ Node B CANNOT detect this — `uart_write_bytes()`
  succeeds into an unterminated line, so B's "Tunnelled" counter climbs regardless; only Node A can
  prove a frame crossed. Guard added sep. 16 on Node A: if `s_tunnel_received == 0` at terminate it
  prints a TUNNEL CARRIED NOTHING banner (check B-TX→A-RX + COMMON GROUND; `uart_link_test` is the
  bring-up project).

- sep. 20, 2026 — ⚠️ **CORRECTION, and it matters: "only ONE cell has data" and "ZERO wormhole captures
  exist" were BOTH WRONG** (they were in STATUS.md and MEMORY.md and I repeated them). New
  `tools/inventory_cells.py` scans live **and archived** exports against the M4/M5 criteria and finds
  **18 runs, 8 COMPLETE, 5 attack×topology cells with data — all 5 having at least one complete run —
  and 2 locations (G402 + home).** **Wormhole captures DO exist**: linear r2/r3, star r1/r2/r3,
  partial_mesh r1. So Table 3.5 is not unvalidated, it is un-**analysed**, and the 6 wormhole runs are
  the cheapest route to M7's "no feature uniformly NaN" — no new capture needed.
  **Root cause of the error: `archive.ps1` MOVES captures out of `tools/exports/`, and everyone
  (including every tool) was only ever looking at `tools/exports/`.** Archived runs are real data.
  ⚠️ Team judgement call, NOT mine: those 6 wormhole runs come from the sep. 16 pre-restart snapshot
  (schema v1, pre-F1/F3). Mechanically complete; whether pre-restart data counts toward M4 is yours to
  decide. Re-run the inventory any time with `python tools/inventory_cells.py`.

- sep. 20, 2026 — **P5 `analysis/leakage.py` is the ONE place deciding what a model may see**, with a
  written reason per exclusion. Out: FR/Consistency/IED (role-gated; 3 columns, ONE measurement),
  RetryRate, the 3 Tunnel features. **C7 Option 3.** Writes `leakage_audit.csv` every pass.

- sep. 20, 2026 — **F2: attacker MAC is a RUNTIME value** (NVS, compiled constant as fallback);
  `export_logs.py --set/--get/--clear-attacker-mac`. **Takes effect on the NEXT boot — power-cycle the
  victim.** Full rationale in `components/mesh_common/include/blackhole_target.h`.

- **aug. 29, 2026 — honest nodes cannot observe their own forwarding.** Victims send `esp_mesh_send(NULL, ..., MESH_DATA_TODS)`, so the mesh stack relays *below the app layer* and only the blackhole attacker sees transit packets (victims address it explicitly). ⇒ un-gating the relay features is **not** a mask widening — there is no honest-relay data to un-gate, and F3's dedicated counters do not create any. That is what C7 Option 1 exists to change. Per-role column meanings: `docs/DATA-DICTIONARY.md`. Full text in ARCHIVE.md.

- ⚠️ **Known leak (panel P1), now ENFORCED in code:** the role-gated features are non-NaN only for their attacker role, so "is this column NaN?" is a perfect label. `analysis/leakage.py` excludes them from model inputs and documents why per column. ⚠️ **But see the PDR 0.9987 entry above — exclusion is not sufficient.** Full pre-fix text in ARCHIVE.md.

- ⚠️⚠️ **RECURRING RUN-KILLER — verify the attacker MAC before EVERY blackhole run.** Blackhole victims send
  `MESH_DATA_P2P` to one exact MAC (`victim_main.c`), so if it names a board not in the mesh every probe is
  addressed to nobody. **The failure is SILENT**: boards look healthy and `probes_count` climbs normally, but
  the root logs ZERO arrivals in ALL phases, `arrivals.csv` is header-only, and BOTH primary features (PDR and
  ForwardingRatio) come out 100% NaN. Cost a full run on sep. 15 AND again on sep. 16. Symptom→cause shortcut:
  **all-NaN PDR + empty arrivals + root `probes_count` stuck at 0.**
  **Since F2 (sep. 20) the check and the fix are cheap:** `export_logs.py --port COMxx --get-attacker-mac` on
  each victim, and `--set-attacker-mac <mac>` + power-cycle to correct it — NO re-flash. Two older guards
  still stand: the attacker compares its own STA MAC to the effective target at boot and prints an abort
  banner, and `features.py`'s `load_arrivals` warns loudly when arrivals files exist but are all header-only.
  ⚠️ The compiled `BLACKHOLE_ATTACKER_MAC` is still the FALLBACK, and `Confirm-BlackholeAttackerMac`
  (menu.ps1:201) still only runs at BUILD/FLASH time — so a victim with no NVS override and a stale compiled
  value fails exactly as before. Full incident history in ARCHIVE.md.

- sep. 20, 2026 — **TESTBED SCENARIO IS EVIDENCE-BACKED; sources ALREADY in our bibliography.**
  **Khan et al. (2022), Sustainability 14(24):16630** — its ESP32+ESP-MESH air-quality nodes sit **"at a
  different location on a COLLEGE CAMPUS"**, i.e. the campus environmental-monitoring scenario IS the
  published use case of our own protocol. Cite: **120 s reporting interval**; **baseline PDR >97%, loss
  <1.8%** — our corrected **0.998±0.025 lands inside their range** (a validation result). Karlof & Wagner
  (2003) = the "target deployment" cite. ⇒ **The gap is NOT literature — it is (a) a measured floor plan
  per topology and (b) a declared traffic profile.** ⚠️ Zhukabayeva's "4-storey office building" detail is
  from a teammate's full-text read, NOT the abstract — re-verify vs the PDF before publishing it.

- sep. 20, 2026 — **"Realistic data" resolved (panel 9:10-12:00).** Every dependent variable is
  network-layer (forwarded? arrived? RSSI, retries, hops) and **none depends on payload bytes** — a
  blackhole drops a frame carrying 28.4 °C exactly as it drops a synthetic one. So: network behaviour
  **MUST be real** (it is); sensor VALUES **may be synthetic**; timing/size/mix must be **cited**;
  placement and RF context must be **real AND RECORDED** (real but undocumented today — the actual gap).
  The paper needs ONE paragraph stating measured vs generated. ⚠️ Do NOT slow the probe to 120 s — PDR
  resolution is probes-per-window. Keep 1 Hz as the declared measurement instrument.

- sep. 20, 2026 — **Five pre-fix diagnostics in ARCHIVE.md.** Still load-bearing:
  (a) ⚠️ **re-run M6→M7 on ANY cell analysed before sep. 20** (the WINDOW_SECONDS bug hit every table since D-9).
  (b) **Quotable proof the blackhole worked:** root arrivals **6.07/s baseline → 0/s attack → 6.01/s cooldown**;
      attacker forwarded 2605/2600 baseline vs **1/1020** attack; ~182 contiguous missing seq per victim.
  (c) **Table 3.4's predicted victim-retransmission increase is a pre-registered MISS — REPORT it, do NOT edit
      the table** (§3.3.1.2 explains why). A declared miss is a finding; an edited table is misconduct.
  (d) `combine_all.py:52-55` ships `attack_type`+`node_role` as label equivalents (excluded by `leakage.py`).

- sep. 20, 2026 — **TELEMETRY IS SCHEMA v2 (14 cols) — EVERY BOARD MUST BE RE-FLASHED.** F3 appends
  `recv_count,forward_count,drop_count`; v1's 11 unchanged and in place; `validate_integrity.py` accepts
  BOTH. **Point: `retry_count` means ONE thing on every role again** — it used to carry the attacker's DROP
  count (why `RetryRate` went 0.0033→0.9991 on that board alone). recv = accepted FOR RELAY, forward =
  passed on, drop = accepted and not passed on. ⚠️ **The ROOT reports 0/0/0, NOT its arrival count** —
  recv>0 with forward=0 would score the root ForwardingRatio 0.0, making the node that MEASURES the attack
  read as the one committing it. Full rationale: `csv_logger.h` F3 block + `root_main.c`.

- sep. 21, 2026 — **`leakage.py` is DATASET-AWARE, not hardcoded.** `relay_features_are_gated(df)`
  counts how many `node_role`s carry each relay column: pre-C7 (1 role) excludes them, post-C7 (>=2)
  re-admits them. Both firmware generations coexist for months. Before/after score = deliverable E2.

- sep. 21, 2026 — **`docs/REVIEWER-QUESTIONS.md`** answers every adviser/panel side comment against
  verified source. Key: the MAC is `esp_read_mac(ESP_MAC_WIFI_STA)`, an **eFuse read** — the CP210x
  USB bridge has no MAC and cannot be the source; RSSI is read from the driver, not computed by us;
  PDR/LatencyHopRatio going NaN during the attack are **results, not gaps**.

- sep. 21, 2026 — **C7 OPTION 1 SHIPPED (D-12): every node relays hop-by-hop at the app layer.**
  Shared `probe_relay.{h,c}`; victims send to their PARENT (`MESH_DATA_P2P`); **the attacker runs the
  SAME relay and differs by ONE boolean callback**. Both wormhole ends relay; UART tunnel untouched.
  ⚠️ **This IMPLEMENTS the paper — the old TODS behaviour was the deviation**: §3.1.3.2 mandates
  recv/send with MESH_DATA_P2P, and Table 4.2 already specified recv/forward/drop counters.
  ⛔ **CONFLICTS WITH THE SIGNED MILESTONE FORM** ("victims address probes directly to the attacker's
  MAC"). Every milestone CRITERION still passes; only the mechanism changed, and the form's own
  "behavioral equivalent of" concedes the old model was a substitute. **Adviser sign-off required.**
  Fixes panel 2:40-4:50 at the root and makes attacker POSITION a real variable (12:45-16:00).
  ⚠️ **Pre-C7 and post-C7 captures are NOT comparable.** Full rationale: D-12.

- Spawning a build/flash window as plain `powershell.exe` — `idf.py`/`esptool.py` are POWERSHELL
  FUNCTIONS from `C:\Espressif\Initialize-Idf.ps1`, and functions don't survive into a child process
  (only env vars do). Dot-sourcing it with no `-IdfId` also fails silently: `idf-env config get
  --property python --idf-path <path>` returns the STRING "null", not an error. Fix in use:
  `Get-EspIdfActivation` reads the real Start Menu shortcut's `-IdfId` at runtime (never hardcode it —
  a reinstall changes it).

- sep. 21, 2026 — **`docs/EXPECTED-RESULTS.md` §0 explains HOW TO READ every number** (added after the
  team said the numbers were unreadable). Covers: ratios are percentages with the % removed
  (0.001 = 0.1%, and **NaN ≠ 0** — NaN means "nothing to measure here", 0.001 means "measured, almost
  nothing got through"); RSSI dBm is negative and **closer to zero = stronger** (0 is the no-parent
  placeholder, not a perfect signal); `*_delta` = how much a counter rose in THAT window, not a
  running total; `mu ± sd` = average ± normal wobble; **`z` = how many wobbles away from normal**
  (worked arithmetic: 1.001 ÷ 0.025 ≈ 40), threshold 3 from Zhukabayeva 2025 so the bar isn't
  self-serving; `(n)` = sample count. Also two by-eye sanity checks: `forwarded ÷ received` must
  equal ForwardingRatio, and `received` ≈ victims-upstream × probe rate.

- sep. 21, 2026 — **`layer` → `hop` (D-11).** New `hop` column (root = 0); `LayerChangeCount` →
  **`HopChangeCount`**; raw `layer` kept. ⚠️ **Off-by-one is the point** — Espressif numbers the root
  layer 1, so a plain rename would read "the root is 1 hop from itself"; `layer == -1` → NaN, never
  -2. Feature VALUES unchanged (offset-invariant); verified zero shared values moved over 7704 rows.
  Dated `2026-07-*` issue logs keep the old name deliberately: historical record.

- sep. 21, 2026 — **A stale `BLACKHOLE_ATTACKER_MAC` is NO LONGER a run-killer** — bookkeeping only.
  The old "RUN WILL BE EMPTY / ZERO arrivals" alarms are now FALSE and would cause good captures to
  be aborted; downgraded in `menu.ps1` + the attacker boot banner. Dead `BLACKHOLE_VICTIM_TARGET`
  removed. ⚠️ `BLACKHOLE_ROLE` is still REQUIRED — it selects which source file builds.

- sep. 21, 2026 — **Smart trimmer**: `trim_run.py` scores boot sessions on PHASE PROGRESSION, not
  length. Old rule kept a long idle/export session over a short or aborted real run. Proven: 400-row
  real run (+102.6) beat a 3000-row idle session (-146.5). Warns when two sessions look real, or none.

- ⚠️ **WORMHOLE's run-killer is DIFFERENT — it has NO MAC at all**: the tunnel is a physical wired UART1
  link between the two endpoint boards, so its silent failure is a dead/mis-wired cable (Tunnel* features
  empty, both boards look healthy). ⚠️ **Node B CANNOT detect this** — `uart_write_bytes()` succeeds into
  an unterminated line, so B's counter climbs regardless; only Node A can prove a frame crossed. Guard on
  Node A: `s_tunnel_received == 0` at terminate prints a TUNNEL CARRIED NOTHING banner (check B-TX→A-RX +
  COMMON GROUND; `uart_link_test` is the bring-up project).

- Long `idf.py -B <dir>` build-directory names in this repo (e.g. `build_cc_verify`) — the workstation path is
  already deep, so object paths cross Windows' `MAX_PATH`/`CMAKE_OBJECT_PATH_MAX` and ninja fails inside the
  **bootloader** subproject, long after the app's own files compiled fine; the failure looks unrelated.
  ⚠️ Worse on a machine with a longer username (measured 265 chars on Angelo Calpoporo's, sep. 17).
  ✅ **Mitigation CONFIRMED WORKING sep. 20** on that same machine: short `-B` names build all 6 variants
  clean (`bh1`,`bv1`,`wa1`,`wb1`,`rb1`,`rn1`). Unapplied alternative: `LongPathsEnabled=1` (needs admin).

## Rolled from MEMORY.md — sep. 22, 2026 (cap pressure; both entries are CLOSED)

- sep. 20, 2026 — **SCOPE SETTLED by the user: "TinyTrust / Collaborative TinyML IDS" is DROPPED** — it came
  from an externally-suggested (ChatGPT) prompt template, not the adviser or panel. The thesis is and stays
  *Cross-Layer Dataset Design and Exploratory Analysis of ESP32-Based ESP-WIFI-MESH Network*, which does NOT
  implement an IDS and excludes Sybil (§1.4.1). Risk R1 CLOSED. Two attacks only: blackhole + wormhole.
  ⚠️ The user's prompt template still says "our thesis is focused on intrusion detection" — template
  residue, do not act on it.
- sep. 20, 2026 — Scope evidence: "TinyTrust"/"TinyML"/"intrusion detection system" appear ZERO times in the
  approved proposal or this repo (grep); the abstract says "Rather than implementing a real-time IDS".
- sep. 20, 2026 — **Attacker placement is not topological.** Valid chain of 8, but the attacker sits at
  **layer 7 of 8** — ONE victim downstream, five UPSTREAM, so those five send probes DOWN the chain and it
  relays them back UP. The attack works; the traffic pattern is not one a real forwarding adversary produces.
  The panel's "deployment appears random", made concrete. F2 (done) makes moving it cheap; **C7 Option 1 is
  what would make position actually mean something.** (C7 Option 1 shipped sep. 21 as D-12.)
- sep. 20, 2026 — **Five pre-fix diagnostics** (full text was already here); the three load-bearing parts
  were carried forward into MEMORY.md as a compact pointer on sep. 22.

## Rolled from MEMORY.md — sep. 22, 2026 (cap pressure; compact pointers left behind)

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
- sep. 20, 2026 — **F1 `PHASE_ID_UNSET`/`GT_LABEL_UNSET` = 255.** A node that has not heard a broadcast
  RECORDS that instead of claiming baseline. ⚠️ **Host handling is NOT optional**: 255 is non-zero, so the
  phase-exit anchor would otherwise treat a node's FIRST window as its exit. Handled in
  `preprocess.assign_segments()` + `validate_integrity.PHASE_TO_LABEL`; `analysis/test_segments.py` proves
  **v1 and v2 give IDENTICAL segments**. Run `python test_segments.py` (no pytest here). Why: mesh_config.h.
- sep. 20, 2026 — `member_boards.json` had **child_8/child_10 transposed** (child_8 listed B4:90, actually
  70:68). Corrected against the boards' own telemetry — the export filename carries the nickname the board
  reports for itself and column 2 its MAC, so the boards are ground truth. Every other entry verified.
- sep. 20, 2026 — **P5 `analysis/leakage.py`** = C7 Option 3 (exclude role-gated features from model
  inputs, with a written reason per column). **Superseded in part by C7 Option 1** — see the sep. 21
  dataset-aware entry above; full original text in ARCHIVE.md.
- sep. 20, 2026 — Audit report Rev 3: https://claude.ai/artifact/RGB3RTXvfK7yzK9erEFNzE · the sep. 18 tooling batch + the sep. 16 root-as-blackhole-attacker proposal are in ARCHIVE.md; live threads carried in STATUS.md.

## Rolled from MEMORY.md — sep. 22, 2026 (drive move pushed the cap)

- sep. 20, 2026 — **Pre-fix diagnostics (full text in ARCHIVE.md).** Load-bearing: (a) ⚠️ **re-run M6→M7 on
  ANY cell analysed before sep. 20** (WINDOW_SECONDS bug); (b) **quotable blackhole proof** — root arrivals
  **6.07/s → 0/s → 6.01/s**, attacker forwarded 2605/2600 baseline vs **1/1020** attack; (c) **Table 3.4's
  predicted victim-retransmission increase is a pre-registered MISS — REPORT it, do NOT edit the table.**
- sep. 20, 2026 — **Testbed scenario is EVIDENCE-BACKED, sources already in our bibliography** (Khan
  et al. 2022, Sustainability 14(24):16630 — campus ESP32+ESP-MESH, baseline PDR >97%; our 0.998±0.025
  lands inside it). ⇒ **The gap is a measured floor plan + declared traffic profile, NOT literature.**
  Full cites in ARCHIVE.md.
- sep. 20, 2026 — **"Realistic data" resolved (panel 9:10-12:00):** network behaviour MUST be real (it is),
  sensor VALUES may be synthetic, placement/RF context must be real AND RECORDED. ⚠️ Do NOT slow the probe
  to 120 s — keep 1 Hz as the declared measurement instrument. Full entry in ARCHIVE.md.
- sep. 20, 2026 — **F1 `PHASE_ID_UNSET`/`GT_LABEL_UNSET` = 255** — a node that heard no broadcast RECORDS
  that instead of claiming baseline. ⚠️ **Host handling is NOT optional** (255 is non-zero). Handled in
  `preprocess.assign_segments()` + `validate_integrity.PHASE_TO_LABEL`; `analysis/test_segments.py` proves
  v1/v2 give IDENTICAL segments (`python test_segments.py`, no pytest here). Full entry in ARCHIVE.md.
- sep. 21, 2026 — **`docs/EXPECTED-RESULTS.md` §0 explains HOW TO READ every number** (the team could
  not read them). Key points: **NaN ≠ 0** (NaN = nothing to measure; 0.001 = measured, almost nothing
  got through); RSSI dBm negative, **closer to zero = stronger**, and `0` is the no-parent
  placeholder; `*_delta` = rise in THAT window; **`z` = how many normal wobbles from normal**
  (1.001 ÷ 0.025 ≈ 40), threshold 3 from Zhukabayeva 2025 so the bar isn't self-serving.
- sep. 22, 2026 — ⚠️ **Over USB, row counts come from `runs.csv`, not from counting the file.** Picker shows
  **`rows unknown (<size>)`**; **`?` NEVER renders as `0`** — 0 rows is a REAL state (what D-13 looked like).
  Mismatch on import prints `NOTE: got N rows, manifest said M` = a capture cut short.
- sep. 21, 2026 — **C7 OPTION 1 SHIPPED (D-12): every node relays hop-by-hop at the app layer.**
  Shared `probe_relay.{h,c}`; victims send to their PARENT (`MESH_DATA_P2P`); **the attacker runs the
  SAME relay and differs by ONE boolean callback**. ⚠️ **This IMPLEMENTS the paper** (§3.1.3.2
  mandates it; Table 4.2 already specified the counters) — **the old TODS behaviour was the
  deviation**. ⛔ **CONFLICTS WITH THE SIGNED MILESTONE FORM; adviser sign-off required** — every
  milestone CRITERION still passes, only the mechanism changed. Fixes panel 2:40-4:50 at the root.
  ⚠️ **Pre-C7 and post-C7 captures are NOT comparable.** Full rationale + the conflict: D-12.

## Rolled from MEMORY.md — sep. 22, 2026 (trim-fix entry pushed the cap)


## Rolled from MEMORY.md — sep. 22, 2026 (resolved sep. 20 reference entries)

- sep. 20, 2026 — `analyze.ps1 -Verify` = **three exit-code-checked gates** (integrity → topology → attack);
  NOT-CONFIRMED after a failed gate reads **INCONCLUSIVE, not a negative result**.
- sep. 20, 2026 — `member_boards.json` child_8/child_10 were **transposed**; corrected against the boards'
  own telemetry (**the boards are ground truth**). Every other entry verified. Details in ARCHIVE.md.
- sep. 20, 2026 — **`docs/DATA-DICTIONARY.md`**: per-role meaning of every column; **no column holds an
  802.11 MAC retry**. **Read it before writing schema text.**
- sep. 20, 2026 — **Testbed scenario EVIDENCE-BACKED** (Khan 2022, Sustainability 14(24):16630 — campus
  ESP-MESH, PDR >97%; ours 0.998±0.025 sits inside). ⇒ gap is a floor plan + traffic profile, NOT literature.
- sep. 20, 2026 — **"Realistic data" resolved:** network behaviour real, sensor VALUES may be synthetic,
  placement/RF RECORDED. ⚠️ Do NOT slow the probe to 120 s — 1 Hz is the declared instrument.
- sep. 20, 2026 — **P1/P2/P3 analysis fixes applied + verified (ARCHIVE.md).** Sigma still 3;
  `BASELINE_FLOOR` RAISED 0.50→0.90. Audit report Rev 3 link is in ARCHIVE.md.
- sep. 20, 2026 — **F1 `PHASE_ID_UNSET`/`GT_LABEL_UNSET` = 255**; a node hearing no broadcast RECORDS that,
  never "baseline". ⚠️ Host handling NOT optional. `analysis/test_segments.py` proves v1/v2 identical.
- sep. 20, 2026 — **F2: attacker MAC is a RUNTIME value** (NVS; `export_logs.py --set/--get/--clear-
  attacker-mac`, next boot). ⚠️ Since C7 Option 1 this is **bookkeeping only** — victims no longer target it.
- sep. 20, 2026 — **P5 `analysis/leakage.py`** = C7 Option 3 (exclude role-gated features, reason per
  column). **Superseded in part by C7 Option 1** — see the sep. 21 dataset-aware entry above.

## Rolled from STATUS.md — sep. 22, 2026 (cap pressure)

- sep. 21, 2026 — **C7 Option 1 (D-12)** + `probe_relay.{h,c}`; `leakage.py` dataset-aware.
  (full D-12 detail already in ARCHIVE.md and docs/issue_logs/thesis-deviate.md.)

## Rolled from MEMORY.md - sep. 22, 2026 (export-fix batch needed room)

- sep. 20, 2026 — **Resolved sep. 20 reference entries moved to ARCHIVE.md**: `analyze.ps1 -Verify`'s three
  exit-code gates (a NOT-CONFIRMED after a failed gate = **INCONCLUSIVE, not negative**), the
  `member_boards.json` child_8/child_10 transposition (**boards are ground truth**),
  `docs/DATA-DICTIONARY.md` (**read before writing schema text**), the evidence-backed testbed
  scenario, the "realistic data" resolution (⚠️ keep the probe at **1 Hz**), and P1/P2/P3
  (sigma still 3; `BASELINE_FLOOR` raised 0.50→0.90).
- sep. 22, 2026 — ⚠️ **Over USB, row counts come from `runs.csv`, not by counting the file.** Picker shows
  **`rows unknown (<size>)`**; **`?` NEVER renders as `0`**. Import mismatch prints `NOTE: got N rows, manifest said M`.
- sep. 22, 2026 — **`--delete-source` REFUSED with `--port`**: `DELETE_SD_PATH` removes FOLDERS, not files; the picker's `d` is hidden in board mode.

## Rolled out of MEMORY.md — sep. 22, 2026 (line cap)
Pointer entries; the full text they point to is already elsewhere in this file. Kept for their
still-load-bearing annotations.

- sep. 20, 2026 — **F1 `=255` / F2 runtime attacker-MAC / P5 `leakage.py`** — full entries in ARCHIVE.md.
  Still load-bearing: F1's 255 sentinel means host handling is **NOT optional**; F2 is **bookkeeping only**
  since C7 Option 1; P5 is partly superseded by C7 Option 1.
- sep. 20, 2026 — **Settled sep. 20 reference entries are in ARCHIVE.md** (analyze.ps1 -Verify gates =
  INCONCLUSIVE not negative; member_boards transposition; DATA-DICTIONARY; testbed evidence; keep probe
  at **1 Hz**; P1/P2/P3 sigma 3, BASELINE_FLOOR 0.90).

- sep. 20, 2026 — **SCOPE SETTLED, risk R1 CLOSED: no IDS, no TinyML, no Sybil** — two attacks only
  (blackhole + wormhole). ⚠️ The user's prompt template still says "our thesis is focused on intrusion
  detection" — template residue, do NOT act on it. Full entry + grep evidence in ARCHIVE.md.
- sep. 20, 2026 — **Pre-fix diagnostics (ARCHIVE.md).** (a) ⚠️ re-run M6→M7 on ANY cell analysed before
  sep. 20; (b) blackhole proof: root arrivals **6.07/s → 0/s → 6.01/s**, attacker **1/1020** vs 2605/2600;
  (c) Table 3.4's victim-retransmission rise is a pre-registered **MISS — REPORT it, don't edit the table.**
- sep. 20, 2026 — ⚠️ **Attacker PLACEMENT still matters post-C7:** an attacker at the far end of a chain
  intercepts nothing, because it only drops what transits it. Full entry in ARCHIVE.md; the operational
  warning lives in `run_wizard.ps1` and `docs/EXPECTED-RESULTS.md`.

## Rolled out of MEMORY.md — sep. 22, 2026 (line cap, 2nd pass)
Both still live as one-line warnings in STATUS.md.

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
- sep. 20, 2026 - **CORRECTION (ARCHIVE.md): "only ONE cell has data"/"zero wormhole captures" were WRONG** - `inventory_cells.py` is the source of truth; `archive.ps1` MOVES data out of exports/.
- sep. 21, 2026 - **`docs/REVIEWER-QUESTIONS.md`** answers every adviser/panel side comment against verified code.
- sep. 21, 2026 - **`verify_topology.py --structure`** rebuilds the parent/child table from CSVs (wizard VERIFY menu).
- sep. 22, 2026 — **All 4 boards reflashed** with `ab74ec4` (COM3 ROOT/bcr, COM10+COM9 victim/bcbv, COM11
  attacker/bcba; MACs re-read via `esptool read_mac`, matched to `presets/Cal/TRY.json`, hashes verified).
  ⚠️ COM10 boot 9 + COM9 boot 1 were never exported — the reboot moved them to `<leaf>/_archive/`, which
  `import_sdcard.py` deliberately skips. Recover by hand from `_archive/`. User accepted the loss.
- sep. 21, 2026 - **`layer` -> `hop` (D-11).** New `hop` column (root = 0); `LayerChangeCount` -> `HopChangeCount`; values unchanged.
- sep. 21, 2026 — **A stale `BLACKHOLE_ATTACKER_MAC` is NO LONGER a run-killer** — bookkeeping only.

## Rolled out of MEMORY.md — sep. 22, 2026 (room for the 0xB8 BSOD entry)
- sep. 21, 2026 — **`docs/EXPECTED-RESULTS.md` §0 = how to READ every number.** **NaN ≠ 0** (NaN = nothing
  to measure); RSSI closer to zero = stronger, `0` = no-parent placeholder; **`z` = normal wobbles from
  normal**, threshold 3 from Zhukabayeva 2025. Full text in ARCHIVE.md.
- sep. 21, 2026 - **`leakage.py` is DATASET-AWARE**: it asks how many roles carry each relay column, never hardcodes.
  The old "RUN WILL BE EMPTY / ZERO arrivals" alarms are FALSE now and would abort good captures;
  downgraded in `run_wizard.ps1` (the launcher in use), BOTH copies in `menu.ps1`, and the attacker
  boot banner. ⚠️ `BLACKHOLE_ROLE` is still REQUIRED — it selects which source file builds.
- sep. 21, 2026 — **Smart trimmer**: `trim_run.py` scores boot sessions on PHASE PROGRESSION, not
  length (the old rule kept a long idle session over a short/aborted real run). Proven: 400-row real
  run (+102.6) beat a 3000-row idle session (-146.5). Warns if two look real, or none does.

## Rolled out of MEMORY.md — sep. 22, 2026 (room for the hop-rename / leaf-guard entry)
- sep. 22, 2026 — **Export has TWO sources, one pipeline.** `run_wizard.ps1` asks *board over USB* vs
  *pulled SD card*, then runs the SAME picker → dry-run → confirm → import (`Import-OneSdCard -Card|-Port`).
  New firmware cmds **`LIST_SD`** + **`EXPORT_SD_PATH=<rel>`**; `LIST_FILES` adds `|<bytes>|<rows>`. Host:
  `import_sdcard.py --port COMx`. Both routes verified byte-identical.
- sep. 22, 2026 — ⚠️ **Over USB, row counts come from `runs.csv`, not by counting the file.** `?` NEVER renders as `0`.

## Rolled out of MEMORY.md — sep. 22, 2026 (hop-rename entry, 2nd pass)
- sep. 21, 2026 — **C7 OPTION 1 SHIPPED (D-12): every node relays hop-by-hop at the app layer.** Shared
  `probe_relay.{h,c}`; victims send to their PARENT; **the attacker runs the SAME relay, differing by ONE
  boolean callback**. ⚠️ This IMPLEMENTS the paper (§3.1.3.2) — the old TODS behaviour was the deviation.
  ⚠️ **Pre-C7 and post-C7 captures are NOT comparable.** Full rationale: D-12 in thesis-deviate.md.
- sep. 21, 2026 — ⚠️ **TRAP THAT WOULD HAVE SILENTLY KILLED EVERY WORMHOLE RUN.** The relay first forwarded
  only `PROBE_MAGIC`; Node A's duplicate carries `PROBE_MAGIC_WORMHOLE`, so every intermediate relay would
  have dropped it and wormhole runs would have looked clean. Both magics now
  relay. **Any future change to the relay's accept-filter must re-check this.**

## Rolled out of MEMORY.md — sep. 22, 2026 (room for the import stderr-trap entry)
- sep. 22, 2026 — ⚠⚠ **STILL RUNNING was STICKY — the live-flag bug, now fixed.** `sd_is_live_mirror()`
  compared PATH STRINGS only, but `csv_logger_close()` nulls the mirror FILE*s at TERMINATE and keeps the
  path strings (ARCHIVE_SD needs them). So after ANY completed run every file on that card reported
  STILL RUNNING for the rest of the boot and the importer refused it — seen live on COM10+COM9. Now gated
  on an OPEN handle. ⚠️ REFLASH needed; until then read the card in a reader, or power-cycle the board.
- sep. 22, 2026 — **Children now stop cleanly at TERMINATE.** `heartbeat_task` was the only thing still
  transmitting after a run (`while(true)`, timer-driven); it now exits for non-root nodes. probe_gen and
  telemetry already self-exited; relay_task parks on an empty queue. Root keeps beating (owns the member
  table). App-level only — the child stays joined and USB-reachable. All 6 variants build clean.
- sep. 22, 2026 — **Location pre-flight now covers the MANUAL run path too**, via shared

## Rolled out of MEMORY.md — sep. 22, 2026 (room for the r1 home-run data check)
- sep. 22, 2026 — ⛔⛔ **NEVER FLASH `build_all_variants.ps1`'s OUTPUT. It is a COMPILE CHECK ONLY.**
  It hardcodes `-DMESH_TOPOLOGY=0` on every variant (M1 criterion 1 = 'do all variants compile'), and
  `NIS_TOPO_STAR = 0` with `s_topo_dirs[0] = "star"` — so those binaries run a STAR mesh (depth capped at
  2) and log into `<attack>/star/<location>` whatever the experiment is. Flashed to all 4 boards sep. 22,
  which then wrote `blackhole/star/home` for a LINEAR run — MAC/role were verified, topology was not.
  Real flashing goes via `run.ps1 -Flash -Topology <t>` (star=0, tree=1, **linear=2**, partial=3), driven
  by `run_wizard.ps1` from the preset. bcr/bcc/bcba/bcbv/bcwa/bcwb prove compilation, they do not deploy.
- sep. 22, 2026 — **Per-file CSV delete, BOTH sources.** New firmware `DELETE_SD_FILE=<rel>` deletes ONE
  capture (`DELETE_SD_PATH` only ever took whole folders, which is why `--delete-source` used to be
  refused over `--port`). Guards: `sd_rel_capture_file_valid()` accepts only `*_telem.csv`/`*_arrivals.csv`
  — so **runs.csv/location.txt can never be deleted this way** — and the board refuses a file it has OPEN.
  Host: `export_logs.py --delete-sd-file`, `import_sdcard.py --delete-source` (now allowed with `--port`),
  wizard picker's `d` works over USB too. Auto-delete-after-import stays OFF for USB (opt-in only).
  ⚠️ **Any `& python ... 2>&1` here MUST set `$ErrorActionPreference='Continue'` first**: under the
  script-wide `Stop`, PS 5.1 makes a NATIVE command's first stderr line TERMINATING. Shipped without it,
  so one refused file killed the whole selection as "Could not run import_sdcard.py / python on PATH?".

## Rolled out of MEMORY.md — sep. 22, 2026 (room for the jitter scenario)
- sep. 22, 2026 — ⚠️ **`ERROR:LOCATION_WRITE_FAILED` = the card MOUNTED and the write still failed** (vs
  `LOCATION_NO_CARD` = mount failed). Hit live on COM10/COM11, which also had NO location.txt — consistent
  with a **write-protect lock switch on the microSD adapter** (mounts + reads fine, every write fails).
  Else: full card, or FAT damage → read-only mount. Triage: lock switch →
  power-cycle → write-test in a reader (a good card, E:, wrote fine with 3.63 GB free). **UNRESOLVED.**
- sep. 22, 2026 — **Over USB an ARRIVALS file reports rows UNKNOWN, not the telem count.** `runs.csv`'s
  `rows` is that boot's TELEM count; a root's arrivals.csv shares the boot but counts something else.
  `_BoardCard.rows()` returned it for both kinds → wrong count in the picker AND `_already_imported()`
  could never match, so re-import over `--port` COPIED A DUPLICATE. Now None for non-telem → identity-only
  fallback catches it. `--card` unaffected; preprocess.py already archives same-key dupes, so not contamination.
- sep. 22, 2026 — ⚠️ **"ABORTED" WAS A LIE: it also meant "still running".** runs.csv only gets its
  `clean` row at TERMINATE, so a live run and a dead one are indistinguishable to the host — every
  card read mid-capture reported ABORTED + "rows unknown". Firmware now reports whether it still has
  each mirror OPEN (`sd_is_live_mirror()`, 3rd field of `SDFILE:<name>|<bytes>|<live>`); the picker
  says **STILL RUNNING** and the importer REFUSES it (not behind --include-aborted: importing a live
  file yields a truncated run that looks complete). Proof it was benign: boot 759 grew 179->434 KB
  between two reads.
- sep. 22, 2026 — ⚠️ **SET_LOCATION broke after an SD hot-swap — root cause + fix.**
  `mount_for_location_op()` returned early on `s_card != NULL`, so pulling a card from a RUNNING board
  left a stale handle and every later write failed until reboot (it "spread" because each swap broke
  one more board). Now: on write failure the mount is rebuilt and retried — but **only between runs**.
  Mid-capture it returns the new `ERROR:LOCATION_STALE_MOUNT` and says reboot, because unmounting
  under a live run kills the SD mirror (mount_for_location_op's own comment warns of this).

## Rolled out of MEMORY.md — sep. 22, 2026 (room for the warm-build false-pass)
- sep. 22, 2026 — ⚠️ **BOARD NOT YET REFLASHED with today's hop-rename/leaf-guard/positional-header
  firmware.** The r1 home-run above was captured on the OLD firmware, and is still VALID data — today's
  C changes are console-display and boot-warning ADDITIONS only (`mesh_setup.c`, `blackhole_victim.c`),
  they touch NO CSV column, NO phase timing, NO probe logic. Reflashing changes what the SERIAL CONSOLE
  shows and adds a boot-time safety warning; it does not invalidate or require re-capturing anything
  already exported.
- sep. 22, 2026 — **SD files no longer date to 1980.** get_fattime() feeds `time(NULL)` into each FAT
  entry; no RTC = 1970 -> clamped. `sd_status_seed_clock_from_build()` seeds it from BUILD stamp + uptime
  in `sd_status_run_boot_check()`. ⚠️ A dating AID, not a measurement; boot counter + runs.csv stay exact.

## Rolled out of MEMORY.md — sep. 22, 2026 (batch 4; build false-pass now FIXED via -Clean)
- sep. 22, 2026 — ⛔⛔ **`build_all_variants.ps1` CAN REPORT A FALSE "0 warnings" — M1 CRITERION 1 EVIDENCE
  IS NOT TRUSTWORTHY ON A WARM BUILD.** It never wipes `bcr/bcc/bcba/bcbv/bcwa/bcwb`, so ninja reuses cached
  objects and a file that did not recompile CANNOT re-emit its warnings. PROVEN sep. 22: same source, same
  script, twice — warm run said `ALL 6 VARIANTS BUILD CLEAN - 0 warnings`; after `touch
  child_node/main/wormhole_victim.c` the SAME tree reported WORMHOLE A=1, B=1. The script's own banner says
  "Do NOT hide these in the presentation", and a panel rebuilding from scratch sees what the warm run hid.
  **Before quoting a clean build as M1 evidence, delete the build dirs first.** The 2 latent warnings are
  `wormhole_victim.c:262 root_data set but not used` + `:481 mdata unused` — harmless pre-C7 leftovers
  (both tasks now send via `probe_relay_send_own()`; call sites traced, no behavioural gap), STILL UNFIXED.
  A third warning, `root_main.c jit_attack unused`, WAS mine and IS fixed (baseline root preprocesses out
  both consumers; silenced with `(void)`).
- sep. 22, 2026 — **Location pre-flight in the wizard.** "Yes - use it" now reads each board's
  location.txt, diffs it against the preset, and offers to fix it BEFORE flashing. The board picks its
  `<location>` folder from its OWN card, not the menu answer, so a mismatch splits one run across two
  site folders — hit for real 2026-09-22 (ran `-Location home`, cards said G402, `home/` was empty).
- sep. 22, 2026 — **Root arrivals.csv exports fine over USB**; runs.csv `rows` is TELEM-only, so the manifest check is too.
- sep. 22, 2026 — ⚠️ **AUTO-ANALYSIS WAS SKIPPING THE TRIM (fixed).** `run.ps1 -Analyze` — what
  `run_wizard.ps1` gives the ROOT (`New-RunParams`) — ran M6/M7 over the RAW export and never called
  `trim_run.py`, while `analyze.ps1` always trimmed. A raw folder can hold SEVERAL boot sessions and the
  right one is NOT the longest, so idle sessions were silently folded in; and BOTH paths write the same
  `analysis/<cell>/feature_table.csv`, making trimmed/untrimmed tables indistinguishable afterwards.
  Fixed: run.ps1 clears stale `trimmed/`, runs `trim_run.py --apply`, points BOTH M6+M7 at `$analysisSrc`;
  a trim failure falls back to raw and SAYS SO. ⚠️ **Re-run `.nalyze.ps1` on any cell auto-analysed
  before sep. 22.** Left alone (not a bug): the wizard's "Run analysis only" asks via
  `Select-AnalysisInput`, which already prefers `trimmed/`. **Auto-EXPORT was correct** (`-Analyze`
  implies `-Export`, run.ps1:240).

## Rolled out of MEMORY.md — sep. 22, 2026 (batch 5)
- sep. 22, 2026 — ⚠️ **THE WORKING COPY MOVED TO `A:\Angelo\Excelsior\THESIS\T`.**
  `C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment` is now a BACKUP only — do NOT edit it.
  Reason: C:'s depth pushes ESP-IDF build paths into Windows `MAX_PATH` (worst case **exactly 260**); on
  A: it is **199**. Same repo/branch/commit (THESIS3 @ 764ff06). A: was merged to hold everything: it
  already had `archive/2026-09-18_Incomplete-2` + `_incomplete-3` C: never had, and received C:'s 13 work
  files + `archive/20260913_pre-redesign` (513 files/293 CSVs) + `tools/feature_separability.py`
  (PANEL-REQUIREMENT tool: proves no single feature decides the dataset) + 4 PDFs. SHA256-verified.
  ⚠️ **NOT copied on purpose:** ~1.8 GB July build junk + superseded root `docs/`,`memory/`,`tools/`.
- sep. 22, 2026 — **`Select-Port` crashed "Key cannot be null"** on the new USB-export flow: called without
  `-Ports`, and piping `$null` through `Where-Object` yields ONE iteration with `$_ = $null`, so `$shown`
  held a single null and the loop hit `ContainsKey($null)`. Fixed at the call site AND hardened in
  `Select-Port` (`{ $_ -and ... }`).

## Rolled out of MEMORY.md — sep. 22, 2026 (batch 6; superseded by the archive-menu entry)
- sep. 22, 2026 — **G402 cell RESTORED from git** (`git checkout` of the 9 staged-deleted files, incl.
  BOTH root files). User then chose to ARCHIVE G402 + home as test data — correct order: `archive.ps1`
  MOVES into `archive/` where `inventory_cells.py` still counts them, vs a staged deletion which loses
  them silently. `archive.ps1` moves `tools/exports/` AND generated `analysis/` output together.
- sep. 22, 2026 — ⚠️ **ROOT CAUSE of "sometimes 0 rows off the SD card" (D-13): `fflush()` without
  `fsync()`.** On ESP-IDF's FAT VFS `fflush()` writes the BYTES but not the **directory entry**, so any boot
  not reaching `csv_logger_close()` (brownout, reset, card pulled live) left a file whose recorded size was
  **0** — rows present, unreachable. Fixed: `sd_mirror_sync()` = `fflush` + `fsync`, rate-limited by
  `LOGGER_SD_SYNC_INTERVAL_MS` (**5000 ms**, time-based), forced unconditionally in `csv_logger_flush()`.
  ⚠️ **Does NOT repair existing cards** — a PRE-FIX 0-row card file is **LOST DATA, not "the node logged
  nothing"**. Compiles clean; **NOT hardware-tested** (needs a board + mid-run reset).

## Rolled out of MEMORY.md — sep. 22, 2026 (batch 7; coverage blocker now in STATUS Next step 2)
- sep. 22, 2026 — ⚠️ **`home` blackhole/linear is NOT `[x]` because of COVERAGE, not archiving.**
  `inventory_cells.py:63` `COVERAGE_FLOOR = 0.95` (M5): the ROOT logged **93.7%** of expected samples, so
  the cell is disqualified by 1.3 points despite clean topology, exact phase timing and a CONFIRMED
  blackhole. G402 fails the same way (worst 93.9%). **The root dropping samples is now a MILESTONE
  BLOCKER, not a cosmetic warning** — same finding `validate_integrity.py` reports as a WARN.

## Rolled from MEMORY.md — sep. 22, 2026 (to hold the 200-line cap)
### Failed approaches — settled, fix is in the code
- Splitting recovered SPIFFS dumps on newlines after stripping page metadata — welds row tails to heads
  and fabricates data that passes a field regex. `recover_spiffs.py` now accepts only byte runs delimited
  by a newline on BOTH sides.
- `run_matrix.py --record` with hand-typed `--repeat` — silently re-recorded the wrong run. Use
  `--autorecord` (scans, validates, records; no flags to mistype).

### Rolled from MEMORY.md — sep. 22, 2026: the stderr-promotion trap (full detail)
- sep. 22, 2026 — ⚠️⚠️ **THE STDERR-PROMOTION TRAP BIT AGAIN — in `Invoke-ImportSdCard` this time.**
  A USB export dry-ran fine then died on the real copy with "Could not run import_sdcard.py / Is python on
  PATH?" while python was on PATH and working. Cause: `import_sdcard.py`'s real copy streams a progress bar
  to **stderr** (`export_logs.py:213` writes a CR-padded progress line); under `Stop`, PS 5.1 promotes
  a native command's FIRST stderr line to a TERMINATING error. The dry run survives only because it prints
  no progress. Tell-tale: `$_.Exception.Message` renders EMPTY (the promoted line is just CR + padding).
  Both calls now wrap in `$ErrorActionPreference='Continue'` + `finally` restore. The "Is python on PATH?"
  hint was HARDCODED after the catch (fired on ANY exception, named a "5.3" window absent on this 5.5.4
  laptop); it probes for python now. ⚠️ **Editing `run_wizard.ps1` does NOT affect an ALREADY-RUNNING
  wizard — exit [17] and relaunch.** Grep every `& python ... 2>&1` before shipping.

### Rolled from MEMORY.md — sep. 22, 2026: USB BSOD 0xB8 investigation (full detail)
- sep. 22, 2026 — ⚠️⚠️ **WINDOWS BSOD `ATTEMPTED_SWITCH_FROM_DPC` (0xB8) WHEN TALKING TO A BOARD OVER USB.**
  Angelo's laptop (Win11 26200) hard-crashed 2× on sep. 22 (11:45 + 13:36 local, dumps in `C:\Windows\Minidump`)
  during export / `DELETE_SD_FILE` / `SET_LOCATION`, plus a 0xA0 INTERNAL_POWER_ERROR sep. 21. HOST DRIVER
  fault — **not the firmware, not the scripts**; nothing an ESP sends over a COM port can crash Windows.
  **PRIME SUSPECT, topology CONFIRMED by the PnP parent chain: EVERY CP210x ever enumerated sat 2–3 Genesys Logic hubs
  (VID_05E3) deep behind ONE Intel root port — the Dell D6000 dock (DisplayLink VID_17E9/PID_6006, driver
  9.3.33xx from 2020) plus a further hub chained onto it.** Boards shared that one port with the dock's video
  chip. `silabser.sys` 11.3.0.176 is the other driver in the path. FIXED sep. 22: **USB selective suspend
  disabled (AC+DC)**. MANDATORY: **boards go DIRECT into a laptop port, NEVER the dock or any hub** — this is
  the same rule STATUS.md already had for ROOT POWER. Also update the CP210x + DisplayLink drivers.
- sep. 22, 2026 — Export overhaul + 3 follow-up fixes (D-13 fsync, `LIST_SD`, dedup, `DELETE_SD_FILE`). Rolled out of STATUS.md.
- sep. 22, 2026 — Console `LAYER`→`HOP` (root = H00), blackhole header rewritten to match C7's positional model, leaf/off-path guards, `TOPOLOGY TREE` block, USB-export stderr trap. 6/6 variants build clean. Rolled out of STATUS.md.

### Rolled from MEMORY.md — sep. 22, 2026 (cap): non-ASCII argparse docstrings
- Non-ASCII characters (`⚠`, `—`, `…`) in a Python tool's **module docstring** when it is passed to `argparse`
  as `description` — the Windows console is cp1252, so `--help` dies with `UnicodeEncodeError` before printing
  anything. `tools/command_center.py` is deliberately ASCII-only and calls
  `sys.stdout.reconfigure(encoding="utf-8")` before `rich` draws.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): SD status/runs/location/clock file roles
- sep. 22, 2026 — `status_NODE_<mac>.txt` is rewritten every boot and holds `Boot count:`, which IS the boot
  counter — deleting it resets `b<n>` to 1. It is NOT what the picker dates files from (that is `runs.csv`,
  also the run-number + USB row-count/abort source). `DELETE_SD_FILE` accepts only `*_telem.csv`/`*_arrivals.csv`,
  so it, `runs.csv`, `location.txt` and `clock.txt` are all undeletable by design.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): SD reader VCC + printf format specifier
- Powering the SD reader module's VCC from ESP32 3V3 — its onboard AMS1117-3.3 drops ~1.1-1.3V, leaving the
  card below its ~2.7V minimum. Symptom: CMD0 succeeds (R1=0x01) but ACMD41/OCR times out forever (0x107) —
  looks like wiring but isn't. Use VIN/5V; the module's 74HC125 level-shifter never puts 5V on ESP32 GPIOs.
- sep. 16, 2026 — Matching a `printf` format specifier to `sdmmc_card_t`'s `real_freq_khz`/
  `max_freq_khz` declared type — it differs by ESP-IDF version (see CLAUDE.md bootstrap facts).
  `sd_status.c`'s boot-check `rep()` now casts explicitly (`(unsigned long)x` + `%lu`) instead.

### Rolled from MEMORY.md — sep. 22, 2026 (cap): MAX_PATH build-dir failure, full detail
- Long `idf.py -B <dir>` names — deep paths push object paths past Windows `MAX_PATH`; ninja fails in the
  **bootloader** subproject long after the app compiled, so the error looks unrelated. ✅ **FIXED in
  `build_all_variants.ps1` (sep. 22, 2026)**: it used `build_check_<Name>` and the longest row (BLACKHOLE
  attacker) measured **exactly 260** — reporting FAILED for good code, with the budget shifting per user's
  own path. Now a per-variant `Bld` field (`bcr`,`bcba`,…) + a preflight WARNING. ⚠️ **Don't rename them
  back.** Still unapplied alternative: `LongPathsEnabled=1` (admin).
- sep. 22, 2026 — **Console `LAYER`→`HOP` (root = H00), blackhole header → C7 positional model, leaf/off-path guards, `TOPOLOGY TREE`, USB-export stderr trap. 6/6 build clean.** **NEEDS REFLASH.**  (rolled out of STATUS.md sep. 22)

### Rolled from MEMORY.md — sep. 22, 2026 (cap): jitter scenario, full rationale
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

### Rolled from MEMORY.md — sep. 22, 2026 (cap): campaign checklist scanner, full detail
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
- - sep. 22, 2026 — **`jitter` scenario; per-node PDR; build `-Clean`; wormhole warnings; wizard [15] crash; SMART ARCHIVE menu (duplicate + completeness detection).** MEMORY.md.  (rolled out of STATUS.md sep. 22)

### Rolled from MEMORY.md — sep. 22, 2026 (cap): wizard smart-archive front end, full detail
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

### Rolled from MEMORY.md — sep. 22, 2026 (cap): first clean r1 capture, full detail
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

### Rolled from MEMORY.md — sep. 22, 2026 (cap): first clean r1 capture, full detail
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

### Rolled from MEMORY.md — sep. 23, 2026 (cap): LAYER→HOP rename + leaf guards, full detail
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

### Rolled from MEMORY.md — sep. 23, 2026 (cap): jitter scenario summary
- sep. 22, 2026 — **SCENARIO `jitter` (TRAFFIC_PROFILE=3) — ROOT ONLY, ADDITIVE ONLY.** Root draws a random
  per-boot EXTENSION to baseline (0..45s) and attack (0..30s), so phases don't land at the same wall-clock
  offset every run. WHY: identical schedules made elapsed time alone score **0.857** against the label — the
  panel's "runs are all identical" objection. ⛔ **NEVER MAKE IT SUBTRACTIVE:** `preprocess.py` takes
  baseline as the LAST `PHASE_BASELINE_S` of phase 0, so a shorter baseline pulls mesh-formation noise into
  the benign class. Full rationale: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): wizard smart-archive summary
- sep. 22, 2026 — **WIZARD SMART ARCHIVE FRONT END (`Invoke-ArchiveMenu`).** Adds per-cell tables,
  **byte-identical duplicate detection across every `archive/*/`**, a COMPLETE-run warning and `-WhatIf`.
  ⚠️ **WHY — a real mistake:** `archive.ps1` MOVES data out of `tools/exports/`, leaving git-tracked paths as
  STAGED DELETIONS; those were mistaken for data loss and `git checkout`-restored, recreating 9 G402 files
  already safe in `archive/2026-09-22_incomplete/`. **A staged deletion under `tools/exports/` usually means
  archive.ps1 moved it — check `archive/` BEFORE restoring with git.** Full detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): timeseries alignment, full detail
- sep. 23, 2026 — **TIMESERIES PLOTS WERE MISALIGNED — 2 bugs in `eda.py`, both fixed.** (1) `window_start`
  is each node's OWN run clock restarting at 0 on ITS boot, and boards are flashed one at a time, so the same
  instant is a different x on every node (phase 0 began at 60s on the root but **670s on node2**, which is why
  its baseline "started at 600s" — NOT a bug in the data; `preprocess.py` excludes phase 255 anyway). The phase
  bands were taken from whichever node sorted first, so they were right for at most ONE line. New
  `_align_to_baseline()` re-bases x on each node's own phase-0 entry: t=0 = baseline starts, pre-baseline idle
  goes NEGATIVE. Plot axis only — the feature table is untouched, so nothing reaches a model. **Anchor on the
  RAW `segment` column, not `_phase_names()`** (that returns display strings like "Baseline" and silently
  never matches). (2) `_extract_run_id()` regex expects the OLD `RUN_xxx_telem` filename, so every real capture
  fell back to per-file and each node got its own figure — the opposite of the function's purpose. Now grouped
  on attack/topology/location/run_repeat. ⚠️ **BOTH views are written and BOTH are wanted** — the per-run
  overlay AND one figure per capture file (`timeseries_<source_file>.png`). Making it per-run alone silently
  dropped the per-node plots the team already used; they were deleted, then restored from git. Shared
  `_draw_timeseries()` so the two can't drift. The overlay SHOWS the positional finding: the downstream
  victim's PDR drops to 0 exactly across the red attack band while the upstream one stays flat at 1.0, and
  node2's parent switches sit entirely at NEGATIVE t (formation), never touching the experiment.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): data sync branch + push bugs, full detail
- sep. 22, 2026 — **DATA SYNC: follows your CURRENT BRANCH, and pushes ANALYSIS + EDA** (`push_data.py`).
  `--branch` was hardcoded `"Unified"`, sending CSVs to one branch while the code sat on another. Now
  `current_branch()`. New `--area analysis` shares `analysis/<attack>/<topology>/<site>/` output; TWO guards,
  both required — extension whitelist AND a **cell-depth rule**, since the pipeline's `.py` sits beside its
  output. Listed WITHOUT `--exclude-standard` (those outputs are `.gitignore`d as rebuildable).
  ⚠️ **TWO BUGS IT EXPOSED — the push SILENTLY did nothing.** (1) The private clone carries the same
  `.gitignore`, so `git add` skipped every analysis path **without a word** and the commit staged nothing —
  needs `git add -f`. (2) "already on GitHub?" was answered from the clone's WORKING TREE, so files the failed
  push left on disk made every later run print **"already on GitHub, identical"** and push nothing, forever.
  Now answered from the git TREE. **Verify a push against the REMOTE (`git ls-tree origin/<branch>`), never
  the tool's own summary.**


### Rolled from MEMORY.md — sep. 23, 2026 (cap): capture dates / SET_TIME, full detail
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

### Rolled from MEMORY.md — sep. 23, 2026 (cap): Initialize-Idf / export.ps1 activation, full detail
- Spawning a build/flash window as plain `powershell.exe` — `idf.py`/`esptool.py` are POWERSHELL
  FUNCTIONS from `C:\Espressif\Initialize-Idf.ps1`, and functions don't survive into a child process.
  Dot-sourcing with no `-IdfId` also fails silently (`idf-env config get` returns the STRING "null").
  Fix in use: `Get-EspIdfActivation` reads the real Start Menu shortcut's `-IdfId` at runtime.
  ⚠️ **sep. 22, 2026 — `export.ps1` ALSO fails here and LOOKS LIKE "ESP-IDF is not installed". It is.**
  `activate.py` derives the venv name from whichever `python` is first on PATH (3.12 on Angelo's box), then
  reports `idf5.5_py3.12_env ... not found`. The real venv is **`idf5.5_py3.11_env`**. Never conclude IDF is
  absent from an `export.ps1` failure — check `C:\Espressif\idf-env.exe config get` first. Working line:
  `. C:\Espressif\Initialize-Idf.ps1 -IdfId esp-idf-20ee62e792ea89630ac6a777ab3ebc57` (**this laptop = v5.5.4**).


### Rolled from MEMORY.md — sep. 23, 2026 (cap): per-node PDR, full detail
- sep. 22, 2026 — **`verify_attack.py` NOW PRINTS PER-NODE PDR under the pooled row — use THAT in the paper.**
  Pooled PDR averages nodes the attack never touched with nodes it annihilated, so it describes NO actual
  node. On blackhole/linear/home r1: pooled 0.514 = mean of victim H01 **1.0000** (upstream of the
  attacker, never transits it) and victim H03 **0.0137** (downstream, near-total loss) — a ~37x
  understatement of the real effect, and the pooled value moves run-to-run purely with where the attacker
  lands. The pooled row STAYS (the 3-sigma test consumes it); the split prints underneath, and a victim
  above the attacker is called out explicitly. ⚠️ Uses the PRE-`block_aggregate` frame (`df_nodes`) —
  `verify()` rebinds `df` to the pooled frame, which drops `node_role`/`hop` (first attempt printed `?`/`-`).

### Rolled from MEMORY.md — sep. 23, 2026 (cap): de-hardcoding, full detail
- sep. 23, 2026 — **DE-HARDCODED the machine-specific paths.** `tools/Get-EspMac.ps1` pinned
  `esp-idf-v5.3.5` + `idf5.3_py3.11_env` — **dead on this laptop, which has 5.5.4 only**, and the only symptom
  was "no MAC". It and `board_check.py` now discover the install from `IDF_PATH`/`IDF_TOOLS_PATH`, then glob
  `<SystemDrive>\Espressif` newest-first. `C:\Python314\python.exe` in all three menus → the `py` launcher.
  `board_check.py`'s MAC→label table is now overridable by `presets/boards.json` (`--roster`), so a new or
  swapped board needs no code edit — deliberately NOT the per-run presets, which disagree by design (the same
  MAC is `ROOT` in one and `node2` in another). ⚠️ **STILL DUPLICATED, not fixed:** the phase schedule lives
  in `mesh_config.h` (`PHASE_BASELINE_S` etc., overridable with `-DPHASE_BASELINE_S=`), AND in
  `preprocess.py:88`, AND in `validate_integrity.py:93`. Override it at build time and the host tools are
  silently wrong. Real durations are recoverable from `phase_id` transition timestamps — worth doing.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): timeseries alignment summary
- sep. 23, 2026 — **TIMESERIES PLOTS WERE MISALIGNED — 2 bugs in `eda.py`, fixed.** (1) `window_start` is
  each node's OWN clock from ITS boot and boards are flashed one at a time (phase 0 began at 60s on the root
  but **670s on node2** — why its baseline "starts at 600s"; harmless, `preprocess.py` drops phase 255). The
  phase bands came from whichever node sorted first, so they were right for at most ONE line.
  `_align_to_baseline()` re-bases x on each node's own phase-0 entry (t=0 = baseline, pre-baseline negative);
  **anchor on the RAW `segment` column, not `_phase_names()`** (that returns "Baseline" and never matches).
  (2) `_extract_run_id()` expects the OLD `RUN_xxx_telem` filename, so every capture fell back to per-file.
  Now grouped on attack/topology/location/run_repeat. ⚠️ **BOTH views are written and BOTH are wanted** — the
  per-run overlay AND one per capture file; making it per-run alone silently dropped the per-node plots the
  team uses (deleted, then restored from git). Shared `_draw_timeseries()` so they can't drift.
  Full detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): exposure column, full detail
- sep. 23, 2026 — **"VICTIM" IS NOW DERIVED FROM THE TOPOLOGY, not the firmware role** (`analysis/exposure.py`,
  new). Every child logs itself `victim` at build time, but since C7 the blackhole is POSITIONAL: a child ABOVE
  it never transits it and is untouched. New `exposure` column per node per run: `root` / `attacker` /
  `downstream` (= the REAL victims) / `upstream` (present but unreachable by the attack) / `no_attacker` /
  `unknown` (chain unresolved — never folded into another value). Resolved from `parent_mac` (the parent's
  SoftAP BSSID = STA+1, same rule `verify_topology.py` uses), preferring the parent held DURING the attack
  window, with a cycle guard. Verified on blackhole/linear/home r1: `downstream` → attack PDR **0.0000**,
  `upstream` → **1.0000**. `verify_attack.py`'s per-node table now prints "built as" vs "exposure" and names
  only downstream nodes VICTIM. ⚠️ **Registered in `leakage.py` METADATA_COLUMNS** — inside an attack window
  "downstream" is nearly the label, same leak class as `node_role`.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): phase-schedule mismatch guard, full detail
- sep. 23, 2026 — **THE PHASE SCHEDULE IS DECLARED TWICE AND NOTHING CHECKED THEY AGREE — now it does.**
  `mesh_config.h`'s `PHASE_*_S` are overridable at build time (`-DPHASE_BASELINE_S=180`) but `preprocess.py`
  and `validate_integrity.py` carry their own copies. Damage is silent and ONE-DIRECTIONAL: `preprocess.py`
  slices baseline BACKWARDS from the phase-0 exit, so a firmware baseline SHORTER than the host assumes
  reaches past the real start and labels mesh-formation noise BENIGN. Both now MEASURE real durations from
  `phase_id` transitions: warn on SHORT, note LONG (normal — `jitter` extends phases), `--phase-durations`
  declares a different schedule, `preprocess.py` reports `short_baseline` per node. Verified with a wrong
  nominal (`0=600`): silent when they agree, loud when not. **Still duplicated — but never silent now.**

### Rolled from MEMORY.md — sep. 23, 2026 (cap): victim->child rename, full detail
- sep. 23, 2026 — **FIRMWARE ROLE RENAMED `victim`→`child` (Change B, DONE).** `victim_main.c` writes `child`;
  a plain child is only a VICTIM if the attacker sits between it and the root, which `exposure` now says.
  ⚠️ **The compat map is what makes this safe:** `preprocess.py`'s `ROLE_ALIASES` folds BOTH spellings to the
  canonical `child` at the ONE place `node_role` is produced, so pre-2026-09-23 captures (which say `victim`
  forever) keep working. `features.py` gates on `CHILD_ROLE`, deliberately NOT on both spellings — accepting
  both there would hide a canonicalisation that had stopped running. **Verified by regenerating
  feature_table.csv and diffing: shape identical (3502x66), `node_role` the ONLY column that changed, PDR
  non-null 1318 and sum 1074.0 unchanged.** ⚠️ **NEEDS REFLASH** before the next capture.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): exposure column summary
- sep. 23, 2026 — **"VICTIM" IS DERIVED FROM THE TOPOLOGY, not the firmware role** (`analysis/exposure.py`).
  New `exposure` column per node per run: `root`/`attacker`/`downstream` (**the REAL victims**)/`upstream`
  (present, unreachable by the attack)/`no_attacker`/`unknown` (chain unresolved — never folded into another
  value). Resolved from `parent_mac` (parent's SoftAP BSSID = STA+1), preferring the parent held DURING the
  attack window, with a cycle guard. Verified: `downstream` → attack PDR **0.0000**, `upstream` → **1.0000**.
  `verify_attack.py` prints "built as" vs "exposure" and names only downstream nodes VICTIM.
  ⚠️ **In `leakage.py` METADATA_COLUMNS** — in an attack window "downstream" is nearly the label.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): de-hardcoding summary
- sep. 23, 2026 — **DE-HARDCODED the machine-specific paths.** `Get-EspMac.ps1` pinned `esp-idf-v5.3.5` +
  `idf5.3_py3.11_env` — **dead on a 5.5.4 laptop, symptom just "no MAC"**. It and `board_check.py` now discover
  via `IDF_PATH`/`IDF_TOOLS_PATH`, then glob `<SystemDrive>\Espressif` newest-first. `C:\Python314\python.exe`
  in all 3 menus → the `py` launcher. `board_check.py`'s MAC→label table is overridable by
  `presets/boards.json` (`--roster`) so a new board needs no code edit — NOT the per-run presets, which
  disagree by design. Detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): live exposure block, full detail
- sep. 23, 2026 — **THE ROOT NAMES THE VICTIMS LIVE, DURING THE RUN** (`mesh_setup.c`, EXPOSURE block after
  the TOPOLOGY TREE). Same rule as `exposure.py` but walked UPWARD through `g.parent[]`, step-guarded: any
  attacker ancestor ⇒ VICTIM. Prints each node ATTACKER / VICTIM / "not in the attack path" + a count, and
  **errors outright when NO node is downstream** ("it will drop NOTHING and this run will look benign") — to
  catch bad attacker placement BEFORE burning an 11-minute run, which post-hoc analysis structurally cannot.
  Console role word `VICTIM`→`CHILD`; **the enum VALUE is on the wire and did NOT change.**
  `verify_topology.py` gained an EXPOSURE column + `canonical_role()`. Vocabulary now consistent across
  firmware console, verify_topology, verify_attack and feature_table.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): timeseries alignment summary
- sep. 23, 2026 — **TIMESERIES PLOTS WERE MISALIGNED — fixed.** `window_start` is each node's OWN clock from
  ITS boot and boards are flashed one at a time (phase 0 began 60s in on the root, **670s on node2** — why its
  baseline "starts at 600s"; harmless, phase 255 is dropped). Bands came from whichever node sorted first.
  `_align_to_baseline()` re-bases on each node's phase-0 entry; **anchor on the RAW `segment` column, not
  `_phase_names()`** (returns "Baseline", never matches). Also `_extract_run_id()` expected the OLD filename,
  so the overlay never existed. ⚠️ **BOTH views are written and BOTH are wanted** (per-run overlay AND one per
  capture file) — per-run alone silently dropped plots the team uses. Detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): victim->child rename summary
- sep. 23, 2026 — **FIRMWARE ROLE RENAMED `victim`→`child` (Change B, DONE).** ⚠️ **The compat map is what
  makes it safe:** `preprocess.py`'s `ROLE_ALIASES` folds BOTH spellings to canonical `child` at the ONE place
  `node_role` is produced, so pre-rename captures keep working; `features.py` gates on `CHILD_ROLE` and
  deliberately NOT on both, which would hide a canonicalisation that had stopped running. Verified by
  regenerating feature_table.csv: shape identical, `node_role` the ONLY changed column, PDR unchanged (it sits behind the gate, so that IS the proof). ⚠️ **NEEDS REFLASH.**


### Rolled from MEMORY.md — sep. 23, 2026 (cap): phase-schedule guard summary
- sep. 23, 2026 — **PHASE-SCHEDULE MISMATCH CAN NO LONGER PASS UNNOTICED.** `mesh_config.h`'s `PHASE_*_S`
  are build-time overridable but `preprocess.py`/`validate_integrity.py` carry copies. Silent and
  ONE-DIRECTIONAL: preprocess slices baseline BACKWARDS from the phase-0 exit, so a firmware baseline
  SHORTER than the host assumes labels mesh-formation noise BENIGN. Both now MEASURE from `phase_id`
  transitions — warn SHORT, note LONG (`jitter`), `--phase-durations` overrides. Detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): first clean r1 capture summary
- sep. 22, 2026 — **FIRST CLEAN r1 CAPTURE VERIFIED (blackhole/linear/home) — attack CONFIRMED.**
  ForwardingRatio 1.000→0.026, PDR 1.000→0.514. ⚠️ **Aggregate PDR HIDES a positional split:** the victim
  UPSTREAM of the attacker stayed at PDR=1.000 throughout; the downstream one fell to 0.0137. Pooling
  describes no real node — **report PDR PER NODE relative to the attacker.** ✅ NOT a gap: `leakage.py`'s
  survivors warning already catches ForwardingRatio/ConsistencyScore; the documented fix is attack-PARAMETER
  VARIATION across repeats, not a code change. Full detail: ARCHIVE.md.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): SET_TIME clock summary
- sep. 22, 2026 — **CAPTURE DATES ARE REAL: the board takes its clock from the laptop (`SET_TIME`).** The
  picker's date was `sd_status_build_stamp()` (link-time `__DATE__`), identical on every boot of one flash —
  why deleting CSVs and re-running still showed the same date. No RTC, no NTP ⇒ only a host can supply one.
  `SET_TIME`/`GET_TIME` + `/sdcard/clock.txt`; the anchor is applied **after mount, before the folder tree**,
  which is what makes Explorer's "Date modified" true. FORWARD-only. `runs.csv` += `started`,`clock_src`.
  ⚠️ **NEEDS REFLASH.** Full detail: ARCHIVE.md.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): stderr-promotion trap summary
- sep. 22, 2026 — ⚠️ **PS 5.1 PROMOTES A NATIVE COMMAND'S FIRST STDERR LINE TO A TERMINATING ERROR**
  under `$ErrorActionPreference='Stop'` — so a tool that writes a progress bar to stderr (`export_logs.py`)
  kills its PowerShell caller with an EMPTY exception message. Both `run_wizard.ps1` import calls now wrap
  in `'Continue'` + `finally` restore. **Grep every `& python ... 2>&1` before shipping.** ⚠️ Editing
  `run_wizard.ps1` does NOT affect an ALREADY-RUNNING wizard — exit [17] and relaunch. Detail: ARCHIVE.md.

## Durable facts & constraints

### Rolled from MEMORY.md — sep. 23, 2026 (cap): groupmate audit, full detail
- sep. 23, 2026 — **AUDIT of groupmate `fac59c5`/`13b607c` (`docs/2026-09-23_LAYER-HOP-MAC-EXPLAINER.md`):
  every load-bearing number FACT-CHECKED and CORRECT** — `MESH_ROOT_LAYER (1)` (re-verified in 5.5.4, not
  just the 5.3.5 cited), `layer -1 → NaN`, SoftAP = STA+1 on all 4 values, attacker `recv 180/fwd 0/drop
  180`, arrivals `301→0→121` downstream vs `300→180→121` upstream. No errors; their MEMORY edits held both
  caps. Also: zero absolute paths left in code, no silent `except: pass`, and the lone `ForwardingRatio>1`
  (4.00) window is node2's re-parent queue flush in **pre_baseline** (EXCLUDED) — baseline FR is genuinely
  n=600, sd=0.000000.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): attack-window parent rationale
- sep. 23, 2026 — ⚠️ **`exposure.py` MUST use the ATTACK-WINDOW parent, not the whole-run mode — the sep. 22
  data proves it.** node2 (`B0CBD8F33218`) sat BELOW the attacker for its entire 671-window pre-baseline, then
  re-parented to the root before baseline began. Whole-run mode is dominated by those pre-baseline rows and
  returns the ATTACKER as its parent (it even makes node2/attacker look like a 2-cycle). That would label an
  untouched node `downstream` — the exact error the column exists to prevent. Its PDR was 1.000 throughout.
  **Never "simplify" `_dominant_parent()` to a plain mode.**


### Rolled from MEMORY.md — sep. 23, 2026 (cap): role-gate guard detail
- sep. 23, 2026 — **ROLE-GATE COVERAGE GUARD** (`features._warn_on_missing_attack_role`). Manipulation
  features are gated on `node_role == "<attacker>"` behind `if mask.any()`, so a gate matching ZERO rows
  computes nothing and SAYS nothing — `ForwardingRatio` (PRIMARY) goes all-NaN and `verify_attack` fails
  invisibly. Causes: attacker never exported, wrong `<attack>/` folder, or a role string drifting (what
  victim→child would have done to PDR). Now warns, naming the roles present. `ATTACK_ROLES` constants.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): exposure column detail
- sep. 23, 2026 — **`exposure` COLUMN: who the attack could actually reach** (`analysis/exposure.py`), per
  node per run: `root`/`attacker`/`downstream` (**the REAL victims**)/`upstream`/`no_attacker`/`unknown`
  (never folded). From `parent_mac` (parent's SoftAP BSSID = STA+1), using the parent held DURING the
  attack, cycle-guarded. Verified: `downstream` → PDR **0.0000**, `upstream` → **1.0000**. ⚠️ **In
  `leakage.py` METADATA_COLUMNS** — nearly the label in an attack window. Detail: ARCHIVE.md.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): phase-schedule guard detail
- sep. 23, 2026 — **PHASE-SCHEDULE MISMATCH IS NO LONGER SILENT.** `mesh_config.h`'s `PHASE_*_S` are
  build-time overridable but the host tools carry copies; preprocess slices baseline BACKWARDS from the
  phase-0 exit, so a SHORTER firmware baseline labels formation noise BENIGN. Both now MEASURE from `phase_id`
  transitions — warn SHORT, note LONG (`jitter`), `--phase-durations` overrides. Detail: ARCHIVE.md.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): live exposure detail
- sep. 23, 2026 — **THE ROOT NAMES THE VICTIMS LIVE, DURING THE RUN** (`mesh_setup.c`, EXPOSURE block after
  the TOPOLOGY TREE). Same rule as `exposure.py`, walked UPWARD through `g.parent[]`, step-guarded. Prints each
  node ATTACKER / VICTIM / "not in the attack path", and **errors when NO node is downstream** — catches bad
  attacker placement BEFORE burning an 11-minute run. Console role word `VICTIM`→`CHILD`; **enum VALUE is on
  the wire and did NOT change.** `verify_topology.py` gained an EXPOSURE column. Detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): victim->child detail
- sep. 23, 2026 — **FIRMWARE ROLE RENAMED `victim`→`child`.** ⚠️ **The compat map makes it safe:**
  `preprocess.py`'s `ROLE_ALIASES` folds BOTH spellings to canonical `child` at the ONE place `node_role` is
  produced; `features.py` gates on `CHILD_ROLE` and deliberately NOT on both (which would hide a
  canonicalisation that stopped running). Verified: regenerating feature_table changed ONLY `node_role`; PDR
  unchanged, and PDR sits behind the gate so that IS the proof. ⚠️ **NEEDS REFLASH.** Detail: ARCHIVE.md.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): timeseries detail
- sep. 23, 2026 — **TIMESERIES PLOTS WERE MISALIGNED — fixed.** `window_start` is each node's OWN boot clock
  (phase 0 began 60s in on the root, **670s on node2**), so bands drawn from whichever node sorted first were
  right for at most one line. `_align_to_baseline()` re-bases per node; **anchor on the RAW `segment` column,
  not `_phase_names()`** (returns "Baseline", never matches). ⚠️ **BOTH views are written and BOTH are wanted**
  (per-run overlay AND one per capture file). Detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): wireshark guide MAC fix
- sep. 23, 2026 — ⚠️ **`docs/WIRESHARK-GUIDE.md` had ROOT and a CHILD SWAPPED** — it listed
  `b0:cb:d8:f3:32:18` as ROOT, but since at least sep. 22 the root is `70:4b:ca:25:b7:68` and `b0:cb…18` is
  the UPSTREAM child. Every "the root" filter pointed at a child and would have shown plausible-but-wrong
  traffic. Corrected against the capture + a one-liner to re-derive it. Also: filter 4 is **attacker → its
  PARENT**, not "→ root" — it worked only because the attacker's parent happened to be `b0:cb…18`; the parent
  changes with the topology. Verified `simple_sniffer` DOES exist in the installed 5.5.4 (Path A is viable).


### Rolled from MEMORY.md — sep. 23, 2026 (cap): phase schedule in status report
- sep. 23, 2026 — **STATUS REPORT RECORDS ITS OWN PHASE SCHEDULE** (`[6]`, `sd_status.c`): compiled
  `PHASE_STABILISE/BASELINE/ATTACK/COOLDOWN_S` + whether jitter is on. WHY: the host tools cannot DERIVE the
  nominal — jitter EXTENDS phases on purpose, so the measured duration legitimately differs. Recording the
  compiled value is the only way a pulled card can state its own provenance. Free-form text; nothing parses it.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): de-hardcoding detail
- sep. 23, 2026 — **DE-HARDCODED machine paths.** `Get-EspMac.ps1` pinned IDF `v5.3.5`+`py3.11` — dead on a
  5.5.4 box, symptom just "no MAC". It and `board_check.py` discover via `IDF_PATH`/`IDF_TOOLS_PATH` then glob
  `<SystemDrive>\Espressif`. `C:\Python314\python.exe` → `py` launcher. Board roster overridable by
  `presets/boards.json` (`--roster`). Detail: ARCHIVE.md.

### Rolled from MEMORY.md — sep. 23, 2026 (cap): USB BSOD detail
- sep. 22, 2026 — ⚠️⚠️ **PLUG BOARDS DIRECT INTO THE LAPTOP — NEVER THE DOCK OR ANY HUB.** Win11 26200
  hard-crashed 2x (BSOD `ATTEMPTED_SWITCH_FROM_DPC` 0xB8) during export / `DELETE_SD_FILE` / `SET_LOCATION`.
  HOST DRIVER fault, **not the firmware or scripts** — nothing an ESP sends over a COM port can crash Windows.
  Confirmed by the PnP parent chain: every CP210x sat 2-3 Genesys hubs deep behind the Dell D6000 dock,
  sharing one Intel root port with its DisplayLink video chip. USB selective suspend now off (AC+DC); still to
  do: update CP210x + DisplayLink drivers. Dumps in `C:\Windows\Minidump`. Detail: ARCHIVE.md.


### Rolled from MEMORY.md — sep. 23, 2026 (cap): data sync push bugs
- sep. 22, 2026 — **DATA SYNC: follows your CURRENT BRANCH, and pushes ANALYSIS + EDA** (`push_data.py`
  `--area analysis`). `--branch` was hardcoded `"Unified"`. ⚠️ **TWO BUGS IT EXPOSED — the push SILENTLY did
  nothing:** the private clone carries the same `.gitignore`, so `git add` skipped every analysis path without
  a word (needs `-f`); and "already on GitHub?" was answered from the clone's WORKING TREE, so leftovers from
  the failed push made every later run say "already on GitHub, identical" forever. **Verify a push against the
  REMOTE (`git ls-tree origin/<branch>`), never the tool's own summary.** Full detail: ARCHIVE.md.

## Rolled from MEMORY.md (sep. 23, 2026)
- ⚠️ **Paper-scope conflict R-A:** paper §1.4.1 + abstract commit to a *"controlled indoor environment"*. The DLSU-campus decision deliberately relaxes that — must be amended in §1.4.1/abstract and logged in `thesis-deviate.md` as D-5, not slipped in.
- ⚠️ **Paper-scope conflict R-B:** paper §1.4.1 explicitly EXCLUDES *"grayhole, Sybil, or selective forwarding"* from the threat model. Partial/probabilistic drop rates ARE selective forwarding — so the obvious fix for the panel's "vary the attacks" comment collides with approved scope. Safest reading: the panel asked for different **attacker positions**, not different drop rates. Adviser decides (plan §7 R-B).
- ✅ **§2.8 + Table 2.8 already survey existing wireless datasets** — extend that table for the dataset-comparison work, don't write a new section.
- sep. 23, 2026 — **firmware role `victim`→`child` + `exposure` column; phase-schedule mismatch detected from the data.** MEMORY.md. ⚠️ **NEEDS REFLASH.**
- ✅ **Already have a pre-registered attack signature (panel P6):** paper **§3.4.4 + Tables 3.4/3.5** state the expected observables for blackhole and wormhole, written at proposal time before any capture. Quote as-published; NEVER edit them to match results. §3.3.1.1/§3.3.2.1 hold the theory citations.
- Feature coverage is run-type-dependent: baseline 10/16, blackhole 13/16, wormhole 13/16, **combined matrix 16/16**. "No feature uniformly NaN" is a claim about the assembled dataset, not any single run.
- The FOLDER you build from decides the role, not the COM port: `root_node/` → root, `child_node/` → victim.
- Mesh identity is shared across every board: `MESH_ID {0xAB,0xCD,0xEF,0x01,0x23,0x45}`, `MESH_PASSWORD "MeshSecure2026!"` in `components/mesh_common/include/mesh_config.h` — never change between flashing root and victims.
- Blackhole signature (M2): attack-window PDR ~0.08 vs 0.94 benign, ForwardingRatio ~0.02, root logs zero arrivals. Wormhole signature: duplicated `(src_mac, seq_num)` arrivals (×2 on the tunnelled node).
- sep. 23, 2026 — **root names VICTIMS live during the run** (errors if nothing is downstream of the attacker) + vocabulary `victim`→`child`. MEMORY.md. ⚠️ **REFLASH.**
- **aug. 29, 2026 — honest nodes cannot observe their own forwarding** (MESH_DATA_TODS => the stack
  relayed below the app layer). ✅ **SOLVED sep. 21 by C7 Option 1 (D-12)** — every node now relays
  explicitly and reports real recv/forward/drop. Kept for the why; full text in ARCHIVE.md.

- (rolled from MEMORY.md sep. 23, 2026)
- sep. 22, 2026 — **CONSOLE SAYS `HOP`, NOT `LAYER` (adviser); root = H00.** ESP-MESH `layer` is 1-based, so
  the console now prints hop = layer-1 and agrees with the paper. Blackhole header rewritten to the C7
  positional model; leaf/off-path guards added; `TOPOLOGY TREE` block added. Full detail: ARCHIVE.md.
- sep. 23, 2026 — **status report records its own phase schedule `[6]`; Wireshark guide ROOT/child MACs were SWAPPED (fixed).** ⛔ Two self-inflicted breakages killed a live run — MEMORY.md, first entry.
- (rolled from MEMORY.md sep. 23, 2026)
- sep. 22, 2026 — **FIRST CLEAN r1 CAPTURE (blackhole/linear/home) — attack CONFIRMED**, independently
  re-verified sep. 23 (see the AUDIT entry). ⚠️ **Report PDR PER NODE relative to the attacker, never pooled**
  — the upstream child held 1.000 throughout while the downstream one fell to ~0. Detail: ARCHIVE.md.
- (rolled from MEMORY.md sep. 23, 2026)
- sep. 22, 2026 — **SCENARIO `jitter` (TRAFFIC_PROFILE=3) — ROOT ONLY, ADDITIVE ONLY.** Random per-boot
  EXTENSION to baseline/attack windows so phases don't land at the same offset every run (elapsed time alone
  scored 0.857 against the label). ⛔ **NEVER SUBTRACTIVE** — a shorter baseline pulls mesh-formation noise
  into the benign class. Full rationale: ARCHIVE.md.
- (rolled from MEMORY.md sep. 23, 2026)
- sep. 22, 2026 — **`build_all_variants.ps1` HARDENED + the 2 wormhole warnings FIXED.** New `-Clean`
  switch wipes every build dir first; a warm run now REFUSES to print "ALL VARIANTS BUILD CLEAN" and
  instead names the variants that reused cached objects. **Use `-Clean` for any M1 criterion-1 evidence.**
  Dead `mesh_data_t root_data`/`mdata` descriptors deleted from `wormhole_victim.c` (pre-C7 leftovers;
  both tasks send via `probe_relay_send_own()` — call sites traced, no behavioural change).
- sep. 23, 2026 — TWO SELF-INFLICTED BREAKAGES in `run_wizard.ps1`, both killed a live run, both fixed and verified by a clean 6/6 build: (1) writing C string literals through a shell heredoc turned its escape sequences into real newlines inside the literals, producing "missing terminating \" character" x102 mid-flash — fix: use a script FILE with an r-string, never an inline heredoc, for C string work. (2) .NET format strings use `{1,6}` (positive width = right-align), not Python's `{1,>6}` — `run_wizard.ps1:2348` threw "Input string was not in a correct format".
- sep. 23, 2026 — STATUS REPORT RECORDS ITS OWN PHASE SCHEDULE (`[6]`, `sd_status.c`): the host cannot derive the nominal phase durations since jitter extends them on purpose, so recording the compiled value on the SD card is the only way a pulled card states its own provenance. Free-form text; nothing parses it.
- sep. 23, 2026 — Rolled from STATUS.md "Recently done": `run.ps1` failed-flash retry at 115200 (never exports a blank board) shipped; wizard MacBook sniffer test passed (Wi-Fi ON-but-disconnected); mesh was HT40 at the time, was going to try 40 MHz width for the sniffer instead — superseded same day by MESH_FORCE_HT20 (see MEMORY.md), which then broke mesh joining outright (see MEMORY.md's newest Decisions entry) and was partially reverted.
- sep. 24, 2026 — Rolled from MEMORY.md: the old "verify the attacker MAC before EVERY blackhole run" run-killer is RETIRED by C7 Option 1 — victims no longer address the attacker by MAC, so a stale value is bookkeeping only; its old symptom (all-NaN PDR + empty arrivals + root probes_count stuck at 0) now means something else.
- sep. 24, 2026 — Rolled from STATUS.md "Recently done": sep. 23 wizard PARKS the root (bootloader) before flashing children and wakes it at its turn — the old root's stale TERMINATE was killing fresh children. Hardware-exercised sep. 24 (4-board join test ran in exactly that order).
- sep. 24, 2026 — Rolled from MEMORY.md (fully written up in docs/ATTACK-VALIDATION.md): **Two conformance gaps, both now MEASURED and written up** in `docs/ATTACK-VALIDATION.md`: (a) the blackhole is a *placed* relay — it does not ATTRACT traffic by false route advertisement; (b) the wormhole duplicates arrivals but does **NOT** re-form parent selection (0 switches, r2 and r3). The paper's own functional naming (§4.2.1.2/4.2.1.3, Tables 4.6/4.7) already makes the defensible claim.
- sep. 24, 2026 — Rolled from STATUS.md: sep. 23, 2026 — **board dates now PHT (UTC+8) + fixed build-stamp-8h bug that made every capture keep the build-time date.** Root+child build clean. Also: false early `NO NODE IS DOWNSTREAM` now waits for all nodes. ⚠️ **REFLASH.** MEMORY.md.
- sep. 24, 2026 — Rolled from STATUS.md: sep. 24, 2026 — **Campaign checklist: LIVE/ARCHIVE views, `[x]` needs capture + analysis, scenarios RANDOMISED per cell (`tools/campaign_plan.json`, 4 of 6, balanced), `none` shown as "stationary".** 144 planned runs. MEMORY.md.
- sep. 24, 2026 — Rolled from MEMORY.md (full detail already in ARCHIVE.md): sep. 23, 2026 — **DE-HARDCODED machine paths.** `Get-EspMac.ps1` pinned IDF `v5.3.5`+`py3.11` — dead on a 5.5.4 box. It and `board_check.py` now discover via `IDF_PATH`/`IDF_TOOLS_PATH` then glob `<SystemDrive>\Espressif`. `py` launcher replaces `C:\Python314`. Board roster overridable by `presets/boards.json` (`--roster`). Detail: ARCHIVE.md.
- sep. 24, 2026 — Rolled from MEMORY.md (full detail already in ARCHIVE.md): sep. 23, 2026 — **TIMESERIES WERE MISALIGNED — fixed.** `window_start` is each node's OWN boot clock (phase 0 at 60s on the root, **670s on node2**), so bands from whichever node sorted first were right for one line at most. `_align_to_baseline()` re-bases per node; **anchor on the RAW `segment` column**, not `_phase_names()`. ⚠️ **BOTH views are written and BOTH are wanted.** Detail: ARCHIVE.md.
(rolled from MEMORY.md sep. 25, 2026) - sep. 22, 2026 — ⚠️ **M3 CONVERGENCE FAILS on the sep. 22 home run.** node2 (`B0CBD8F33218`, hop 1) took
  **607.1s** to converge, 3 parent_switches, 6 layer_changes (others 0-31s / 0) — explains its 647s of
  phase-255 idle, its 11906-row file and likely its ~8.6Hz attack/cooldown cadence. `verify_topology.py`:
  "Converged within 60s: NO". Structure itself is CORRECT linear H00-H03. Run it with `--dir tools/exports`
  (the exports ROOT, not a leaf cell).
(rolled from MEMORY.md sep. 25, 2026) - sep. 22, 2026 — **`validate_integrity.py`: WARN separates LOST DATA from SLOW CADENCE; derived dirs skipped.**
  It said "node was dropping samples" for pure cadence drift. Now reports median interval + gaps-vs-own-cadence
  and names which. `_find_csvs()` prunes `trimmed/`,`_archive/`,`archive/` (`--include-derived` restores):
  trimmed output is **byte-identical to raw when a capture holds ONE boot session — the HEALTHY case** (all 5
  live captures verified: 1 session, 0 regressions). **`trimmed/` is correct — do not delete or "fix" it.**
(rolled from MEMORY.md sep. 25, 2026) - sep. 22, 2026 — **DATA SYNC follows your CURRENT BRANCH; pushes ANALYSIS + EDA** (`--area analysis`).
  ⚠️ **Two bugs it exposed — the push SILENTLY did nothing:** the private clone carries the same
  `.gitignore` (needs `git add -f`), and "already on GitHub?" read the clone's WORKING TREE, so leftovers
  from the failed push made every later run claim "identical" forever. **Verify against the REMOTE
  (`git ls-tree origin/<branch>`), never the tool's summary.** Detail: ARCHIVE.md.
(rolled from MEMORY.md sep. 25, 2026) - sep. 22, 2026 — **CAPTURE DATES ARE REAL: the board takes its clock from the laptop (`SET_TIME`).** The old
  date was the link-time build stamp, identical on every boot of one flash. `/sdcard/clock.txt` anchor applied
  **after mount, before the folder tree** (that ordering is what makes "Date modified" true). Detail: ARCHIVE.md.
(rolled from MEMORY.md sep. 25, 2026) - sep. 22, 2026 — **FIXED: wizard [15] campaign checklist CRASHED at the end** — `run_wizard.ps1:2232`
  called `Read-YesNo`, which is defined ONLY in `menu.ps1` and never dot-sourced here, so it threw
  `CommandNotFoundException` AFTER printing the whole checklist. Now uses this file's own `Read-Line`
  idiom. Swept for the same class: `Get-BuildDirSpec`/`Show-MainMenu` appear in run_wizard.ps1 but only
  inside COMMENTS — `Read-YesNo` was the one real cross-script call.
- sep. 24, 2026 — (rolled from STATUS.md sep. 25) Multi-laptop wizard fix: "N boards need ports" wrongly counted a remote root/child as needing a LOCAL port. Fixed + clarifying banners added.
- sep. 24, 2026 — (rolled from STATUS.md sep. 25) Scenario `none` → `stationary` everywhere, with its own `stationary\` folder (`none` still accepted). Fixed: jitter runs could not export. 20 py + 19 PS checks + firmware build pass.
- sep. 23, 2026 — (rolled from STATUS.md sep. 25) FIXED + HARDWARE-VERIFIED: `MESH_FORCE_HT20` had broken mesh joining (0 nodes in 11 min). HT20 now set BEFORE `esp_wifi_start()` (APSTA mode). 4-board test: all joined, correct chain, all 20 MHz, phases reach children.
- sep. 25, 2026 — (rolled from MEMORY.md) sep. 22, 2026 — `status_NODE_<mac>.txt`/`runs.csv`/`location.txt`/`clock.txt` roles + why `DELETE_SD_FILE` only accepts `*_telem.csv`/`*_arrivals.csv` — full detail ARCHIVE.md.
- (rolled from STATUS.md sep. 25, 2026) sep. 24, 2026 — **Root build fix** `%u` vs `uint32_t` on Xtensa (`cd7c212`); `PCAP/`+`*.pcap` git-ignored (120 MB > GitHub cap).
- (rolled from MEMORY.md sep. 25, 2026) sep. 23, 2026 — **`analysis/eda.py` plot readability overhaul + new `analysis/column_legend.py`.** Analysis-only, no reflash, Basti's clone (not `A:\Angelo\...`). **UNCOMMITTED.** **Bug fixed:** phase shading compared raw `Label` (NaN on unlabelled rows), stacking hundreds into one red block that read as the attack; now compares `segment`-derived names, and PCA/t-SNE drop unlabelled windows too — moved `blackhole/linear/home`'s PCA variance 30.5/23.0%→39.1/28.0%. ⚠️ Heatmap upper-triangle masking was tried and REJECTED — don't reintroduce. `column_legend.py`'s `_L` dict is now the single source of column meanings.
- (rolled from STATUS.md sep. 25, 2026) sep. 24, 2026 — **Root dashboard EXPORT column** (`5f4443b`): per-board SAFE / not yet + summary line. MEMORY.md.
- (rolled from MEMORY.md sep. 25, 2026) sep. 22, 2026 — **WIZARD SMART ARCHIVE FRONT END** (`Invoke-ArchiveMenu`): per-cell tables, byte-identical duplicate detection across every `archive/*/`, COMPLETE-run warning, `-WhatIf`. ⚠️ **`archive.ps1` MOVES data, so git shows STAGED DELETIONS under `tools/exports/` — check `archive/` BEFORE `git checkout`-ing them back; doing that once recreated 9 files already safely archived.** Detail: ARCHIVE.md.
- (rolled from STATUS.md sep. 25, 2026) sep. 24, 2026 — **TERMINATE-miss fixes:** cooldown watchdog (`4144d30`), root re-sends TERMINATE 60 s, serial `END_RUN` + wizard offer (`d122033`/`489709a`). Honest manifest rows `term_timeout` / `manual_end`. MEMORY.md.
- (rolled from STATUS.md sep. 25, 2026) sep. 25, 2026 — **Wizard run logs:** filed `run_logs/<attack>/<topology>/<location>/<scenario>/`, page-by-page full view, keep/archive/delete, push after saving, `--area logs`; Data sync grouped + DELETE/RESTORE (undoable, sim-tested). NOT pushed live yet.
- (rolled from MEMORY.md sep. 25, 2026) sep. 22, 2026 — **`vTaskDelay`→`xTaskDelayUntil` IN ALL 4 TELEMETRY LOOPS — THE M5 COVERAGE BLOCKER'S ROOT CAUSE.** They slept 100ms AFTER the body, so the real period was body+100ms; with `CONFIG_FREERTOS_HZ=100` (10ms tick) any non-zero body cost a whole tick. Root measured **110.0ms = 9.09Hz → 93.6%** vs the 10Hz the validator assumes — **with ZERO gaps** (longest interval 0.36s). Nothing was lost; no node with a >0ms body could ever have passed. Fixed in `root_main.c`, `blackhole_victim.c`, `victim_main.c`, `wormhole_victim.c`; **6/6 `-Clean` build verified, 0 warnings.** ⚠️ **Re-measure coverage after the reflash before M5 is done.**
- (rolled from MEMORY.md sep. 25, 2026) sep. 23, 2026 — **`run.ps1` now flashes and monitors as TWO calls; a failed flash retries once at `-b 115200`, then `exit 1`
  before export.** Why: COM4 hit `Failed to leave compressed flash mode (C800)` (USB serial glitch) and the old combined
  `flash monitor` fell through into exporting a freshly-erased board. ⚠️ Mesh runs at **HT40 (log: `channel 11, 40D`)** — Mac Sniffer width may need 40 MHz for data frames.
- (rolled from MEMORY.md sep. 25, 2026) sep. 23, 2026 — **MAC WIRELESS DIAGNOSTICS SNIFFER gave a 0-BYTE file (M1, full run).** Likely cause: the
  guide said "turn Wi-Fi OFF" (true for Wireshark monitor mode only) — the Sniffer needs Wi-Fi ON but DISCONNECTED.
  New wizard item **MacBook sniffer test** (`Invoke-MacSnifferTest`, ~2 min, no attack; listens to root serial to prove the air had traffic). ✅ sep. 23: short test PASSED (packets seen); full-run capture still unverified.
- (rolled from STATUS.md sep. 25, 2026) sep. 25, 2026 — **Incomplete-capture guards:** validator FAILs phase-255-only files + `child` role fix; preprocess skips them
  and no longer archives a complete capture for a newer empty one; import picker shows NO EXPERIMENT DATA; analyze.ps1 exit gates.
- (rolled from MEMORY.md sep. 25, 2026) sep. 23, 2026 — **`tools/check_pcap.py` + wizard "Check a Mac sniffer capture file"** (stdlib, pcap+pcapng): finds mesh nodes
  by behaviour — mesh beacons have a HIDDEN SSID (not `ESPM_*`) + scrambled IE, so node = hidden-SSID beacon whose MAC−1 also transmits.
  Verified on the real 126 MB M1 capture (sep. 23, `Downloads\Jose's MacBook Air_ch11_...pcap`): exactly 4 boards, 1848 mesh DATA frames, root sent 0 → likely 20 MHz width missed HT40 data.
