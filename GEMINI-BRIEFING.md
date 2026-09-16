# CONTEXT BRIEFING — Read this fully before answering anything below it

<!-- Reusable context dump for any AI (Gemini, ChatGPT, etc.) that has zero prior
     exposure to this project. Paste this WHOLE file as the first message, then
     ask your actual question underneath the "END OF BRIEFING" line. Regenerate
     by asking Claude: "update GEMINI-BRIEFING.md with everything since the last
     update" rather than rebuilding from scratch. -->

You are being given the full history and current state of an undergraduate thesis
project so you can answer questions about it without guessing or asking me to
re-explain things I've already documented here. Do not assume any prior knowledge.
Everything below is verified against the actual repository files, the approved
thesis PDF, and the firmware source — not secondhand summary. Treat all of it as
ground truth. If your answer would depend on something not in this document, say
so explicitly rather than inventing it.

---

## 1. What this project is

**Title:** *Cross-Layer Dataset Design and Exploratory Analysis of ESP32-Based
ESP-WIFI-MESH Network*

**Institution:** De La Salle University Manila, College of Computer Studies.
**Adviser:** Mr. Gregory G. Cu.
**Proponents:** Calpoporo, Carlos, Ong, Reinante.
**Internal codename:** NIS16 / CTTHES (the thesis has gone through CTTHES2 →
CTTHES3 revision cycles; there is no separate "Thesis 1" artifact anywhere in the
repo — the documented history starts at CTTHES2).

**What it actually is:** a hardware-derived dataset project, NOT an intrusion
detection system. Real ESP32 boards form a real ESP-WIFI-MESH network. Two
routing-layer attacks (blackhole, wormhole) are emulated and telemetry is
captured across three layers (PHY/RSSI, MAC/retry, Network/routing) at 1 Hz,
aggregated offline into 5-second windows with 16 engineered features. The
deliverable is a labelled dataset plus exploratory data analysis and
unsupervised clustering — **no real-time detector is built, and predictive
performance is explicitly out of scope** (approved paper §1.4.1, paraphrased:
"exploratory and unsupervised analysis, rather than predictive performance or
real-time deployment").

**Testbed:** 5–10 ESP32 boards (approved paper's stated scale), currently 8
physical boards: 4 are a 38-pin variant (GPIOs silkscreened with a `G` prefix,
e.g. `G18`), 4 are a 30-pin variant (`D` prefix, e.g. `D18`) — same underlying
GPIO numbers, different silkscreen labels, mixed/paired depending on the
topology under test.

**Topologies (4):** linear chain, star, tree, partial mesh.
**Attacks (2):** blackhole (forwarding suppression) and wormhole-inspired
(topology distortion via a physical out-of-band UART tunnel between two
colluding boards). The paper deliberately names these functionally —
**"Forwarding Suppression (Blackhole)"** and **"Topology Distortion
(Wormhole-Inspired)"** (§4.2.1.2 / §4.2.1.3) — the "-Inspired" qualifier is
doing real work; it is a narrower, more defensible claim than "this is a
textbook wormhole," and should be led with whenever the attack's fidelity is
questioned.

**Ground-truth labels (Table 4.8, approved paper):** `0` = Baseline (Normal
Operation), `1` = Controlled Forwarding Suppression (Blackhole), `2` =
Controlled Topology Distortion (Wormhole-Inspired). This 3-class scheme is
locked; anything else (disturbances, environment, run metadata) must be a
separate metadata column, never a new label value, without an explicit scope
amendment.

---

## 2. Binding constraints from the APPROVED paper (§1.4.1, quoted, not paraphrased)

These are locked unless explicitly amended with the adviser, and any new design
work must be checked against them:

> "Second, the threat model is strictly limited to two specific routing-layer
> behaviors: blackhole and wormhole attacks. The dataset does not include other
> routing-layer threats (such as grayhole, Sybil, or selective forwarding),
> application-layer attacks, cryptographic exploits, physical tampering,
> firmware compromise, or adversarial radio interference beyond controlled
> routing manipulation."

> "Finally, all experiments are conducted in a controlled indoor environment to
> ensure repeatability and consistent labeling. While this improves
> experimental reliability, it may not capture environmental variability such
> as outdoor interference, mobility-induced topology changes, or
> weather-related signal effects."

Also: testbed fixed at "approximately 5 to 10 ESP32 nodes"; framing fixed at
"exploratory and unsupervised analysis, rather than predictive performance or
real-time deployment."

**Table 4.1 phase timeline (approved, currently what the firmware implements):**
60 s stabilise + 300 s baseline + 180 s attack + 120 s cooldown = **660 s (11
minutes) per run**. This is hardcoded as compile-time `#define`s in
`NIS16-ESP32-Environment-semi-final/components/mesh_common/include/mesh_config.h`
(lines ~129-138) and consumed by hardcoded `vTaskDelay` calls in
`root_node/main/root_main.c`. Changing any duration requires re-flashing the
root board. A shorter **30+90+90+30 = 4-minute** timeline has been *proposed*
(see §5 Workstream C, item C5) but is NOT yet implemented — do not assume it is
live unless a later update to this document says so.

**§3.2.2.1 "Impact of Physical Obstacles"** (cites Espressif 2023a): RF-shielding
objects (walls, metal, furniture) can attenuate signal enough that a physically
close node is rejected as a parent candidate due to low RSSI, so the logical
mesh topology can differ from the physical layout. This is theoretical-framework
prose, not an experimental procedure — but it is what justifies "RF-shielding
insertion" as a disturbance type in later design work (§7 below).

---

## 3. Known dataset/analysis problem: the missingness-as-label leak

Three of the 16 engineered features — **ForwardingRatio, IngressEgressDelta,
ConsistencyScore** — are computed ONLY for rows where `node_role == "blackhole"`
(the attacker), and are `NaN` everywhere else, in EVERY phase including
baseline. This is enforced in
`NIS16-ESP32-Environment-semi-final/analysis/features.py` (the gate is around
lines 140-164; the module's own docstring near the top documents the gating
policy). Two more features, TunnelIntensity/TunnelBytes, are similarly gated to
`node_role in {wormhole_a, wormhole_b}`.

**Why this matters:** "is this column NaN?" is a *perfect* predictor of the
label. This is a harsher version of a real thesis-panel criticism (P1 below) —
not one feature correlating with the attack, but a missingness *pattern* that
IS the ground truth. Any clustering on the current feature table is trivially
separable and demonstrates nothing. This was root-caused further on 2026-08-29:
honest (non-attacker) nodes structurally cannot observe their own forwarding,
because `esp_mesh_send(NULL, ..., MESH_DATA_TODS)` in `victim_main.c` means the
ESP-WIFI-MESH stack relays *below* the application layer — only the blackhole
attacker sees transit packets at all, because victims explicitly address it.
So "un-gating" this feature is not a one-line fix; it needs one of: (a) new
application-layer relay-accounting firmware for every node (invalidates
existing captures), (b) inferring forwarding from root arrivals + topology as a
derived Python estimate, or (c) keeping the features attacker-only and
excluding them from any model input. No option has been chosen yet as of the
last update to this document — this is an open decision.

A related feature-correctness bug found sep. 12, 2026: **RSSI_Hop_Diff**
normalises against a per-layer baseline RSSI median computed from
`window_label == 0` rows. If any future disturbance-injection design (§7) places
disturbances inside baseline windows (which it does, deliberately), that same
baseline population is what gets perturbed — so an unfiltered median would
silently bias RSSI_Hop_Diff in the *attack* windows of the same run. The fix
(excluding `disturbance_active == True` windows from the median) is specified
in the variability-design plan (§7) but not yet implemented in
`features.py`.

Also worth knowing: LatencyHopRatio and TunnelLatency are NaN in every run
captured so far — there is no RTT/return leg in the current protocol design to
compute them from (documented in the code repo's own dated notes, not the
approved paper).

---

## 4. Full chronological history (day 0 → today)

### Firmware repo genesis (git history of `NIS16-ESP32-Environment-semi-final/`)

- **2026-06-18/19** — repo created; initial mesh README/setup guide committed.
- **2026-06-22** — core firmware skeleton lands in one dense commit cluster:
  `phase_listener.c`, `csv_logger.h/.c`, `root_main.c`, `victim_main.c`,
  `partitions.csv`; mesh parent RSSI tuning + custom partition table.
- **2026-06-25** — first working mesh formation.
- **2026-06-29/30** — serial export task (UART) added; manual export first
  works; probe de-duplication added at the root.
- **2026-07-03** — two parallel team branches ("Kyle" and "m6,7,8") merge into
  `integration-test`, the branch that remains the working branch. This is when
  the M6→M7→M8 analysis pipeline (preprocess/features/eda) and the probe-dedup
  tooling both land, from separate contributors.
- **2026-07-04** — blackhole victim firmware added (Milestone 2 begins).
- **2026-07-08/09** — wormhole attack becomes functional; same window as two
  firmware bugs fixed (I-008 WiFi link flapping, I-010 victims joining too
  late — see the issue table in §5).
- **2026-07-11** — M6/M7/M8 pipeline code consolidated into `analysis/`.
- **2026-07-13** — four tooling/pipeline issues (I-011 through I-014) fixed same
  day: stale CMake build-dir path caching, Windows USB selective-suspend
  dropping ports mid-flash, an ESP-IDF log line contaminating a telemetry CSV,
  and a corrupt-timestamp sample causing a 30 GB OOM in preprocessing.
- **2026-07-14** — first real capture data committed to the repo
  (`ATTACKS-Commands.md`, baseline/blackhole/wormhole exports); export-speed
  bug (I-015, readline() bottleneck) fixed.
- **2026-07-15** — attacker telemetry starvation (I-016, priority inversion)
  and full-SPIFFS CSV corruption (I-017, `DELETE_LOGS` not reclaiming space)
  both fixed.
- **2026-07-23** — first dated milestone report (`2026-07-23.md`). State: M1/M6
  done, M2/M3/M5/M7/M8 partial, **M4 (the ≥24-run capture matrix) at 0/24** —
  every run captured so far was an `r1` singleton across 8 topology×attack
  combinations, no repeats yet.
- **2026-07-24** — `validate_integrity.py` (M5) finished after fixing two
  bugs; first full validator pass over 55 exported CSVs: 7 PASS / 32 WARN / 16
  FAIL (all 16 fails were SPIFFS-bleed timestamp regressions from not wiping
  between captures).
- **2026-07-25/26** — first M4 matrix runs actually captured: `baseline·linear·r1`
  (clean), then `blackhole·linear·r1` (**first matrix cell, 1/24**) — PDR
  collapsed 0.944→0.082, RetryRate 0.004→0.165, ForwardingRatio 1.001→0.024,
  root recorded zero arrivals during the attack window. Same window: four
  tooling bugs found and fixed in `trim_run.py`/`run_matrix.py`/
  `verify_topology.py` (one was CRITICAL — silently produced a zero-row
  arrivals file that later crashed `features.py`). `thesis-deviate.md` created
  this day, recording deviations D-1 through D-4 from the original proposal.
- **2026-07-26 (afternoon)** — a run nearly lost to full SPIFFS from children
  left powered through a prior run's late phases (**I-017 recurring**);
  `recover_spiffs.py` built on the spot and used to recover 6,334 rows via raw
  flash extraction. `run_matrix.py --autorecord` added to stop a second class
  of operator slip (re-recording the wrong repeat number).
- **2026-07-27** — matrix reaches **16/24** (all four topologies now have at
  least a blackhole run; linear and wormhole rows both fully complete at 3/3).
  `thesis-deviate.md` gains D-5 (baseline defined as a run's own phase-0, not a
  separate capture), D-6 (repeats don't fix parent assignment — A/B hop
  separation varied 2-3 hops across repeats with no signature change), and D-7
  (a `run_repeat` column added so pooled repeats can be un-pooled). **This is
  the current HEAD of the git history — no firmware/tooling commits after
  2026-07-27 exist in the repo.**
- **2026-07-27 (same day) — Thesis 2 defended.** Presentation and the matrix
  push to 16/24 happened on the same calendar day.

### Thesis 3 pivot (post-defense panel response)

- **2026-08-06** — `Paper/Improvements.pdf` (the panel's recorded comments) is
  read and distilled into **7 problems (P1-P7)**, documented in
  `Plan/THESIS3-PANEL-PLAN.md`:
  - **P1** — single-feature decidability (see §3 above — this is the panel
    comment the missingness-leak problem answers).
  - **P2** — attacks have no parameter variation; every script is a
    hardcoded compile-time constant, identical every run.
  - **P3** — repeats (r1→r3) are redundant; vary attacker *position* instead;
    plus a "is the dataset balanced" bookkeeping ask.
  - **P4** — only one physical environment used (a house).
  - **P5** — no declared IoT deployment scenario; node placement looks
    arbitrary.
  - **P6** — no attack validation/provenance — what are the attack scripts
    based on, and how do you know they're really a blackhole/wormhole?
  - **P7** — the benign baseline isn't characterized; benign and attack
    conditions are otherwise identical (a raw traffic-volume threshold alone
    reproduces the attack label), and a high-legitimate-load benign class is
    needed so the model doesn't just learn "high volume = attack."
  Same day: the deployment scenario is settled as **smart campus /
  environmental-building monitoring, sited at DLSU Manila** — justified from
  the paper's own §1.1/§1.5 framing, and chosen specifically because a real
  campus deployment needs no "6 boards representing a 30-node farm" scale-down
  argument. `Plan/` created as the sole home for Thesis 3 planning; Thesis 2
  defense materials archived to `0_Resources/archive/`.
- **2026-08-19** — the panel-response plan is split into four member lanes
  (`Plan/THESIS3-TASK-SPLIT.md`): **M1** data integrity/leakage (owns P1),
  **M2** attack provenance/validation (owns P6), **M3** scenario/siting/
  environment (owns P3-placement, P4, P5), **M4** firmware/tooling/campaign
  (owns P2, P3-execution, P7-capture). M4's C1 (making the attacker's MAC
  address runtime-configurable instead of a compile-time `#define`) is called
  "the load-bearing change in the entire plan," because without it, varying
  attacker position for P3 means re-flashing every victim board per run.
- **2026-08-29** — the ForwardingRatio gating problem (§3 above) is root-caused
  to the mesh stack's below-application-layer relay behaviour, escalating C7
  (the fix) from a simple mask-widening change to a firmware-or-estimation
  decision that is still open.

### SD card sub-track (adviser-requested, parallel to the main Thesis 3 work)

- **2026-09-12 (today, all same day)** — an adviser-requested SD card storage
  option (SPI reader module, on top of the existing SPIFFS telemetry logging)
  goes from bring-up to real-firmware integration in one session:
  1. Standalone bring-up (`sd_card_test/`) passes after two hardware bugs:
     (a) the reader module's VCC was wired to the ESP32's 3.3V pin, but the
     module's onboard AMS1117-3.3 regulator drops ~1.1-1.3V, leaving the card
     itself under its ~2.7V minimum — fixed by moving VCC to the ESP32's
     VIN/5V pin (safe because the module's own level-shifter chip runs off the
     regulator's 3.3V *output*, not the 5V input, so the ESP32's GPIOs never
     see 5V); (b) `ESP_ERR_INVALID_CRC` at the higher default SPI clock,
     fixed by capping `host.max_freq_khz = 4000` (jumper wires can't reliably
     carry a full data burst at the ~20MHz ESP-IDF default).
  2. A stack-overflow crash traced to a 2KB report buffer declared as a local
     variable inside `app_main` (whose task stack is only ~3.5KB) — fixed by
     making it `static`.
  3. A long-standing `fopen(..., "w")` returning NULL bug root-caused to
     `CONFIG_FATFS_LFN_NONE=y` (default) restricting FATFS to 8.3 short
     filenames — both the test file and status file names exceeded that.
     (A filesystem-corruption theory was tested and explicitly ruled out via a
     full PC-side FAT32 reformat, which did not fix it.) Fixed by enabling
     `CONFIG_FATFS_LFN_HEAP=y`.
  4. **Decision:** the SD boot-check ships in the REAL mesh firmware
     (`root_node`/`child_node` via a new `mesh_common/src/sd_status.c`
     module), not just the standalone sandbox. It builds a
     `<topology>/<location>` folder tree matching `export_logs.py`'s existing
     topology-directory naming, reads topology from the existing compile-time
     `MESH_TOPOLOGY` macro, and reads **location at runtime** from a new
     `/sdcard/location.txt` file — specifically so moving a board between
     physical sites never requires a rebuild. Only the diagnostic report goes
     to SD; SPIFFS telemetry logging is untouched, since whether SD replaces
     SPIFFS is still an open adviser decision.
  5. **Decision:** four location names are defined for the first time —
     `home`, `G402`, `DLSU_Library`, `Goks` — filling in an "owned but
     undefined" environment field that had been flagged since the 2026-08-19
     task split. `home` is explicitly noted as the site the panel's P4 comment
     effectively rejected — usable only as a control/baseline, not as
     evidence of environmental variation, if cited toward P4.
  6. `--location` threaded through `export_logs.py`, `run_matrix.py`,
     `run.ps1`; `run_ledger.csv`'s 14 pre-existing rows backfilled
     `location=unrecorded` (not guessed) with a `.bak-pre-location` safety
     copy.
  7. Several reference files (`ATTACK-MECHANICS.md`, `OUTPUT-VERIFICATION.md`,
     `NODE-INVENTORY.md`, topology figures) reorganized from the workstation
     root into a new `Resources/reference/` and `Resources/figures/`
     structure, superseding an earlier note that said they'd stay at root.
  8. **Current state, unverified on real hardware:** the real-firmware
     wiring only compiles clean so far — it has NOT yet been flashed to a
     physical board. Next step: flash a real board, confirm the folder tree +
     `location.txt` read + report write on the serial monitor, then run
     negative tests (no card present, missing `location.txt`, malformed
     `location.txt`). After that, the adviser decides whether SD storage
     replaces SPIFFS or remains diagnostic-only.
  9. **Later the same day**, a user test (deleting all SD card content and
     re-powering a board) was clarified to have been run against the
     *standalone* `sd_card_test` firmware, not the real mesh firmware — that
     firmware only ever writes one flat status file and has no folder-tree
     logic, so "nothing happened except a status report" was confirmed as
     expected behaviour for that build, not a bug.
  10. **Also the same day:** a `skills/` folder (Claude Code skill
      definitions: codebase-design, domain-modeling, frontend-design,
      grill-me, grilling, improve-codebase-architecture, reconcile) was added
      to the workstation for use in later sessions.
  11. **Also the same day:** a variability-design review was done (see §7
      below) and a `Setups/` folder was created at the workstation root,
      consolidating the 3 attack setup docs (`BASELINE-SETUP.md`,
      `BLACKHOLE-SETUP.md`, `WORMHOLE-SETUP.md`), the 5 per-topology runbooks
      (`LINEAR/STAR/TREE/PARTIAL/ARCHIVE-RUNBOOK.md`), and a newly-authored
      `SD-CARD-WIRING.md` pinout reference (CS→GPIO5, SCK→GPIO18, MOSI→GPIO23,
      MISO→GPIO19, VCC→VIN/5V not 3V3, 4MHz clock cap) — all as **copies**;
      the originals remain in place inside the `NIS16-ESP32-Environment-semi-final/`
      git repo so no existing cross-references break.

**Note on gaps:** the project kept dated daily/session logs
(`2026-07-23.md` … `2026-07-27.md`) only during that one week in July. No dated
`.md` files exist for August or September — that activity is tracked only in
the rolling `MEMORY.md` / `STATUS.md` / `ARCHIVE.md` triad instead, which this
document has folded in above.

---

## 5. Firmware bug log (I-001 through I-017), full table

All fixed unless marked otherwise. Source: `esp32-issues.md` +
`esp32-issues-Part2.md` + `esp32-issues-Part3.md` in the code repo.

| ID | Symptom | Root cause | Fix | Status |
|---|---|---|---|---|
| I-001 | Export hangs, no END_OF_FILE marker | Monitor→export handoff resets board mid-stream; attacker/wormhole tasks kept logging to UART0 during export | Silence logging during export; export completes on byte-count match instead of waiting for the marker | Fixed |
| I-002 | Export fails "could not open COM9" | Windows reassigned COM ports | Identify boards by boot banner, not assumed port number | Fixed (operator) |
| I-003 | `idf.py monitor` build errors | Run from the wrong (parent) directory | Run only from `root_node/`/`child_node/` | Fixed |
| I-004 | Victim can't find network | Root board not actually running/up yet | Confirm root shows `Role: 0` before starting victims | Fixed (operator) |
| I-005 | `run.ps1` missing `-Wipe` | Feature only existed on a different branch | Ported into integration-test | Fixed |
| I-006 | Blackhole required manual file edits | No build-time attack selector existed | Added `-DACTIVE_ATTACK` build flag + `run.ps1 -Attack` | Fixed |
| I-007 | CSV export slow at 115200 baud | Console baud is the bottleneck | Attempted 460800 baud — reverted, broke wipe/export via a config regeneration mismatch | Not fixed, reverted |
| I-008 | WiFi link flaps, weak RSSI | Power/brownout + RF proximity on one root board | Swapped root board + moved to channel 11 | Workaround |
| I-009 | Full rebuild on every attack-mode switch | Attack define applied globally, invalidating every object | Scoped the define to root's main component only; later added ccache cross-config sharing | Fixed |
| I-010 | Victims join too late / miss the attack phase | Root's phase clock doesn't wait for children; root sometimes flashed without an attack defined | Flash victims first, root last; put the attack flag on the root too | Fixed |
| I-011 | Build fails after repo folder moved | CMake bakes absolute paths into its cache | `run.ps1` self-heals by detecting the mismatch and deleting the stale build dir | Fixed |
| I-012 | Flash/wipe fails, port disappears | Windows USB selective suspend powers down the USB-serial chip | Disabled system-wide via `powercfg` | Fixed |
| I-013 | `preprocess.py` dtype crash | An ESP-IDF log line leaked into a telemetry CSV over shared UART | Pipeline drops unparseable rows and reports the count | Workaround (export-side leak still open) |
| I-014 | `preprocess.py` OOM (30GB alloc) | One corrupt timestamp sample exploded the reindex grid | Pipeline caps session length and row count | Workaround (firmware-side cause still open) |
| I-015 | Export progress crawls | `readline()` read one byte at a time | Bulk-read + local line splitting | Fixed |
| I-016 | Attacker telemetry starved, blackout | Telemetry task priority too low, starved by relay/phase-listener load | Raised attacker telemetry task priority | Fixed |
| I-017 | Attacker under-sampled + corrupt CSV | Full SPIFFS from `DELETE_LOGS` never reclaiming space | `DELETE_LOGS` now formats the whole partition | Fixed, but recurs operationally — carry boards unplugged between runs, `board_check.py --wait` before every run |

---

## 6. Deviations from the original proposal (`thesis-deviate.md`)

- **D-1 through D-4** — recorded 2026-07-26, around the first M4 matrix runs
  (exact wording lives in `thesis-deviate.md`; not fully re-quoted here — ask
  for it explicitly if you need the literal text).
- **D-5** — baseline is defined as a run's own phase-0 segment, not a
  separately captured run.
- **D-6** — repeats vary hop-distance between colluding wormhole nodes (2-3
  hops observed) without a fixed parent assignment; the tunnel signature
  (duplicate count) held steady regardless.
- **D-7** — added a `run_repeat` column so pooled repeat captures can be
  un-pooled later.
- A **D-5 scope amendment is separately proposed** (not yet written) to cover
  moving experiments outside the "controlled indoor environment" the approved
  paper's §1.4.1 commits to — see Risk R-A in §7.

---

## 7. Most recent design work: the 40-run variability campaign (in progress, NOT yet executed)

The adviser has asked that, within each of the 8 topology×attack cells (4
topologies × 2 attacks), each of 5 repeat runs use a **different deliberate
disturbance** — e.g. a person walking between nodes, unplugging and
reconnecting a node, physical obstruction — so the benign class stops being
"whatever we recorded when nothing was happening" (this directly extends P7).

Two draft scenario documents were produced and checked against the actual
paper/firmware. They contained four errors, since corrected in a working
design (`good-now-it-works-scalable-haven` plan, referenced but not yet
executed):

1. Their central claim — "ForwardingRatio stays ≈1.0 under every benign
   disturbance" — is not measurable with the current NaN-gating described in
   §3 above. Benign windows hold NaN, not 1.0.
2. They assumed a runtime command channel (to remotely change probe rate,
   target a specific node, or trigger a remote reboot) that does not exist —
   the only inter-board message today (`phase_msg_t`) carries a phase ID and
   nothing else. About a quarter of the drafted disturbances (simultaneous
   high-rate alarm, bulk transfer, burst-then-silence, remote soft reboot)
   cannot run without new firmware.
3. They invented a 270-second phase timeline that matches neither the
   approved paper's Table 4.1 (660s) nor the repo's own shorter proposal
   (240s, item C5 above).
4. They varied disturbance, physical site, AND attacker position
   simultaneously between some runs in the same cell, at n=1 — making nothing
   attributable to anything, the exact error their own "disturbances must
   never overlap the attack phase" rule was meant to prevent.

The corrected design uses a **fixed 5-rung ladder** (CLEAN → human crossing →
leaf node disconnect/reconnect → intermediate node disconnect/reconnect →
board reorientation) identical across all 8 cells, restricted to disturbances
the current firmware can actually execute (no new command channel needed), plus
two small firmware/analysis fixes (un-gating ForwardingRatio per §3, and
excluding disturbance-active windows from the RSSI_Hop_Diff baseline
median) that must land before the campaign is meaningful. It is NOT yet
implemented or captured — treat it as a design in progress, not a completed
change.

Also clarified during this design review: the "disturbances must never overlap
an attack window, because overlap makes the effect un-attributable" rule does
**not** appear anywhere in the approved paper (verified: zero hits for
"disturb", "confound", or "attribution"). It is the students' own rule and
needs its own justification if a panelist asks — the more defensible framing
is that a single run per disturbance gives no statistical power to separate a
disturbance's effect from an attack's effect, not that overlap is impossible
to analyze in principle (window-level attribution, via a
`disturbance_overlap_pct` metadata column, remains possible).

---

## 8. Current status snapshot (as of 2026-09-12)

- **Main track:** in "CTTHES3 planning, not capturing" mode — panel-requested
  design changes (scenario, attack validation, variability) are being worked
  out before any new data collection, per the adviser's own request.
- **M4 capture matrix:** 16 of 24 original-design runs recorded (git HEAD,
  2026-07-27). This predates the Thesis 3 redesign and will very likely be
  superseded or reframed as a "fixed-parameter control block" rather than
  extended as-is.
- **SD card track:** hardware bring-up complete and working; real-firmware
  integration written and compiling but NOT hardware-verified; next action is
  flashing a real board and running the negative-test checklist.
- **Open adviser decisions:** whether SD storage replaces SPIFFS or stays
  diagnostic-only; how to fix the ForwardingRatio missingness leak (firmware
  relay-accounting vs. derived estimate vs. exclude-from-model); the R-A scope
  amendment (controlled-indoor-environment claim vs. moving to DLSU campus);
  the R-B taxonomy question (would partial/probabilistic drop rates as a
  variability axis actually be "grayhole," which the approved paper's scope
  explicitly excludes?).

---

## 9. Where things live (repository map)

```
Thesis_workstation_SDCard/              ← workstation root
├── STATUS.md, MEMORY.md, ARCHIVE.md    ← rolling state (read STATUS.md first)
├── FILEMAP.md                          ← full repo layout, kept current
├── Setups/                             ← NEW (2026-09-12): copies of attack
│                                          setup docs, topology runbooks, and
│                                          the SD-card wiring reference
├── Plan/                               ← all Thesis 3 planning
│   ├── THESIS3-PANEL-PLAN.md           ← the P1-P7 breakdown (aug. 06)
│   ├── THESIS3-TASK-SPLIT.md           ← the M1-M4 member lanes (aug. 19)
│   └── THESIS3-MEMBER-HOWTO.md
├── Implementation Issues/
│   └── SD-CARD-AND-WORMHOLE-WIRING.md  ← hardware bring-up Q&A (sep. 2026)
├── Resources/reference/, Resources/figures/  ← moved here 2026-09-12
├── Paper/                              ← approved thesis PDF + panel comments PDF
└── NIS16-ESP32-Environment-semi-final/ ← the actual code, own git repo
    ├── components/mesh_common/         ← shared firmware (mesh_config.h,
    │                                      sd_status.c, csv_logger.c, etc.)
    ├── root_node/, child_node/         ← board-role firmware
    ├── analysis/                       ← preprocess.py → features.py → eda.py
    ├── tools/                          ← export_logs.py, run_matrix.py, etc.
    ├── *-SETUP.md, *-RUNBOOK.md        ← originals (Setups/ holds copies)
    └── esp32-issues*.md, 2026-07-*.md  ← the bug log and dated milestone reports
```

---

# END OF BRIEFING — my actual question/task follows below

