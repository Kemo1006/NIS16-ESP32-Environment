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
