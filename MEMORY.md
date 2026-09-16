# Memory — facts, decisions, preferences

<!-- FACTS ONLY — behavior rules belong in CLAUDE.md. One line (or short block) per entry, newest first.
     SHARED across every laptop/user on this project — every Claude session logs here after any
     user-requested change (see CLAUDE.md → Working rules). Write cold: a session on a different
     machine with zero other context should be able to act on an entry without asking again.
     Read when you need the "why" or a fact, not at session start.
     Cap: 200 lines — move the oldest entries to ARCHIVE.md when near it. -->

## Decisions
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
- sep. 17, 2026 — BUILT: "edit a specific node" on the pre-flash plan summary, both `menu.ps1` and
  `run_wizard.ps1` (independent implementations — the two scripts' board/roster models differ, kept
  in sync in spirit only). After the Attack/Topology/"Order (root is always last)" box, the operator
  can now: edit one node's port/label/toggles (Wipe/Flash/Export+Location/Clean in `menu.ps1`) and
  attack sub-role (blackhole attacker/victim, wormhole A/B — reassigns ALL peers together in
  `run_wizard.ps1` to keep "exactly one attacker"/"exactly one A and one B" true; `menu.ps1` edits
  just the one board's field, matching its existing warn-only philosophy); change which node is ROOT
  (promotes one, demotes the other, re-sorts children-first-root-last, and in `run_wizard.ps1`
  re-triggers the attack-sub-role picker for the new child set); or change the run's TOPOLOGY
  (global, rebuilds every board's command line). Every change reprints the plan (and, in `menu.ps1`,
  re-runs the sanity warnings incl. `Confirm-BlackholeAttackerMac`) before the per-board CONFIRM
  loop / "Proceed?" runs — no blind apply-to-all. NOT build/hardware-tested beyond a PowerShell
  parser syntax check (`[System.Management.Automation.Language.Parser]::ParseFile`, both files
  clean) — no ESP-IDF/board access in the session's shell; the menu.ps1 toggle screen WAS confirmed
  live by the user mid-session (pasted output matched).
- sep. 16, 2026 — FIXED (supersedes this entry's earlier "NaN logic is correct" claim — it was
  NOT): `features.py`'s PDR gated attributability on a run-wide `covered_macs` set, so a victim
  the root never logged ANYTHING for got NaN in every window — exactly the node a blackhole hits
  hardest. Consequence: `PDR == 0` occurred in **0 of 446 rows**; the feature could never record
  the value it exists to detect. Now gated per-window on evidence: node transmitted
  (`probes_count_delta > 0`) AND was associated (`layer > 0`, parent_mac non-zero) AND the window
  is inside the root's arrival-logging span (that last one replaces the old safety against a
  never-pulled root CSV). Also fixed a latent FALSE-POSITIVE: `0/(0+EPSILON)` returned a literal
  `0.0` for windows where a node sent nothing — a fabricated blackhole signature. Before→after on
  `G402/mobility`: PDR non-null 41→238, `PDR==0` 0→201, NaN 405→208; victim PDR by phase now
  baseline 0.217 → attack 0.000 → cooldown 0.750. `verify_attack.py` still says NOT CONFIRMED
  there (that capture's own baseline is degraded, 0.164±0.372) — i.e. it surfaces the signature
  WITHOUT fabricating one. Full rationale: `docs/issue_logs/thesis-deviate.md` **D-8**.
  ⚠️ Remaining NaN is correct, not a gap: root never originates probes (PDR undefined for it).
- sep. 16, 2026 — ⚠️ CAPTURE QUALITY, archived unresolved: `blackhole/linear/G402/mobility` — 3 of 4
  victims probed all run but root logged nothing from them in ANY phase (`B4BFE932FE90` changed
  layer 4→5 mid-run; `2805A532D7B4` at layer 6). NOT the MAC bug below (that run's attacker `0c:80`
  DID match the then-configured MAC, and one victim got through) — suspected mobility-disrupted TODS
  relay, still untested since the 15:36 re-run was itself voided by the MAC bug. `home/mobility`
  also exported ONLY root's CSVs — check `-Location`/`-Scenario` match on every board before export.
- sep. 16, 2026 — PROPOSED, NOT BUILT (team decides first): root-as-blackhole-attacker, STAR
  ONLY — thesis fig 4.17 shows ROOT as the attacker in star, since every child connects directly
  to root so no child-relay position exists there (tree/linear/partial keep a child attacker; all
  wormhole topologies unchanged). Design: `ROOT_BLACKHOLE_ATTACKER` flag (`#error`-gated to
  star+blackhole) + a drop branch in `root_main.c`'s `probe_data_cb` (just skip
  `csv_logger_append_probe_arrival`) + swap root's telemetry role string to `"blackhole"` so
  `features.py`'s existing mask picks it up with ZERO analysis changes. Children need NO firmware
  change. ⚠️ Biggest trap: pass `-DestAttack blackhole` for folder placement but NOT
  `BlackholeRole=victim` (that compiles in P2P-to-attacker-MAC addressing, wrong for this variant);
  the MAC pre-flight check does not apply and must be skipped, not extended. Full plan in
  `.claude\plans\mutable-honking-spindle.md` (under the Basti user profile) — read before building.
- sep. 16, 2026 — BUILT: run scenarios v1 (`none|burst|highload|mobility|powercycle`) in run.ps1
  (`-Scenario`/`-ScenarioTarget`), both front-ends, presets, `run_matrix.py`, `verify_topology.py` and
  the Python export chain — the panel's "real-world variation" ask. Build flag `-DTRAFFIC_PROFILE=1`
  burst / `=2` highload; `none` passes NO flag, so its compile line and build dir stay byte-identical
  to pre-scenario. Who gets it: burst → root + the ONE `-ScenarioTarget` child; highload → every
  child; mobility/powercycle → nobody (human-performed, label-only). Burst fires `BURST_COUNT`(100)
  probes `BURST_OFFSET_S`(60) into the attack-length window, and on a BASELINE run the root holds a
  matching extra window so a legit burst and a burst-under-attack form a matched pair.
  ⚠️ Export-folder rule: the scenario folder is added ONLY for a real scenario — `none` gets NO extra
  folder (all 5 path-builders agree on this; it was the bug fixed the same night). Build-dir suffix
  `_burst`/`_highload` is a SEPARATE concern (firmware variant, not export path).
  ⚠️ Verified only without hardware attached — NOT bench-tested on real boards yet.
- ⚠️ TERMS-GLOSSARY.md (archived aug. 06 with the Thesis 2 defense docs) may still be live
  reference for THES3 writing (vocabulary for paper Tables 4.11/4.12) — pull it back to root
  if so. See ARCHIVE.md for the doc-reorganization history.

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
