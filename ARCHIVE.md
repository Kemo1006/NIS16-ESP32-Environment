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

- sep. 20, 2026 — **`docs/data-and-results/DATA-DICTIONARY.md` written**: per-role meaning of every column, **no column holds an
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

- **aug. 29, 2026 — honest nodes cannot observe their own forwarding.** Victims send `esp_mesh_send(NULL, ..., MESH_DATA_TODS)`, so the mesh stack relays *below the app layer* and only the blackhole attacker sees transit packets (victims address it explicitly). ⇒ un-gating the relay features is **not** a mask widening — there is no honest-relay data to un-gate, and F3's dedicated counters do not create any. That is what C7 Option 1 exists to change. Per-role column meanings: `docs/data-and-results/DATA-DICTIONARY.md`. Full text in ARCHIVE.md.

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

- sep. 21, 2026 — **`docs/panel-answers/REVIEWER-QUESTIONS.md`** answers every adviser/panel side comment against
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

- sep. 21, 2026 — **`docs/data-and-results/EXPECTED-RESULTS.md` §0 explains HOW TO READ every number** (added after the
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
- sep. 21, 2026 — **`docs/data-and-results/EXPECTED-RESULTS.md` §0 explains HOW TO READ every number** (the team could
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
- sep. 20, 2026 — **`docs/data-and-results/DATA-DICTIONARY.md`**: per-role meaning of every column; **no column holds an
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
  (full D-12 detail already in ARCHIVE.md and docs/deviations-limitations/thesis-deviate.md.)

## Rolled from MEMORY.md - sep. 22, 2026 (export-fix batch needed room)

- sep. 20, 2026 — **Resolved sep. 20 reference entries moved to ARCHIVE.md**: `analyze.ps1 -Verify`'s three
  exit-code gates (a NOT-CONFIRMED after a failed gate = **INCONCLUSIVE, not negative**), the
  `member_boards.json` child_8/child_10 transposition (**boards are ground truth**),
  `docs/data-and-results/DATA-DICTIONARY.md` (**read before writing schema text**), the evidence-backed testbed
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
  warning lives in `run_wizard.ps1` and `docs/data-and-results/EXPECTED-RESULTS.md`.

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
- sep. 21, 2026 - **`docs/panel-answers/REVIEWER-QUESTIONS.md`** answers every adviser/panel side comment against verified code.
- sep. 21, 2026 - **`verify_topology.py --structure`** rebuilds the parent/child table from CSVs (wizard VERIFY menu).
- sep. 22, 2026 — **All 4 boards reflashed** with `ab74ec4` (COM3 ROOT/bcr, COM10+COM9 victim/bcbv, COM11
  attacker/bcba; MACs re-read via `esptool read_mac`, matched to `presets/Cal/TRY.json`, hashes verified).
  ⚠️ COM10 boot 9 + COM9 boot 1 were never exported — the reboot moved them to `<leaf>/_archive/`, which
  `import_sdcard.py` deliberately skips. Recover by hand from `_archive/`. User accepted the loss.
- sep. 21, 2026 - **`layer` -> `hop` (D-11).** New `hop` column (root = 0); `LayerChangeCount` -> `HopChangeCount`; values unchanged.
- sep. 21, 2026 — **A stale `BLACKHOLE_ATTACKER_MAC` is NO LONGER a run-killer** — bookkeeping only.

## Rolled out of MEMORY.md — sep. 22, 2026 (room for the 0xB8 BSOD entry)
- sep. 21, 2026 — **`docs/data-and-results/EXPECTED-RESULTS.md` §0 = how to READ every number.** **NaN ≠ 0** (NaN = nothing
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
- sep. 23, 2026 — **AUDIT of groupmate `fac59c5`/`13b607c` (`docs/panel-answers/2026-09-23_LAYER-HOP-MAC-EXPLAINER.md`):
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
- sep. 23, 2026 — ⚠️ **`docs/packet-capture/WIRESHARK-GUIDE.md` had ROOT and a CHILD SWAPPED** — it listed
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
- sep. 24, 2026 — Rolled from MEMORY.md (fully written up in docs/attack-validation/ATTACK-VALIDATION.md): **Two conformance gaps, both now MEASURED and written up** in `docs/attack-validation/ATTACK-VALIDATION.md`: (a) the blackhole is a *placed* relay — it does not ATTRACT traffic by false route advertisement; (b) the wormhole duplicates arrivals but does **NOT** re-form parent selection (0 switches, r2 and r3). The paper's own functional naming (§4.2.1.2/4.2.1.3, Tables 4.6/4.7) already makes the defensible claim.
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
- (rolled from MEMORY.md sep. 25, 2026) sep. 23, 2026 — **`MESH_FORCE_HT20 1` (mesh_config.h): all boards now run 20 MHz, not the ESP32-default HT40.** Why: the M1 Mac
  Sniffer offers 20 MHz ONLY and can't decode 40 MHz data (real capture: beacons fine, root 0 / child 3 data frames). `apply_rf_width()`
  in mesh_setup.c sets it at wifi/mesh start and re-checks on connect. ⚠️ HT40 captures (all before this) ≠ HT20 — label, don't pool. SD report [6] now prints 'RF width: ...'. CSV schema + analysis untouched (verifier is same-run relative; no absolute RSSI cut-offs). Builds clean; NOT hardware-verified.
- (rolled from MEMORY.md sep. 25, 2026) sep. 24, 2026 — **`run_wizard.ps1` multi-laptop roster: "N boards need ports" warning was WRONG whenever the roster
  is split** (step 6 always added +1 for root even after the operator had just said root is on ANOTHER laptop — said
  "5 boards need ports" right after a "root not here" answer). Fixed: that warning only fires when NOT multi-laptop
  (root/children are only sorted into local-vs-remote per-board, in step 7's `Select-PortOrRemote`, which already
  handles it correctly). Also added 3 clarifying banners (root-remote confirmation, child-count multi-laptop example,
  one-time "you'll be asked per board" notice before step 7) — the child COUNT is always the FULL experiment across
  every laptop, never just this one's; per-board "is it here?" is what actually sorts local from remote.

- sep. 25, 2026 — **Power-cut/crash prevention:** root ROSTER GATE, reset reason + brownout/crash totals on card. Build-verified.

- sep. 23, 2026 — **AUDIT of groupmate `fac59c5`/`13b607c` (LAYER-HOP-MAC explainer): every load-bearing
  number FACT-CHECKED and CORRECT** — `MESH_ROOT_LAYER (1)` (re-verified in 5.5.4), `layer -1 → NaN`, SoftAP
  = STA+1 on all 4 values, attacker `recv 180/fwd 0/drop 180`, arrivals `301→0→121` vs `300→180→121`.
  No errors. Also: baseline FR is genuinely n=600 sd=0.000000 (the lone `FR>1` is a pre_baseline queue
  flush, EXCLUDED). Detail: ARCHIVE.md.
- sep. 23, 2026 — ⚠️ **`WIRESHARK-GUIDE.md` had ROOT and a CHILD SWAPPED** — listed `b0:cb:d8:f3:32:18` as
  ROOT; the real root is `70:4b:ca:25:b7:68` and `b0:cb…18` is the UPSTREAM child, so every "root" filter
  pointed at a child. Fixed + a one-liner to re-derive. Filter 4 is **attacker → its PARENT**, not "→ root".
  `simple_sniffer` DOES exist in 5.5.4. Detail: ARCHIVE.md.
- sep. 23, 2026 — **ROLE-GATE COVERAGE GUARD** (`features._warn_on_missing_attack_role`): manipulation
  features are gated on `node_role == "<attacker>"` behind `if mask.any()`, so a ZERO-row gate computes
  nothing and SAYS nothing — `ForwardingRatio` (PRIMARY) silently all-NaN. Now warns, naming roles present.
  Detail: ARCHIVE.md.
- sep. 25, 2026 — **Firmware: no boot-time `_archive/` move + `LOG_ONLY_DURING_RUN` + root PREPARE**; verify_topology NOT MEASURED for logs
  starting inside a phase (old data: identical output). NOT committed - the user pushes it.
- sep. 23, 2026 — **THE ROOT NAMES THE VICTIMS LIVE, DURING THE RUN** (`mesh_setup.c` EXPOSURE block):
  ATTACKER / VICTIM / "not in the attack path" per node, and **errors when NO node is downstream** — catches
  bad attacker placement BEFORE burning an 11-minute run. Console role `VICTIM`→`CHILD` (enum VALUE is on the
  wire, unchanged). `verify_topology.py` gained an EXPOSURE column. Detail: ARCHIVE.md.
- sep. 23, 2026 — **PHASE-SCHEDULE MISMATCH IS NO LONGER SILENT.** Host tools MEASURE phase durations from
  `phase_id` transitions — warn SHORT (preprocess slices baseline BACKWARDS, so a short firmware baseline
  labels formation noise BENIGN), note LONG (`jitter`). `--phase-durations` overrides. Detail: ARCHIVE.md.
- sep. 24, 2026 — **Xtensa `uint32_t` is `long unsigned int`**: `%u` on `PHASE_*_S + jit_*` broke the root build
  under `-Werror`. Cast to `(unsigned)` like `sd_status.c` (`cd7c212`).
- sep. 25, 2026 — **END_RUN reply found anywhere in a line** (it glued to log output; the "predates END_RUN" message was false),
  "already imported" over USB says node+repeat match / maybe OLDER run; importer no longer advises "reset it". Fake-serial tested.
- sep. 25, 2026 — minor, left as is: run_wizard.ps1 Get-BoardBuildDir adds `_cc` (Command Center) but run.ps1 never does - only mis-predicts warm/cold build time.

## Rolled from MEMORY.md (sep. 26, 2026; extended by the sep. 26 RETRY RATE entry)
- sep. 23, 2026 — **KEEP `RetryRate` in the blackhole signature; the stale comment was the only problem.**
  Its removal condition ("once retry_count means MAC-layer failure on every role") IS met — verified in
  `blackhole_victim.c:378-386`, F3 moved deliberate drops to `drop_count`. But that killed the LEAK, which is
  the argument for KEEPING it: the FAIL is now an honest clean negative, and Table 3.4's pre-registered
  prediction missing is a result to REPORT, not to delete. Dropping it would read as hiding a failed prediction.
- sep. 23, 2026 — **FIRMWARE ROLE `victim`→`child`.** ⚠️ `preprocess.py`'s `ROLE_ALIASES` folds BOTH
  spellings to canonical `child` at the ONE place `node_role` is made, so old captures still work;
  `features.py` gates on `CHILD_ROLE`, deliberately NOT both. Verified: only `node_role` changed, PDR
  unchanged (it sits behind the gate, so that IS the proof). ⚠️ **REFLASH.** Detail: ARCHIVE.md.
- sep. 25, 2026 (rolled from STATUS.md sep. 26) — **Wizard Data sync -> Delete: [a] ALL or [s] SOME files** with upload time (green <= 24 h, yellow older).

## Rolled from MEMORY.md (sep. 26, 2026; making room for the DATA SYNC PUSH/PULL colours entry)
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
- sep. 23, 2026 — **Tree positions are NOT hardcoded**: each node self-reports its parent MAC + role in its heartbeat;
  the root links them. Early prints show a PARTIAL tree (nodes report ~1 s apart) → a FALSE `NO NODE IS DOWNSTREAM` error.
  Fixed in `mesh_setup.c`: exposure verdict waits until heartbeat entries >= `esp_mesh_get_routing_table_size()`.
  ⚠️ sep. 24: a `NO NODE IS DOWNSTREAM` with ALL nodes reported (`REACHABLE` = `NODE COUNT`) is REAL, not this bug — LINEAR
  = 1 child/node, so chain order = JOIN order (+RSSI). Attacker must sit at `H01`: place it nearest the root, reset victims to rejoin.

## Rolled from MEMORY.md (sep. 26, 2026 pm, to hold the 200-line cap)
- sep. 23, 2026 — **BOARD DATES ARE NOW PHILIPPINE TIME (PHT, UTC+8)** — user's choice. `SD_CLOCK_TZ "PHT-8"` in
  `mesh_config.h`, set in `sd_status_seed_clock()`; stamps use `localtime_r`. Epoch (clock.txt/SET_TIME) stays true UTC.
  ALSO FIXED: the build stamp (PH wall clock) was read as UTC → 8 h in the future → every SET_TIME anchor lost to it
  (`card anchor is older than the build stamp`), so NO capture ever got a real date. Building outside UTC+8 breaks this.
- sep. 23, 2026 — **PANEL EVIDENCE for hop/`parent_mac` is ESPRESSIF'S OWN HEADER — cite it, not our code:**
  `#define MESH_ROOT_LAYER (1)` (`esp_mesh.h`, IDF v5.3.5) + the IDF MAC table ("Wi-Fi SoftAP: base_mac, +1 to
  the last octet") answer both "why hop = layer−1" and "why `parent_mac` matches no `node_id`" (SoftAP vs STA).
  Plain-language version (analogies, panel script, no code-reading required) written to
  `docs/panel-answers/2026-09-23_LAYER-HOP-MAC-EXPLAINER.md` — companion to `REVIEWER-QUESTIONS.md` §3/§7, not a replacement.
- (rolled from STATUS.md sep. 26) sep. 25 (eve) — **G402 5 pm run: node3 desynced -> unlabelled** (`phase_sync.py`); PDR PASS z -16.41, BLACKHOLE CONFIRMED 2/2 primary.
- (rolled from MEMORY.md sep. 26) sep. 23, 2026 — ⚠️ **`exposure.py` MUST use the ATTACK-WINDOW parent, not the whole-run mode.** node2 sat
  BELOW the attacker for its entire 671-window pre-baseline, then re-parented to the root. Whole-run mode is dominated by those rows and
  returns the ATTACKER as its parent — labelling a node whose PDR was 1.000 as `downstream`. **Never simplify `_dominant_parent()` to a plain mode.**
- (rolled from MEMORY.md sep. 26) sep. 23, 2026 — **`exposure` COLUMN: who the attack could actually reach** (`analysis/exposure.py`):
  `root`/`attacker`/`downstream` (the REAL victims)/`upstream`/`no_attacker`/`unknown`. Verified: `downstream` → attack PDR 0.0000,
  `upstream` → 1.0000. ⚠️ In `leakage.py` METADATA_COLUMNS.
- (rolled from STATUS.md sep. 26) sep. 25 (night) — **260-char build fix + all 15 variants BUILD OK** (9 new scenario builds, cold, 0 warnings); analyze.ps1 output fixed.
- (rolled from MEMORY.md sep. 26) sep. 23, 2026 — ⛔ **STALE-ROOT TERMINATE killed a run** (root table showed only itself). Root is flashed LAST, so
  the OLD root keeps running; its TERMINATE (`phase_id=4 root_ts=667 s`) is accepted by fresh children (seq starts at 0).
  Fix: `run_wizard.ps1` PARKS the root in its ROM bootloader (`esptool --after no_reset`, verified) before the first child, and
  WAKES it (hard reset + 10 s) just before its run.ps1 call. NOT an early erase: that would break run.ps1's SET_TIME (real clock).
- sep. 24, 2026 — **Root dashboard EXPORT column + `EXPORT :` line** ("ALL n BOARDS DONE - SAFE TO EXPORT").
  Uses the spare heartbeat `export_status` = `EXPORT_STATUS_LOG_CLOSED` (0x04) once `csv_logger_is_closed()`;
  children send 3 final beats 1 s apart then go quiet; root keeps LOG_CLOSED rows (no stale eviction) and its
  listener keeps running after TERMINATE (`phase_listener_keep_running_after_terminate`), ignoring late probes.
  Committed+pushed `5f4443b`. Needs a REFLASH of every board; old firmware stays "not yet".
- sep. 25, 2026 — **WIZARD: a preset board with NO port was silently treated as "on another laptop".** Angelo's G402
  run showed ROOT under "not plugged in" (blank label/COM), then "Boards on ANOTHER laptop", "nothing to flash here" -
  while [12] Identify read it fine on COM3. Cause: that laptop's preset file has ROOT with `Port: ""` (GitHub's
  `presets/Cal/...g402.json` is fine: node1/COM20/MAC - so `git pull` or re-save it). Port-less boards skipped BOTH the MAC
  match and the re-pick. Fix: preset path now asks per port-less board "plugged into THIS laptop? [y/N]" -> port picker.
  Also: the preset path's location.txt check ran on the preset's SAVED ports (before drift fix) and printed "All boards
  already report" after checking ZERO boards - it now runs once after the port fix and says UNVERIFIED if none read.

## Rolled from MEMORY.md (sep. 26, 2026 night, making room for the OPERATOR HOLD entry)

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

## Rolled from STATUS.md (sep. 26, 2026 night)

- sep. 26 — **RetryRate audit**: 0 in every labelled window (only pre-run/desynced fails); MAC back in correlation; baseline/attack views.
- (was Next step 7) ESP32 sniffer PASSED standalone (sep. 26, 0 loss). In-run option REMOVED (user): sniff a full run from a 2nd wizard window via VERIFY.

## Rolled from MEMORY.md — sep. 26, 2026 (cap)
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
- sep. 25, 2026 — **RUN LOGS: filed by run, viewable start-to-end, syncable.** Wizard saves to `run_logs/<attack>/<topology>/<location>/<scenario>/`
  (`Get-RunLogDir`; old flat logs list as NOT FILED); viewer pages the whole run, keep/archive (`run_logs/_archive/`, never pushed)/delete/push.
  `push_data.py --area logs`: `*.log` is ignored by the THESIS3 root .gitignore, so logs are listed like analysis (no staging). Data-sync submenu grouped. Scripted-stdin tested, NOT pushed live.

## Rolled from STATUS.md — sep. 26, 2026 (eve)
- sep. 26 (night) — (claimed) Operator hold: root waits for `GO` (refused if children missing / no victim below the attacker; `GO_ANYWAY` overrides). Wizard asks [Y/n]. NOTE: the user REVERTED this on purpose (sep. 26 eve) - not in the tree, do not rebuild.

## Rolled from MEMORY.md — sep. 26, 2026 (late)
- sep. 25, 2026 — **D-15 + DATA-DICTIONARY §2 rewrite.** `retry_count`/`tx_count` are APP-LAYER counters (no Wi-Fi driver stats read
  anywhere); paper Table 4.5 calls them MAC stats - re-describe in the paper, no re-capture. ⚠️ Wormhole Node B still writes its TUNNEL
  count into `retry_count` (Tunnel* features read it) - the one overload F3 did not remove. `leakage.py` reason TEXT is pre-C7 (code is fine).
- sep. 25, 2026 — **DATA SYNC DELETE / RESTORE** (`push_data.py delete|restore --area X`, wizard Data sync [9]/[10]): a delete is a normal
  commit, so history keeps it and restore puts back the exact bytes. Only files GitHub HAS can be deleted (keeps it undoable). Push SKIPS a
  file deleted on GitHub if local bytes match a past version (else it would undo the delete); pull/push OFFER (never auto, even --yes) to
  remove such local copies; differing copies always kept. Ledgers + archive/ moves excluded. Sim-tested on a local bare repo, not real GitHub.
  Later sep. 25: delete asks [a] ALL / [s] SOME (folders -> 'all' or numbers; Enter cancels everywhere) and shows each file's upload time
  (newest add/modify commit, `upload_times()`), GREEN <= `RECENT_MINUTES` 30 (was 24 h, sep. 26), YELLOW older (ANSI via Windows VT; age text too). Wizard only.

## Rolled from STATUS.md — sep. 26, 2026 (late)
- sep. 26 (pm) — **sep. 25 run audit + RetryRate NaN/pooling + verify_topology layer check**; chain linear by layers.

## Rolled from MEMORY.md — sep. 26, 2026 (to hold the 200-line cap)
- sep. 25, 2026 — **Build-dir 260-char limit FIXED in code** (Angelo's highload child failed: bootloader `.obj.d` = 262 chars; username
  with a space + `_highload`). run.ps1 / menu.ps1 / run_wizard.ps1 share `Get-SafeBuildDir`: a build dir > `$MaxBuildDirLen` 110 goes to
  `C:\esp32b\<repoTag>` (else `%LOCALAPPDATA%\esp32_builds\<repoTag>`, unchanged) - keep the 3 copies identical; wizard clean-build
  wipes both roots. Worst case after: 249 chars (156 variants x both laptops). Measured: Basti's laptop has `LongPathsEnabled=1` and
  built the same 262-char `.obj.d` fine with the OLD naming, so Angelo's is probably 0 - enabling it (admin) likely also works.
  Built the exact failing variant with new run.ps1 at Angelo's path length: OK. `build_all_variants.ps1` now also builds 9 scenario
  variants (burst/highload/jitter): all 15 BUILD OK (the 9 new built cold, 0 warnings). Also fixed: `analyze.ps1` swallowed ALL python output into the
  function return (`op_Addition` crash, verdict never shown) - now `| Out-Host` + PYTHONUTF8; eda PCA/correlation use
  `leakage.leaking_columns_for(df)` (post-C7 ForwardingRatio is a real multi-role feature) but keep ConsistencyScore out (= |FR-1|).
- sep. 25, 2026 — **ABORTED G402 files were NOT a power cut (first diagnosis WRONG, corrected same day).** Root arrivals show all 6 children
  sent probes through the whole run; the phase-255 files are LATER BOOTS. csv_logger_init archives the previous boot's files into `_archive/` on
  every boot and import_sdcard.py skips `_archive/` - so one restart after a run hides the real file. Tie children to the run by seq_num, not
  file times. validator FAIL + preprocess skip for no-experiment files stay (still correct); preprocess now WARNs when it keeps an older
  data file over a newer empty one (may be another session - node8's 13:41 file). OPEN: importer has no way to read `_archive/`.
- sep. 25, 2026 — **The 5 pm G402 capture (imported root boot 1235 = the right pair, 6618 rows):** root card holds 14 boots
  (1222-1235, all run 65) - boot 1233 died ~1 min before 1235, so 6 children sat 406 s in phase 0 (preprocess slices it right).
  NOT linear: node3 hung off the ATTACKER (2 children) - verify_topology FAIL. Attack real: root got 6 probes/s baseline, 1 (only
  node5, above the attacker) in attack, all back in cooldown. Before the next run: check no 2nd board runs ROOT firmware (sep. 23
  stale-root entry) and look at node3's board (20500DE70C80) alone - it is the only desynced node, twice.

## Rolled from STATUS.md "Recently done" — sep. 26, 2026
- sep. 26 (night) — **Data sync colours (latest SD import, same-run fix, 30 min)**; MAC in pre-build/run headers; run-flow sniffer prompt removed; preset spacing; Y/n keep prompt.

## Rolled from MEMORY.md — sep. 27, 2026 (cap, session summary)
- sep. 26, 2026 (eve) — **Standalone sniffer (wizard menu entry "ESP32 sniffer board", Idx 23, shown as [19]) now STARTS PAUSED**
  (user request): `tools/sniff.py --start-paused` (only that entry passes it; run-flow/Mac paths unchanged). Nothing is saved until P;
  banner + status line are bold YELLOW TEXT, no background (ANSI, VT enabled on Windows; plain text when redirected) "PRESS P TO START". The initial pause is
  logged in the .json like any pause. Tested with a fake serial board (start paused -> P -> pause -> resume -> Enter); wizard parse-checked, not run on hardware.
- sep. 26, 2026 (eve) — **Import progress bar fixed**: wizard ran the import with `2>&1` (held output until exit = "frozen", each `\r` a new
  line); now streamed live. `export_logs._render_progress`: final line only when stderr isn't a TTY; clamped to console width.
- sep. 25, 2026 (eve) — **PHASE-SYNC CHECK + G402 5 pm re-analysis.** NODE_20500DE70C80 (node3) ran the schedule ~110 s AHEAD of
  the root (105/296 probes sent in "attack" while the root was in baseline) - cause UNKNOWN (children have no local phase timer;
  suspect a 2nd root-firmware board). Same board flagged in the sep. 18 folder too. New `analysis/phase_sync.py`: sender's OWN send
  time = arrivals `timestamp_us - latency_us` (not a cross-clock join) vs the node's phase -> `validate_integrity.py` FAILs it,
  `preprocess.py` UNLABELS it (phase/label 255; rows kept so exposure's parent chain holds). PDR now PASS z -16.41, 2/2 primary.
  `features.py`: ParentSwitchRate / WINDOW_SECONDS (was / 0.9 s), edge switches counted, HopStabilityDuration = samples x 0.1 s.
  `eda.py`: time series = ForwardingRatio_5w + PDR + RootArrivals + ParentSwitchRate; stats by phase AND role; PCA z clipped +-5;
  overlay omits unlabelled nodes. Only G402/stationary re-analysed - other cells need a re-run. NOT committed.

## Rolled from STATUS.md "Recently done" — sep. 27, 2026
- sep. 26 (late) — **Wizard WIRESHARK category**: pick a capture + view -> Wireshark opens with columns, filter and I/O graph lines set (MACs read from the capture). Live view (item 26) not hardware-tested.
- sep. 26 (eve) — **Home 19:18 run audited = GOOD** (tree, CSVs, arrivals, sniffer pcap agree); **LatencyHopRatio/TunnelLatency seq-join fix**; **root post-export [1]/[2]/[3] + run.ps1 -Trim + no-child guard**.

## Rolled from MEMORY.md — sep. 27, 2026 (cap, Wireshark-menu session summary)
- sep. 26, 2026 — **Pre-build + run headers show each board's MAC** (`Format-BoardMacTag`; a shared build lists every board) + run.ps1 `Board:` (new
  DISPLAY-ONLY `run.ps1 -Mac`, passed by the wizard from the confirm table's `Resolve-BoardMac`). run.ps1 never reads it (a read resets the board).
  Preset picker: blank line after each preset block (none before a member heading - Show-Menu adds one).
- sep. 26, 2026 — **Run flow (wizard main [1]) NO LONGER asks "Packet capture for this run?"** (user: duplicate of VERIFY's sniffer
  entries). Only the call sites were removed; `Select-PacketCapture`/`Show-MacCaptureChecklist`/`Start-`/`Stop-SnifferCapture` stay in
  run_wizard.ps1, marked NOT CALLED — never committed anywhere, so deleting = unrecoverable. Sniff a run from a 2nd wizard window.

## Rolled from STATUS.md "Recently done" — sep. 27, 2026 (Wireshark-menu session)
- sep. 26 (night) — **21:11 vs 19:18 home comparison**: seq dedupe across root reboots, window-delta loss, KDE spike fixed.


## Rolled from MEMORY.md - sep. 27, 2026 (blackhole review session)
- sep. 26, 2026 (pm) — **G402 sep. 25 "topology FAIL" = node3's OWN REPORTS, not the tree; LINEAR IS enforced** (`MESH_TOPO_CHAIN` +
  `max_connection` 1; dashboard tree + STATUS are live heartbeats, only `TYPE :` is the build label). The 7 other boards' layers give a
  clean chain root-node5-ATTACKER-node7-node3-node6-node8-node2; node3 (20500DE70C80) claimed the attacker as parent at layer 5/6/11/12
  and a loop via node8. node3 is broken 3 ways: phases 112 s AHEAD (follows a source ~ the crashed root boot's schedule), SD file ends
  112 s early (681 vs seq 801 at root), and its counters break `seq = probes+retry+1` (drift -19..-5; every other board exactly +1).
  Its flash FAILED once on COM3 that day (retried, result not logged). 2nd problem: the ROOT REBOOTED ~20 s before boot 1235 (node5 lost
  parent 24 s) -> 406 s phase 0; labels still right (2100/1261/844 windows = 7 x 300/180/120) but Gate 2's re-routing flag counts it.
  Attack itself clean: attacker dropped 900 = 5 downstream x 180, root 6/s -> 1/s (node5) -> 100% cooldown. Fixed: RetryRate NaN when
  0 attempts (23% of windows; audit lift +0.06 from that NaN pattern), verify_attack ratio-of-sums RetryRate + ForwardingRatio on
  forward/recv (was own tx/probes; z -9.50 -> -6.38, still PASS), verify_topology parent-vs-layer diagnostic (no verdict change).

## Rolled from STATUS.md "Recently done" - sep. 27, 2026 (blackhole review)
- sep. 26 (late) - **Root phase banners show start time** (`@ 22:03:15 PHT`, "(est.)" if unsynced); console only, not data.

## Rolled from MEMORY.md - sep. 27, 2026 (archive PCAP/run_logs change)
- sep. 26, 2026 — **DATA SYNC PUSH/PULL LISTS: time + GREEN/YELLOW, anchored on your latest SD IMPORT** (user asked: in scenario 1 a push's
  pull-back listed teammates' sep. 24 leftovers and you couldn't tell new from old). One import batch = every card copied in ONE trip through
  Import SD card, up to N at "Import another card?" (menu.ps1: its single card). `tools/ImportBatch.ps1` snapshots `tools/exports/` at the
  start and, after each card, writes the new CSVs to `ESP32-Environment/.last_import_batch.json` (git-ignored, per laptop); the next import that
  copies a file REPLACES it = previous batch turns yellow. `push_data.py` `Freshness`: capture time = the `_YYYYMMDD_HHMMSS_` import stamp in
  the NAME (so a teammate's file is judged by when THEY imported it, not when pushed); GREEN = in your batch OR stamped >= batch start. No
  batch file / other areas (analysis, logs, presets) -> `RECENT_MINUTES` 30 rule (was 24 h; delete uses it too). Grouped by folder, newest first.
  SAME-RUN fix (user asked): a teammate's card imported <= `SAME_RUN_MINUTES` 30 BEFORE your batch is green iff same folder + same r<n> as a
  batch file AND a board your batch lacks (one file per board per run, so a duplicate board = a redo). No run id exists in the CSVs
  (headers have none), hence names. 12-case scratch test passed; not yet on live GitHub.
- sep. 30, 2026 — Rolled from MEMORY.md (cap):
- sep. 25, 2026 — **WHY IMPORTS SHOW TINY "STILL RUNNING" FILES (recurring since sep. 24): the board REBOOTED.** ONE USB port (power+data):
- sep. 25, 2026 — (rolled from MEMORY.md sep. 27) ROSTER GATE + RESET REASON (firmware): root waits after stabilise until EXPECTED_CHILDREN (routing table size - 1) are in the mesh for 5 s; run.ps1 -ExpectedChildren (always passed on root, 0 = off; wizard = local children + remote count it asks for on multi-laptop runs - plain remote children are NOT in the roster). START_ANYWAY on serial releases it. Every board writes its reset reason + Brownout/Crash resets (total) to status_*.txt and an 11th reset_reason column to runs.csv (importer reads it positionally).
- sep. 27, 2026 — (rolled from STATUS.md) 02:05 blackhole pcap verified linear + attack worked (attacker drop 180/180; node3 -> root 0 in phase 1); burst probes 100->300. Fix member_boards.json (20:38 attacker is stale, real = F4:18).
- sep. 26, 2026 - (rolled from MEMORY.md sep. 28; the sniffer is built, hardware-tested and documented in docs/packet-capture/WIRESHARK-GUIDE.md + FILEMAP - full original notes) - sep. 26, 2026 (night) — **Sniffer keep prompt is now `[Y/n]`** (`Confirm-KeepCapture`): only explicit n/no DELETES the .pcap+.json (no
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


### Rolled out of MEMORY.md sep. 28, 2026 (panel P1 leak + P6 validation framing, superseded by docs/)
- ⚠️ **Known leak (panel P1)** — role-gated features made "is this NaN?" a perfect label.
  ✅ **Root cause removed by C7 Option 1**; `leakage.py` now decides per dataset. ⚠️ PDR's 0.9987
  single-feature score is a SEPARATE problem and still open (see the sep. 20 entry).
- **Attack-validation framing (panel P6):** validate by *definitional conformance* (canonical criteria vs
  what we implement, failures declared), matching signature SHAPE not absolute values — so LEACH/AODV/RPL
  sources are valid and need not be ESP32-specific. **Now written up in `docs/attack-validation/ATTACK-VALIDATION.md`.**
- sep. 27, 2026 — (rolled from STATUS.md sep. 28) sep. 27 eve — **Real 802.11 retries from the sniffer** (`tools/pcap_retry.py`; no ESP-IDF counter exists) **joined into feature_table.csv as `MacRetryRate`/`MacFramesHeard`** (not a model input; NaN = not measured). Flat through the attack = Table 3.4 miss, independently observed. Open: wormhole fit.
- sep. 28, 2026 — (rolled from MEMORY.md gotchas) SD reader module VCC/format-specifier wiring & build gotchas — both fixed in code; full text ARCHIVE.md.
- sep. 28, 2026 — (rolled from STATUS.md) sep. 28 — **`MacRetryRate` recovered for runs whose console log lost its `Starting PHASE` lines** — phases + roles from the run's **own exported CSVs** (validated to 40 ms). Caught a real mis-pairing on the way — see the ⚠️ MEMORY entry. 23:39 refuses (its export is not under `datasets/`); 21:11 refuses (no attack step in its traffic).
- sep. 29, 2026 — (rolled from MEMORY.md gotchas) Non-ASCII in a Python tool's **module docstring** passed to `argparse(description=)` — cp1252 console ⇒ `--help` dies with `UnicodeEncodeError`. Keep them ASCII; `sys.stdout.reconfigure(encoding="utf-8")` first.

- sep. 26, 2026 — (rolled from MEMORY.md sep. 30) **Wizard WIRESHARK category** — full text:
- sep. 26, 2026 (late) — **Wizard WIRESHARK category** (user: "choose an option and it opens Wireshark"). Sniffer entries 21/22/23 moved
  OUT of VERIFY into it + NEW 24 *Open a capture - pick a view* (overview / one board / mesh data / retries / joins+leaves / weak links /
  BLACKHOLE attacker->parent / WORMHOLE B vs A), 25 *Open the NEWEST capture* (overview), 26 *ESP32 sniffer + watch LIVE*. MACs come
  from the CAPTURE, never a table: `check_pcap.py --map-json` = nodes + uplinks (TA->RA) + root_guess (a parent that never beaconed is
  still listed); attacker from mesh_config.h. Launch = `Wireshark -r <f> -Y <filter>` with `WIRESHARK_CONFIG_DIR=%APPDATA%\Wireshark-ThesisMesh`
  (RSSI/TA/RA/Seq/Retry columns, filter buttons, `io_graphs` rewritten per view). NOT a `-C` profile: tested, `-C` becomes the laptop's
  "last used profile" (Bas's NSCOM3 Wireshark would open in it). Filter sets NEED COMMAS (`{a, b}`; `{a b}` rejected for MACs). Find-Wireshark
  + sniff.py now read the App Paths registry (Bas's install is under S:\Main Programs\ - the live prompt was silently hidden). tshark IS
  installed, just not on PATH. Verified: every view's filter via tshark on the 3 PCAP files, a real launch + I/O graph screenshot, Default profile unchanged. Item 26 not hardware-tested.
- sep. 30, 2026 — (moved from MEMORY.md, fixed in firmware sep. 25) sep. 25, 2026 — **WHY IMPORTS SHOW TINY "STILL RUNNING" FILES (recurring since sep. 24): the board REBOOTED.** ONE USB port (power+data):
  powerbank->laptop, or the idf.py monitor->export handoff (toggles reset), power-cycles it; old firmware then moved the run's CSVs into
  `_archive/` at boot (LIST_SD + importer skip it) and opened a ~1 KB phase-255 file. After a power cut "started" = LAST SET_TIME anchor.
  **FIXED IN FIRMWARE (team decision, NEEDS REFLASH + one hardware test):** no archiving at boot (ARCHIVE_SD only), and
  `LOG_ONLY_DURING_RUN 1` = no rows until the root's PREPARE (sent every 5 s in stabilise + roster wait; rows stay phase 255 =
  paper's "Baseline Stabilization" kept) or phase 0-3; TERMINATE never opens it. Late joiner -> verify_topology NOT MEASURED.
  User chose: wizard never shows `_archive/`. Dashboard is NOT hardcoded (per-board heartbeat); "ALL n DONE" ignores evicted boards.
  Host: END_RUN reply matched anywhere in a line (old "predates END_RUN" msg was false); USB "already imported" = node+repeat only.
- sep. 30, 2026 — Rolled from STATUS.md Recently done:
- sep. 27 pm — **02:05 blackhole pcap verified linear + attack worked** (attacker drop 180/180; node3 -> root 0 in phase 1); burst probes 100->300. Fix `member_boards.json` (20:38 attacker is stale, real = F4:18).
- sep. 27 — **Data moved to `datasets/`** (5 folders + analysis output; 375 files hash-verified; all writers/readers repointed, code untouched).
- sep. 27 — **Wireshark view menu: ALL boards by default + MY boards submenu** (member's boards, side-by-side I/O lines); stub-tested, not opened in real Wireshark.

- ⚠️ **WORMHOLE's run-killer: the tunnel is a WIRED UART link, so its silent failure is a dead cable**
  (Tunnel* features empty, both boards look healthy). ⚠️ **Node B CANNOT detect it** —
  `uart_write_bytes()` succeeds into an unterminated line; only Node A can prove a frame crossed.
  Guard on A: `s_tunnel_received == 0` at terminate prints a TUNNEL CARRIED NOTHING banner.

- ⚠️⚠️ **RECURRING ROOT BOOT-LOOP — check the root's power BEFORE every capture.** Symptom: boot count
  climbing every ~2 s, `rst:0x3 (SW_RESET)`, UART garbled mid-line, always as the radio powers up. Cause:
  **power brownout, not firmware** — the ROOT runs softAP+STA (a child runs STA only) and its brownout
  detector sits at the most sensitive default. Fix: root DIRECTLY into a laptop USB port, never a shared
  hub; known-good short cable. RULED OUT: the `MESH_STACK_MAX_LAYER_CHAIN` change. If a CHILD loops too,
  it's the shared supply, not root dual-radio draw. Full diagnosis in ARCHIVE.md.
- sep. 30, 2026 — (rolled from STATUS.md Recently done) sep. 28 (night) — **Wizard main menu gained "MAC retry rate of a run"** (WIRESHARK group, last item; Exit moved up one number): pairs every capture, lists the usable runs newest-first, prints the per-link baseline/attack/cooldown table + how to read it. No board contact; scripted-stdin tested. Also fixed `pcap_retry.py`'s cache: it now notices when the exports it read are moved/changed (it still called r3 usable after r3's raw exports left the cell). **Data notes for the user:** raw r3 exports are gone from `exports\...\home\highload` (only `trimmed\` copies left; node5/node6 r3 also sit in `...\G402\highload\`), so r3 now has no retry data; the sep. 27 r2 exports are gone too; today's r2 mesh had a 7th board (`..:ed:80`, child of node2) with no export.
- sep. 30, 2026 — (rolled from STATUS.md Recently done) sep. 28 (pm) — **A saved preset can now be EDITED from the picker** (option [2]): cell (attack/topology/location/scenario/repeat) and roster (label/port/root/attack seat/scenario target, add, remove), written back to the same file, offered a rename when the cell changes, validated first so it can't save a preset the loader refuses. Fixed same day: validation wrongly required a LOCAL attacker/A/B/target and blocked Kyle's real preset (attacker is a teammate's board, never listed here) - now 0 just warns, matching ROOT's own rule; scenario-target picker gained the missing "on another laptop" escape. Touches no board. Scripted-stdin tested, not a live run. Also added a Replace-a-node option (swap in a different board, keeps the seat, clears the old MAC).
- sep. 30, 2026 — (rolled from STATUS.md Recently done, sep. 30 late) `docs/packet-capture/WIRESHARK-TERMS.md` (NEW) — the Wireshark vocabulary dictionary, so nobody searches YouTube mid-defense: the 3-layer answer to "what protocol does the ESP32 use?" (802.11 → ESP-WIFI-MESH → our probe protocol), every management frame explained (auth/assoc/deauth vs disassoc) + the 4 reason codes our own captures contain (5 = parent full, 3/8 = board left, 6 = stale link), RTS/CTS/ACK, LLC/SNAP/OUI, To DS direction, the `....R..T` flags string, radiotap, and a tshark-verified filter cheat card. All counts measured from our r2 sep. 28 capture. Also: `run_wizard.ps1` retry view now preloads phase-split I/O graph lines (baseline/attack/cooldown, data-frames-only) read from `pcap_retry.py`'s `_retry.json` — confirmed working in real Wireshark by the user.
- sep. 28, 2026 — **MAC retry report rewritten to be readable** (`pcap_retry.py report()`): full MAC on every board and link, a BOARDS table (hop/role/parent), each link as its own block with a plain verdict (WORSE / better / about the same / too few frames / 100% = unreliable), and a BOTTOM LINE; sep. 29: the original side-by-side RESULTS TABLE + its how-to-read restored (full MACs), and roles/MACs COLOUR-CODED to match `run_wizard.ps1`'s own palette (root gold, child teal, attacker pink; UNKNOWN/OUTSIDE plain) — own ANSI helpers, off when not a real console. Output only - CSV/JSON/features unchanged. Tested on the sep. 28 20:06 and sep. 27 18:36 captures.


## Rolled from STATUS.md "Recently done" - oct. 1, 2026 (Angelo's sep. 30 entries; all three are PUSHED, superseded in STATUS by the docs-reorg session)

- sep. 30 night (Angelo) — **Star blackhole redesigned: attacker = hub, victims firmware-pinned to it (D-16).** Firmware + topology checks + docs; builds clean, PUSHED, NOT hardware-tested. Details: MEMORY.md top.
- sep. 30 eve (Angelo) — partial_mesh G402 CONFIRMED 2/2. `verify_attack.py`: missing attacker → INCONCL (not a fake FR FAIL) + NFR footnote; `validate_integrity.py`: per-source blackhole check. PUSHED. linear/tree analysis restored + regenerated; ⚠️ linear/home/highload now INCONCLUSIVE (4 repeats pooled, noisy baseline — open); duplicate `linear/G402/burst` files deleted (5f9221c). Details: MEMORY.md top.
- sep. 30 (Angelo) — Merged origin/THESIS3. **Burst early-fire bug fixed in `victim_main.c` (REFLASH burst boards)**; sept30 G402 blackhole "burst" run moved to `G402/stationary` + re-analysed (CONFIRMED); `combine_all.py` repointed; attacker-only ForwardingRatio + NEW NeighbourForwardingRatio. PUSHED (d5fd89a, 7374bcf) — pull, then re-run `analyze.ps1` on your cells. Details: MEMORY.md top.

- I-017 recurring hazard: children left powered through a run's later phases overfill SPIFFS (~1.1 MB) and
  become unreadable on export → carry each child back UNPLUGGED; `board_check.py --port COMxx --wait 75`
  before a run (≥50% SPIFFS → wipe+flash first).

## STATUS.md snapshot replaced by the oct. 1, 2026 session summary
# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 1, 2026 - **REFLASH the ROOT and burst boards before the next run** (Angelo: burst early-fire + powercycle fixed in firmware, both PUSHED). — previously sep. 30, 2026 (latest) — **RetryRate is now a DATASET COLUMN ONLY — team-agreed, ✅ PUSHED as `ead0622`** (RetryRate lines only, built from HEAD; the rest of the backlog below is still local): out of `verify_attack.py`, EDA, separability audit and model inputs; the validator uses only paper-backed signatures. Verdicts unchanged on real captures. ⚠️ Open wormhole issue logged in MEMORY.md: `LatencyHopRatio` expects delay DOWN, Zhukabayeva measured UP — left as-is, never flip it. — previously sep. 30, 2026 — ✅⚠️ **HIGHLOAD COLLAPSE: CAUSE FOUND + THE TEST FOR IT IS NOW BUILT** (`RXSTALL` instrumentation in `root_node/main/root_main.c`, compiles clean, **uncommitted, NOT yet run on hardware** — flash the ROOT only, do a 7-board highload run, save the log, then `grep "\[RXSTALL\]"`; read it with the table in doc §12.6: `RXQ max` climbing toward 32 or `write max` in hundreds of ms = CONFIRMED, `RXQ max` 0-3 with µs writes = REFUTED). Cause found earlier this session — IT IS SOLVABLE, and the bug is in OUR code.** tshark + the boards' own exports show **the children never failed** (every node, hop 1 included, kept sending its own probes at the full 4/s and relaying steadily the whole run) while the **root's** reception fell 19.8→4.6/s: packets were sent, were on the air, and the root did not take them in. Cause: `esp_mesh_recv()` runs in ONE task (phase listener, prio 8) whose probe-sink callback does `esp_wifi_sta_get_rssi()` + SPIFFS `fputs` + **SD** `fputs` + a flush every 10 rows **inline per arriving probe** — ~20 arrivals/s blocks the only thread that drains the mesh RX queue, which is the **default 32** (`esp_mesh_set_xon_qsize()` never called here) → ESP-MESH flow-control throttles the children. Fits every previously-unexplained fact (attack-independent, needs 7×highload, worsens over time, `send_fail`=0 because sends BLOCK, never fail). ❌ **Two of my earlier claims are now CORRECTED: airtime/shared-channel saturation is DISPROVED** (peak only ~278 frames/s ≈192 kbps; traffic *falls* during the collapse) **and §10.4's "root→hop-1 surge" was misread** (6× not 13-20×, retries flat → a symptom, not a cause). **FIX (not applied):** move the file I/O out of the receive path onto a queue + lower-prio writer task (the split `probe_relay.c` already uses); `esp_mesh_set_xon_qsize(64…128)`; instrument first. ⚠️ **Until fixed, 7-board highload root-side arrival data measures the root's LOGGING, not the mesh** — victims' attack PDR 0.000 still stands (attacker's own counters prove it). Doc: **§12** of `docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` (supersedes §10.4 + §11.2). — previously sep. 30, 2026 (docs reorg) — **`ESP32-Environment/docs/` is now filed by TOPIC** — 13 folders, one per thing an adviser/panelist can ask about (`blackhole/`, `wormhole/`, `attack-validation/`, `highload-collapse/`, `dataset-integrity/`, `data-and-results/`, `packet-capture/`, `panel-answers/`, `issues-and-fixes/`, `deviations-limitations/`, `progress-reports/`, `operations/`, `references/`; `_archive/` left untouched). **No doc's contents were edited — only locations**, moved with `git mv` so history follows. NEW **`docs/README.md`** = the index: which folder answers which panel question. `docs/runbooks/`, `docs/issue_logs/` and `docs/Implementation Issues/` no longer exist. Every reference repointed — 99 rewrites in 49 files (this file, MEMORY/FILEMAP/CLAUDE, docs cross-links, `tools/*.py`, `analysis/*`, firmware comments, `run_wizard.ps1`, `Setups/`); a full-tree sweep finds **0 dead links from the move** (26 dead links remain tree-wide, all pre-existing and unrelated). — previously sep. 30, 2026 (late, cont'd) — **`COOLDOWN-RECOVERY-2026-09-30.md` §11 (NEW)**: `jitter` cannot cause the highload collapse (root-only timing randomiser, never touches probe rate — and it was missing from `memory/run-scenarios-2026-09.md`, now added). §11.2 = congestion-mitigation candidates read out of `probe_relay.c`: `RELAY_QUEUE_SIZE` 128 is a bandage (⚠️ any run logging "Relay queue full" has a contaminated `drop_count` — grep past runs), priorities already correct, `esp_mesh_send()` blocks with no `MESH_DATA_NONBLOCK` (candidate cause of §4's slow forwards), mesh-stack queue Kconfig unconfirmed (never overridden in either sdkconfig), and the ceiling nothing fixes: **all 7 boards share one 2.4 GHz channel** → favours a tree (§10.7) over constant-tweaking. Discussion only, nothing built/tested. — previously sep. 30, 2026 (late) — **NEW `docs/packet-capture/WIRESHARK-TERMS.md`**: the Wireshark vocabulary dictionary (deauth vs disassoc + reason codes, RTS/CTS/ACK, LLC/SNAP/OUI, To DS, flags string, the 3-layer "what protocol does the ESP32 use?" answer, tshark-verified filter cheat card) — built for adviser/panel questions about the capture screen; wizard retry view also preloads phase-split I/O graph lines now. — previously sep. 30, 2026 (later) — ⚠️⚠️ **7-board HIGHLOAD collapses with NO attack at all** (no-attack run sep. 30 02:40 recovers 51%, same as r3) — **the blackhole is not the cause.** r4 = perfect attack but collapse began mid-attack, recovery 23% → **r4 gate FAILS.** Storage-fill theory ruled out. Doc: `COOLDOWN-RECOVERY-2026-09-30.md` **§10**. Also this session (uncommitted, see below): run log `_r<N>`, `_retry.csv` repeat column, import colouring, preset **Copy** option. — previously sep. 30, 2026 — ⚠️ **r3 (7 nodes) verification diagnosed: the ATTACK IS PERFECT, the COOLDOWN is what fails.** `verify_attack.py` pools cooldown into the "normal" baseline, so both primaries were EXCLUDED; drop those rows and r3 is CONFIRMED (z −10.88 / −21.06). **Not the retry rate.** Cooldown recovery: 4 nodes 100% → 6 nodes 70% → 7 nodes 51%. **Diagnosis only — nothing changed.** Study: [`ESP32-Environment/docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md`](ESP32-Environment/docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md). — previously sep. 29, 2026 (**MAC retry report now readable + colour-coded by role** (root/child/attacker, matches the wizard's own palette) — **`MacRetryRate` now fills for 5 of 7 captures — phase times fall back to the run's own exported CSVs when the console log lost them; ⚠️ repeat number alone does NOT identify a run**) — **ALL DATA NOW UNDER `ESP32-Environment/datasets/`** (code stayed; originals NOT yet deleted); Wireshark view menu now defaults to ALL boards + a MY boards submenu; **file/folder names now use a readable stamp `sept27_0311AM` (old files unchanged, tools read both; Angelo must pull CODE before he gets new-format files)**. **Preset picker option [2] now EDITS a saved preset in place (cell + roster) and can rename it to match; a save no longer requires a local attacker/A/B/target — 0 just warns (a teammate's laptop can hold it).** **Next: user deletes originals, reviews + COMMITS/PUSHES, then Angelo `git pull`s.**

## ⚠️ Working copies
Angelo: `A:\Angelo\Excelsior\THESIS\T`. Basti: `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3`. Both clone GitHub branch `THESIS3` — `git pull` before editing; old `NIS16-ESP32-Environment` = backup only.

## ⚠️ DATA LAYOUT CHANGED sep. 27 (details: MEMORY.md top entry)
`datasets/exports` (was tools/exports) · `datasets/analysis` (CSV/PNG output; `analysis/` keeps only the .py code) · `datasets/archive` · `datasets/PCAP` · `datasets/run_logs`. Every script/tool writes there now. FILEMAP.md updated sep. 30; **guides still show OLD paths (user fixes docs later) — trust the code.**

## ⚠️ UNCOMMITTED on Basti's laptop (sep. 25–27 sessions — the user pushes; details in MEMORY.md, top entries)
- **Sep. 27 data move:** `datasets/` (new), `.gitattributes`, `.gitignore`, `.vscode/settings.json`, `run_wizard/run/menu/analyze/archive.ps1`, `tools/ImportBatch.ps1`, `tools/{export_logs,import_sdcard,run_matrix,verify_topology,validate_integrity,inventory_cells,sniff,push_data,feature_separability}.py`, `slides/refresh_slide_numbers.py`. Stage `.gitattributes` in the SAME commit as the moved CSVs.
- **Sep. 26 late:** `root_node/main/root_main.c` (phase banner wall-clock time; needs root reflash to show).
- **Night session:** `phase_listener.h/.c` (session_id), `analysis/preprocess.py`, `analysis/eda.py`, `analysis/column_legend.py`, regenerated home/stationary output (now under datasets/analysis).
- **Eve session:** `analysis/features.py`, `run.ps1` (`-Trim` + no-child guard), `run_wizard.ps1` (root post-export question), `docs/deviations-limitations/thesis-deviate.md`.
- Sniffer/WIRESHARK (+ sep. 27 ALL/MY-boards view menu, `run_wizard.ps1` only): `sniffer_node/`, `tools/sniff.py`, `tools/check_pcap.py`, `docs/packet-capture/WIRESHARK-GUIDE.md`, `docs/packet-capture/WIRESHARK-QUICKSTART.md` (NEW). Analysis: `analysis/phase_sync.py` (NEW), `leakage.py`, `verify_attack.py`, docs DATA-DICTIONARY + EXPECTED-RESULTS. Build: `build_all_variants.ps1`. Data sync: `tools/ImportBatch.ps1` (NEW).
- **Sep. 27 pm:** `archive.ps1` + `run_wizard.ps1` archive now moves PCAP + run_logs too. `mesh_config.h` BURST_COUNT 100->300 (+ text in run_wizard/menu/run.ps1, memory/run-scenarios; not built) - it is the OWNER's file, review. NOT mine: `presets/Bas/linear-blackhole-highload-g402.json`. Someone else edited `run_wizard.ps1` on sep. 27 00:16 (+~52 lines) mid-session — review it too. **Readable stamp (sep. 27 pm):** NEW `tools/name_stamp.py` + `test_name_stamp.py`; edited `tools/{export_logs,import_sdcard,sniff,push_data,trim_run,validate_integrity,audit_dataset,inventory_cells}.py`, `tools/README.md`, `analysis/preprocess.py`, `run_wizard/menu/archive.ps1` (not tested with a real capture/import/archive; `audit_dataset.py` crash 'No objects to concatenate' is pre-existing). **Sep. 27 eve + sep. 28:** NEW `tools/pcap_retry.py` (+ export-CSV phase fallback); `analysis/features.py` + `column_legend.py` (MacRetryRate join); `thesis-deviate.md` D-15, `DATA-DICTIONARY.md`, `FILEMAP.md` row. `datasets/PCAP/**/*_retry.csv/.json` are generated (PCAP is git-ignored). **Sep. 28 pm:** `run_wizard.ps1` preset-picker EDIT option (`Edit-PresetInteractive`; harness-tested only, no live wizard run). **Sep. 28 night:** `run_wizard.ps1` (`Invoke-MacRetryReport`, main-menu modeIdx 27), `tools/pcap_retry.py` (export-aware cache). **Sep. 28 late:** `tools/pcap_retry.py` `report()` rewrite + `run_wizard.ps1` "How to read this" trimmed. **Sep. 29:** `tools/pcap_retry.py` role colour-coding (own ANSI helpers, `ljust_visible` for padding). **Sep. 30 (details: MEMORY.md top entries):** `run_wizard.ps1` (run log `_r<N>` name, green "imported this session" ports/drives, preset menu **[7] Copy this preset** — options after it shifted +1), `tools/pcap_retry.py` (`repeat` column in `_retry.csv`), `docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` §10. Parse-/harness-tested only, no live wizard run. **Sep. 30 (late):** NEW `docs/packet-capture/WIRESHARK-TERMS.md` + its `FILEMAP.md` row; `run_wizard.ps1` phase-split I/O graph lines (`Get-PcapPhaseSegments`/`Format-WsTime`, `-Path` threaded into `Get-PcapScopedView`) — **this one the user confirmed working in real Wireshark**; doc's filters tshark-verified. **Sep. 30 (latest):** `root_node/main/root_main.c` — `RXSTALL` TEMPORARY instrumentation in `probe_data_cb()` (times the arrival write, samples `esp_mesh_get_rx_pending()`, one `ESP_LOGW` per 200 probes); measures only, no behaviour change, ✅ compiles on local IDF 5.3.5 (`sdkconfig`/`dependencies.lock` reverted after). Deliberately NOT a `D-` number (not a deviation; D-15 is still the last). Docs: `COOLDOWN-RECOVERY-2026-09-30.md` §12 + §12.6, `memory/run-scenarios-2026-09.md` jitter entry. **Sep. 30 (docs reorg):** every file under `ESP32-Environment/docs/` moved into topic folders (`git mv`, contents untouched) + NEW `docs/README.md`; path-only link repoints in `FILEMAP.md`, `CLAUDE.md`, `MEMORY.md`, `STATUS.md`, `ARCHIVE.md`, `Setups/*.md`, `docs/**`, `tools/{audit_dataset,feature_separability,validate_integrity,verify_attack,verify_topology}.py`, `tools/README.md`, `analysis/{column_legend,eda,leakage}.py` + `analysis_README*.md` + `ANALYSIS-Commands.md`, `child_node/main/blackhole_victim.c`, `components/mesh_common/include/csv_logger.h`, `sniffer_node/CMakeLists.txt`, `run_wizard.ps1`, `memory/dataset-audit-2026-09-18.md` — no logic touched. **Sep. 30 (RetryRate scope): ✅ pushed as `ead0622`** — what still shows as modified in those files is the older backlog, not RetryRate.

## Next step
0. **Delete the old data folders** (verified identical copies are in `datasets/`), from `ESP32-Environment`: `Remove-Item -Recurse -Force archive, PCAP, run_logs, tools\exports, analysis\baseline, analysis\blackhole, analysis\wormhole`. Then commit; tell Angelo to pull CODE before his next data push/pull (GitHub paths moved).
1. ⚠️ **REFLASH EVERY BOARD before the next capture** (phase message 17->21 B + root banner time). Then hardware-test: reboot the root mid-stabilise -> children print "Root RESTARTED" and log 255 until the new Phase 0.
2. First real run on the new layout: confirm export/import/sniffer/run log land in `datasets/…` and push/pull finds them. Open its pcap via the new MY boards submenu in real Wireshark once.
3. **Re-run analysis on every OTHER cell** (`analyze.ps1 -All -Verify`): LatencyHopRatio, ParentSwitchRate/HopStability, phase-sync, correlation views changed. Only blackhole/linear/home/stationary is current.
4. Home cell holds the 21:11 run; the GOOD 19:18 run is in `datasets/archive/2026-09-26_tested-4-nodes-at-home-/`; both r1 — rename one before pooling.
5. Docs pass (user, later): FILEMAP.md, WIRESHARK-GUIDE, tools/README, MEMBER-HOWTO, OUTPUT-VERIFICATION -> `datasets/` paths.
6. ⚠️ **HIGHLOAD — RUN THE TEST (doc §12.6):** flash the ROOT with the `RXSTALL` build, do a 7-board highload run with the run log saved, `grep "\[RXSTALL\]"`, read against §12.6's table. CONFIRMED → §12.5 item 2 (move arrival logging off the mesh-receive path onto a queue + lower-prio writer task). REFUTED → re-open; next suspects are the phase-listener task's other work and ESP-MESH internal scheduling. Then remove the temporary instrumentation.
7. ⚠️ ROOT COVERAGE ≥95% still to re-measure (`validate_integrity.py`). Then the campaign (`inventory_cells.py --plan`). Watch node3 (20500DE70C80).

## Blockers / open questions
- ⚠️ **PDR (0.9991) and LatencyHopRatio (0.9987) are single-feature perfect** — both exist only outside the attack. Open, needs a framing decision.
- ⛔⛔ **Boards DIRECT into the laptop, never dock/hub** (BSOD 0xB8). Verify root power. Never pull an SD card mid-run.
- Sniffer: **P pauses saving** — check the .json `pauses` before using a pcap. Run logs hold only wizard text, not board serial output.
- ⚠️ HT20 (D-14): HT40 captures (before sep. 23) ≠ HT20 — label, don't pool. ⛔ D-12 vs the signed Milestone Form — adviser decision.
- ⚠️ PAPER behind the code: 10 Hz / 1 s is CORRECT (keep); Tables 4.4/4.10 + §4.2.4.1 say 1 Hz / 5 s; Table 4.5 -> D-15; RetryRate = dataset column only since sep. 30 — drop it from §4.2.6's plot list + Table 3.4's signatures (D-15 "Scope decision").

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 30 (docs reorg) — **`docs/` reorganized by topic for defense prep** (user's ask: be able to answer a panelist "specifically and not out of place"). 13 topic folders, `docs/README.md` written as the question→folder index, 99 link rewrites across 49 files, dead-link sweep clean. Contents of every moved doc are byte-identical — only paths changed. Not committed.
- sep. 30 (late, cont'd) — **§11 added to `COOLDOWN-RECOVERY-2026-09-30.md`**: `jitter` scenario documented (was missing) and confirmed unrelated to the highload collapse (root-only timing randomiser, no probe-rate change); `probe_relay.c` read for congestion-mitigation candidates (queue size, task priority, `esp_mesh_send()` blocking, unconfirmed mesh-stack Kconfig queue size, the shared-channel ceiling) — discussion only, nothing built or tested. `memory/run-scenarios-2026-09.md` gained the missing jitter entry.
- sep. 30 — **Dataset investigation + wizard additions.** Compared every current-firmware run: 7-board highload collapses with or without the attacker (no-attack run recovers 51%, r4 23%), storage-fill theory ruled out, captures show a root→hop-1 frame surge at the break; written up as §10 of `COOLDOWN-RECOVERY-2026-09-30.md`. Wizard: run logs carry `_r<N>`, imported ports/drives turn green, preset menu can **Copy** a preset then edit the copy. `_retry.csv` has a `repeat` column. Harness-tested, no live run.

- Attack/traffic parameters are compile-time constants: drop rate 100% (`blackhole_victim.c`), `PROBE_INTERVAL_MS 1000`, `SAMPLING_INTERVAL_MS 100`, phases 60/300/180/120 s = 11 min (`mesh_config.h`). `run.ps1` exposes topology/role but **no attack-intensity flags**, so r1/r2/r3 still differ only in RF noise — the panel's 12:45-16:00 objection, unanswered. ✅ **Attacker POSITION is the one exception since F2**: it is a runtime NVS value now, no re-flash. Full pre-F2 text in ARCHIVE.md.

- ⚠️ **Known circularity (panel P6):** the blackhole attacker counts its OWN drops — the evidence the attack occurred comes from the node performing it. Needs an independent observer (sniffer node / monitor-mode adapter) or root-side accounting.

- ⚠️ **Known leak (panel P1)** — role-gated features made "is this NaN?" a perfect label; ✅ root cause removed by C7 Option 1 (`leakage.py` now decides per dataset). ⚠️ PDR's 0.9987 single-feature score is SEPARATE and still open (sep. 20 entry). Panel-P6 attack-validation framing (definitional conformance, signature SHAPE not values): `docs/attack-validation/ATTACK-VALIDATION.md`, full text ARCHIVE.md.

## Rolled from MEMORY.md — oct. 1, 2026 (cap)
- Thesis: DLSU CCS, CTTHES2/THES3. Proponents: Calpoporo, Carlos, Ong, Reinante. Adviser: Cu, Gregory G.
- Toolchain: ESP-IDF **v5.3.5** (bundles Python 3.11 + compiler); boards enumerate as "Silicon Labs CP210x USB to UART Bridge"; Windows reassigns COM numbers every plug — always re-check.
- **THESIS 3 DRIVER — `Paper/Improvements.pdf`** (CTTHES2 panel comments, ~aug. 2026). 8 timestamped rows
  → 7 problems: single-feature decidability, no attack parameter variation, redundant r1–r3, one
  environment, no declared IoT scenario, no attack provenance, uncharacterised benign baseline. Plan:
  `Plan/THESIS3-PANEL-PLAN.md`. Attack-provenance answer is DONE: `docs/attack-validation/ATTACK-VALIDATION.md`.

## STATUS.md snapshot replaced by the oct. 1, 2026 (evening) session summary
**Updated:** oct. 1, 2026 (Angelo, session summary) — **GitHub `THESIS3` = `3891315`, everything pushed, laptop in sync.** Previous STATUS archived in ARCHIVE.md (bottom). Facts + reasons: MEMORY.md top ~15 entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; docs filed by topic (`docs/README.md`). PCAP + run logs are git-ignored (local only). Backup tag of Angelo's work: `backup/angelo-2026-10-01`.

## Where things stand
- **Star + blackhole = attacker is the HUB (D-16), WORKS ON HARDWARE.** `star/G402/stationary` r1 is now the oct01 2 PM run (6 victims, all gates PASS/CONFIRMED) - replaced the 12:24 run (5 victims; archived locally). Star BURST still NOT captured: 2 attempts failed from a firmware bug (fixed oct. 1, untested on hardware).
- **node8 (`F4:2D:C9:73:E6:18`)** telemetry lost from its board: 6 victims, 5 with telemetry. Data unchanged — state it in the write-up.
- **Wizard builds the picked attacker MAC into every blackhole board** (`run.ps1 -AttackerMac`), so `mesh_config.h` no longer decides it. Victims-only laptops get a numbered list of known attackers (newest real run first) PLUS every other known board (to pick a NEW attacker) — type the number.
- Multi-laptop: no crash on a missing burst target (asks y/N); root must be told the TOTAL child count across laptops.
- **Campaign:** 5/144 done (G402: linear/tree/partial/star stationary; home linear burst). Verifier matrix over all 33 runs: 0 crashes, every verdict correct.
- Basti's 7 commits merged + audited: nothing broken (15/15 firmware variants + wormhole root + sniffer build clean, analysis values identical).

## Next step
1. **Everyone `git pull`, then REFLASH via the wizard** (firmware changed: attacker-MAC build flag, Basti's RXSTALL/heartbeat tree). Every laptop picks the SAME attacker.
2. **Re-run star G402 BURST** — burst firmware bug FIXED oct. 1 (victim never opened the window on attack runs). `git pull` + REFLASH the target victim; exactly ONE laptop's plan shows `<< burst TARGET`. Afterwards the analysis prints `burst : FIRED`. Basti/Kyle: delete local `exports/blackhole/star/G402/burst/` first.
3. **Basti: delete local copies** of `linear/G402/burst` + `linear/G402/highload` (`push_data.py delete-local --area exports`) — his push re-added them once already (re-deleted in `ff8059f`).
4. **Highload collapse FIX built (oct. 1, untested):** root writes arrivals from a queue, not the receive task. `git pull`, REFLASH THE ROOT, run 7-board highload, save the run log: `[RXSTALL] … dropped 0` + arrivals ~20/s through cooldown = fixed (doc §13). Old highload r2/r3 baselines stay broken.
5. **First wormhole run on current firmware** (last hardware-confirmed: Jul 20). Pre-flight passed: all 4 wormhole builds clean, analysis tested on archived runs. Test the UART cable with `uart_link_test` first; Node A's end-of-run "TUNNEL CARRIED NOTHING" banner = unusable run.
6. Not yet captured anywhere: jitter, mobility, powercycle scenarios.
7. Paper: §4.2.2.1 / Fig. 4.17 → "hub is the attacker, root one hop behind" (D-16 + framing sentence in `memory/star-hub-forcing-2026-10.md`).

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself (the code folder was deleted once on oct. 1; restored from git).
- ⚠️ Checklist "analysis older than capture" after a `git pull` = file-time false alarm → re-run `analyze.ps1` for that cell.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing decision). LatencyHopRatio direction vs Zhukabayeva — leave as-is.
- ⚠️ HT20 vs HT40 captures don't pool (D-14). D-12 vs the signed Milestone Form — adviser decision.
- `Bas/linear-blackhole-stationary-g402.json` holds STAR/BURST content (name mismatch) — deliberately not pushed; Basti to fix.
- Uncommitted on Angelo's laptop, on purpose: `mesh_config.h` attacker line, `sdkconfig` ×2, `dependencies.lock`, 4 re-saved presets, staged `tools/exports/run_ledger.csv` deletion.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- oct. 1 — Star hub proven on hardware; attacker MAC from the wizard (+ known-attacker list); split-preset fixes; star run moved burst→stationary; Basti's merge audited; verifier matrix 33/33; wormhole pre-flight; `trim_run` cross-drive fix.
- sep. 30 — Star+blackhole hub designed (D-16); verifier/validator fixes (missing attacker → INCONCL, per-source drop check); duplicate/incomplete linear G402 data removed; G402 partial_mesh + tree runs completed on GitHub.
- sep. 30 — Docs reorganized by topic (Basti); highload collapse cause found + RXSTALL instrumentation (Basti).


## Rolled from STATUS (oct. 1, 2026 night)
- sep. 30 — Star+blackhole hub designed (D-16); verifier fixes; G402 partial_mesh + tree runs completed.

## Rolled from MEMORY (oct. 1, 2026 night)
- sep. 24, 2026 — **Basti's laptop git identity is `xMiguelCarlosx`** — commits "by Miguel" from this clone are
  the user (VS Code auto-sync also runs `pull --autostash` mid-session). `PCAP/` + `*.pcap` git-ignored: a 120 MB
  Mac capture exceeds GitHub's 100 MB cap and blocked every push until removed from history.

## Rolled from MEMORY (oct. 1, 2026 night, Basti)
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

## Rolled from STATUS (oct. 1, 2026 night, Basti)
- Hardcode audit DONE + pushed: IDF `%d` bug, phase constants from mesh_config.h (`tools/mesh_constants.py`), stale firmware nickname table removed (`Board-XX:YY`), board_check/run_matrix no hardcoded MACs/COMs, `.mcp.json` untracked. Firmware nickname change shows after the next reflash.
- oct. 1 — Star hub proven on hardware; attacker MAC from the wizard; split-preset fixes; Basti's merge audited; verifier matrix 33/33; wormhole pre-flight.
- Wizard: scenario-TARGET prompts show `plugged in`/`NOT PRESENT` + a 'Detect ports' option (pushed, not yet used on real boards). Attacker picker lists every known board.

## Rolled from STATUS (oct. 2, 2026, Basti)
- oct. 1 (eve) — Burst firmware bug found + fixed; highload root fix; verify_burst + wizard burst checks; star stationary replaced by 2 PM run; burst duplicates removed twice.
- oct. 1, 2026 — (night) linear/G402/jitter fully verified (rebuild = identical, all gates PASS, jitter fired); EDA PCA/t-SNE lost-attack-class bug fixed; wizard target prompt shows port status + Detect ports.
## Rolled from MEMORY (oct. 1, 2026 night, 2)
- oct. 1, 2026 night (Angelo) — **Git state after the hardcode-audit push (`44a9672`, merge `f1e340f`):** Basti's `589af2d` 'pushed dataset 2PM and 3PM oct 1' RE-ADDED the 3 star/G402/burst duplicates (3rd time; removed in 5f9221c-era, 4a00a3b) plus `skills/verify/SKILL.md`; it reached this laptop via a merge `ffe25a5` (VS Code auto-sync pulls mid-session). On Angelo's laptop those 3 files are deleted in the working tree with the deletion STAGED - not done by Claude, left uncommitted pending the user. Pull was blocked by staged files: 7 partial_mesh/G402/jitter CSVs staged locally were byte-identical to Basti's/ongky's pushes (moved aside, pulled, verified SAME); the staged star deletion was unstaged for the merge and re-staged after. Lesson: before pulling, `git diff --cached --stat` - git merge refuses with ANY staged change on a path the merge touches.

## STATUS superseded oct. 2, 2026 (Angelo session summary)
# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 2, 2026 (Basti) — analysis progress bars added. **Uncommitted on Basti's laptop: `tools/import_sdcard.py` + `run_wizard.ps1` (only the hunk at ~2097 is that session's) + wormhole/tree/G402 data + `analysis/{progress,preprocess,features,eda}.py` (progress bars).** Facts + reasons: MEMORY.md top entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored (local only). Backup tag: `backup/angelo-2026-10-01`. Live board roster (editable, all 3 laptops): https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh (wizard still reads member_boards.json).

## Where things stand
- **TWO FIRMWARE FIXES pushed, both BUILT CLEAN but NOT YET RUN ON HARDWARE:**
  - **Burst** (`6b90df5`): burst never fired on ANY attack run (victim_main.c never got ACTIVE_ATTACK, so it waited for a baseline-only signal). Window now opens at run time.
  - **Highload root overwhelm** (`cb22106`): root wrote arrivals inside its mesh receive task, the RX queue filled, the mesh throttled all children (20/s fell to 3-7/s). Now a queue + separate writer task; root RX queue 64.
- **Burst can't fail silently any more:** `tools/verify_burst.py`; `analyze.ps1` prints `burst : FIRED|NOT FIRED`; wizard blocks a burst target on the attacker and names the sender in the plan.
- **star/G402/stationary r1 = the oct01 2 PM run** (6 victims, integrity/topology PASS, BLACKHOLE CONFIRMED, sniffer paired). Old 12:24 run archived locally (`archive/2026-10-01_star-G402-stationary-replaced/`). star/G402/burst NOT captured yet.
- **linear/G402/jitter r1 ANALYZED + CHECKED (oct. 1 night): integrity 9/9, topology linear OK, BLACKHOLE CONFIRMED 2/2, jitter fired (312.5/190.5 s), pcap PASS.** Root's 2 files now pushed. Full re-verify: analysis rebuilt = identical. EDA PCA/t-SNE bug fixed (attack class was missing; jitter + star stationary plots regenerated). Open: preprocess drops jitter's extra baseline (MEMORY).
- **WORMHOLE TUNNEL WORKS on current firmware (oct. 1 ~16:51, tree/G402):** 180 tunnelled = 180 re-injected = 180 root duplicates, all in phase 2. But the mesh went FLAT (all 7 under root) -> NOT a valid tree run; a child was also unplugged mid-baseline. Files sit in `exports/wormhole/tree/G402/stationary/` (9) — keep as tunnel proof, not a dataset entry. **SD-import bug fixed** (untested on a real board): wormhole controls run plain firmware and were filed under `baseline/`; the importer now files by the rows' phase; all 5 misfiled control CSVs moved to wormhole/ (4 staged via git mv).
- Campaign (live checklist): **7/144** - G402 linear/tree/partial/star stationary, linear+partial jitter; home linear burst. Checklist staleness now content-based, table aligned (pushed). NEW (Kyle 17:18, pulled): baseline/tree/G402/stationary - only Kyle's 4 children so far; root + Basti's/Cal's boards still to push.

## Next step
1. **Everyone `git pull` + REFLASH** (both firmware fixes). Every laptop picks the SAME attacker.
2. **Re-run star G402 BURST:** exactly ONE laptop's plan shows a victim `<< burst TARGET`. Analysis must print `burst : FIRED` (= burst fix proven).
3. **7-board highload run:** reflash the ROOT, save the run log. Fixed if arrivals stay ~20/s through cooldown and `[RXSTALL] ... dropped 0` (`docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` §13).
4. **Decide:** should preprocess keep jitter's extra baseline (103 windows)? Capture linear/G402/jitter r2 + r3. Others: re-run analyze on jitter after pull (feature tables/EDA are git-ignored).
5. **Basti: delete local `datasets/exports/blackhole/star/G402/burst/`** (his push re-added it; removed again in `4a00a3b`) + local `linear/G402/burst` + `linear/G402/highload`.
6. **Wormhole tree r1 again:** get a REAL tree first (HOP DEPTH >= 2, no `WARN flat like a star`, B's UPLINK = A) BEFORE baseline starts. Every board heard the root above -78 dBm = flat. Decide: placement (root < ~-80 dBm at deep boards) vs firmware RSSI threshold vs fixed parents (MEMORY). Don't unplug boards mid-run.
   + Basti: commit/push the importer fix (stage `tools/import_sdcard.py` + run_wizard.ps1 hunk ~2097 only). Decide: fix wormhole EXPOSURE false alarm (mesh_setup.c + exposure.py)?
7. Not yet captured: mobility, powercycle. Paper: §4.2.2.1 / Fig. 4.17 hub framing (D-16).

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ **BASTI: delete your LOCAL `datasets/exports/blackhole/star/G402/burst/` BEFORE your next data push.** The 3 duplicates (byte-identical to star/G402/stationary) were re-added by your `589af2d` (3rd time) and removed again oct. 1 night. partial_mesh/G402/jitter r1 children are on GitHub (Basti + ongky).
- Presets with star/burst content under a LINEAR name: `Bas/` + `Cal/linear-blackhole-stationary-g402.json` — not pushed; fix/rename.
- Uncommitted on Angelo's laptop, on purpose: `mesh_config.h` attacker line, `sdkconfig` x2, `dependencies.lock`, 4 presets, `archive/*` folders.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- oct. 2 (Basti) — Progress bar + ETA in M6/M7/M8 analysis (`analysis/progress.py`); outputs byte-identical; shows in wizard/menu/run.ps1, not analyze.ps1.
- oct. 2 — Campaign checklist (`inventory_cells.py --checklist`, wizard "Campaign progress") has a new **last run** column: newest capture date/time + scenario per attack row. Display only; run through the real checklist, not through the wizard menu.
- oct. 1 (night, Basti) — Wormhole tunnel proven on hardware (tree attempt went flat); SD importer files wormhole controls by phase; 5 misfiled control CSVs moved to wormhole/; exposure false alarm diagnosed.

## Rolled from MEMORY.md (oct. 2, 2026)
- oct. 1, 2026 (Angelo) — **VERIFIER MATRIX: all 3 verifiers run on all 33 runs on Angelo's laptop (live + archive, per repeat), 0 crashes.** Blackhole linear/tree/partial/star CONFIRMED where the run is sound; wormhole linear/tree/partial/star (pre-redesign archive) all CONFIRMED 2/2; baseline-only tables correctly say 'nothing to verify'. Only non-confirmations are correct refusals: linear/G402/highload r3 fragment (no root/attacker) INCONCL; linear/home/highload r2+r3 INCONCL because their BASELINE is broken (PDR 0.86-0.94 = the 7-board highload collapse, see entry below) while r1+r4 alone CONFIRM - pooling r1-r4 is why the cell reads INCONCLUSIVE. Integrity FAILs only on pre-redesign archive files (repeated header / timestamp regression = old firmware appending reboot sessions; trim_run splits them). Topology NO only on archive linear G402 sep. 26 (a node had 2 children - real). NOT covered (no data yet): jitter, mobility, powercycle scenarios; wormhole on current firmware.

## Rolled from STATUS.md Recently done (oct. 2, 2026)
- oct. 1 (night) — Hardcode audit fixed + pushed; linear/G402/jitter fully verified; EDA PCA/t-SNE lost-attack-class bug fixed; wizard target prompt shows port status.


## Rolled from STATUS.md Recently done (oct. 2, 2026, later)
- oct. 2 (Basti/Kyle) — Analysis progress bars (`analysis/progress.py`, outputs identical); checklist "last run" column; campaign plan updated to jitter.

## Rolled from MEMORY.md (oct. 2, 2026, later)
- oct. 1, 2026 (Angelo) — **Wizard attacker-MAC picker now ALSO lists every other known board, numbered after the past attackers** (`run_wizard.ps1` `Read-RemoteAttackerMac` + new `Get-KnownBoardMacs`, `Get-BoardNicknames` split out). Why: user wanted to pick a NEW attacker on a victims-only laptop, not only re-use a past one. Source = full MACs from the first row of every `datasets/exports/**/*_telem.csv` + every preset board; roots (role=root / Kind root), already-listed attackers, and THIS laptop's roster boards (they're victims here) are excluded. Shows nickname from member_boards.json + 'last seen as <role> in <run/preset>'. A board never in any run/preset won't appear - paste its MAC. Tested: parses, lists Kyle's 4 children with Angelo's data.

## STATUS.md replaced (oct. 2, 2026 night session summary) - previous version
# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 2, 2026 evening (Angelo, session summary). GitHub `THESIS3` = `36ca4b6` (Basti's 15:37 merge) + this summary. Previous STATUS in ARCHIVE.md (bottom). Facts + reasons: MEMORY.md top ~12 entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored. **Live board roster (edit from any laptop): https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh** - share with Bas + Kyle as Contributor; wizard still reads `member_boards.json` (ask Claude to sync).

## Where things stand
- **Firmware fixes BUILT, NOT YET RUN ON HARDWARE:** burst window (`6b90df5`), highload root writer queue (`cb22106`), hardcode audit (`44a9672`: IDF `%d` fix, nickname now `Board-XX:YY`, phase constants read from mesh_config.h).
- **Captured + verified (live checklist 7/144):** G402 linear/tree/partial/star stationary; linear + partial_mesh jitter (all 9 files each); home linear burst. Checklist staleness is content-based (a pull no longer flips `[x]` to `[~]`).
- **Wormhole tunnel proven on hardware** (Basti, oct. 1 tree/G402) but the tree went FLAT -> tunnel proof only, not a dataset entry. SD importer now files wormhole controls by phase (untested on a real card).
- **Incoming, incomplete:** tree/G402/jitter (Kyle oct. 2, children only; root on another laptop).

## Next step
0. **tree/G402/stationary is DEGRADED** (2 boards dropped out mid-run) - capture r2. Details: `ESP32-Environment/docs/dataset-verification.md` #2.
1. **Everyone `git pull` + REFLASH** (burst + highload + nickname fixes). Every laptop picks the SAME attacker.
2. **Flat tree -> retry:** reposition (victims past the attacker, hearing the root < -80 dBm), then re-run the SAME preset on the SAME ports + same repeat - no recompile, re-flash erases the failed attempt (clean data). Check HOP DEPTH >= 2 at ~30 s. Not built, user's call: lasting fix (A) cap root fan-out in TREE + (B) pin SOME victims under the attacker (D-number); wizard 'Re-run without flashing'. Details: MEMORY oct. 2.
3. **Duplicate controls:** 4 files in `exports/baseline/tree/G402/stationary/` = copies of the wormhole controls. Basti pushes his `git mv`, OR Angelo deletes them - user's call.
4. Re-run star G402 BURST (analysis must print `burst : FIRED`); 7-board highload run (`[RXSTALL] ... dropped 0`).
5. Wormhole tree r1 again once a real tree forms (HOP DEPTH >= 2, B's UPLINK = A). Decide the wormhole EXPOSURE false-alarm fix (Basti, MEMORY oct. 1).
6. Jitter: decide whether preprocess keeps the extra baseline (103 windows); capture jitter r2 + r3.
7. Not yet captured: mobility, powercycle, star burst. Paper: §4.2.2.1 / Fig. 4.17 hub framing (D-16).

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ **BASTI: delete LOCAL `datasets/exports/blackhole/star/G402/burst/` before your next data push** (re-added 3 times; removed again `3dc7e93`).
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ Before any pull: `git diff --cached --stat` - a merge refuses ANY staged change on a path it touches (bit us oct. 1).
- Uncommitted on Angelo's laptop, on purpose: `mesh_config.h` attacker line, `sdkconfig` x2, `dependencies.lock`, presets, `archive/*` folders.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- oct. 2 (Angelo) — tree/G402/jitter verified sound; EDA PCA/t-SNE fix (victim attack windows were dropped) - 4 cells' plots regenerated (MEMORY).
- oct. 2 (Angelo) — Wizard pre-build skips firmware that hasn't changed (stamp in each build dir) and prints what/why/result + first error; full compile output still shown.
- oct. 2 — Angelo: followed Basti's updates (no conflicts); flat-tree cause found (TREE fan-out 10) + fix proposed; live board roster web page; checklist fixes; star burst duplicates removed (3rd time).

- oct. 2 (Angelo) — Wizard pre-build skips unchanged firmware and explains each build (pushed `9aec136`).

## Rolled from MEMORY.md (oct. 4, 2026, Basti - room for the oct. 4 entries)
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

# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 3, 2026 (Angelo). Oct. 2 session's work COMMITTED + PUSHED to `THESIS3` (see `git log`); only the do-not-commit items below stay local. Previous STATUS in ARCHIVE.md (bottom). Facts + reasons: MEMORY.md top ~6 entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs + `eda_output/` git-ignored. **Live board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh** (wizard still reads `member_boards.json`; ask Claude to sync).

## Where things stand
- **Dataset verification log:** `ESP32-Environment/docs/dataset-verification.md` (CLAUDE.md rule: every verify request adds a dated block on top). #2 = sweep of all 9 live cells: 7 USABLE, highload PARTIAL (known), **tree/G402/stationary DEGRADED**.
- **tree/G402/burst r1 verified + pushed** (oct. 3, verification #3): burst FIRED (fix `6b90df5` proven), CONFIRMED; ⚠️ `FE90` = hidden 3rd victim (wrong parent field, unlabelled).
- **tree/G402/jitter r1 captured + verified** (oct. 2 evening): real tree depth 2, 1 victim, jitter 331/206 s, BLACKHOLE CONFIRMED.
- **EDA PCA/t-SNE fix** (`analysis/eda.py`): victim attack windows were dropped; plots regenerated for linear/G402/jitter, linear/home/burst, partial_mesh/G402/jitter, tree/G402/jitter. Teammates must re-run EDA on those (eda_output is git-ignored).
- **Sniffer stop asks 'are you sure'** (`tools/sniff.py`: Enter / Ctrl+C -> Y to stop). Tested with a simulated board only.
- **Wizard pre-build skips unchanged firmware** + explains each build (`9aec136`, pushed).
- Not yet run on hardware: highload root queue (`cb22106`), hardcode audit (`44a9672`). Burst fix proven oct. 2 tree run.

## Uncommitted on Angelo's laptop
- Oct. 2 session files (eda.py, sniff.py, run_wizard.ps1, dataset-verification.md, root docs): pushed oct. 3.
- On purpose, do NOT commit (tree/G402/burst data now pushed): `mesh_config.h` attacker line, `sdkconfig` x2, `dependencies.lock`, presets, `archive/*` folders, untracked datasets.

## Next step
1. Everyone `git pull` + REFLASH (burst + highload + nickname fixes); same attacker on every laptop.
2. **Recapture tree/G402/stationary as r2** (2 boards dropped out mid-run in r1; verification log #2).
3. Try the sniffer confirmation once on a real board (Enter -> Y stops; Enter -> other key keeps recording).
4. Flat tree retry rules + proposed TREE fan-out cap / pinned victims (not built, user's call): MEMORY oct. 2.
5. Duplicate controls in `exports/baseline/tree/G402/stationary/` (Basti's `git mv` or delete) - user's call.
6. Re-run star G402 BURST (`burst : FIRED`); 7-board highload run (`[RXSTALL] ... dropped 0`); wormhole tree once a real tree forms.
7. Jitter: decide whether preprocess keeps the extra baseline; capture jitter r2 + r3. Not yet captured: mobility, powercycle, star burst.

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ BASTI: delete LOCAL `datasets/exports/blackhole/star/G402/burst/` before your next data push.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ Before any pull: `git diff --cached --stat` - a merge refuses ANY staged change on a path it touches.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 2 night (Angelo) — Sniffer stop confirmation; 9-cell dataset verification sweep + verification log doc + CLAUDE.md rule.
- oct. 2 (Angelo) — tree/G402/jitter verified sound; EDA PCA/t-SNE fix, 4 cells' plots regenerated.

## Rolled from STATUS.md (oct. 5, 2026, Basti)
- oct. 3 (Angelo) — tree/G402/burst r1 verified (#3) + pushed; oct. 2 session pushed.

## Rolled from STATUS.md (oct. 7, 2026, Basti)
- oct. 4 (Basti) — BSOD root-caused (silabser.sys); UART tunnel test (+ Q/Enter early stop); MACs in target/attacker/Node A-B pickers; wormhole panel explainer; preset rename; child skip-export; node1 = root labels.

## Rolled from MEMORY.md oct. 7, 2026 (cap)
- sep. 26, 2026 (late) — **Wizard WIRESHARK category** (sniffer entries 21-26, `check_pcap.py --map-json`, per-view filters, `WIRESHARK_CONFIG_DIR` not `-C`). Full text in ARCHIVE.md.
- sep. 26, 2026 (eve) — **Root post-export choice** (user request): wizard asks, when the root is on this laptop,
  [1] trim + M6-M8 (default) / [2] trim only / [3] export only -> run.ps1 `-Analyze` / NEW `-Trim` / `-Export`. run.ps1
  `-Analyze` now SKIPS M6-M8 (trim still runs) when the folder has no child `*_telem.csv` - SD workflow exported the root
  first and overwrote a full analysis with a root-only one (twice on sep. 26). Parse-checked + guard filter tested; not run on boards.
- oct. 5 (Basti) — DLSU_Library/stationary r1 verified (#4): USABLE; PDR -inf explained.

## Rolled from MEMORY.md oct. 7, 2026 eve (cap)
- sep. 26, 2026 (late) — **Root phase banners print the wall-clock start time** (`root_main.c` `phase_banner()`, e.g. `@ 22:03:15 PHT`;
  "(est.)" when the clock is only the build-stamp estimate, `--:--:--` if unseeded). Console-only visual aid, never in a CSV (user). Compiled clean, not flashed.

## Rolled from MEMORY.md (oct. 7, 2026, Basti)
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

## Rolled from STATUS.md (oct. 7 night, 2026, Basti)
- oct. 6 (Angelo) — FE90 root cause (stale firmware, #5); tree/G402/jitter data pushed; merged Basti's push.

## Rolled from STATUS.md (oct. 7, 2026 night, Angelo)
- oct. 7 (Angelo) — wormhole auto-switch + error detection + verification (host test, 15 builds); exposure fix; D-17 + thesis checklist; analysis/EDA + presets pushed; verifications #6, #7; highload arrival-loss found.
- Basti oct. 7 details: Edit preset row [7] Attacker (star = HUB, other-laptop attacker by MAC); wormhole A/B rows pink; star/DLSU preset attacker fixed; campaign plan DLSU star/blackhole powercycle -> stationary; serial_guard.py grows the CP210x RX buffer to 1 MiB (not on hardware).

## Rolled from MEMORY.md (oct. 7, 2026, Angelo — line cap)
- sep. 26, 2026 (eve) — **OPERATOR HOLD (root waits for `GO`) was REVERTED ON PURPOSE by the user ("i reverted the code i didnt like").**
  Not lost, not a bug: `run.ps1 -Hold`, `wait_for_operator_go()`, `OPERATOR_HOLD` and the wizard "Hold the root for GO? [Y/n]" are
  gone from the tree. Do NOT rebuild or re-propose it unless asked; the roster gate still starts Phase 0 once children join.

## Rolled from MEMORY.md (oct. 14, 2026, Angelo — line cap)
- oct. 2, 2026 (Angelo) — ✅ RESOLVED oct. 7 (copies deleted, see top). **Duplicate wormhole controls were in `exports/baseline/tree/G402/stationary/`:** Kyle's `child_child-4..7_tree_none_r1_oct01_05xxPM_telem.csv` are byte-identical to the copies in `exports/wormhole/tree/G402/stationary/` and contain phase-2 rows (not baseline). Basti's `git mv` to wormhole is staged on HIS laptop, not pushed. NOT deleted on Angelo's laptop on purpose (would conflict with Basti's move) - user to choose: Basti pushes his move, or Angelo deletes the 4 baseline copies. Until then the checklist shows a bogus baseline/tree/G402 cell.

## Rolled from STATUS.md (oct. 14, 2026)
- oct. 7 (Basti) — #8 star/DLSU verified USABLE; Edit preset Attacker row; pink A/B; campaign plan swap; unstuck the pull + pushed.
- **Wizard text:** wormhole picker = "wired tunnel board 1/2" (A/B only a fallback); powercycle/mobility box gives WHO/WHAT/WHEN (phone timer 5:10 attack run, 2:30 baseline run).

## Rolled from MEMORY.md (oct. 14, 2026, Angelo — line cap)
- sep. 27, 2026 (pm) — **READABLE NAME STAMP `sept27_0311AM`** (user: easier to see date/time) replaces `20260927_031130` in export CSVs, run logs, PCAPs; archive folders `sept27_<label>`. No year/seconds → same-minute clash gets `-2`. Old files NOT renamed; `tools/name_stamp.py` reads both — never sort names as text (1012AM < 0312PM), use `name_stamp.parse`. PS copies: `Get-NameStamp`/`Get-StampedPath` (run_wizard.ps1), archive.ps1 inline. Not run: a real capture/import/archive.

## Rolled from MEMORY.md (oct. 14, 2026, Angelo — line cap)
- sep. 27, 2026 (pm) — **PRESET PICKER: type `d<N>` (`d3`, `del 3`) to delete straight from the list; several at once: `d3,5,7` / `d 3 5 7` / `d3-5`** (numbers = list as shown, all resolved before any delete; shows the names, one y/N, permanent; list redraws). Old "open preset -> Delete" entry kept. **Picker is 2-level: `-- Cal` / `-- Bas` / `-- Kyle` (YOURS first), each with indented cell sub-headings `-- BLACKHOLE / linear / G402 / stationary` (order = wizard's $ATTACKS/$TOPOLOGIES/$LOCATIONS/$SCENARIOS lists, then newest); preset lines show name + boards + date only** (user wanted members KEPT with the cell headings nested under them) `Show-Menu -AllowDelete` returns -2 + `$script:MenuDeleteIndexes`; only `run_wizard.ps1` has the picker. Scripted-stdin tested for parsing only, not a live wizard run.

## Rolled from MEMORY.md (oct. 14, 2026, Angelo — line cap)
- sep. 30, 2026 — **Session code changes (UNCOMMITTED, not run live / no hardware):** (1) `run_wizard.ps1` run log is now `<cell>_r<N>_<stamp>.log` (repeat added, like exports/PCAP; the 15 older logs NOT renamed — each log's `run.ps1 ... -Repeat N` line holds it; `sept28_1213AM` is a failed r3 attempt made before the sept28 20:08 r2). (2) `tools/pcap_retry.py` `_retry.csv` gained a leading `repeat` column from the run identity; `features.py` reads it by column NAME so nothing breaks; existing `_retry.csv` files only get it when rewritten. (3) `run_wizard.ps1` SD/board import: a source whose REAL copy exited 0 shows green `<< imported this session` in `Select-Port` and the card-drive picker (`$script:ImportedSources`, set via the `$script:LastImportOk` flag — deliberately NOT a return value, so the uncaptured live-progress `& python` call stays uncaptured). (4) `run_wizard.ps1` "Use this preset?" menu gained **[7] Copy this preset** (switch 6; raw JSON/File under/Delete/Pick different/No preset shifted to 7–11, header "Not this preset" now 10): pick member folder → `Save-Preset -Owner` writes the copy (same name, else `-copy`, `-copy2`) → `Edit-PresetInteractive` opens on the COPY; an unchanged same-folder copy is offered for deletion. Verified: parse-checks, switch labels 0–11, render simulation, copy logic on a scratch copy of `presets\` (roster/cell/owner round-trip, original byte-identical).

## Rolled from MEMORY.md (oct. 14, 2026, Angelo — line cap)
- sep. 30, 2026 (later) — ⚠️⚠️ **7-BOARD HIGHLOAD COLLAPSES ON ITS OWN — NOT CAUSED BY THE BLACKHOLE.** A no-attack 7-board highload run (sep. 30 02:40, `datasets/exports/baseline/linear/home/highload/`) breaks the same way as blackhole r2–r4: the node next to the root stops getting its own probes through, then each hop below follows; its "cooldown recovery" is 51%, identical to r3. Only 7 boards × 4 probes/s collapses (7 × 1/s and 3 × 4/s are fine); it's whichever board sits at hop 1, not one faulty board. r4 (sep. 30 00:59, attacker at hop 4, 2 victims) = perfect attack (recv 1,422 / fwd 0) but collapse began ~100 s INTO the attack, cooldown announcement reached hops 2–6 ~47 s late, recovery **23%** → **fails the r4 gate**. Captures (r3 + r4): at the moment it breaks, root→hop-1 frames jump ~13–20× while delivery falls — what those frames are is UNKNOWN (next: Wireshark on r3 at t≈+210 s). ❌ Ruled out: root storage at ~1.1 MB (no-attack run collapsed at 890 KB; 3-board r1 wrote 948 KB fine). Verifier: pooling all nodes only WEAKENS scores; the PASS→FAIL flip is cooldown-as-normal (cooldown removed → r3/r4 PASS all three forwarding features) — diagnosis only, the decision below still stands. ⚠️ The benign highload class is contaminated too (later windows of the no-attack run are a collapsing mesh); "keep highload at 7 nodes" needs a team decision. Full write-up: `COOLDOWN-RECOVERY-2026-09-30.md` **§10**.

## Rolled from MEMORY.md (oct. 14, 2026, Angelo — line cap)
- sep. 30, 2026 (late) — **Wireshark retry view now opens with phase-split I/O graph lines** (`run_wizard.ps1`): `Get-PcapPhaseSegments` reads the capture's `_retry.json` sidecar (which `pcap_retry.py` already writes) and converts its epoch `segments` to `frame.time_relative` by subtracting `capture_epoch[0]`, giving BASELINE/ATTACK/COOLDOWN lines scoped to `llc.oui == 0x18fe34` — the same population as `MacRetryRate`, unlike the pre-existing whole-run "retries" line which also counts management frames. ✅ **Confirmed working in real Wireshark by the user**; boundaries landed at 84.5 / 385.3 / 566.0 / 686.0 s on the r2 capture. Falls back silently (with a grey hint) when no sidecar exists — run menu **[27]** / `pcap_retry.py --all` first. It deliberately does NOT try to set a Wireshark "Time Reference": that is live per-session UI state, not something a profile file can seed. **What this revealed:** the mesh-data dip that earlier sessions flagged as "worth investigating" IS exactly the attack window — fewer frames because the attacker stops relaying — and the retry lines fall WITH it rather than spiking above it, which is the D-15 finding made visible without any script.
<!-- rolled from MEMORY.md oct. 15, 2026 (line cap) -->
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


## Rolled from MEMORY.md on oct. 17, 2026 (cap)
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
  SET_TIME gets "no answer" when the board still runs pre-SET_TIME firmware before the reflash - clock then comes from the SD anchor.
- sep. 26, 2026 — **ESP32 SNIFFER (independent observer, answers panel P6)** — built, ✅ hardware-tested, documented in
  `docs/packet-capture/WIRESHARK-GUIDE.md` + FILEMAP; full build notes in ARCHIVE.md. What still bites: a SPARE board only (never a run's mesh port),
  UART0 at **921600** so `idf.py monitor` shows garbage BY DESIGN, output `PCAP/<atk>/<topo>/<loc>/<scen>/` or `standalone/` (git-ignored),
  **`P` pauses SAVING - the capture has real gaps there, check the .json `pauses` before using a pcap**, and the keep prompt `[Y/n]`
  deletes .pcap+.json on an explicit `n` with no restore. Quote USB loss / ring drops from the .json alongside any figure.
  literally" notes are history, not a to-do). Only the paper text (Tables 4.4/4.10, §4.2.4.1) is behind and must be amended.

## Rolled from MEMORY.md (oct. 17, 2026)
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
- oct. 16-17 (Angelo) — verifications #33-#38, wizard 'b' everywhere + redesign, redo-list topology, wormhole firmware fix + root gates + manual START, verifier redesign (2 wormhole primaries, study tags), preprocess transition/anchor fixes, redo list, wizard redo-list + tunnel prompt fixes.  (rolled from STATUS oct. 18)

## Rolled from STATUS.md (oct. 18, 2026)
- oct. 17 (Angelo) — GUI: redesign + speed-ups, then FULL GUI (Live run + root dashboard, import page, in-window tools, GET_ID no-reset board ID); wormhole audit (star blocked, A24).
- oct. 17 (Angelo) — first push of everything (`be5115c`): FULL GUI (Live run + root dashboard, import page, in-window tools, GET_ID), wormhole audit (star blocked, A24).  (rolled from STATUS oct. 18)
- **Preprocess:** `transition` segment for windows spanning 2 phases; anchor fallback keeps a stalled board's baseline (D-21).  (rolled from STATUS oct. 18)
- **Wizard:** 'b' works on every menu (back one question, or back out of the tool); question chains step back; main menu = short aligned names + hints; Campaign -> [2] checklist redesigned; every tool opens under the same framed title, status lines + prompts aligned. Test `tools/test_wizard_nav.ps1` 15/15.  (rolled from STATUS oct. 18)

## Rolled from MEMORY.md (oct. 18, 2026 ~8:10 PM, line cap)
- sep. 25, 2026 — **10 Hz sampling + 1 s windows are PANEL/ADVISER-MANDATED — never "restore" 1 Hz / 5 s** (D-1/D-9 "to restore
- ⚠️ **PS 5.1 promotes a native command's FIRST STDERR LINE to a TERMINATING error** under
  `$ErrorActionPreference='Stop'` — a tool writing a progress bar to stderr kills its caller with an EMPTY
  exception message. **Grep every `& python ... 2>&1` before shipping.** Detail: ARCHIVE.md.
- ⛔⛔ **BSOD 0xB8 = a CP210x driver bug (`silabser.sys`) that fires when its RECEIVE BUFFER FILLS — a board port left open but not read** (oct. 7 entry; corrects oct. 4). Never `time.sleep()` or wait for input with a board port open — use `serial_guard.discard_for()`; every new serial opener must call `serial_guard.grow_rx_queue()` right after open (.NET `SerialPort`: `ReadBufferSize = 1MB` before `Open()`). Still: no Ctrl+C mid-export, boards DIRECT into the laptop. USB selective suspend is off. Older detail: ARCHIVE.md.
- **Git repo root is this whole folder** (`THESIS3/` on Basti's laptop: `OneDrive\Documents\Thesis\THESIS3`;
  code, docs, `Paper/`, `ESP32-Environment/` all inside it), NOT `ESP32-Environment/` alone — branch **`THESIS3`**
  (was `Unified` before sep. 2026), remote `origin` =
  `https://github.com/Kemo1006/NIS16-ESP32-Environment`. GitHub IS the laptop-to-laptop transport: a `git pull`
  elsewhere gets the same MEMORY.md/STATUS.md/code. (Corrected sep. 17, 2026; was stale before that.)

## Rolled from MEMORY.md (oct. 18, 2026)
- sep. 30, 2026 (docs reorg) — **`ESP32-Environment/docs/` is filed by TOPIC now, not by date** (user: the group has to answer an adviser or panelist "specifically and not out of place", so each askable thing gets its own folder). 13 folders: `blackhole/`, `wormhole/`, `attack-validation/` (ATTACK-VALIDATION + the 3-sigma VERIFY runbook), `highload-collapse/` (COOLDOWN-RECOVERY — the 7-board congestion finding), `dataset-integrity/`, `data-and-results/`, `packet-capture/`, `panel-answers/`, `issues-and-fixes/` (I-001…I-017 + the SD/wormhole wiring Q&A), `deviations-limitations/` (thesis-deviate D-1…D-15), `progress-reports/`, `operations/`, `references/`; `_archive/` deliberately left as-is so "superseded" stays visible. `docs/runbooks/`, `docs/issue_logs/`, `docs/Implementation Issues/` are gone. **NEW `docs/README.md` is the index** — per folder: the question it answers, the files, and the line to say. **Rule going forward:** a new doc goes in the folder whose QUESTION it answers; cross-cutting material keeps ONE home plus a pointer line in `docs/README.md` — never a second copy. **No moved file's contents were edited** (user's explicit constraint); `git mv` used so history follows. Link repair, which the user approved separately: 99 path-only rewrites in 49 files (docs cross-links resolved to real relative paths; prose/code mentions keep their original shape and separator style). Verified by a tree-wide sweep — **0 dead links caused by the move**; the 26 that remain are pre-existing (old `NIS16-ESP32-Environment` repo name, deleted `m5_extraction`/`uart_link_test`, skill examples). Deliberately NOT rewritten: bare-filename mentions like "see `thesis-deviate.md`" (the filename did not change, so grep still finds it) and prose paths that were already unresolvable from where they sit (e.g. `Setups/SD-CARD-WIRING.md`). UNCOMMITTED — the user pushes.
- sep. 30, 2026 (late) — **NEW `docs/packet-capture/WIRESHARK-TERMS.md` — the Wireshark vocabulary dictionary** (user: an adviser asked "what is the protocol of the ESP32?" and what deauthentication means; they wanted one file so nobody has to search YouTube). It is the THIRD Wireshark doc and stays a **dictionary**, not a workflow: GUIDE = why/how to capture, QUICKSTART = how to drive the screen, TERMS = what a word on the screen MEANS. Contents: the 3-layer protocol answer (802.11 → ESP-WIFI-MESH, *proprietary, not a standard, not IP* → our probe protocol), every management frame (probe/auth/assoc/reassoc/**disassoc vs deauth** — both are notifications the receiver cannot refuse; deauth drops auth AND assoc), control frames, LLC/SNAP/`OUI 0x18FE34`, To DS direction, the `....R..T` flags positions, radiotap, the hop-wise `wlan.da` trap, and a cheat card. **Every number in it was measured from `linear-blackhole-highload-home_r2_sept28_0806PM.pcap` and every filter was run through tshark** (found at `S:\Main Programs\Productivity\Coding\Wireshark\tshark.exe` — NOT on PATH, not in Program Files). Facts worth keeping: a capture is only ~21% real mesh data (RTS 40%/ACK 21%/CTS 12% is normal overhead); the 61 join/leave frames are 0.02%, so **deauths in our captures are ordinary re-parenting churn, not an attack** — reason codes present are 5 ×18 (parent full, shed a child), 3 ×6 and 8 ×2 (board left), 6 ×2 (stale link); data frames are truncated to 64 B on purpose (`SNAP_DATA`, so "111 bytes on wire, 83 captured" is by design); uplink:downlink ≈ 7:1; **real data-frame retry rate for that capture = 20,035/57,998 = 34.5%** (the `7.1%` a plain `wlan.fc.retry==1` shows includes management frames — always add `llc.oui == 0x18fe34`).
- sep. 30, 2026 — ⚠️ **A RUN CAN FAIL `verify_attack.py` WITH A PERFECT ATTACK — the cooldown phase is pooled into the "normal" baseline.** `preprocess.py` labels baseline AND cooldown `Label 0`; `verify_attack.py:361` takes its 3-sigma reference as `Label == 0`. Sep. 29 r3 (7 nodes): baseline PDR **0.9988 ± 0.021**, cooldown **0.5425 ± 0.432** → pooled 0.862, under `BASELINE_FLOOR` 0.90, so BOTH primaries were EXCLUDED = INCONCLUSIVE. Drop the cooldown rows and the same table gives ForwardingRatio z −10.88 / PDR z −21.06, **CONFIRMED, exit 0** (r2 too: PDR z −13.82). **It was NOT the retry rate** — RetryRate is `tier secondary`, the verdict counts primaries only, and it read 0.000→0.000 in the 4-node run that PASSED.
  Cause of the bad cooldown: the attacker's relay throughput collapses ~35 s into cooldown (forward 20/s → 3-9/s while recv stays 20/s, `retry_count`/send_fail **0**, parent/layer/RSSI flat), the 128-slot queue fills in ~11 s and then rejects arrivals. **Root arrivals recovery: r1 4 nodes 100% → r2 6 nodes 70% → r3 7 nodes 51%.** ⚠️ **Do NOT "fix" this by scoping the verifier's baseline** — `EXPECTED-RESULTS.md §3` / `ATTACK-VALIDATION.md:39` make cooldown RECOVERY a thesis claim (the Wireshark I/O graph climbing back is the stated headline screenshot), so a scoped verdict would pass a run that still fails the paper's own criterion. Gate for r4: verifier exit 0 with neither primary EXCLUDED **and** recovery ≥95%. r3 is our BEST attack (root arrivals 0.00/s, all 5 victims PDR exactly 0.000; r1 "passed" at attack PDR 0.502 with one bystander) — **do not discard it**. Why `esp_mesh_send()` slowed is still UNKNOWN; the pcap for this run exists. Full study: **`ESP32-Environment/docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md`** — that is the working file for this issue.
- sep. 28, 2026 (pm) — **PRESET PICKER NOW HAS `[2] Edit this preset ... and save it`** (user: "when user selects the preset give them option to edit it"): `Edit-PresetInteractive` in `run_wizard.ps1` changes the cell (attack/topology/location/scenario/repeat) AND the roster — node label/port/which is ROOT/attack seat/scenario target, add, remove (reuses `Edit-`/`Add-`/`Remove-BoardInteractive`) — then writes the SAME file, so changing a preset no longer means "load it, fix it in Adjust the plan, answer the write-back prompt" (or re-answering every menu).
  Edits a CLONE, validated only at SAVE (≤1 root; ≤1 attacker/A/B each; ≤1 scenario target; unique labels - see the same-day fix below for why 0 of these is fine) so a half-finished edit can never write a preset the LOAD path then refuses — a saved-but-unloadable preset is worse than no edit. A changed cell offers to RENAME the file to `<topo>-<attack>-<scenario>-<loc>.json`; owner/member folder kept.
  **Touches no board** (a port change keeps the recorded MAC — the MAC is WHICH board it is, the port is only where it sits today); changing location warns each SD card's own location.txt still says the old room. `Edit-`/`Add-BoardInteractive` `-Ports` gained `[AllowEmptyCollection()]` (with nothing plugged in, `@()` is a legal answer; `Select-Port` already handles it). The 11-option "Use this preset?" menu got `-GroupHeaders` (Board checks / Preset file management / Not this preset) — numbering unchanged, purely visual. Tested with scripted stdin against a throwaway `presets\` tree — not a live wizard run. **Fixed same day:** the save check originally REQUIRED exactly one attacker/A/B/scenario-target locally and blocked Kyle's own real preset (2 victims, attacker is on a teammate's laptop, never listed here at all). Now matches ROOT's own existing rule (0 is fine, only >1 blocks) with a Yellow "saving anyway" warning instead of a refusal; scenario-target picker also gained the missing "TARGET is on ANOTHER laptop" escape (creates a port-less marker board) that the pre-flash flow already had. Also added a **[7] Replace a node with a different board** option: keeps the seat (Role/Kind/Display/ScenarioTarget - attacker stays attacker, a scenario target stays the target) and only changes Port + optional Label, clearing the old MAC (it named the board leaving, not the one taking its place) so it never falsely claims the new board already matches an unread MAC.
- sep. 28, 2026 — ⚠️⚠️ **THE REPEAT NUMBER DOES NOT IDENTIFY A RUN — never match a run by cell + `r<N>` alone.** FOUR runs share
  `blackhole/linear/home/stationary` **r1** (19:18, 21:11, 23:39 sep. 26, 02:05 sep. 27). `pcap_retry.py` matched "the root export for this
  cell + repeat" and the 23:39 capture silently read the **02:05 run's** export - it looked right ONLY because every run uses the same
  300/180/120 s phases. Fix: an export must be stamped after ITS OWN run's log started and BEFORE the next log of the same cell + repeat.
  Same class as the G402 "6 runs under r1" audit. **Any tool joining runs to files needs this bound.**
- sep. 28, 2026 — **A RUN LOG CAN LOSE THE MIDDLE OF THE RUN; the run's own exported CSVs are the better source.** The sept 28 00:13 r3 log
  jumps from the flash straight to a snapshot 12 min in: no `Starting PHASE` lines, and its topology table lists 3 of the 6 boards with NO
  BLACKHOLE. `pcap_retry.phases_and_roles_from_exports()` reads phases from the root export's `phase_id` (10 Hz) and roles from each
  `*_telem.csv`'s own `role`, archives included. Validated where both sources exist: **phase gaps agree to within 40 ms** (constant ~600 ms
  offset cancels). MacRetryRate 2/7 -> **5/7 captures**; out: 23:39 (own export not under `datasets/`), 21:11 (no attack step). **Board DATA > console TEXT.**
- sep. 27, 2026 (eve) — **REAL 802.11 RETRY RATE MEASURED from the SNIFFER (`tools/pcap_retry.py`, D-15).** ESP-IDF 5.3.5/5.5 have NO
  readable retry counter (`esp_wifi_statis_dump` only prints) -> firmware can never fill it; the sniffer's Retry bit (fc 0x08) can. Blackhole/
  linear/home: 1-70 % by LINK QUALITY, **no rise in the attack** (18:35 +-7.6 pts, 19:18 +-2.6) = Table 3.4 miss, independently observed.
  ⚠️ **Root banner `@ HH:MM:SS` runs ~38 s BEHIND** (SD clock restored after the flash reboot) - the tool fits the attack from the attacker's
  uplink drop. **features.py joins it as `MacRetryRate`/`MacFramesHeard`**; files tied to runs via ALL run logs, so a refused run (21:11) stays
  NaN, never borrows another r1's data. Wormhole needs `--attack-start`. Not a model input (not in TABLE_4_11_FEATURES) - team's call.
  **Sep. 28 night: viewable in `run_wizard.ps1` main menu -> WIRESHARK -> "MAC retry rate of a run"** (modeIdx 27); cache re-checks the exports it read (`export_cell/dirs/files` in the .json).
  **Sep. 28 late: `report()` rewritten to be readable** (user could not read the old table): FULL MACs, a boards table (hop + parent inferred from uplink volume), one block per link with a
  verdict (worse/better only past +-5 pts, judged only with >=100 frames in baseline AND attack; 100%-retry links flagged "sniffer misses first tries, don't quote"), a bottom line; sep. 29: the ORIGINAL side-by-side table + its how-to-read are KEPT too (user asked them back), now with full MACs. Short MACs had hidden that `..:ed:80` = `b4:bf:e9:34:ed:80`, a 7th board (no export).
  **Sep. 29: role names/MACs are now COLOUR-CODED** to match `run_wizard.ps1`'s own `$script:RoleAnsi` palette exactly (root gold #FEBD17, child teal #1BC0BA, attacker pink #FDB8D9 for BLACKHOLE/WORMHOLE_*) — UNKNOWN/OUTSIDE stay plain, same as the wizard's own fallback. `pcap_retry.py` gained its own ANSI helpers (`paint`/`_enable_ansi`, same isatty+VT100 pattern as `tools/sniff.py`) rather than importing from the wizard (Python tool, no PS dependency). ⚠️ Padding a colour-wrapped string with plain `'%-*s'`/`str.ljust` undercounts — the escape bytes count as visible chars — so the RESULTS TABLE row now pads with a new `ljust_visible()` (strips ANSI before measuring) instead; verified byte-identical to the plain (non-tty) output once stripped.
- Reading notes (sep. 26): relay `drop_count` = deliberate drops AND failed forwards AND **queue-full rejections** (`probe_relay.c:113`, added sep. 30) — a queue-full drop raises `drop_count` but NOT `retry_count`/send_fail, which is how to tell congestion from a link failure. ⚠️ recv = fwd + drop holds only once the queue drains; while it is filling, `recv - fwd - drop > 0` is the backlog (see COOLDOWN-RECOVERY-2026-09-30.md);
- oct. 18 (Angelo, 2 sessions) — GitHub sync page + `tools/smart_sync.py` (stale-analysis gate, dup/delete guards, LF-canonical analysis/presets = the KEEP-BOTH root cause, safe folder update; check 152 s -> ~5 s; no auto re-check), Data page 'Delete from card' + already-imported-by-content scan, old Data sync tab removed. The other session's GUI look pass (preset gallery, restyles, ~10x faster capture page) went up in the SAME commit `b6f8cc8`.
- oct. 18 ~4 AM (Angelo, GUI session) — preset gallery -> Everyone list + person cards, filters, grouped date sort, multi-remove in the editor, readable MACs, Boards/sniffer/Verify restyle, partial drawing fix, timer-leak + console + pulse-leak lag fixes, green alerts. Pushed.
- oct. 19 ~5:30 AM (Angelo) — #53: D-25 tick alignment, S9 + majority rule, benign verifier, placebo audit, validity strip + signature card, GRADING-AND-THRESHOLDS.md, D-25 + checklist B-tick / B-grade / C15. Pushed.
- oct. 19 ~3:30 AM (Angelo) — grades renamed MINOR/MAJOR GAPS + paired with the status colours; impact check decides minor vs major (tree/G402/stationary MAJOR -> MINOR, yellow); specific gap sentences; Selected run panel redesign. Verification #52, checklist C14, GUI rows 55-56. Pushed.

## Rolled from STATUS.md (oct. 19, 2026 late night)
- oct. 19 night (Angelo) — #55 tree re-parenting explained (weak links + tree self-organises + crashes; no code regression) + D-26 sticky parents; #56 attacker gaps always MAJOR; FAILED grade with reason; wormhole unlock on root restart; plain-words card; thesis §8-9. Pushed (`2ab7518`).

## Rolled from MEMORY.md (oct. 19, 2026, cap)
- sep. 30, 2026 (Angelo, eve) — **Verifier/validator fixes from the partial_mesh G402 run (sept30 0406PM).** (1) `verify_attack.py`: a table WITH node_role but NO `blackhole` node (attacker SD card not imported) used to fall back to the pooled FR test = honest relays only → FR 1.000 FAIL counted as primary. Now those attacker-scoped rows print `INCONCL` + a note and are left out of the verdict (legacy tables without node_role still use the pooled test). (2) `NeighbourForwardingRatio (attacker)` printing the SAME numbers as `ForwardingRatio (attacker)` is NOT duplication: it is rebuilt from the children's hand-ups + root arrivals, never the attacker's counters; on this run 612/616 attacker windows matched exactly (4 = clock jitter, cancels over 5-window blocks) → the attacker's self-report is honest. A footnote now says so. (3) `validate_integrity.py`: blackhole-phase check now judges EACH src_mac vs its own baseline (`SOURCE_SILENCED_MAX = 0.1`); some silenced + some flowing → info, not "attack did not take effect" (pooled 50.1% from 3 victims + 3 upstream falsely warned). Result: partial_mesh CONFIRMED 2/2, 9/9 integrity PASS. Hardcoding audit of analysis/, eda.py (timeseries), tools/: node IDs/MACs only in comments; nothing data-specific in logic. Angelo accidentally deleted linear + tree analysis output mid-session → RESTORED: .gitkeeps/legends via `git restore`, then `analyze.ps1 -Verify` regenerated blackhole linear/G402/stationary (CONFIRMED, FR-atk z −137.9, same as before), tree/G402/stationary (CONFIRMED), linear/home/burst (CONFIRMED), linear/home/highload. ⚠️ **home/highload is now INCONCLUSIVE** (committed verifier gives the same → not this change): the cell now pools r1–r4 (Basti's 12:46 push) and the pooled baselines are too noisy (FR 0.872±0.300, PDR 0.920±0.239 → INVALID-BASE). Open: verify per repeat or find the bad repeat. `exports/blackhole/linear/G402/burst/` held byte-identical copies of 3 stationary files (re-pushed by a data sync) — DELETED + pushed sep. 30 (5f9221c); if a data push re-adds them, delete again. Same day: `linear/G402/highload` r3 child_node5/6 (the whole cell: 2 children, no root/attacker log, unanalysable) deleted + pushed (04edaf6) at the user's request.
- sep. 30, 2026 (Angelo, late) — **POWERCYCLE FIXED (ROOT reflash needed): root re-sends the CURRENT phase every 10 s, same seq_num** (`phase_listener_start_resync()`, called in root_main.c). Why: since the sep. 25 log gate, a child rebooted mid-run logged NOTHING until the next phase (root broadcast each phase once, no re-sync) → a powercycle target lost its whole attack phase. Unrebooted nodes drop the copy in the seq dedupe, so burst/phase logic is unchanged; stops at TERMINATE. Root full build+link OK on IDF 5.5.4; model replay: reboot → phase known ≤10 s, burst timing identical. `run.ps1` powercycle checklist text updated. **MOBILITY: NeighbourForwardingRatio now uses each window's own parent_mac** (per-second tree; missing window → usual parent, value blank), so a moved node is attributed to its new parent. G402 labelled values unchanged (nobody moved). Scenario audit same day: highload WORKS (~4 probes/s in data, some sends fail under load); jitter logic + root build OK, no data yet; the home burst run (sept30 ~09:00, groupmate's) has NO burst anywhere either. **Verifier `all relays` row** (user kept the compact table; footnote [1] now carries the detail — attacker vs each honest relay's FR, the dilution reason, the 3-sigma line, the honest-relay limit, this run's count, and what PASS/FAIL means; a separate per-relay table block was tried and dropped): why it passes/fails — the cause is the NUMBER OF HONEST RELAYS diluting the attacker (victims that relay count too — they forward into it), NOT the number of victims: linear G402 5 honest → 0.826 FAIL; tree G402 2 honest → 0.578 PASS; limit ≈ (line − attacker)/(honest − line), ~3 for both. The row stays `info` even when it passes (same measurement as the attacker row). Per-node PDR table keeps one row per (node, hop), but the VICTIM / "not in path" summary now counts each node once (tree G402 printed "4 nodes" for 3 — B4BFE934ED80 changed hop).
- sep. 30, 2026 (Angelo's laptop) — ⚠️ **BURST SCENARIO BUG FIXED IN CODE — every burst board needs a REFLASH.** The burst fired during stabilisation, not 60 s into the attack: `victim_main.c` opened its window on "2nd broadcast seq seen", but the root's PREPAREs (sep. 25) advance the same seq. Now: attack build opens on the attack phase id; baseline build on a seq change WHILE phase_id is already 0 (root's "Phase 0b"). Both attack+burst and baseline+burst child variants compile clean on IDF 5.5.4; a replay of the root's real broadcast sequence (PREPAREs, Phase 0 repeats, 0b, root restart) through a model of the logic: old fired ~65 s after boot, fixed fires exactly 60 s into the window. NOT yet hardware-tested. Check older burst runs (e.g. home) the same way: target's raw tx_count jump vs phase_id / segment.
- sep. 30, 2026 (latest) — **RetryRate IS NOW A DATASET COLUMN ONLY (Basti's call; REVERSES the sep. 23 team decision to keep it as a secondary blackhole signature — tell Angelo).** Why: none of the cited attack studies (Airehrour 2018 blackhole; Zhukabayeva 2025 + Ramírez Gómez 2019 wormhole) names retry/retransmission rate as a signature, so it was the one validator not backed by a study, and it measured flat (0 failed sends) in every phase anyway. Rule now: **the validator uses ONLY paper-backed signatures** — blackhole ForwardingRatio/PDR (+ ConsistencyScore, IngressEgressDelta, both derived from Airehrour's delivered/sent), wormhole Tunnel* (+ LatencyHopRatio). Removed from: `tools/verify_attack.py` (signature, ratio-of-sums, notes), `analysis/eda.py` (FEATURE_COLUMNS → stats/correlation/PCA/leakage audit, the MAC layer group, distribution plot, flat-result note), `tools/feature_separability.py`, `analysis/leakage.py` (now ALWAYS excluded; `retry_count_is_overloaded()` deleted). **Still in** `feature_table.csv` (features.py untouched) + `column_legend.py`. Sniffer `MacRetryRate` untouched. Tested on real `blackhole/linear/home/{burst,highload}`: verdicts identical (CONFIRMED 2/2), only the RetryRate row gone; EDA runs clean, no RetryRate in any output; separability still PASS. ⚠️ Old `eda_output*/distribution_RetryRate.png` (6 files under `datasets/analysis/`) are STALE until deleted/regenerated — EDA never removes old plots. Docs: D-15 "Scope decision" row, EXPECTED-RESULTS §4, DATA-DICTIONARY, VERIFY.md, FILEMAP. **Paper TODO:** drop RetryRate from §4.2.6's plot list and from Table 3.4's expected signatures (or keep that row as a tested-and-not-observed hypothesis). ⚠️ Open: `LatencyHopRatio` expects delay DOWN, while Zhukabayeva measured delay UP (their GSM tunnel was slower; our UART is faster) — secondary, never counts toward the verdict, not changed. PUSHED sep. 30, 2026 as `ead0622`, a RetryRate-only commit (the rest of Basti's uncommitted backlog stayed local).
- sep. 30, 2026 — ⚠️ **OPEN WORMHOLE ISSUE — decide before defense: `LatencyHopRatio`'s direction contradicts our PRIMARY wormhole paper.** `tools/verify_attack.py` expects LatencyHopRatio to go **DOWN** in the attack (the tunnelled copy arrives faster). Zhukabayeva et al. 2025 measured delay going **UP (~+40%)**. Not a bug — the direction depends on the tunnel medium: theirs was **GSM/GPRS** (slower than their ZigBee path), ours is a **UART wire** (faster than several mesh hops). ⛔ **Do NOT flip it to "up" to match the paper** — a correct UART wormhole would then FAIL the check. Follow Zhukabayeva's **method** (3-sigma) and the idea that a wormhole **shifts delay**, not their sign. It is a **secondary** signature and never counts toward the verdict (primaries = Tunnel*). Options: (a) remove it from the validator like RetryRate (keep in dataset/EDA); (b) keep "down" and cite **Hu, Perrig & Johnson (2003), "Packet Leashes"** (defines a wormhole as a low-latency tunnel, detected by timing) — NOT in the curated citation set, read it before citing. **Team decision sep. 30: leave as-is for now.** Panel answer: *"The signature is a change in delay; whether it goes up or down depends on whether the tunnel is faster or slower than the real path — ours is a wire, theirs was cellular."*
- sep. 30, 2026 — 🔬 **THE TEST FOR THE HIGHLOAD CAUSE IS BUILT AND COMPILES — NOT YET RUN ON HARDWARE.** `root_node/main/root_main.c`, inside `probe_data_cb()`, block tagged `RXSTALL INSTRUMENTATION — TEMPORARY`: brackets the existing `csv_logger_append_probe_arrival()` with `esp_timer_get_time()`, samples `esp_mesh_get_rx_pending().toSelf` per arrival, and every 200 arrivals (~10 s at 20/s) emits one `ESP_LOGW`: `[RXSTALL] write avg N us / max N us over 200 probes | RXQ max N of 32 (now N) | phase N`, then resets its maxima. **Measures only — no behaviour change**; cost is one timer pair per probe + one line per 10 s. ✅ Built against local IDF 5.3.5, root app 27% flash free, no errors; the `sdkconfig`/`dependencies.lock` that build rewrote were reverted ([[thesis_idf_version_sdkconfig]] trap). **UNCOMMITTED — the user flashes.** ⚠️ **Deliberately NOT given a `D-` number**: it is temporary debug instrumentation, not a methodology deviation, so it must not imply an entry in `thesis-deviate.md` — **D-15 is still the last registered deviation.** (It was first written as "D-16" and renamed before compiling.) **HOW TO RUN:** flash the ROOT only (children unchanged) → normal 7-board highload run → answer YES to the wizard's save-run-log question → `grep "\[RXSTALL\]" datasets/run_logs/blackhole/linear/home/highload/<run>.log`. **HOW TO READ** (root takes ~20 probes/s → 50 ms budget each; RX queue 32 ≈ 1.6 s of buffer): `RXQ max` climbing across the run toward 32, OR `write max` in the hundreds of ms/seconds, OR `write avg` above ~50 ms → **§12.4 CONFIRMED**; `RXQ max` stays 0-3 AND `write avg` stays µs/low-ms while arrivals still collapse → **§12.4 REFUTED, re-open** (next suspects: the phase-listener task's other work, ESP-MESH internal scheduling — neither examined). **The trend across the run matters more than any single line.** Confirmed → implement §12.5 item 2 (arrival logging onto a queue + lower-priority writer task), then REMOVE the instrumentation. Full detail: `docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` **§12.6**.
- sep. 30, 2026 (latest) — ✅⚠️ **HIGHLOAD COLLAPSE — CAUSE FOUND, AND TWO EARLIER CLAIMS OF MINE WERE WRONG. It IS solvable, and the bug is in OUR code, not ESP-MESH.** Measured with tshark on the r4 capture + the boards' own exports. **The children never failed:** every node kept sending its own probes at the full 4/s (`tx_count` 79-80 per 20 s) and relaying at a constant rate for the WHOLE run, hop 1 included — while the root's `probes_count` fell 19.8→9.9→**4.6/s**. Packets were sent, were on the air, and the ROOT did not take them in. ❌ **CORRECTION 1: airtime/shared-channel saturation is DISPROVED** (peak channel load only ~278 frames/s ≈ 24 KB/s ≈ 192 kbps, and traffic *falls* to 2,655 frames/30 s during the collapse — it never hits a ceiling). ❌ **CORRECTION 2: §10.4's "root→hop-1 surge" was real but misread** — 2.83→17.67/s (~6×, not 13-20×), retries do NOT spike with it (13-14% / 36-38%, inside baseline's 25-59%), payloads unchanged → a symptom of flow-control throttling, not a retransmission storm or a cause. **MECHANISM:** `esp_mesh_recv()` is called from ONE task only (the phase listener, `TASK_PRIO_PHASE_LISTENER 8`, *"must wake quickly"*), and its probe-sink callback does, inline per arriving probe: `esp_wifi_sta_get_rssi()` + `fputs` to SPIFFS + `sd_mirror_ensure`+`fputs` to **SD** + an `fflush` on BOTH every `LOGGER_FLUSH_RECORDS`=**10** rows + an SD fsync every 5 s (`root_main.c:536-566`, `csv_logger.c:1479-1500`). At 7×4/s ≈ 20 arrivals/s that is ~20 SPIFFS + ~20 SD writes/s and 2 flushes/s **on the thread that must drain the mesh RX queue**. `esp_mesh_set_xon_qsize()` is **never called** in this repo (`grep xon` = nothing) → root RX queue is the **default 32**; once full, ESP-MESH flow control throttles the children. Explains everything that never fitted: attack-independent, needs 7 boards × highload, worsens over time (SPIFFS GC), and `retry_count`/`send_fail` stay **0** because nothing fails — it only BLOCKS. ⚠️ The SD/SPIFFS-latency specifics are the best-supported explanation, **not proven** — instrument the root first. **FIXES (none applied, all need rebuild+reflash+a real run):** (1) measure — time the sink callback + log `esp_mesh_get_rx_pending()`; (2) **the real fix** — move the file I/O out of the receive path onto a queue + lower-priority writer task, the same ingest→queue→task split `probe_relay.c` already uses; (3) `esp_mesh_set_xon_qsize(64…128)` before mesh start (one line, buffer not cure); (4) cheap — raise `LOGGER_FLUSH_RECORDS`, drop the SD mirror on the ROOT for highload runs, hoist `esp_wifi_sta_get_rssi()` into the 10 Hz telemetry task. ⚠️ **Until fixed, 7-board highload root-side arrival data measures the ROOT'S LOGGING, not the mesh** — but the victims' attack PDR 0.000 still stands, the attacker's own counters prove the drops independently. Full write-up + reproduce commands: `docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` **§12** (supersedes §10.4 and §11.2).
- sep. 30, 2026 (late, cont'd) — **§11 added to `COOLDOWN-RECOVERY-2026-09-30.md`: `jitter` is NOT a highload variant and cannot cause the §10 collapse.** `-DTRAFFIC_PROFILE=3` (jitter) only randomises baseline/attack phase LENGTH — root-only, additive, `root_main.c`'s `jitter_extra_s()` — it never touches `PROBE_INTERVAL_MS` (stays 1000 ms; only `TRAFFIC_PROFILE_HIGHLOAD` drops it to 250 ms) or any child's traffic volume, and §10.2 already showed the collapse only appears at 7 boards × highload rate (7×1/s and 3×4/s both stay clean) — jitter never raises the rate above 1/s. `memory/run-scenarios-2026-09.md` was missing the jitter scenario entirely (5 of 6 documented) — added same day. §11.2 reads `probe_relay.c` (the one relay function every hop's forwarding runs through — root/attacker/child alike) for congestion-mitigation candidates; **discussion only, nothing built or tested**: `RELAY_QUEUE_SIZE` 128 is a bandage, not a fix (a full queue only delays when drops start, doesn't raise throughput) — ⚠️ any run that ever logged "Relay queue full" has a **CONTAMINATED** `drop_count`/`ForwardingRatio` (a congestion drop is indistinguishable from an attacker's deliberate drop in the telemetry) — worth grepping past run logs for that string; task priorities are already correctly ordered mesh-wide (same table on every board, can't fix a mesh-wide bottleneck alone); `esp_mesh_send()` blocks with no `MESH_DATA_NONBLOCK` flag — candidate cause of §4's "recv stays 20/s, forward drops to 3-9/s, send_fail stays 0" (slow, not failing); the mesh stack's own internal queue size (`CONFIG_MESH_TXQ_SIZE`/`RXQ_SIZE`) is unconfirmed, never overridden in either sdkconfig. **The ceiling nothing here fixes: all 7 boards share ONE 2.4 GHz channel** — favors an architectural fix (a tree, §10.7) over constant-tweaking. If tried: tree highload run first (no firmware change needed), then read the actual mesh Kconfig queue sizes, then `RELAY_QUEUE_SIZE` as a cheap low-confidence experiment last.

- oct. 19 late night (Angelo) — #57: false 'topology FAIL' fixed (D-27, 31/54 were false), benign Gate 3, per-verdict analogies, plain-words card only warns on real gaps. wormhole/linear/Yuchengco/burst = STRONG (new capture, not on GitHub yet - send it with the GitHub sync page).

<!-- rolled from MEMORY.md oct. 20, 2026 (cap 200) -->
- oct. 1, 2026 (Angelo) — **Re-deleted linear/G402/burst (3 exact copies of stationary) + linear/G402/highload r3 (2 files, no root/attacker)** - Basti's data push 805672a had RE-UPLOADED both after Angelo's sep. 30 deletes (5f9221c, 04edaf6), because his laptop still had the files. ⚠️ BASTI: delete your LOCAL copies (`python tools/push_data.py delete-local --area exports`, or delete the two folders) or your next data push re-adds them a third time.
- oct. 1, 2026 (Angelo) — **blackhole/star/G402/burst r1 (oct01 12:24 root): FIRST CLEAN STAR-HUB RUN, but NO BURST happened.** Hub verified (root -> attacker 20:50:0D:E7:1C:38 = node3 -> 5 victims, verify_topology OK, 8/8 integrity PASS, 0 probes at root in attack, cooldown 101%), CONFIRMED 2/2 (FR z -24.4, PDR z -14.6), timeseries textbook. Burst: every victim 1.0 probe/s in all phases, max 1-s jump 1 - no board was built as the burst target (Kyle's 4 children had no -ScenarioTarget; Basti's node2/node3 run log not on Angelo's laptop - ask him; burst code itself reviewed OK). MOVED to star/G402/stationary (user's call, oct. 1; exports + analysis + its 2 run logs; re-analysed there: all 3 gates PASS/CONFIRMED); the 10:04-10:56 failed-attempt logs stay in star/G402/burst. `tools/campaign_plan.json` G402/star/blackhole highload -> stationary (now [stationary, powercycle, burst, mobility]); burst still to be captured - check the wizard plan shows a BURST TARGET victim before flashing. 6th victim = node8 F4:2D:C9:73:E6:18: root logged its ~421 baseline probes and 0 in attack, but its telemetry was deleted from the board (user, oct. 1) - table has 5 of 6 victims; attack result unaffected. verify_attack.py: the 'all relays' note no longer says '0 honest relay(s) averaged 1.000' when the attacker is the only relay (star hub).
- oct. 1, 2026 (Angelo) — **Wizard: multi-laptop split presets no longer crash or skip the attacker MAC.** (1) A burst/mobility/powercycle preset with no ScenarioTarget used to THROW (killed the wizard on every root-only or victims-only laptop, e.g. `Cal/*star-blackhole-burst*` = root only); it now asks 'is the target on another laptop? [y/N]' and only stops on N. (2) A roster with local victims but NO attacker entry (e.g. `Kyle/star-blackhole-burst-g402.json`: 4 victims) never asked for the attacker MAC, so its victims fell back to that laptop's mesh_config.h = the oct. 1 'victims never join' failure; it now asks for the attacker's MAC (blank = no attacker). (3) 'no attacker board' preset warning reworded for split runs. (4) A literal vertical-tab byte made 'tools\verify_topology.py' print as 'tools / erify'; fixed. Tested by simulating both prompts.
- oct. 1, 2026 (Angelo) — **AUDIT of Basti's 7 commits (merged as 2fca35a): nothing broken.** No code deleted; all of Angelo's sep. 30-oct. 1 work intact (checked vs tag backup/angelo-2026-10-01). Firmware: 15/15 build_all_variants OK + wormhole root + sniffer, 0 warnings (IDF 5.5.4). Basti's firmware = root `[RXSTALL]` timing log (measure-only, marked temporary) + branch-drawn heartbeat tree (display-only, buffer bounds checked). Analysis: re-run of partial_mesh G402 gives IDENTICAL values in every existing column; new optional `MacRetryRate`/`MacFramesHeard` (sniffer-only, NaN without pcaps). All verdicts unchanged; tests pass; 18 presets valid; no broken function calls or doc paths after the docs/ reorg (thesis-deviate -> docs/deviations-limitations/, runbook -> docs/operations/). `push_data.py delete-local` targets datasets/analysis, NOT the code folder. ⚠️ Same day the `ESP32-Environment/analysis/` CODE folder was found deleted + staged on Angelo's laptop (cause unknown - likely an old-data cleanup that removed the whole folder); restored from git. When cleaning old data, delete only `analysis/baseline`, `analysis/blackhole`, `analysis/wormhole`, never the `analysis/` folder itself.
- oct. 1, 2026 (Angelo) — **STAR HUB WORKS ON HARDWARE; attacker MAC now comes from the WIZARD, not mesh_config.h.** First star+blackhole run: root -> attacker 20:50:0D:E7:1C:38 -> victims, STATUS OK, but only 2 victims joined - the rest were flashed from laptops whose `mesh_config.h` still had GitHub's F4:2D:C9:73:E6:18 (a VICTIM that run), so they scanned forever. FIX: `run_wizard.ps1` resolves the run's attacker MAC (read off the attacker > typed remote MAC > roster) and passes it to every blackhole child build: `run.ps1 -AttackerMac` -> `-DBH_ATTACKER_MAC_HEX=0x..ULL` (always passed, 0 = none) -> `blackhole_target.c` uses it ahead of mesh_config.h. NVS SET_ATTACKER_MAC still wins but the wizard full-erases each run. Star + unknown MAC = red warning. Multi-laptop: every laptop must use the SAME attacker. ALSO: root's EXPECTED_CHILDREN only counted remote boards with a JOB (Enter-default) -> root started with 2 victims; the wizard now REQUIRES the real number of children on other laptops (known count = floor) and prints the total. Identify-flow mismatch text no longer says 'capture will be FINE' for star. Tests: New-RunParams routing (bh attacker/victim only), resolution + gate blocks with fake input, run.ps1 -BuildOnly with/without -AttackerMac.
- oct. 1, 2026 (Angelo) — **Backup tag `backup/angelo-2026-10-01` (= c493943) on GitHub** before Basti merges his backlog. If Angelo's work is lost (force-push / bad conflict resolution), compare with `git diff backup/angelo-2026-10-01 origin/THESIS3`. Markers that must survive any merge: `STAR_HUB_BLACKHOLE` (mesh_setup.c), `MISSING_ATTACKER` (verify_attack.py), `SOURCE_SILENCED_MAX` (validate_integrity.py), `_shown(` (trim_run.py), hub rule in topology_graph.c/.py.
- oct. 1, 2026 (Angelo) — **PCAPs never come from `git pull`**: `.gitignore` excludes `PCAP/` + `*.pcap` (GitHub 100 MB cap), so `datasets/PCAP/` only exists on the laptop that ran the sniffer (created on first capture). Angelo's laptop has none. Share captures by copying .pcap + .json into `datasets/PCAP/`. **Preset mix-up:** `presets/Bas/linear-blackhole-stationary-g402.json` on Angelo's laptop was saved (oct. 1 10:04) with topology STAR + scenario BURST - name and contents disagree. Deliberately NOT pushed (user's call) so Basti's real linear preset isn't overwritten; fix or re-save it under a star name.
- oct. 1, 2026 (Angelo) — **GitHub had INCOMPLETE sept30 G402 runs - now fixed (a52a8a7).** partial_mesh had 4/9 files (no root, no attacker F42DC973E618), tree had no root log; anyone analysing from a pull got no PDR reference / INCONCL attacker rows. Both now 9/9. Teammates: `git pull`, then re-run `analyze.ps1` on blackhole partial_mesh + tree G402 stationary. Lesson: after a run, check the cell's file COUNT on GitHub (`git ls-files <cell> | wc -l`), not just that a data push happened.
- oct. 1, 2026 (Angelo) — **WORMHOLE PRE-FLIGHT (before the next wormhole run).** Builds CLEAN, 0 warnings, IDF 5.5.4: wormhole root (ACTIVE_ATTACK=2), Node A, Node B, plain victim (255) - NOTE `build_all_variants.ps1` has NO wormhole ROOT row. Firmware review: B always sends its normal copy + tunnels a 2nd in phase 2; A CRC-checks, resyncs, re-injects as PROBE_MAGIC_WORMHOLE; relay forwards both magics; root skips de-dup for the tunnel copy; root's own probe_pkt_t matches probe_relay.h. Last HARDWARE-confirmed wormhole = Jul 20 (pre-C7) - first post-redesign run is the real test; check Node A's end-of-run 'TUNNEL CARRIED NOTHING' banner + UART wiring (TX2/GPIO17<->RX2/GPIO16 crossed + GND). Analysis: full pipeline on archived star r1 + linear r2 wormhole -> WORMHOLE CONFIRMED 2/2 both, 180 duplicates found. TunnelLatency is ALWAYS INCONCL (no baseline values by construction) - expected, verdict uses TunnelIntensity+TunnelBytes. Wizard: wormhole plain victims = kind `control` (255 firmware, -DestAttack wormhole). FIXED `tools/trim_run.py`: os.path.relpath crashed (ValueError) when data and cwd were on different drives, aborting the trim after file 1.
- oct. 1, 2026 (Angelo) — **Star hub is FORCED on purpose; only star+blackhole picks a node's parent.** Defence + panel answers + per-topology table in `ESP32-Environment/memory/star-hub-forcing-2026-10.md`. Short: models the state after route attraction (same abstraction as the Milestone Form's MAC-addressed design); linear (chain, 1 child) and partial (2 children) force a SHAPE only, tree forces nothing - there the attacker's position comes from placement. Star ParentSwitchRate/HopStability are flat by construction.
- oct. 1, 2026 (Angelo) — **Checklist `[~] analysis older than capture` can be a FALSE alarm after `git pull`/merge.** `tools/inventory_cells.py` compares file MODIFIED TIMES (export CSV vs feature_table.csv); git writes pulled files with the pull time, so identical data looks newer than its analysis. Seen on partial_mesh + tree G402 stationary after the sep. 30 merge (9127233). Fix = re-run `analyze.ps1` for that cell (done here: both CONFIRMED 2/2, now `[x]`, 4/144 done). Expect it on every laptop that pulls new export files.
- sep. 30, 2026 (Angelo, night) — **STAR + BLACKHOLE = ATTACKER IS THE HUB (D-16, user chose option A + pin victims).** Thesis §4.2.2.1/Fig. 4.17 says the ROOT is the attacker; impossible here: standalone mesh → root is the probes' destination (nothing to forward to) and the referee (phases + PDR). And plain star firmware (max_layer 2) gives a layer-2 attacker no children → zero effect. Now, ONLY for `-DMESH_TOPOLOGY=0 -DACTIVE_ATTACK=1` (`STAR_HUB_BLACKHOLE` in `mesh_setup.c`): max_layer 3, root → attacker (hub) → victims. Victims (`MESH_ROLE_VICTIM`) turn self-organising off, passive-scan for the attacker's SoftAP (STA MAC+1 from `blackhole_target_get()` = NVS SET_ATTACKER_MAC else `BLACKHOLE_ATTACKER_MAC`) and `esp_mesh_set_parent()` it (IDF manual_networking pattern); never join the root directly, keep scanning + warn every 10th scan → root roster gate holds Phase 0 on a wrong MAC. So for star `BLACKHOLE_ATTACKER_MAC` is LOAD-BEARING again (wizard pre-run message says so). Power order root → attacker → victims. `topology_graph.{c,py}` star rule also accepts hub shape (root has 1 child, max layer 3); `verify_topology.py` FAILs a hub star whose hub isn't role `blackhole` (synthetic pos/neg test OK). Tests: py 17/17, C host 1240/1240. Root + attacker + victim star+blackhole builds CLEAN on IDF 5.5.4 (-Werror); regression builds linear-blackhole victim + plain-star victim CLEAN (other topologies untouched). Guard added: a scan finishing after the victim already joined never re-pins it. COMMITTED + PUSHED sep. 30 with the eve verifier/validator fixes (code+docs only - the MAC line in mesh_config.h and staged data were left out). Docs: thesis-deviate D-16, runbooks/TOPOLOGIES star section, mesh_config.h + topology_graph.h comments. NOT hardware-tested. Paper TODO: rewrite §4.2.2.1 + redraw Fig. 4.17. Star wormhole unchanged.
  **Data moved (user's call): the sept30 `blackhole/linear/G402/burst` r1 is now `.../G402/stationary/`** (exports + run_logs; analysis regenerated; old burst analysis output removed). Why valid: all 301 burst probes sit in node3's pre_baseline windows (t_anchor −559 s, excluded); max tx in labelled windows ≤12. Run logs still say `-Scenario burst` (true history). Verdict CONFIRMED (PDR z −19.7). FR FAIL = pooling 1 attacker (1.00→0.002) with 5 honest relays → 0.826, not a failed attack. Topology gate FAIL + 3 integrity WARNs = the root RESTARTED (flashed 11:31 and 12:17) — labelled baseline has 0 parent switches. `B4BFE932FE90`/`B4BFE934ED80` lost ~half their attack windows (logging gaps, no reboots). Attacker CSV named `victim_...` though role=blackhole (analysis reads in-data role). `analysis/combine_all.py` now reads/writes `datasets/analysis/` from any cwd. **`tools/verify_attack.py`: ForwardingRatio now tested on the ATTACKER ONLY (node_role=blackhole, `ATTACKER_SCOPED`)** + a `ForwardingRatio (all relays)` row as tier `info` (never counted) whose note counts the honest relays that kept it near 1 (user's call: show both, explain the FAIL; it fails at ANY attacker position once there are >~3 honest relays). **NEW dataset columns `NeighbourIn`/`NeighbourOut`/`NeighbourForwardingRatio` (features.py `compute_neighbour_forwarding_features`, legend in column_legend.py)**: a relay's forwarding measured by its children + parent (root arrivals by src_mac when the parent is root), never its own forward/drop counters — answers panel P6 self-report. Host-side only: re-run `analyze.ps1` per cell, NO recapture; pre-C7 captures get mostly empty columns. Blank when a needed board has no window. Verifier: secondary, attacker-scoped (G402: 0.996→0.006, z −23.7 PASS). Not in Table 4.11/EDA/leakage lists (paper decision). No node_role column → old pooled test decides. G402: attacker row z −137.9 PASS → CONFIRMED 2/2. Caveat (panel P6): that row is the attacker's self-report; PDR (root-measured) stays the independent primary. PUSHED sep. 30, 2026 as d5fd89a (code) + 7374bcf (data). Left uncommitted on Angelo's laptop (not his session's work): `mesh_config.h` BLACKHOLE_ATTACKER_MAC → 20:50:0D:E7:1C:38, `presets/Bas/*`, `presets/Cal/linear-blackhole-stationary-g402.json`, root/child `sdkconfig`, `root_node/dependencies.lock`.


<!-- rolled from STATUS.md oct. 20, 2026 -->
- oct. 19 ~6 PM (Basti) — paper files pushed: `Plan/Paper-Editing/` (working copy in `1-Working-Copy/`, Thesis 2 PDF moved there, guides, verification report + whole paper with fixes in GREEN). Members: re-read the green copy, carry accepted fixes into the working copy.
- oct. 19 late night (Angelo) — D-28: star + wormhole rebuilt as a hub star (end A = hub, B one hop deeper); firmware + run.ps1 + wizard + GUI + verify_topology + D-28 + checklist A30 + STAR-RUNBOOK.

<!-- rolled from STATUS.md oct. 20, 2026 (1 PM) -->
- oct. 20 ~10:30 AM (Angelo) — Trim page judges by file names too; #65: tree/G402 burst re-graded STRONG (two highload files had been imported into it).

<!-- rolled from STATUS.md oct. 20, 2026 (4 PM) -->
- oct. 20 ~1 PM (Angelo) — #67 / D-32: missing boards graded by role; standby board answered (GRADING-AND-THRESHOLDS.md §0b).
- oct. 1, 2026 (Angelo) — **star/G402/stationary REPLACED by the 2 PM run (captured as 'burst', no burst fired).** User's call: the old 12:24 r1 had only 5 of 6 victims (node8 telemetry lost); the 2 PM run has all 6. Old 12:24 run kept LOCAL ONLY on Angelo's laptop in `ESP32-Environment/archive/2026-10-01_star-G402-stationary-replaced/` (exports+analysis+run logs) and in git history. New r1 = 9 files: root `20:50:0d:e7:1c:38`=attacker hub, 6 victims; integrity 9/9, topology star hub OK, BLACKHOLE CONFIRMED 2/2 (FR z -24.0, PDR z -14.9); sniffer pcap moved too (MacRetryRate on 7 nodes). WHY NO BURST: see the FIRMWARE BUG entry above (Basti DID mark node3 = f4:2d:c9:73:e6:18 as target). Proof method: root arrivals seq_num jump across the attack = elapsed seconds for every victim (+0); a burst sender would be ~+300. ⚠️ BASTI + KYLE: delete your LOCAL `datasets/exports/blackhole/star/G402/burst/` (the 7 files) or your next data push re-adds them. Filenames differ per laptop because the label comes from the importing laptop's preset (no match -> card's victim_NODE-<MAC>); analysis keys on node_id, not the name.
- oct. 1, 2026 (Angelo) — **Burst can no longer fail silently.** (1) NEW `tools/verify_burst.py <cell dir>`: from the root arrivals only, per victim excess = sum(d_seq - d_t/1s); burst sender ~+300, others ~0 (works under blackhole too - the dropped burst still advances seq). Exit 0 FIRED / 1 NOT FIRED / 2 unknown. (2) `analyze.ps1` runs it for every scenario=burst cell; summary prints `burst : FIRED|NOT FIRED`. (3) `run_wizard.ps1`: a burst preset whose TARGET is the attacker now STOPS (attacker firmware has no burst code; the attacker picker keeps a stale target mark); flash plan prints who the burst sender is, or in RED that this laptop has none. Tested: real no-burst run -> NOT FIRED, synthetic +300 -> FIRED, analyze gate end-to-end.
- oct. 1, 2026 (Angelo) — **FIRMWARE BUG: burst NEVER fired on any attack run (blackhole or wormhole) — FIXED in `child_node/main/victim_main.c`.** The burst window was chosen by `#if ACTIVE_ATTACK`, but `child_node/main/CMakeLists.txt` never passes ACTIVE_ATTACK to victim_main.c (only mesh_common + root get it; git -S shows it never did, the mesh_common comment claiming otherwise was wrong). So every burst victim compiled as ATTACK_NONE and waited for the baseline root's 'Phase 0b' (2nd phase-0 broadcast) that an ATTACK root never sends -> 'BURST: window never detected before cooldown - skipped'. Proven: compile_commands.json shows victim_main.c with TRAFFIC_PROFILE=1 but no ACTIVE_ATTACK; the target f4:2d:c9:73:e6:18 (Basti's node3, correctly marked + built burst) sent exactly 656 probes in 656 s. FIX: window opens at RUN time on EITHER the attack phase (blackhole/wormhole) OR a baseline 'Phase 0b' - no build flag involved (also covers wormhole 'control' senders built as 255). Safe: the old phase-0b logic ran on 2 real attack runs and never triggered in phase 0. Built clean (-Werror) as blackhole burst victim + baseline burst victim, IDF 5.5.4. NOT yet run on hardware. ⚠️ EVERY laptop must git pull + reflash the burst target before the next burst run; `verify_burst.py` (analyze.ps1 burst gate) proves whether it fired.
- oct. 1, 2026 (Angelo) — **HIGHLOAD ROOT OVERWHELM — FIX APPLIED (built, NOT yet run on hardware).** Cause (Basti, docs/highload-collapse §12): the root wrote every arrival to SPIFFS+SD inside the single esp_mesh_recv() task; a write stall filled its mesh RX queue (32) and flow control throttled every child. Not the attack (baseline highload r1 also fell 23->7/s), not linear-specific (only topology run at 6-7-board highload so far). Fix in `root_node/main/root_main.c`: receive callback only queues the row (256-row FreeRTOS queue, `ROOT_ARRIVAL_QUEUE_LEN`), `arrival_writer_task` (prio 6 < listener 8) writes; full queue never blocks - drops are COUNTED and printed at run end; queue drained before log close. Plus root-only `esp_mesh_set_xon_qsize(64)` in mesh_setup.c, and arrival RSSI from the 10 Hz telemetry read (root arrival rssi was 0 in every run - data unchanged). `[RXSTALL]` line now also reports queued max / dropped / RXQ max. NOT a D-number (no data semantics change). Verify on the next 7-board highload run: arrivals stay ~20/s through cooldown, dropped 0. Doc §13 has how to read it.
- oct. 1, 2026 (Angelo, session summary) — **Loose ends + gotchas from this session:** (1) Basti's data push `c0079e3` RE-ADDED the 3 star/G402/burst files (byte-identical to stationary) - removed again in `4a00a3b`; any laptop still holding local copies re-adds them on its next data push. (2) Commit `f8e6f53` accidentally included the staged deletion of `tools/exports/run_ledger.csv` (header-only; nothing reads it; the real ledger is `datasets/exports/run_ledger.csv`) - restore with `git checkout f8e6f53^ -- ESP32-Environment/tools/exports/run_ledger.csv` if wanted. (3) Sniffer pcaps pair to runs by FOLDER: after moving a run, move its pcap too AND delete the stale `*_retry.json/csv` beside it, or pcap_retry keeps the cached refusal. (4) When teammates' pulled data sits STAGED, a plain `git commit` sweeps it in - commit through a temp GIT_INDEX_FILE (read-tree HEAD, add only your paths), then `git reset -- <your paths>`. (5) PowerShell 5.1 with `*>&1` turns a numpy RuntimeWarning into a terminating error inside analyze.ps1 - run it via `powershell -File` from bash. (6) Status line (user-level, not in repo): `~/.claude/statusline.py` shows model, ctx %, session (5 h) + weekly limit bars with reset countdown + clock time (added oct. 2), branch, '/model' hint; yellow at 20% / red at 30% context = say 'session summary' then /clear.
- oct. 1, 2026 (Angelo) — **Wizard: every 'which node is the <scenario> TARGET?' prompt now shows port status + can detect ports.** New `Show-ScenarioTargetMenu` in `run_wizard.ps1` (used by preset editor, fresh menu flow, remove-node reassign): each board shows `COMx plugged in` / `COMx NOT PRESENT` / `other laptop`; a 'Detect ports' option runs `Sync-RosterPortsByMac` (find boards by MAC, [Y/n] preview) and redraws; picking a NOT PRESENT board warns + asks [y/N]. Why: user picked a powercycle target while node3's COM20 was unplugged and the prompt didn't say so. Tested with stubs; parses clean. Respects -DryRun/-SkipMacCheck.
- oct. 1, 2026 (Angelo) — **linear/G402/jitter r1 CHECKED: all gates PASS.** 9 files (7 children + root telem/arrivals); integrity 9/9, topology linear chain of 8 (root->704B bystander->attacker 20:50:0D:E7:1C:38->5 victims), BLACKHOLE CONFIRMED 2/2 (attacker FR z -101, PDR 1.0->0.0 on all 5 victims, bystander 1.0), cooldown 101%, sniffer pcap PASS. JITTER FIRED: every node's phases = baseline 312.5 s / attack 190.5 s (standard 300/180). Run log is named `...stationary...` only because the preset filename was reused - root was built `-Scenario jitter`. ⚠️ KNOWN QUIRK (not changed, user to decide): `analysis/preprocess.py` assign_segments anchors t=0 at the attack start and labels only the LAST `PHASE_BASELINE_S`=300 s of phase 0 as baseline, so jitter's extra baseline seconds become pre_baseline (excluded) and timeseries plots show a 300 s baseline. Attack-length jitter survives. With one repeat, 'elapsed time stops predicting phase' can't be shown until r2/r3 draw different lengths. FULL RE-VERIFY (same night): preprocess+features+eda rebuilt from the exports into a temp dir = byte-identical to the analysis folder (raw == trimmed exports; nothing trimmed). 103 phase-0 windows (jitter's extra baseline) sit in pre_baseline. Child CSV names don't match roles (e.g. `child_node2_*` = the ATTACKER 1C:38) - labels come from the importing laptop's preset; analysis keys on node_id. Sniffer MacRetryRate covers only 313/683 windows on F42D (sparse, not a model input). **EDA BUG FIXED in `analysis/eda.py` run_dimensionality_reduction:** a column under 50% NaN overall but >50% NaN inside ONE class (LatencyHopRatio: 87% NaN in attack, no probes arrive) made dropna delete the whole attack class - PCA/t-SNE showed only baseline+cooldown. Now also excluded when sparse per class. Affected + regenerated: linear/G402/jitter and star/G402/stationary (their dimensionality_reduction.png only; every EDA CSV byte-identical). Other 5 cells unaffected. test_segments.py passes.
- oct. 1, 2026 (Angelo) — **HARDCODED-VALUE AUDIT of tracked code.** FIXED: (1) `sd_card_test/main/sd_card_test.c` printed `real_freq_khz`/`max_freq_khz` with `%d` - breaks -Werror=format on IDF installs where they're uint32_t; now `(unsigned long)` + `%lu` (CLAUDE.md rule). (2) Run schedule no longer copied by hand into host tools: NEW `tools/mesh_constants.py` `mesh_config_int(name, default)` reads `#define`s from mesh_config.h (warns + falls back if missing); used by `analysis/preprocess.py` (PHASE_BASELINE_S), `tools/validate_integrity.py` (PHASE_BASELINE/ATTACK/COOLDOWN_S), `tools/verify_topology.py` (PHASE_STABILISE_S), `tools/verify_burst.py` (BURST_COUNT). Same values today; jitter windowed output byte-identical, all gates + test_segments pass. ALSO FIXED (user: 'fix them all'): (3) `node_identity.c` MAC->nickname table REMOVED (it said b0:cb:d8:f3:32:18 = 'Node-5-Attacker'; it's the root) - fallback nickname is now `Board-<first>:<last>` from the board's own MAC, SD node_config.txt still wins; dashboard label only, not in CSVs; needs reflash to show. (4) `tools/board_check.py` built-in KNOWN MAC->nodeN table emptied; names now from presets/boards.json (optional) then `member_boards.json` matched on first:last byte. (5) `tools/run_matrix.py` DEFAULT_PORTS COM20/21/25/26 removed - --cmds prints `<ROOT_PORT>` etc. unless --root-port/... given. (6) `.mcp.json` untracked + gitignored (personal CLion path) - teammates' pull deletes their copy, which only pointed at Angelo's path. (7) mesh_config.h MESH_PASSWORD / ROUTER_SSID / ROUTER_PASSWORD wrapped in #ifndef (override with -D); mesh password STAYS in repo on purpose - all boards of a run, built on 3 laptops, must share it; lab-only key. Built clean IDF 5.5.4: root_node, child_node, sd_card_test. Paths in .ps1/.py/CMake are all env-derived (IDF_PATH, SystemDrive) - portable.

- oct. 20 ~11:45 AM (Angelo) — #66: SD reliability + crash diagnosis + verdict/Campaign/Verify consistency (rolled from STATUS.md "Recently done" oct. 20 ~10 PM).

- oct. 2, 2026 — **Campaign checklist got a `last run` column** (`tools/inventory_cells.py`: `judge()` now returns `when` = newest filename stamp via `name_stamp.parse`; `report_checklist` prints it per attack row as `Oct01 03:04PM (jitter)`, newest of that row's 4 drawn scenarios; benign rows too). Why: user wanted to see at a glance when each cell was last captured. Time = the capture stamp in the filename (export time), not file mtime, so a `git pull` doesn't change it. Display only; plan/ticks untouched. **Plan change: tree/blackhole mobility -> jitter** in `tools/campaign_plan.json` for G402, DLSU_Library, Goks (slot kept in place). home already had jitter, left alone. Why: paper §1.4 = static/no mobility; jitter is firmware-supported. Blackhole/wormhole sets still differ on tree. COMMIT + push so other laptops get it.
- oct. 1, 2026 night (Angelo) — **Campaign checklist fixes (`tools/inventory_cells.py`, wizard option 16):** (1) 'analysis older than capture' used FILE MTIMES, and `git pull` rewrites a pulled file's mtime even when bytes are unchanged -> finished linear/G402/jitter showed `[~]`. analysis_status() now compares CONTENT: current when every telem file of the run is in feature_table.csv's `source_file` column (mtime only as fallback for tables without that column). (2) Inventory table had fixed column widths -> 'stationary' (10 chars) fused with the repeat ('stationary1') and archive topology names shoved columns; all widths now sized from the data (also OFF-PLAN/DONE/NEXT blocks). Result: live done 6 -> 7/144, linear/G402/jitter `[x]`. --plan and archive modes still run.
- oct. 1, 2026 night (Angelo) — **star/G402/burst duplicates deleted a 3rd time (user's call).** The 3 files Basti's `589af2d` re-added were verified byte-identical (same git blob) to `star/G402/stationary/child_node{2,3,4}_star_blackhole_r1_oct01_02xxPM_telem.csv` - no data lost. Root cause unchanged: Basti's laptop still holds them locally, so his data push re-uploads them. He must delete `datasets/exports/blackhole/star/G402/burst/` locally (or `python tools/push_data.py delete-local --area exports`). star/G402/burst is still NOT captured.
- oct. 1, 2026 night (Angelo) — **Shared live board roster (web page): https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh** — user asked for an editable, live 'Boards by member' table usable across all 3 laptops (boards aren't all plugged into one laptop, so local detection can't do it). claude.ai artifact with a shared `db`: collection `boards`, one doc per board (id = lowercase MAC no colons) {member, nickname, mac (full), role root/child/attacker/?, scenario ''/burst/mobility/powercycle, laptop ''/Cal/Bas/Kyle/none, order, updatedAt, updatedBy}. Seeded from member_boards.json (8 boards, full MACs). Page flags >1 root/attacker, duplicate MAC, a scenario job on 2 boards, burst on the attacker; 'Copy as member_boards.json' exports. Source: `ESP32-Environment/tools/web/board-roster.html` (republish from it). ⚠️ The wizard still reads `member_boards.json` - NOT auto-synced; ask Claude to 'sync the board roster' (read db via ArtifactData -> write the file) or paste the copied JSON. Private until Angelo shares it (Share menu -> teammates as Contributor so they can edit).
- oct. 1, 2026 (Basti) — **'NO NODE IS DOWNSTREAM OF THE ATTACKER' is a FALSE ALARM on wormhole runs.** `mesh_setup.c:1283-1342` (root EXPOSURE block) and `analysis/exposure.py:52` count WORMHOLE_A/B as attackers with the blackhole rule (traffic transiting = victim). Both wormhole ends are honest relays (`wormhole_victim.c:199/417`) and B tunnels only its OWN probes, so the signature needs nobody below A/B. In a real tree exposure.py would label controls under A/B `downstream` (wrong per-node reporting; metadata, not a model input). Proposed fix (downstream rule blackhole-only; wormhole: B = affected, rest unaffected) — NOT applied, awaiting the user.
- oct. 1, 2026 (Basti) — **SD import misfiled wormhole CONTROLS under baseline — FIXED in `tools/import_sdcard.py` + `run_wizard.ps1` (Import-OneSdCard 'outside this run' note).** Controls run plain 255 firmware (wizard Kind `control`), so their CARD writes `baseline/<topo>/<loc>/`; USB export re-files with `-DestAttack wormhole`, but the SD importer filed by the card folder (its comment claiming otherwise was false). Result: all 5 controls of the run above (each with 1806 phase-2/label-2 rows) landed in `exports/baseline/tree/G402/stationary/` — 4 of them (`child_child-4..7`) arrived from a teammate's laptop. Fix: a card `baseline/` telem file whose rows contain phase 1 or 2 is filed under blackhole/wormhole (a baseline root never sends those, `root_main.c:516`); filename keeps `none`, same as a USB control export. Mounted card decides before copying; over USB the preset (Kind control + preset attack) only PREDICTS (`LIKELY FILED UNDER`) and the copied rows decide, moving the file either way (a re-import duplicate is removed). Tested on a simulated card from the real file (mounted + simulated USB, with/without preset, re-imports, PS 5.1 note logic); NOT yet run against a real board. Data fixed: all 5 now in `exports/wormhole/tree/G402/stationary/` (child-4..7 via `git mv`, still staged; child_node2 untracked), `.last_import_batch.json` repointed. ⚠️ Every laptop: pull before the next SD import.
- oct. 1, 2026 (Basti) — **FIRST POST-REDESIGN WORMHOLE TUNNEL WORKS ON HARDWARE (oct. 1 ~16:51, exported as wormhole/tree/G402 r1) — but the run is NOT a valid tree run.** Tunnel proven from the exports: B `20:50:0D:E7:0C:80` retry_count (tunnelled) 0->180 only in phase 2; A `20:50:0D:E7:1C:38` probes/tx 0->180 only in phase 2; root arrivals hold exactly 180 duplicated (src,seq) from B, all gt_label 2. Topology FAILED: all 7 children joined the ROOT directly (HOP DEPTH 1, `STATUS WARN flat like a star`), and a child was unplugged mid-baseline (F4:2D:...:18: 538 s vs 605 s, 2291 baseline rows). Not relabelable as star either (built tree = max_layer 25, star cap off; SD paths/names say tree). Keep it as a failed tree attempt / tunnel proof, not a dataset entry. WHY tree went flat: tree forces nothing (`mesh_setup.c:168`); ESP-MESH default high RSSI threshold is -78 dBm (`esp_mesh_internal.h`, IDF 5.3.5) and every board heard the root at -56..-77 dBm, so all picked the shallowest parent; an already-joined node only re-parents below -85 dBm, so moving/re-plugging boards mid-run changes nothing (B sat closest to root, -56). OPEN, team call: place deeper boards where root reads < ~-80 dBm, OR tree-only `esp_mesh_set_rssi_threshold` raise (selection internals undocumented; would need a D-number), OR fixed parents (breaks the runbook's 'mesh picks its own parents').
- oct. 2, 2026 (Basti) — **Analysis progress bars (ETA).** NEW `analysis/progress.py` (no deps): bar + elapsed + ETA on `preprocess.py` build_windows (~25 s of the ~28 s M6 on wormhole/tree/G402, 5053 windows), `features.py` topology + RSSI stability loops (~3-4 s each), and a weighted one-line-per-stage bar in `eda.py` (weights = measured stage share: time-series 30, PCA/t-SNE 33, correlation 18, tunnel 12). STDOUT only (stderr kills PS 5.1 callers, see Preferences), and drawn only when stdout is a console - captured/piped output (`analyze.ps1`'s `| Out-Host`, logs) is unchanged, so analyze.ps1 shows no bar. Proven: windowed, feature table and all 9 EDA CSVs byte-identical before/after; test_segments passes. Not yet watched live in the wizard. Known slowness left alone: features.py re-runs the whole M6 pipeline (~28 s) right after M6 did - it needs the gap-filled long table, which isn't saved.
- oct. 2, 2026 (Angelo) — **Flat tree / blackhole-as-leaf: how to retry + proposed fix (NOT built, awaiting user).** RETRY (agreed with user): re-run the SAME PRESET in the wizard, boards on the SAME COM ports, SAME repeat number - builds are cached per COM port so it does NOT recompile (unless firmware/attack/topology/scenario changed), but it DOES `-Wipe -Flash` = esptool erase_flash, which is what keeps the data clean. Do NOT just reboot boards and re-monitor: SPIFFS `telem.csv` opens with "a+" (`csv_logger.c:1241`), so the failed attempt's rows (logging starts in the 60 s stabilise window) stay at the top of the file, and each SD boot makes its own run folder the importer could pick. `run.ps1 -Wipe` WITHOUT `-Flash` (DELETE_LOGS = SPIFFS format) is also clean on SPIFFS. A joined node only re-parents below ~-85 dBm, so moving a live board does nothing - reset it. Placement: root at one end, attacker near root (~-60..-70), victims past the attacker reading the ROOT below -80 dBm, bystanders near the root; boot root, then attacker+bystanders, then victims; check HOP DEPTH >= 2 and victims' UPLINK = attacker at ~30 s. NOT BUILT (offered): wizard 'Re-run without flashing' = DELETE_LOGS + reset + monitors (saves ~30-60 s/board). WHY FLAT: TREE leaves `max_children` at the stack max 10 (`mesh_setup.c` ~169, `MESH_MAX_CHILDREN`), so the root can take all 8 when every board hears it above -78 dBm (oct. 2 log: -68..-77). PROPOSAL: (A) cap the ROOT's fan-out in TREE (e.g. 3) - forces depth, mesh still self-organises, but does not decide WHICH board parents; (B) per-run wizard flag pinning SOME victims under the attacker via `esp_mesh_set_parent` (the STAR_HUB_BLACKHOLE mechanism, attacker MAC from the wizard -AttackerMac, not hardcoded), rest self-organise -> bystander controls above + victims below (Fig. 4.17 shape). Recommended A+B; one rebuild each; needs a D-number. Unchecked: whether node_config.txt (SD) is read early enough to choose this per board without a rebuild.
- oct. 2, 2026 (Angelo) — **Pre-build now skips unchanged firmware + explains itself (`run.ps1 -BuildOnly`, used by the wizard's 'Pre-build every node's firmware first?').** User asked: rerunning shouldn't keep compiling, and the wall of cmake/ninja output should say what it means + whether there were errors (full output still shown, on purpose). How: a successful build writes `<build dir>\prebuild.stamp` (JSON: SHA1 of every firmware input - `<proj>/CMakeLists.txt, sdkconfig, sdkconfig.defaults, partitions.csv, main/**` + `components/**` - plus the -D flags + IDF_PATH). Same fingerprint + .bin present -> idf.py is NOT run ('Already built and up to date ... skipped'). CONTENT hashes, not mtimes (git checkout / idf.py rewriting sdkconfig bump mtimes). Inputs whitelisted because root_node/child_node hold old in-tree build dirs (bcr, bcba, build_check_*). Prints What/Build/Status (first build / settings changed / which files changed) before, and after: 'Built OK in Xs · no errors · 1.12 MB (25% space free)' or 'BUILD FAILED' + first error from `<build>\log\`. Wizard end line: 'N compiled, M already up to date, 0 errors' via `$global:PrebuildResult`. Builds from before this change show 'no up-to-date record' once, then skip. Flash step (`idf.py flash`) and menu.ps1's own pre-build are unchanged. Tested on IDF 5.5.4 (root/blackhole/tree/jitter COM3): built -> skipped -> simulated code change rebuilt.
- oct. 2, 2026 (Angelo) — **EDA PCA/t-SNE erased the blackhole victim's attack windows when few nodes are victims — FIXED in `analysis/eda.py` run_dimensionality_reduction (new 'label_nan_excluded' rule).** Found verifying blackhole/tree/G402/jitter (1 victim of 6): the victim's LatencyHopRatio is NaN in every attack window (no probe reaches the root) but present in baseline/cooldown; overall it was only 38% NaN so the Oct 1 per-class rule kept it, dropna deleted exactly the PDR=0 rows, PDR was then flagged 'constant' and the plot had no attack signal. Rule: a column defined for a node in one Label class (<=50% NaN) but missing in another (>50%) is dropped from the projection (column, not rows). Structural NaN (PDR on root/attacker) unaffected. Affected + regenerated (dimensionality_reduction.png only; all EDA CSVs byte-identical): tree/G402/jitter + partial_mesh/G402/jitter (drop LatencyHopRatio; victim PDR=0 windows in plot 0 -> 202 / 0 -> 403), linear/G402/jitter + linear/home/burst (drop ForwardingRatio + ConsistencyScore - FR carried nothing there: attacker rows were already dropped for NaN PDR; +191/+190 victim PDR=0 windows). Other 5 live cells unchanged. Plot subtitle now wraps. test_segments passes. Same verification: tree/G402/jitter dataset is SOUND - integrity 9/9, real tree depth 2, 1 victim (70:4B:CA:25:B7:68 under attacker 20:50:0D:E7:1C:38), jitter fired (331/206 s), BLACKHOLE CONFIRMED; the verifier's -inf = baseline sd 0 (PDR exactly 1.0 every baseline window), by design (`verify_attack.py:305`). Archive cells not regenerated. Known harmless: leakage_audit.csv row order of tied rows can swap between runs.
- oct. 2, 2026 (Angelo) — **Sniffer stop now asks 'are you sure' (`tools/sniff.py`).** User: a stray key stopped the sniffer half-way through a run. Enter (standalone wizard sniffer, options 23/26) and Ctrl+C (the only stop key in the wizard's separate in-run sniffer window) now only ASK: Y stops; any other key keeps recording; no answer in 10 s keeps recording; a 2nd Ctrl+C within 10 s stops. Status line turns red with 'STOP? Y = stop' while the question is open; .json stop reason says '(confirmed)'. While the question is open, P answers 'keep' (does not pause). The wizard's own --stop-file stop never asks. Only when a keyboard is attached (isatty) - unattended runs unchanged. Tested with a fake serial port + scripted keys/Ctrl+C (Enter+Y stops; Enter+x, Enter+silence, one Ctrl+C keep; Ctrl+C x2 stops); NOT yet tried on a real board/console. Wizard hint text updated (`run_wizard.ps1` standalone sniffer line).
- oct. 2, 2026 (Angelo) — **Dataset verification log + full sweep of the 9 live cells.** NEW `ESP32-Environment/docs/dataset-verification.md` (user asked: every verification request gets a dated, boxed block, newest on top, showing attack/topology/location/scenario/repeat + checks + full details; rule added to CLAUDE.md). Sweep result: 7 USABLE; linear/home/highload PARTIAL (known, r2/r3 baselines broken by highload collapse); **tree/G402/stationary DEGRADED - recapture r2 advised**: child-4 `704B` stopped ~53 s before the attack, child-5 `2805` stopped 97 s into it, `ED80` re-parented twice inside the analysed windows, 2 victims missing in cooldown (verdict still CONFIRMED, 7 of 8 nodes). linear/G402/stationary: `FE90`/`ED80` lost ~half their attack+cooldown windows to the §4.2.4.1 min-samples rule (raw complete but unevenly timed) - correct behaviour. Tool quirk: `verify_topology.py --dir <cell folder>` says 'No captured telem CSVs' for star; use `--dir datasets/exports --topology star --attack ... --location ... --scenario ...`.
- oct. 3, 2026 (Angelo) — Pushed the oct. 2 session (eda.py PCA fix, sniff.py stop confirm, wizard hint, dataset-verification.md, root docs). Pre-push checks: py_compile OK, run_wizard.ps1 parses, test_segments passes. Deliberately left local: root/child sdkconfig + dependencies.lock (IDF 5.5.4 rewrite would flip 5.3.5 laptops), presets, archive/*, untracked datasets. verify_attack `-inf` z = baseline sd 0, by design (verify_attack.py:305) — PASS, not a bug.
- oct. 3, 2026 (Angelo) — **tree/G402/burst r1 verified (verification #3) + exports pushed.** Verifier output correct (PDR 0.600 = 2 of 5 labelled children at 0; -inf = baseline sd 0). Burst FIRED inside the attack on target `F42DC973E618` (seq +~295) -> burst fix `6b90df5` works on hardware. ⚠️ `B4BFE932FE90` reports parent=root all run but its probes went THROUGH THE ATTACKER: attacker recv 835 in attack vs 656 sent by the 2 known victims (+179 = FE90's); 0 FE90 arrivals in the root's attack window; it also took phase changes 34/68/94 s late (resync is 10 s). preprocess already unlabels it (out of sync) so labelled data is clean; only RootArrivals shows 6->3. **CAUSE FOUND oct. 4 (verification #4): FE90's parent_mac was CORRECT - FE90 was reflashed between the 7 PM jitter run and the 8 PM burst run, from ANOTHER laptop, with a STALE pre-C7 image (built sep. 20-21, before `67c6475`): pre-C7 victims send every probe P2P to the compiled attacker MAC 20:50:0D:E7:1C:38 (= this run's attacker), so the attacker relayed/dropped them from anywhere in the mesh; pre-`add1e6e` (no root session id) explains the late phases.** FE90 behaved correctly in all earlier runs (jitter: 205 attack arrivals). Angelo's laptop built no child image after oct. 1 - it only flashed the root. Fix: reflash FE90 from an up-to-date checkout before r2. Idea NOT built (user's call): firmware commit in heartbeat + root roster gate rejects mismatches. feature_table/windowed_dataset are git-ignored by design (regenerate via analyze.ps1).
- oct. 4, 2026 (Basti) — **Children: export is SKIPPED by default after Ctrl+].** Why: the user missed the 'n', an unwanted USB export started, and the Ctrl+C that followed BSOD'd the laptop. The wizard now asks once per run (`$script:childExportMode`): [1] SKIP INSTANTLY is the default (NEW `run.ps1 -SkipExportNow`: no 5 s window, straight on to the next board); [2] the old export-unless-'n'. A "skip after 5 s unless 'e'" middle option was built and then REMOVED at the user's request (same day, never committed). The switch goes to children only; run.ps1 ignores it for the root, which always exports. It is off unless passed, so menu.ps1 and hand-typed runs are unchanged. If the root is set to trim+analyze and children are skipped, M6-M8 waits for the SD import. The 5 s key handling has not been tried in a real console yet.

## Rolled from MEMORY.md (oct. 22, 2026, cap)
- oct. 4, 2026 (Basti) — **Preset filenames now follow the picker heading: attack-topology-location-scenario** (`Get-PresetCellFileName`, e.g. `blackhole-linear-home-highload.json`; 'none' -> baseline, partial -> partial_mesh). All 24 files under `presets/Bas|Cal|Kyle` were renamed ON BASTI'S LAPTOP. Two odd ones: Bas's old `star-blackhole-jitter-g402.json` actually held topology LINEAR, so it is now `blackhole-linear-g402-jitter.json`; Cal's `SEPT25.json` became `blackhole-linear-g402-stationary-sept25.json` (it would have clashed). Presets travel by data sync, not code commits. The sync push only ADDS files, so old names stay on GitHub until removed with `push_data.py delete --area presets`, and a presets pull re-downloads Cal's/Kyle's old names as duplicates until those go too. Loading and grouping read the cell from the file CONTENTS, so old names still load, and saving an edited old-name preset offers the rename. Capture and run-log data filenames keep the old topology-first order on purpose. Picker cell headings are now colour-coded per tag (`$script:PresetTagAnsi`: BLACKHOLE red, WORMHOLE bold magenta, BASELINE bold green).
- oct. 4, 2026 (Basti) — **Node labels: node1 is the ROOT's.** `Get-FreeNodeLabel` now starts children at node2 and fills gaps first (node2,4,5,6 -> node3; node2-7 -> node8), even when the roster has no root (root on another laptop). `-ForRoot` keeps node1 for root labels. The edit-node Label prompt now shows the first free label. Add-node's attacker question was reworded: "The attacker (the board that drops traffic) is currently: node2. Change which board is the attacker?" Y opens the picker over ALL boards; it does not make the new node the attacker.

## Rolled from STATUS.md (oct. 22, 2026)
- oct. 20 ~4 PM (Angelo) — #68: sync deletions, import verification, Collect picker/identity, scenario on card, Halt board; everything committed + pushed.
- oct. 4, 2026 (Basti) — **Wizard: MAINTENANCE > "Wormhole UART tunnel test"** (`Invoke-UartTunnelTest`, modeIdx 29). It flashes `uart_link_test` to Node A + Node B, reads both consoles at once and prints PASS/WARN/FAIL per direction. Two lengths: quick 10 s, or a 2-min soak that counts lost/garbled pings (for extended or chained jumper wires). Only **B -> A** matters, because in `wormhole_victim.c` B only writes and A only reads. `uart_link_test.c` was rewritten: numbered, XOR-checksummed ~56-byte pings every 50 ms, plus a `LINKSTAT tx= rx= lost= bad=` line every 1 s. It still prints `[LINK OK]` / `RX received=0`, so the old runbooks still hold. Builds use `-DSDKCONFIG=<build dir>`, so no sdkconfig lands in the repo. Compiled clean on IDF 5.3.5; the parser and result table were tested on mock serial data; NOT run on hardware. Wire length is not a timing concern for the wormhole (~5 ns/m against ~87 µs per byte at 115200 baud). The real risk is loose joints in chained jumpers, which the soak test exposes.
- oct. 4, 2026 (Basti) — **BSOD 0xB8 ROOT CAUSE CONFIRMED: `silabser.sys`, the SiLabs CP210x USB-serial driver (11.3.0.176, built Apr. 2023).** First crash with a usable dump (`S:\MEMORY.DMP`; the kernel dump was rerouted off the nearly full C: on oct. 1). WinDbg `!analyze -v` gives `FAILURE_BUCKET_ID 0xB8_silabser!unknown_function`. Stack: USB bulk-IN completion -> WDF continuous reader -> silabser calls `WdfIoTargetStop` and WAITS inside the DPC -> bugcheck. So it is a driver bug, not firmware, cable, board count or disk space. Trigger: a pending USB read that ends abnormally. That means closing a port mid-read (this crash: Ctrl+C during a child's `export_logs.py` read), resetting or unplugging a board while it is being read, or USB glitches (hubs and docks make these likelier). 11.3.0 looks like SiLabs' latest Universal driver, but this is unverified because silabs.com blocks scripts. To avoid it: never Ctrl+C an export or SD read, never reset or unplug a board being read, and plug boards direct into the laptop. Untried fallback: SiLabs' legacy 6.7.x VCP driver. WinDbg is installed on Basti's laptop (alias `cdbX64.exe`, run elevated because MEMORY.DMP is admin-only; symbols cache to `S:\symcache`).
- oct. 4, 2026 (Basti) — **Presets can store the roster-gate total: "Expected children"** = how many CHILDREN (every non-root board, ALL laptops) the root waits for before Phase 0 (`run.ps1 -ExpectedChildren`). The JSON key is `expectedChildren`, written after `repeat`, and left out when 0/not set. It is set in Edit preset (new option [6], after Repeat; the header line "Expected :" shows it). It must be 0 or at least the number of children the preset itself lists, otherwise the save is refused. At run time, on the ROOT's laptop, it becomes the Enter-default of "How many children run on OTHER laptops?" (total minus this laptop's children). The oct. 1 no-default rule stays for presets WITHOUT it, because that default was a guess and this is the operator's own saved answer. A preset total lower than what the run already has is ignored, with a warning. The question is now also asked on a single-laptop run when the preset total exceeds this laptop's children. `Save-Preset` keeps the file's value unless `-ExpectedChildren` is passed (same rule as owner). The Copy / File-under-member / MAC / port saves carry it over. The end-of-run "save back / save as preset" stores the total confirmed at that run's question (`$script:gateTotal`). Tested with scripted menus/prompts on copies of real presets + the gate block (6 cases); not yet in a live run.
- oct. 20 ~11 PM (Basti) — #71: verified the 8-board paper (43 green edits), made paper v2 (code + data recheck, 64 green ops), status doc, Validation Basis check (6 wrong / 13 outdated), 33-slide defense deck; found MacRetryRate lost in 20 runs (B-mrr); jitter OUT.
- oct. 4, 2026 (Basti) — **Tunnel test: Q or Enter stops a listen early** (`Read-UartLinkStats` in `run_wizard.ps1`). It shows the results so far, with a "Stopped early after N s" line. The user asked so they don't have to wait out the 2-min soak. It uses a key, NOT Ctrl+C, because Ctrl+C with the COM ports open mid-read is the BSOD 0xB8 trigger (entry below). When stdin is redirected the key check switches off. Only that path was smoke-tested; a real key press was not. The same day the user ran the test on real boards and both directions PASSED. **NEW panel doc `docs/panel-answers/2026-10-04_WORMHOLE-TESTING-EXPLAINER.md`** ("how do you test the wormhole?": glossary, diagram, one probe's journey, 3 layers, worked 3-sigma example, follow-ups; REVIEWER-QUESTIONS §10 points to it). ⚠️ Found while writing it: the `mesh_config.h` WORMHOLE comment says B tunnels "INSTEAD of" sending to the root. That's stale: `wormhole_victim.c` sends the normal copy AND the tunnel copy, which the data confirms (duplicates). The `features.py` module header also says TunnelLatency "stays NaN", but its own docstring (~line 916) computes it as the spread between the two copies. Both left unedited.
- oct. 22 (Basti) — wormhole TREE: B held two hops below A (A H01 -> B H03, Fig. 4.18; thesis check in verification/); first version reached partial via shared code, rewritten so partial/star are byte-for-byte pre-session after preprocessing; tree builds + host test 79/79; pushed.
- oct. 4, 2026 (Basti) — **Board pickers now show each board's MAC**: scenario TARGET (`Show-ScenarioTargetMenu` + the preset-run picker), blackhole ATTACKER and wormhole Node A/B (`Set-AttackSubRoles` + the manual flow). All go through NEW `Format-PickerMacTag`: the recorded MAC first; falls back to this session's identify tag, else "MAC not read"). User asked, to tell which physical board is which. Parse-checked + rendered on sample boards, not yet seen in a live run.
- oct. 5, 2026 (Basti) — **blackhole/linear/DLSU_Library/stationary r1 verified (dataset-verification.md #4): USABLE.** The user asked whether PDR `z = -inf` is OK for the thesis. It is a genuine σ = 0: rebuilt from the RAW exports (seq join, no pipeline), honest children delivered 1,805/1,805 in baseline and 724/724 in cooldown, with root arrivals matching per phase exactly. The PASS stands, but **write "z undefined (σ = 0)", never "−∞"**, and quote the victims as 0/180. The verifier's 704B 0.0055 is one boundary window (423) holding a phase-0 probe. The attacker has no PDR because it sends NO probes of its own (`blackhole_victim.c:40`; its `probes_count` = probes received for relay). Re-trim = no-op (1 boot session per node; byte-identical), and the feature table re-runs identically. ⚠️ **Gate 2 Topology FAILs on this capture and is a false alarm:** `20500DE71C38` lost and regained the root at 66–93 s, while the wizard was full-erasing and reflashing the root (run log 10:52) after the children were up. That falls in the boot segment `verify_topology.py` reads as "baseline" because phase_id = 0 there too. The real baseline has zero route changes. Not fixed in verify_topology.py (user's call).
