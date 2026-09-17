# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
- sep. 18, 2026 — BUILT (`run_wizard.ps1`/`menu.ps1`, uncommitted): (1) **Main-menu declutter** — the
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
  fixed to `-Recurse`. The pre-existing `presets\linear-blackhole-none-g402.json` git conflict (still
  UU, see STATUS.md Blockers) was left untouched, still sits unfiled (its MACs resolve to Bas).
  Tested: 21 PS-unit checks (owner detection, folder recursion, same-filename coexistence, Save-Preset
  owner precedence, grouping order) + scripted-stdin runs of both launchers' startup and submenu.
  NOT hardware-tested (no board touched by any of this). PS 5.1 trap hit and fixed:
  `[ordered]@{}` has `.Contains()` but no `.ContainsKey()` — see the global
  `powershell_menu_script_traps` memory (not this file).
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
