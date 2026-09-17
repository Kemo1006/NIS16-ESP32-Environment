# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 17, 2026 — FIXED + PUSHED (`a4f87b4`, `origin/Unified`): "Run analysis only" (both wizards)
  always read the RAW export, ignoring `trimmed\` entirely — new `Select-AnalysisInput` (mirrored in
  both files) now defaults to `trimmed\` when present, blocks (default: cancel) on a stale/incomplete
  trim missing raw files, and blocks (default: cancel) when a run's ROOT has no `*_arrivals.csv` —
  PDR/LatencyHopRatio/TunnelLatency would otherwise come out silently NaN with no warning. Verified
  against synthetic folders (up-to-date/stale trim, missing arrivals) plus the real
  `blackhole/linear/G402` export. Also in this push: `csv_logger.c`'s arrivals SD-mirror flush reused
  the TELEMETRY row counter (which resets on its own cadence), so arrivals almost never flushed
  mid-run — a root losing power before `csv_logger_close()` could lose most of its arrivals despite
  telemetry surviving; gave arrivals their own counter. NOT build-tested (`idf5.3_py3.14_env` still
  broken on this machine) — reviewed line-by-line; reflash root + one test run before trusting. Also
  fixed: Windows PowerShell 5.1's `ConvertFrom-Json` does not enumerate a top-level JSON array, so a
  2+ file SD card crashed the import picker with `Cannot convert System.Object[] to System.Int32`
  (reported as a teammate's crash; the catch block's "is python on PATH?" hint was a red herring, not
  the cause) — fixed with `| ForEach-Object { $_ }` in `Get-CardFileList`/`Import-OneSdCard`;
  reproduced live in PS 5.1 before shipping the fix.
- sep. 17, 2026 — DIAGNOSED: `blackhole/linear/G402`'s exported "root" file (MAC `2805A532D7B4`)
  isn't this run's actual root — every victim's `parent_mac` traces to `B0CBD8F33218` (the preset's
  real root), whose SD card/arrivals were never imported. Distinct from the known stale-
  `BLACKHOLE_ATTACKER_MAC` failure (no arrivals file exists at all here, vs. header-only there) — same
  "PDR NaN" symptom, different cause. Fix: import `B0CBD8F33218`'s card, remove the stray
  `2805A532D7B4` file from the export + `trimmed\`, re-trim, re-analyze.
- sep. 17, 2026 — BUILT in both wizards: "Trim exported CSVs only" is its OWN DATA menu option now
  (`run_wizard.ps1` Idx 10 `Invoke-TrimOnly`, `menu.ps1` Action 11), not folded into "Run analysis
  only" — that action's M6->M8 pipeline runs off the raw export with no trim step (it never had one).
  Both shell out to the EXISTING `tools\trim_run.py --apply` (never `--in-place`), which already
  writes to a `trimmed\` subfolder and leaves the raw export untouched by its own design. Also:
  `run_wizard.ps1`'s manual-flow child-count prompt now accepts `0` for a root-only capture (was
  `-ge 1`) — downstream code already handled an empty roster gracefully. Not hardware-tested.
- sep. 17, 2026 — BUILT: **capture provenance** (build-stamp on `runs.csv`, `--list-json`/`--files`
  numbered file picker in both wizards) — ⚠️ firmware still NOT compiled, build before trusting; full
  writeup in ARCHIVE.md.
- sep. 17, 2026 — BUILT in `run_wizard.ps1` only (`menu.ps1` still has just the edit-a-node step —
  see ARCHIVE.md): "Adjust the plan?" gained ADD / REMOVE a node beside edit/topology; an edited
  preset now offers "save these changes back into <preset>" as its own prompt (separate from "save
  as a new preset", which still appears only for a from-scratch roster); and the mode menu gained
  "Run a capture without a preset", skipping the preset picker even when presets exist. Remove
  refuses to drop the ROOT (swap root first via that node's Role field) or to break "exactly one
  attacker". Three bugs the user then hit on a live run, all fixed: (1) ⚠️ MANUAL-flow boards never
  carried a `Mac` field (only preset-loaded ones did, via `ConvertTo-Roster`) while
  `Resolve-BoardMac` caches with `$Board.Mac = $mac` — a PSCustomObject cannot gain a property by
  assignment, so the confirm table threw AFTER every question was answered and AFTER the
  attacker-MAC gate had rewritten `mesh_config.h`; pre-existing, but the new no-preset option made
  it the default path. Every construction site now seeds `Mac = ''`, plus an `Add-Member -Force`
  fallback (as `Add-BoardMacs` always used). (2) the blackhole role menu FORCED one child to be the
  attacker — with a single child that was no choice at all, and it yielded an attacker with no
  victims, i.e. no attack signature; it now always offers "None of these - they are all VICTIMS",
  the single-laptop twin of the existing multi-laptop escape. (3) `Show-Menu` printed "Type 1-1" for
  a one-option menu and rejected Enter; it now says "Press Enter (or type 1)" and accepts it. NOT
  hardware-tested; parser clean.
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
- ⚠️ Root-as-blackhole-attacker (STAR only) proposed sep. 16, NOT built — team decides first; full
  plan at `.claude\plans\mutable-honking-spindle.md` (Basti profile). Rolled to ARCHIVE.md for detail.

## Durable facts & constraints
- ⚠️ **CORRECTED sep. 17, 2026** (was stale, and answers the old "no sync transport between
  laptops" question): the git repo root is this whole `Unified/` folder (code, docs, `Paper/`,
  `ESP32-Environment/` all inside it), not `ESP32-Environment/` alone — branch `Unified`, remote
  `origin` = `https://github.com/Kemo1006/NIS16-ESP32-Environment`, pushed and up to date as of
  sep. 17. GitHub is now that transport: `git pull` on another laptop gets the same
  MEMORY.md/STATUS.md/code.
- Thesis: DLSU CCS, CTTHES2/THES3. Proponents: Calpoporo, Carlos, Ong, Reinante. Adviser: Cu, Gregory G.
- Toolchain: ESP-IDF **v5.3.5** (bundles Python 3.11 + compiler); boards enumerate as "Silicon Labs CP210x USB to UART Bridge"; Windows reassigns COM numbers every plug — always re-check.
- Mesh identity is shared across every board: `MESH_ID {0xAB,0xCD,0xEF,0x01,0x23,0x45}`, `MESH_PASSWORD "MeshSecure2026!"` in `components/mesh_common/include/mesh_config.h` — never change between flashing root and victims.
- The FOLDER you build from decides the role, not the COM port: `root_node/` → root, `child_node/` → victim.
- Blackhole signature (M2): attack-window PDR ~0.08 vs 0.94 benign, ForwardingRatio ~0.02, root logs zero arrivals. Wormhole signature: duplicated `(src_mac, seq_num)` arrivals (×2 on the tunnelled node).
- **aug. 29, 2026 — honest nodes cannot observe their own forwarding.** Victims send with `esp_mesh_send(NULL, ..., MESH_DATA_TODS)` (`victim_main.c:164`), so the mesh stack relays *below the app layer*; only the blackhole attacker sees transit packets, because victims address it explicitly (`victim_main.c:159`). The 11-column schema gives every node `probes_count`/`tx_count`/`retry_count`, but they mean "probes I originated" on a victim and "received/forwarded/dropped" on the attacker. ⇒ C7 (un-gate the relay features) is **not** a mask widening — there is no honest-relay data to un-gate. Three options in `Plan/THESIS3-MEMBER-HOWTO.md` §1 C7.
- Feature coverage is run-type-dependent: baseline 10/16, blackhole 13/16, wormhole 13/16, **combined matrix 16/16**. "No feature uniformly NaN" is a claim about the assembled dataset, not any single run.
- **THESIS 3 DRIVER — `Paper/Improvements.pdf`** (CTTHES2 panel comments, received ~aug. 2026). 8 timestamped rows → 7 distinct problems: single-feature decidability, no attack parameter variation, redundant r1–r3, one environment only, no declared IoT scenario, no attack provenance/validation, uncharacterised benign baseline. Full analysis + response plan: `Plan/THESIS3-PANEL-PLAN.md`.
- ⚠️ **Known leak (panel P1):** the 5 role-gated features are non-NaN ONLY for their attacker role — `ForwardingRatio`/`IngressEgressDelta`/`ConsistencyScore` for the blackhole attacker, `TunnelIntensity`/`TunnelBytes` for wormhole endpoints. So "is this column NaN?" is a **perfect label**. Combined with PDR 0.08-vs-0.94, the dataset is trivially separable — the panel's "then ML is unnecessary" objection is correct as of aug. 2026.
- ⚠️ **Paper-scope conflict R-A:** paper §1.4.1 + abstract commit to a *"controlled indoor environment"*. The DLSU-campus decision deliberately relaxes that — must be amended in §1.4.1/abstract and logged in `thesis-deviate.md` as D-5, not slipped in.
- ⚠️ **Paper-scope conflict R-B:** paper §1.4.1 explicitly EXCLUDES *"grayhole, Sybil, or selective forwarding"* from the threat model. Partial/probabilistic drop rates ARE selective forwarding — so the obvious fix for the panel's "vary the attacks" comment collides with approved scope. Safest reading: the panel asked for different **attacker positions**, not different drop rates. Adviser decides (plan §7 R-B).
- ✅ **Already have a pre-registered attack signature (panel P6):** paper **§3.4.4 + Tables 3.4/3.5** state the expected observables for blackhole and wormhole, written at proposal time before any capture. Quote as-published; NEVER edit them to match results. §3.3.1.1/§3.3.2.1 hold the theory citations.
- **Attack-validation framing (panel P6):** blackhole/wormhole are defined by adversary BEHAVIOUR, not protocol — so LEACH/AODV/RPL datasets are valid comparison points and sources need NOT be ESP32-specific. Validate by *definitional conformance* (criteria from Karlof & Wagner / Hu-Perrig-Johnson vs. what we implement, failures declared), then match signature SHAPE not absolute values. Tables drafted in plan §5.1.
- Two conformance gaps to declare, not hide: (a) our blackhole is a **placed relay**, it does not *attract* traffic by false route advertisement — hence the paper's name "Forwarding Suppression (Blackhole)"; (b) our wormhole produces duplicate arrivals but whether parent selection re-forms around the fake link is unproven — hence "Topology Distortion (**Wormhole-Inspired**)". The paper's own functional naming (§4.2.1.2/4.2.1.3, Tables 4.6/4.7) already makes the narrower, defensible claim — lead with it.
- ✅ **§2.8 + Table 2.8 already survey existing wireless datasets** — extend that table for the dataset-comparison work, don't write a new section.
- ⚠️ **Known circularity (panel P6):** the blackhole attacker counts its OWN drops — the evidence the attack occurred comes from the node performing it. Needs an independent observer (sniffer node / monitor-mode adapter) or root-side accounting.
- Every attack/traffic parameter is a compile-time constant: drop rate 100% (`blackhole_victim.c:195`), `PROBE_INTERVAL_MS 1000`, `SAMPLING_INTERVAL_MS 100`, phases 60/300/180/120 s = 11 min (`mesh_config.h:129-138`), and `BLACKHOLE_ATTACKER_MAC` is a `#define` (`mesh_config.h:207`). `run.ps1` exposes topology/role but **no** attack-intensity flags → r1/r2/r3 differ only in RF noise, and attacker position can't change without re-flashing every victim board.
- I-017 recurring hazard: children left powered through the run's later phases overfill SPIFFS (~1.1 MB) and become unreadable on export → carry each child back UNPLUGGED; `board_check.py --port COMxx --wait 75` before a run (≥50% SPIFFS → wipe+flash first).
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
- ⚠️ WORMHOLE's equivalent run-killer is DIFFERENT — it has **no MAC at all** (the tunnel is a
  physical wired UART1 link between the two endpoint boards; `mesh_config.h:243` says so outright,
  and wormhole victims send plain TODS since the P2P-to-a-MAC path is `BLACKHOLE_VICTIM_TARGET`
  only). Its silent failure is a dead/mis-wired cable: TunnelIntensity/TunnelBytes/TunnelLatency
  come out empty while both boards look healthy. ⚠️ Node B CANNOT detect this — `uart_write_bytes()`
  succeeds into an unterminated line, so B's "Tunnelled" counter climbs regardless; only Node A can
  prove a frame crossed. Guard added sep. 16 on Node A: if `s_tunnel_received == 0` at terminate it
  prints a TUNNEL CARRIED NOTHING banner (check B-TX→A-RX + COMMON GROUND; `uart_link_test` is the
  bring-up project).

## User preferences
- (none recorded yet)

## Failed approaches — do not retry
- Passing `idf.py -D` flags as `@($spec.Flags)` — that is an array SUBEXPRESSION, not a splat, so both
  defines merge into ONE arg (`-DACTIVE_ATTACK="1 -DMESH_TOPOLOGY=2"` → build failure). Use a plain
  variable and `@flags`. `build_all_variants.ps1:47-53` documents the same gotcha.
- Spawning a build/flash window as plain `powershell.exe` — `idf.py`/`esptool.py` are POWERSHELL
  FUNCTIONS from `C:\Espressif\Initialize-Idf.ps1`, and functions don't survive into a child process
  (only env vars do). Dot-sourcing it with no `-IdfId` also fails silently: `idf-env config get
  --property python --idf-path <path>` returns the STRING "null", not an error. Fix in use:
  `Get-EspIdfActivation` reads the real Start Menu shortcut's `-IdfId` at runtime (never hardcode it —
  a reinstall changes it).
- Long `idf.py -B <dir>` build-directory names in this repo (e.g. `build_cc_verify`) — the workstation
  path is already deep, so object paths cross Windows' 250-char `CMAKE_OBJECT_PATH_MAX` and ninja
  fails inside the **bootloader** subproject, long after the app's own files compiled fine. The CMake
  warning names the path but the failure looks unrelated. Use short names (`bcc`, `cwa`, `bjs`).
  ⚠️ **Confirmed sep. 17, 2026** on teammate Angelo Calpoporo's machine: a longer Windows username
  lengthens `%LOCALAPPDATA%` enough that the same nested bootloader-subproject `.obj.d` path (fine on
  a short-username machine) measured 265 chars there — over real Windows `MAX_PATH`, not just
  `CMAKE_OBJECT_PATH_MAX`. Fix proposed, not applied: `HKLM\...\FileSystem\LongPathsEnabled=1` (needs
  admin); no-admin fallback would need an `$env:ESP32_BUILD_ROOT` override added to `run.ps1`'s
  hardcoded `$buildRoot` so a `subst`-shortened path works instead.
- Non-ASCII characters (`⚠`, `—`, `…`) anywhere in a Python tool's **module docstring** when it is
  passed to `argparse` as `description` — the Windows console is cp1252, so `--help` dies with
  `UnicodeEncodeError` before printing anything. `tools/command_center.py` is deliberately ASCII-only
  and calls `sys.stdout.reconfigure(encoding="utf-8")` before `rich` draws (its box-drawing
  characters hit the same wall on the first repaint).
- Splitting recovered SPIFFS dumps on newlines after stripping page metadata — welds row tails to heads and fabricates data that passes a field regex. `recover_spiffs.py` now accepts only byte runs delimited by `\n` on both sides.
- `run_matrix.py --record` with hand-typed `--repeat` — silently re-recorded the wrong run. Use `--autorecord` (scans, validates, records; no flags to mistype).
- Powering the SD reader module's VCC from ESP32 3V3 — its onboard AMS1117-3.3 regulator drops ~1.1-1.3V,
  leaving the card below its ~2.7V minimum. Symptom: CMD0 succeeds (R1=0x01, card answers "idle") but
  ACMD41/OCR times out forever (0x107) — looks like a wiring fault but isn't. Use VIN/5V instead; the
  module's 74HC125 level-shifter runs off the regulated 3.3V rail regardless, so 5V-in never puts 5V on
  the ESP32's GPIOs for this specific module.
- sep. 16, 2026 — Matching a `printf` format specifier to `sdmmc_card_t`'s `real_freq_khz`/
  `max_freq_khz` declared type — it differs by ESP-IDF version (see CLAUDE.md bootstrap facts).
  `sd_status.c`'s boot-check `rep()` now casts explicitly (`(unsigned long)x` + `%lu`) instead.
