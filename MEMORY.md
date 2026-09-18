# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
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
