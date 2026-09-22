# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 22, 2026 — **All 4 boards reflashed** with `ab74ec4` (COM3 ROOT/bcr, COM10+COM9 victim/bcbv, COM11
  attacker/bcba; MACs re-read via `esptool read_mac`, matched to `presets/Cal/TRY.json`, hashes verified).
  ⚠️ COM10 boot 9 + COM9 boot 1 were never exported — the reboot moved them to `<leaf>/_archive/`, which
  `import_sdcard.py` deliberately skips. Recover by hand from `_archive/`. User accepted the loss.
- sep. 22, 2026 — ⚠⚠ **STILL RUNNING was STICKY — the live-flag bug, now fixed.** `sd_is_live_mirror()`
  compared PATH STRINGS only, but `csv_logger_close()` nulls the mirror FILE*s at TERMINATE and keeps the
  path strings (ARCHIVE_SD needs them). So after ANY completed run every file on that card reported
  STILL RUNNING for the rest of the boot and the importer refused it — seen live on COM10+COM9. Now gated
  on an OPEN handle. ⚠️ REFLASH needed; until then read the card in a reader, or power-cycle the board.
- sep. 22, 2026 — **Per-file CSV delete, BOTH sources.** New firmware `DELETE_SD_FILE=<rel>` deletes ONE
  capture (`DELETE_SD_PATH` only ever took whole folders, which is why `--delete-source` used to be
  refused over `--port`). Guards: `sd_rel_capture_file_valid()` accepts only `*_telem.csv`/`*_arrivals.csv`
  — so **runs.csv/location.txt can never be deleted this way** — and the board refuses a file it has OPEN.
  Host: `export_logs.py --delete-sd-file`, `import_sdcard.py --delete-source` (now allowed with `--port`),
  wizard picker's `d` works over USB too. Auto-delete-after-import stays OFF for USB (opt-in only).
- sep. 22, 2026 — **Children now stop cleanly at TERMINATE.** `heartbeat_task` was the only thing still
  transmitting after a run (`while(true)`, timer-driven); it now exits for non-root nodes. probe_gen and
  telemetry already self-exited; relay_task parks on an empty queue. Root keeps beating (owns the member
  table). App-level only — the child stays joined and USB-reachable. All 6 variants build clean.
- sep. 22, 2026 — **Location pre-flight now covers the MANUAL run path too**, via shared
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
- sep. 22, 2026 — **SD files no longer date to 1980.** get_fattime() feeds `time(NULL)` into every FAT
  entry; with no RTC that is 1970 -> clamped to 1980. `sd_status_seed_clock_from_build()` seeds the clock
  from BUILD stamp + uptime atop `sd_status_run_boot_check()` (all 5 role call sites). ⚠️ build-time+uptime
  is **a dating aid, NOT a measurement**; boot counter + runs.csv stay the exact record.
- sep. 22, 2026 — **Location pre-flight in the wizard.** "Yes - use it" now reads each board's
  location.txt, diffs it against the preset, and offers to fix it BEFORE flashing. The board picks its
  `<location>` folder from its OWN card, not the menu answer, so a mismatch splits one run across two
  site folders — hit for real 2026-09-22 (ran `-Location home`, cards said G402, `home/` was empty).
- sep. 22, 2026 — **Root arrivals.csv exports fine over USB**; runs.csv `rows` is TELEM-only, so the
  manifest-vs-actual check is telem-only (it false-alarmed on every arrivals import).
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
- sep. 22, 2026 — ⚠️ **ROOT CAUSE of "sometimes 0 rows off the SD card" (D-13): `fflush()` without
  `fsync()`.** On ESP-IDF's FAT VFS `fflush()` writes the BYTES but not the **directory entry**, so any boot
  not reaching `csv_logger_close()` (brownout, reset, card pulled live) left a file whose recorded size was
  **0** — rows present, unreachable. Fixed: `sd_mirror_sync()` = `fflush` + `fsync`, rate-limited by
  `LOGGER_SD_SYNC_INTERVAL_MS` (**5000 ms**, time-based), forced unconditionally in `csv_logger_flush()`.
  ⚠️ **Does NOT repair existing cards** — a PRE-FIX 0-row card file is **LOST DATA, not "the node logged
  nothing"**. Compiles clean; **NOT hardware-tested** (needs a board + mid-run reset).
- sep. 22, 2026 — **Export has TWO sources, one pipeline.** `run_wizard.ps1` asks *board over USB* vs
  *pulled SD card*, then runs the SAME picker → dry-run → confirm → import (`Import-OneSdCard -Card|-Port`).
  New firmware cmds **`LIST_SD`** + **`EXPORT_SD_PATH=<rel>`**; `LIST_FILES` adds `|<bytes>|<rows>`. Host:
  `import_sdcard.py --port COMx`. Both routes verified byte-identical.
- sep. 22, 2026 — ⚠️ **Over USB, row counts come from `runs.csv`, not by counting the file.** `?` NEVER renders as `0`.
- sep. 21, 2026 — **`docs/EXPECTED-RESULTS.md` §0 = how to READ every number.** **NaN ≠ 0** (NaN = nothing
  to measure); RSSI closer to zero = stronger, `0` = no-parent placeholder; **`z` = normal wobbles from
  normal**, threshold 3 from Zhukabayeva 2025. Full text in ARCHIVE.md.
- sep. 21, 2026 — **C7 OPTION 1 SHIPPED (D-12): every node relays hop-by-hop at the app layer.** Shared
  `probe_relay.{h,c}`; victims send to their PARENT; **the attacker runs the SAME relay, differing by ONE
  boolean callback**. ⚠️ This IMPLEMENTS the paper (§3.1.3.2) — the old TODS behaviour was the deviation.
  ⚠️ **Pre-C7 and post-C7 captures are NOT comparable.** Full rationale: D-12 in thesis-deviate.md.
- sep. 21, 2026 — ⚠️ **TRAP THAT WOULD HAVE SILENTLY KILLED EVERY WORMHOLE RUN.** The relay first forwarded
  only `PROBE_MAGIC`; Node A's duplicate carries `PROBE_MAGIC_WORMHOLE`, so every intermediate relay would
  have dropped it and wormhole runs would have looked clean. Both magics now
  relay. **Any future change to the relay's accept-filter must re-check this.**
- sep. 21, 2026 - **`leakage.py` is DATASET-AWARE**: it asks how many roles carry each relay column, never hardcodes.
- sep. 21, 2026 — **A stale `BLACKHOLE_ATTACKER_MAC` is NO LONGER a run-killer** — bookkeeping only.
  The old "RUN WILL BE EMPTY / ZERO arrivals" alarms are FALSE now and would abort good captures;
  downgraded in `run_wizard.ps1` (the launcher in use), BOTH copies in `menu.ps1`, and the attacker
  boot banner. ⚠️ `BLACKHOLE_ROLE` is still REQUIRED — it selects which source file builds.
- sep. 21, 2026 - **`layer` -> `hop` (D-11).** New `hop` column (root = 0); `LayerChangeCount` -> `HopChangeCount`; values unchanged.
- sep. 21, 2026 — **Smart trimmer**: `trim_run.py` scores boot sessions on PHASE PROGRESSION, not
  length (the old rule kept a long idle session over a short/aborted real run). Proven: 400-row real
  run (+102.6) beat a 3000-row idle session (-146.5). Warns if two look real, or none does.
- sep. 21, 2026 - **`verify_topology.py --structure`** rebuilds the parent/child table from CSVs (wizard VERIFY menu).
- sep. 21, 2026 - **`docs/REVIEWER-QUESTIONS.md`** answers every adviser/panel side comment against verified code.
- sep. 20, 2026 - **CORRECTION (ARCHIVE.md): "only ONE cell has data"/"zero wormhole captures" were WRONG** - `inventory_cells.py` is the source of truth; `archive.ps1` MOVES data out of exports/.
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
- Long `idf.py -B <dir>` names — deep paths push object paths past Windows `MAX_PATH`; ninja fails in the
  **bootloader** subproject long after the app compiled, so the error looks unrelated. ✅ **FIXED in
  `build_all_variants.ps1` (sep. 22, 2026)**: it used `build_check_<Name>` and the longest row (BLACKHOLE
  attacker) measured **exactly 260** — reporting FAILED for good code, with the budget shifting per user's
  own path. Now a per-variant `Bld` field (`bcr`,`bcba`,…) + a preflight WARNING. ⚠️ **Don't rename them
  back.** Still unapplied alternative: `LongPathsEnabled=1` (admin).
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
