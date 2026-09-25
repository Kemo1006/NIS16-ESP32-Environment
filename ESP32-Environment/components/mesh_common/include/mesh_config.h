/**
 * @file mesh_config.h
 * @brief Centralised compile-time configuration for the ESP-WIFI-MESH testbed.
 *
 * Every constant that might need to change between deployments (credentials,
 * timing, sizing) lives here.  All other source files #include this header;
 * nothing is hard-coded elsewhere.
 *
 * NIS16 — CTTHES2 Milestone 1
 */

#pragma once

#include <stdint.h>

/* ═══════════════════════════════════════════════════════════════════════════
 * MESH NETWORK IDENTITY
 * ═══════════════════════════════════════════════════════════════════════════ */

/** 6-byte mesh network identifier (must be identical on every node). */
#define MESH_ID             {0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45}

/** Mesh network password (WPA2-PSK style; 8–64 printable ASCII chars). */
#define MESH_PASSWORD       "MeshSecure2026!"

/** Wi-Fi channel for the routerless mesh (1–13; must be identical on every
 *  node). Use a non-overlapping channel (1, 6, or 11) that is QUIET in your
 *  environment. Channel 6 is the most congested default — if the mesh keeps
 *  dropping (reason 6 / handshake-timeout storms), try 1 or 11 and pick whichever
 *  your local APs are NOT using. See esp32-issues.md I-008. */
#define MESH_CHANNEL        11

/** 1 = force every interface to 20 MHz (HT20) instead of the ESP32 default
 *  HT40 ("channel 11, 40D" in the logs = 40 MHz, secondary below).
 *  Why: the only sniffer we have (M1 MacBook, Wireless Diagnostics) offers
 *  20 MHz ONLY, and a 20 MHz receiver cannot decode 40 MHz data frames - the
 *  sep. 23 2026 capture heard every board's beacons but ~0 of its data
 *  frames. HT20 also matches what an independent observer can witness.
 *  ⚠️ Changes the RF layer: captures from before this flag (HT40) are not
 *  strictly comparable with captures after it - don't pool them unlabeled.
 *  Boot log shows the result: "RF width (...): STA 20 MHz, AP 20 MHz". */
#define MESH_FORCE_HT20     1

/** Layers are NOT sized from a board count. The mesh stack assigns each node
 *  its layer (hop count from the root, root = layer 1) as it joins, so the
 *  firmware only tells the stack which STRUCTURE to keep and otherwise lets
 *  depth grow to the stack's own ceiling. The only numbers left are ESP-IDF's
 *  hard limits (esp_mesh.h, esp_mesh_set_max_layer / esp_mesh_set_topology):
 *
 *    tree topology  (TREE, PARTIAL)  : max layer 25
 *    chain topology (LINEAR)         : max layer 1000
 *
 *  STAR's 2 is not a limit of this kind - it IS the star structure (center +
 *  direct nodes), set in mesh_setup.c. A fixed MESH_MAX_LAYER (last 7) used to
 *  cap every topology and silently kept the 8th board of a LINEAR run out.
 *  How many layers a run actually has is derived afterwards from the parent
 *  links (topology_graph.c on the root, tools/topology_graph.py offline). */
#define MESH_STACK_MAX_LAYER_TREE    25
#define MESH_STACK_MAX_LAYER_CHAIN   1000

/** Default fan-out per node: the stack's own maximum (mesh_ap_cfg_t
 *  max_connection, esp_mesh.h: "max 10"). LINEAR and PARTIAL narrow it below
 *  because fan-out is part of THEIR structure, not a size limit. */
#define MESH_MAX_CHILDREN   10

/* ── M3 topology shaping (proposal §4.2.2) ────────────────────────────────────
 * The proposal defines FOUR physical deployment layouts (§4.2.2): star, tree,
 * linear chain, and partial mesh. It stresses that these are PHYSICAL node
 * arrangements — ESP-WIFI-MESH still self-organises its routing tree by RSSI +
 * link metrics (§4.2.2, p.86). So placement does most of the work; these knobs
 * BIAS the stack toward the intended shape and are overridable from the build
 * (-DMESH_TOPOLOGY=...) so a run can pick a topology with no source editing:
 *
 *   idf.py build                        → default (TREE, unchanged M1 behaviour)
 *   idf.py -DMESH_TOPOLOGY=0 build       → STAR   (cap depth at 2)
 *   idf.py -DMESH_TOPOLOGY=2 build       → LINEAR (force a chain, 1 child/node)
 *   idf.py -DMESH_TOPOLOGY=3 build       → PARTIAL(multi-hop, constrained fan-out)
 *
 *   NIS_TOPO_STAR    — §4.2.2.1: central hub. Cap depth at 2 so every node is a
 *                      direct child of the root (root=layer 1, leaves=layer 2);
 *                      minimal routing complexity, direct RSSI relationships.
 *   NIS_TOPO_TREE    — §4.2.2.2: native self-organising ESP-MESH tree, multi-hop
 *                      layering beneath the root (unchanged M1 behaviour).
 *   NIS_TOPO_LINEAR  — §4.2.2.3: force a CHAIN (MESH_TOPO_CHAIN) AND cap fan-out
 *                      at 1 child/node, so nodes line up hop-by-hop from the
 *                      farthest node toward the root.
 *   NIS_TOPO_PARTIAL — §4.2.2.4: the "primary experimental environment". Stays
 *                      multi-hop like TREE, but the fan-out cap is narrowed
 *                      (MESH_PARTIAL_MAX_CHILDREN) so nodes cannot all crowd the
 *                      root — they attach to a SUBSET of parents, forcing the
 *                      branched, semi-structured connectivity + adaptive parent
 *                      switching the proposal describes. verify_topology.py
 *                      --expect partial checks for those parent-switch events.
 * Build ALL boards in a run with the SAME topology, or nodes will disagree on
 * max-layer / chain / fan-out shaping. (Names are NIS_-prefixed to avoid
 * clashing with the IDF MESH_TOPO_* enum.)
 * ────────────────────────────────────────────────────────────────────────── */
#define NIS_TOPO_STAR       0
#define NIS_TOPO_TREE       1
#define NIS_TOPO_LINEAR     2
#define NIS_TOPO_PARTIAL    3

#ifndef MESH_TOPOLOGY
#define MESH_TOPOLOGY       NIS_TOPO_TREE
#endif

/** LINEAR chain: each node accepts at most ONE child, so the mesh is forced
 *  into a single hop-by-hop line rather than a branching tree. */
#define MESH_LINEAR_MAX_CHILDREN   1

/** PARTIAL mesh: narrowed fan-out (vs MESH_MAX_CHILDREN) so the root/intermediate
 *  nodes can't absorb everyone — nodes spread across a SUBSET of parents and the
 *  tree branches + deepens instead of flattening into a star. Keep >1 so a real
 *  branched partial mesh (not a chain) can form. */
#define MESH_PARTIAL_MAX_CHILDREN  2

/* ═══════════════════════════════════════════════════════════════════════════
 * ROUTER / UPLINK (only used when the root bridges to an AP)
 * Set MESH_USE_ROUTER to 0 for a pure self-contained mesh (recommended for
 * lab experiments).
 * ═══════════════════════════════════════════════════════════════════════════ */

#define MESH_USE_ROUTER     0          /**< 1 = root connects to an AP; 0 = standalone */
#define ROUTER_SSID         "YourRouterSSID"
#define ROUTER_PASSWORD     "YourRouterPassword"

/* ═══════════════════════════════════════════════════════════════════════════
 * EXPERIMENT PHASE TIMING  (seconds)
 * These match Table 4.1 in the thesis exactly.
 * ═══════════════════════════════════════════════════════════════════════════ */

/* ── Phase durations ──────────────────────────────────────────────────────────
 *
 * Overridable from the build, exactly like ACTIVE_ATTACK / MESH_TOPOLOGY /
 * TRAFFIC_PROFILE:
 *
 *     idf.py -DPHASE_BASELINE_S=180 build
 *
 * They used to be bare #defines, so shortening a run meant editing this header
 * and remembering to put it back. Since every scenario already forces a rebuild
 * (TRAFFIC_PROFILE is a compile-time flag), making these -D-settable costs
 * nothing and turns run length into a per-run parameter.
 *
 * WHY YOU WOULD WANT TO. CTTHES2 panel: "you do not necessarily need to run each
 * test for a full hour. Instead, consider running smaller intervals with more
 * variations." At 10 Hz across 8 nodes ONE run already yields ~5,280 one-second
 * windows, so a 4x4x4 campaign produces ~760,000 — roughly two orders of
 * magnitude past the 10k the panel referred to. Baseline is the cheapest phase
 * to cut: PHASE_BASELINE_S 300 -> 180 removes 2 minutes from every run in the
 * matrix while still leaving ~1,440 baseline windows per run.
 *
 * ⚠️ ONLY THE ROOT'S VALUES MATTER for the timeline — the root announces every
 * phase transition and the children just follow (root_main.c's
 * experiment_controller_task). But build the WHOLE fleet with the same values
 * anyway: PHASE_BASELINE_S is also compiled into preprocess.py's expectations
 * (mirrored there as a module constant) and into the burst scenario's
 * BURST_OFFSET_S bound-check below.
 *
 * ⚠️ Changing these changes what "baseline" means between runs. Captures made
 * with different phase lengths are still comparable window-for-window, but the
 * number of baseline windows per run differs — say so in the methodology rather
 * than letting a reader assume every run was identical.
 * ─────────────────────────────────────────────────────────────────────────── */

/** Stabilisation window before Phase 0 starts (mesh formation, not logged). */
#ifndef PHASE_STABILISE_S
#define PHASE_STABILISE_S   60U
#endif

/** ROSTER GATE - how many CHILDREN (every non-root board in the run) must be in
 *  the mesh before the root starts Phase 0. After PHASE_STABILISE_S the root
 *  keeps waiting, printing who is missing every ROSTER_GATE_LOG_S, until the
 *  routing table holds all of them for ROSTER_GATE_STABLE_S in a row.
 *
 *  Why: the root used to start Phase 0 on a fixed 60 s timer without checking
 *  that its children were there, so a run with missing children looked exactly
 *  like a good one. A SAFEGUARD, not a fix for a known incident: the sep. 24,
 *  2026 G402 run turned out to have all six children present (root arrivals),
 *  so this gate would not have changed it.
 *
 *  run.ps1 -ExpectedChildren sets it for the root build (the wizard passes its
 *  roster's child count). 0 = gate off, the old fixed-timer behaviour. A child
 *  that is genuinely gone: type START_ANYWAY in the root's monitor (or send it
 *  over serial) and the run starts with whoever is there - loudly marked. */
#ifndef EXPECTED_CHILDREN
#define EXPECTED_CHILDREN      0
#endif
#define ROSTER_GATE_STABLE_S   5U    /* all present this many 1 s checks in a row */
#define ROSTER_GATE_LOG_S      10U   /* "still waiting" line cadence              */

/** Phase 0 — Baseline: normal operation, no manipulation. */
#ifndef PHASE_BASELINE_S
#define PHASE_BASELINE_S    300U       /* 5 minutes */
#endif

/** Phase 1/2 — Manipulation window (blackhole or wormhole). */
#ifndef PHASE_ATTACK_S
#define PHASE_ATTACK_S      180U       /* 3 minutes */
#endif

/** Phase 3 — Cooldown: manipulation off, network stabilises. */
#ifndef PHASE_COOLDOWN_S
#define PHASE_COOLDOWN_S    120U       /* 2 minutes */
#endif

/* ═══════════════════════════════════════════════════════════════════════════
 * PHASE IDs  (broadcast in control messages)
 * ═══════════════════════════════════════════════════════════════════════════ */

#define PHASE_ID_BASELINE       0
#define PHASE_ID_BLACKHOLE      1
#define PHASE_ID_WORMHOLE       2
#define PHASE_ID_COOLDOWN       3
#define PHASE_ID_TERMINATE      4

/* ── F1 — "I have not heard a phase broadcast yet" ────────────────────────────
 *
 * NOT a phase the root ever announces. It is the value a node logs from boot
 * until the first phase broadcast reaches it, and it exists because the
 * alternative silently corrupts the dataset.
 *
 * What went wrong without it (2026-09-18, blackhole/linear/G402): the root
 * brownout-looped and joined the mesh 100-551 s AFTER the victims. Those
 * victims were already probing and already logging. phase_listener.c
 * initialised its state to PHASE_ID_BASELINE / GT_LABEL_BASELINE, so every one
 * of those rows was recorded as ordinary baseline. 2,945 of 7,704 windows
 * (38%) were victims probing a mesh with no root in it, scored as a genuine
 * PDR of 0, and pooled into the baseline distribution that the 3-sigma test
 * measures the attack against. The result was a false "attack NOT CONFIRMED"
 * on a capture where the attack had worked perfectly.
 *
 * preprocess.assign_segments() now infers that window host-side, but inference
 * can only work from symptoms. This makes the board RECORD it, so the
 * condition is a fact in the data rather than something a later tool has to
 * deduce — and so it can never again be mistaken for baseline by anything that
 * reads the CSV directly.
 *
 * 255 is chosen so the column stays uint8 and any reader that does not know
 * about this value gets an obviously-invalid phase rather than a plausible
 * wrong one. Both host schemas treat it as "not a real phase".
 */
#define PHASE_ID_UNSET          255

/* NOT a phase: the root sends this every PHASE_PREPARE_INTERVAL_S during the
 * PHASE_STABILISE_S window and the roster-gate wait, i.e. "a run is being set
 * up - start logging". A node that hears it opens its CSV (LOG_ONLY_DURING_RUN)
 * but KEEPS phase_id / gt_label at 255: the stabilisation rows the paper's
 * "Baseline Stabilization" section records (layer, parent, parent switches,
 * RSSI) are logged, never labelled as baseline. Never written to a CSV row. */
#define PHASE_ID_PREPARE        254
#define PHASE_PREPARE_INTERVAL_S 5U

/* Ground-truth labels embedded in every CSV row (Table 4.8). */
#define GT_LABEL_BASELINE       0
#define GT_LABEL_BLACKHOLE      1
#define GT_LABEL_WORMHOLE       2
/* Cooldown and Terminate both map to label 0 (normal) per Table 4.1. */

/** Companion to PHASE_ID_UNSET: the row has no ground truth, because the node
 *  did not yet know what the network was doing. Excluded from the labelled
 *  dataset host-side (window_label = NaN), never counted as class 0. */
#define GT_LABEL_UNSET          255

/* ═══════════════════════════════════════════════════════════════════════════
 * ATTACK SELECTION  (Milestone 2)
 *
 * Selects which manipulation the ROOT announces during the attack window, and
 * (via each project's main/CMakeLists.txt) which victim firmware is built.
 * Overridable from the build so no source editing is needed per run:
 *
 *   idf.py build                       → ATTACK_NONE: baseline-only run (M1)
 *   idf.py -DACTIVE_ATTACK=1 build      → blackhole run (root announces phase 1,
 *                                         victim builds blackhole_victim.c)
 *
 * Build BOTH boards with the SAME flag for a given run, or the root will
 * announce an attack that no victim reacts to (no signature).
 * (Wormhole = 2 is reserved for the other branch; not implemented here.)
 * ═══════════════════════════════════════════════════════════════════════════ */

/** Sentinel meaning "no attack phase — run baseline → cooldown only". */
#define ATTACK_NONE             255

#ifndef ACTIVE_ATTACK
#define ACTIVE_ATTACK           ATTACK_NONE
#endif

/* ═══════════════════════════════════════════════════════════════════════════
 * BLACKHOLE RELAY  (Milestone 2 — ACTIVE_ATTACK == PHASE_ID_BLACKHOLE == 1)
 *
 * TRUE RELAY MODEL (thesis §4.2.1.2 C): one attacker board relays victim probes
 * to the root (baseline) or drops them (attack); the victim boards address the
 * attacker. Pick each board's blackhole role at build time with -DBLACKHOLE_ROLE
 * (mirrors -DWORMHOLE_END). The victim CMakeLists selects the source per role:
 *
 *   idf.py -DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=0   build flash   (attacker relay -> blackhole_victim.c)
 *   idf.py -DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1   build flash   (victim -> victim_main.c, targets attacker)
 *
 * (run.ps1 -Attack blackhole -BlackholeRole attacker|victim injects the flag.)
 * ═══════════════════════════════════════════════════════════════════════════ */

#define BLACKHOLE_ROLE_ATTACKER  0   /**< relays victim probes / drops on attack */
#define BLACKHOLE_ROLE_VICTIM    1   /**< sends its probes to the attacker's MAC  */

#ifndef BLACKHOLE_ROLE
#define BLACKHOLE_ROLE           BLACKHOLE_ROLE_ATTACKER
#endif

/** The blackhole attacker board's Wi-Fi STA MAC. A blackhole VICTIM board
 *  (BLACKHOLE_ROLE=1) sends its probes here instead of to the root, so the
 *  attacker can relay or drop them.
 *  ⚠️ SET THIS to your attacker board's STA MAC before building the victim
 *  boards — the attacker prints it at boot ("Set BLACKHOLE_ATTACKER_MAC ... to
 *  my STA MAC: ..."), or read it with tools/Get-EspMac.ps1. Only blackhole
 *  VICTIM builds read it; the attacker and all other builds ignore it. */
#define BLACKHOLE_ATTACKER_MAC   {0x20, 0x50, 0x0D, 0xE7, 0x1C, 0x38} // attacker_5 (blackhole attacker) - 20:50:0d:e7:1c:38

/* ═══════════════════════════════════════════════════════════════════════════
 * WORMHOLE TUNNEL  (Milestone 2 — ACTIVE_ATTACK == PHASE_ID_WORMHOLE == 2)
 *
 * The wormhole is a TWO-node colluding attack, emulated ENTIRELY at the
 * application layer (normal esp_mesh_send/esp_mesh_recv — no raw 802.11 frames,
 * per the thesis method). Select it with -DACTIVE_ATTACK=2 on EVERY board (the
 * root then announces PHASE_ID_WORMHOLE during the attack window, exactly like
 * blackhole), and pick each attacker board's tunnel end with -DWORMHOLE_END:
 *
 *   idf.py -DACTIVE_ATTACK=2                    build flash   (root)
 *   idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=0   build flash   (Node A — exit)
 *   idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=1   build flash   (Node B — entry)
 *
 * Behaviour during the wormhole phase (baseline/cooldown = normal victim):
 *   Node B (entry, leaf-side) — instead of sending its probes to the root, it
 *     encapsulates each probe and TUNNELS it to Node A (addressed by A's MAC).
 *   Node A (exit, root-side)  — receives the tunnelled probes and RE-INJECTS
 *     the original probe to the root, so B's traffic surfaces near A. This
 *     distorts the path/latency the root observes AND adds A<->B tunnel traffic
 *     — the cross-layer signature CTTHES3's clustering is meant to detect.
 *     (Contrast with blackhole: there probes VANISH; here they still arrive,
 *     but late and via a fabricated shortcut.)
 * Build the SAME -DACTIVE_ATTACK=2 on all three boards; only the two attacker
 * boards take -DWORMHOLE_END. See wormhole_victim.c and WORKFLOWS.md.
 * ═══════════════════════════════════════════════════════════════════════════ */

#define WORMHOLE_END_A          0   /**< exit / root-side  (re-injects to root)  */
#define WORMHOLE_END_B          1   /**< entry / leaf-side (captures + tunnels)  */

#ifndef WORMHOLE_END
#define WORMHOLE_END            WORMHOLE_END_A
#endif

/** UNUSED by the current firmware — the A<->B tunnel now runs over a wired
 *  UART link (WORMHOLE_UART_* below), not the wireless mesh, so no MAC
 *  addressing is needed between the two attacker boards. Left defined only
 *  because tools/run_matrix.py, tools/Get-EspMac.ps1, run.ps1, and
 *  ATTACKS-Commands.md still reference it in their instructions/output. */
#define WORMHOLE_NODE_A_MAC     {0xF4, 0x2D, 0xC9, 0x73, 0xE6, 0x18}

/** Magic cookie prefixing every tunnelled packet on the A<->B channel, so Node A
 *  can tell a tunnelled probe from a corrupted/garbage frame. ("TNL1") */
#define WORMHOLE_TUNNEL_MAGIC   0x544E4C31U

/** Physical out-of-band tunnel between Node A and Node B — Milestone 2 requires
 *  "a wired UART link between A and B" as the out-of-band channel ("this is
 *  what makes it a wormhole rather than ordinary forwarding"); the thesis
 *  proposal's Figure 4.9 tunnel-packet design also assumes a point-to-point
 *  serial link. Wire the two boards directly to each other:
 *
 *      Node A TX (GPIO WORMHOLE_UART_TX_PIN) -> Node B RX (GPIO WORMHOLE_UART_RX_PIN)
 *      Node A RX (GPIO WORMHOLE_UART_RX_PIN) -> Node B TX (GPIO WORMHOLE_UART_TX_PIN)
 *      Node A GND                            -> Node B GND
 *
 *  i.e. TX and RX are CROSSED between the two boards, GND is shared. This is a
 *  separate physical cable between the two attacker boards ONLY — do not wire
 *  it to your laptop, and it is independent of the wireless mesh entirely.
 *
 *  Defaults below are UART_NUM_1's pins on a standard non-PSRAM ESP32
 *  DevKitC. If your boards are WROVER modules (GPIO16/17 used by PSRAM),
 *  change these to a free GPIO pair on both boards before wiring. */
#define WORMHOLE_UART_PORT      1        /* == UART_NUM_1 */
#define WORMHOLE_UART_TX_PIN    17
#define WORMHOLE_UART_RX_PIN    16
#define WORMHOLE_UART_BAUD      115200

/* ═══════════════════════════════════════════════════════════════════════════
 * PHASE BROADCAST RELIABILITY
 * ═══════════════════════════════════════════════════════════════════════════ */

/** Number of times the root repeats each phase broadcast. */
#define PHASE_BROADCAST_REPEAT  5

/** Delay between consecutive repeats (ms). */
#define PHASE_BROADCAST_GAP_MS  100

/** Grace period past the end of cooldown before a node that never heard
 *  TERMINATE ends the run itself (phase_listener_wait_for_terminate()). */
#ifndef TERMINATE_GRACE_S
#define TERMINATE_GRACE_S       60U
#endif

/** After TERMINATE the root keeps re-sending it every TERMINATE_RESEND_GAP_S
 *  for TERMINATE_RESEND_S. A child that was mid-reparent (not in the routing
 *  table) when the first one went out still gets it once it re-joins. Kept
 *  short: the old root must not end a NEW run's children that join it before
 *  it is reflashed (the wizard parks the root first, which also prevents that). */
#define TERMINATE_RESEND_S      60U
#define TERMINATE_RESEND_GAP_S  5U

/* ═══════════════════════════════════════════════════════════════════════════
 * TELEMETRY SAMPLING
 * ═══════════════════════════════════════════════════════════════════════════ */

/** Telemetry sample interval. History of this value:
 *
 *    1 Hz (1000ms) — the proposal's stated rate; Table 4.10's window basis.
 *   20 Hz (  50ms) — 2026-07-12, adviser direction: a single run's telemetry
 *                    file must exceed 10,000 rows, and at 1 Hz the fixed 600s
 *                    (Table 4.1) run yields only ~600-700. 600s/50ms = 12,000.
 *    5 Hz ( 200ms) — 2026-07-25, team decision, to cut export time 4x (a 20 Hz
 *                    telem.csv is ~1MB and takes ~90s/board over the 115200
 *                    console; see tools/export_logs.py BAUD).
 *   10 Hz ( 100ms) — 2026-07-25, team decision, settling between the two: half
 *                    the export time of 20 Hz, double the row count of 5 Hz.
 *                    (The rate moved 20 -> 10 -> 5 -> 10 over this one day; 10 Hz
 *                    is the value the capture campaign should run at.)
 *
 *  ⚠ ROW-COUNT CAVEAT: 600s/100ms = 6,000 rows nominal per file (baseline 480s
 *  -> 4,800; attack 660s -> 6,600). That is still BELOW the 10,000-rows-per-file
 *  floor cited for the 20 Hz change — it reaches ~66% of it (5 Hz reached ~30%).
 *  It clears 10,000 only if the requirement is read as per-RUN pooled across the
 *  6 boards (~40,000 rows/run). CONFIRM THAT READING WITH THE ADVISER before
 *  committing a full capture campaign; if the floor is genuinely per-file, only
 *  20 Hz satisfies it at the run lengths Table 4.1 permits.
 *
 *  ANALYSIS IS UNAFFECTED by this value: preprocess.py downsamples whatever the
 *  raw rate is onto a synthetic 1 Hz grid (preprocess.py:316-319, 337), so
 *  Table 4.10's 5s / 5-sample windows still hold. 10 Hz supplies 10 raw samples
 *  per grid-second, so MIN_VALID_SAMPLES stays comfortably satisfied.
 *
 *  Still a DEVIATION from the proposal's 1 Hz — record it in thesis-deviate.md
 *  (referenced from several files, but that document does not yet exist).
 *
 *  The 4MB partition table (partitions.csv) remains valid: it was sized for
 *  20 Hz, so 10 Hz needs half of that and fits comfortably.
 *
 *  ⚠ Captures are NOT self-describing — the rate is not stored in the CSV. When
 *  validating older data, pass the rate used AT CAPTURE TIME:
 *      --sample-interval-ms 200   the 2026-07-25 baseline/linear capture (5 Hz)
 *      --sample-interval-ms  50   2026-07-12 .. 2026-07-25 captures  (20 Hz)
 *      --sample-interval-ms 1000  anything before 2026-07-12         (1 Hz)  */
#define SAMPLING_INTERVAL_MS    100U

/* ═══════════════════════════════════════════════════════════════════════════
 * PROBE GENERATION (victim nodes)
 * ═══════════════════════════════════════════════════════════════════════════ */

/* ───────────────────────────────────────────────────────────────────────────
 * TRAFFIC PROFILE / RUN SCENARIO  (panel, sep. 2026: run-to-run variation)
 *
 * Selected at build time, like ACTIVE_ATTACK / MESH_TOPOLOGY, so no source
 * edit is needed per run (run.ps1 -Scenario maps to the flag):
 *
 *   (no flag)                    → stationary (formerly "none"): byte-identical
 *                                  to pre-scenario firmware.
 *   -DTRAFFIC_PROFILE=1 burst    → ONE child (the -ScenarioTarget board) fires
 *                                  BURST_COUNT probes back-to-back BURST_OFFSET_S
 *                                  into the attack-length window. The ROOT built
 *                                  with this flag also holds an attack-length
 *                                  PHASE_ID_BASELINE window on a baseline run so
 *                                  the burst lands at the same offset in the
 *                                  matched pair (legit burst vs burst-under-attack).
 *   -DTRAFFIC_PROFILE=2 highload → every child probes at HIGHLOAD_PROBE_INTERVAL_MS
 *                                  for the WHOLE run. Root unchanged.
 *   -DTRAFFIC_PROFILE=3 jitter   → ROOT ONLY: randomises how long the baseline and
 *                                  attack windows run (ADDITIVE only, see below),
 *                                  so phase transitions land at a different
 *                                  wall-clock offset every run and elapsed time
 *                                  stops predicting the label. Children unchanged.
 *
 * mobility / powercycle are HUMAN scenarios: no flag, label-only on the host.
 *
 * ⚠ Like the sampling rate, the scenario is NOT in the CSV. It lives in the
 *   export folder (exports/<attack>/<topo>/<loc>/<scenario>/), the run ledger
 *   and the wizard preset.
 * ─────────────────────────────────────────────────────────────────────────── */
#define TRAFFIC_PROFILE_STATIONARY  0
#define TRAFFIC_PROFILE_BURST       1
#define TRAFFIC_PROFILE_HIGHLOAD    2
#define TRAFFIC_PROFILE_JITTER      3

#ifndef TRAFFIC_PROFILE
#define TRAFFIC_PROFILE             TRAFFIC_PROFILE_STATIONARY
#endif

/* ---------------------------------------------------------------------------
 * TIMING JITTER (TRAFFIC_PROFILE=3) -- ROOT ONLY
 *
 * WHY THIS EXISTS
 * ---------------
 * Every run so far used the SAME fixed schedule (STABILISE 60 / BASELINE 300 /
 * ATTACK 180 / COOLDOWN 120). analysis/leakage.py lists `window_start` as a
 * METADATA column for exactly that reason: with an identical schedule in every
 * run, "how many seconds since this run started" alone scores 0.857 accuracy
 * against the label WITHOUT LOOKING AT THE NETWORK AT ALL. That is a clock, not
 * a measurement, and it is the concrete form of the CTTHES2 panel's
 * 12:45-16:00 objection that the runs are all identical.
 *
 * With this profile the ROOT draws a fresh random EXTENSION for the baseline and
 * attack windows on every boot, so the wall-clock position of each phase
 * transition differs run to run and elapsed time stops being a free label.
 *
 * WHY THE JITTER IS ADDITIVE ONLY (never shortens a window) -- DO NOT "FIX" THIS
 * ------------------------------------------------------------------------------
 * analysis/preprocess.py resolves the real baseline as "the LAST PHASE_BASELINE_S
 * of phase 0", anchored backwards from each node's own phase-0 exit, because
 * phase 0 also covers boot and mesh formation. If a run's true baseline were
 * ever SHORTER than PHASE_BASELINE_S, that backward slice would reach past the
 * start of the real baseline and silently pull mesh-formation noise into the
 * benign class -- a wrong result that still looks perfectly plausible.
 * Extending only keeps the last PHASE_BASELINE_S always inside real baseline, so
 * every existing analysis rule stays correct with no host-side change.
 *
 * NOT RECORDED ANYWHERE, AND IT DOES NOT NEED TO BE: the drawn values are
 * printed at the root's console, and the ACTUAL phase durations are recoverable
 * from the data itself -- every node's CSV timestamps its phase_id transitions.
 * The dataset stays self-describing.
 * --------------------------------------------------------------------------- */
#ifndef JITTER_BASELINE_MAX_S
#define JITTER_BASELINE_MAX_S   45U   /* extra baseline seconds, 0..this        */
#endif
#ifndef JITTER_ATTACK_MAX_S
#define JITTER_ATTACK_MAX_S     30U   /* extra attack seconds, 0..this          */
#endif

/** Probe interval used by the highload profile (4x the normal rate). */
#define HIGHLOAD_PROBE_INTERVAL_MS  250U

/** Interval between application-layer probes sent by victim nodes. */
#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_HIGHLOAD)
#define PROBE_INTERVAL_MS       HIGHLOAD_PROBE_INTERVAL_MS
#else
#define PROBE_INTERVAL_MS       1000U
#endif

/** Burst profile: how many probes, how far into the window, and pacing. */
#ifndef BURST_COUNT
#define BURST_COUNT             100U       /* probes fired by the target child */
#endif
#ifndef BURST_OFFSET_S
#define BURST_OFFSET_S          60U        /* seconds after the window opens   */
#endif
#define BURST_GAP_MS            10U        /* inter-probe gap (~100 pkt/s)     */
#define BURST_POLL_MS           100U       /* window-detection poll granularity */
#define BURST_QUEUE_RETRY       3          /* retries on ESP_ERR_MESH_QUEUE_FULL */

#if (BURST_OFFSET_S >= PHASE_ATTACK_S)
#error "BURST_OFFSET_S must fall inside the attack-length window (PHASE_ATTACK_S)"
#endif

/** Maximum payload length for probe packets (bytes). */
#define PROBE_PAYLOAD_LEN       32U

/* ═══════════════════════════════════════════════════════════════════════════
 * COMMAND CENTER — HEARTBEAT  (NIS16 — CTTHES3)
 *
 * Low-rate, independent of SAMPLING_INTERVAL_MS: every node (root included)
 * sends a node_heartbeat_pkt_t (mesh_messages.h) to the root every
 * HEARTBEAT_INTERVAL_MS. The root aggregates the latest row per MAC into a
 * table (mesh_setup.c) and reprints it, sorted by layer, whenever a node's
 * layer/role/nickname changes, OR every HEARTBEAT_TABLE_REPRINT_MS regardless
 * of change — the periodic reprint is what makes a disconnect visible (AGE(s)
 * climbs on the stale row) since a disconnect/reconnect by itself doesn't
 * change any tracked field.
 * ═══════════════════════════════════════════════════════════════════════════ */

#define HEARTBEAT_INTERVAL_MS    7000U

/** How often the root reprints the table even with no field changes, so a
 *  disconnected node's rising AGE(s) (and a reconnected one's reset AGE(s)) is
 *  visible without waiting on a layer/role/nickname change.
 *  ⚠️ The check runs on the heartbeat send loop, so the real cadence is
 *  rounded UP to the next multiple of HEARTBEAT_INTERVAL_MS — keep this an
 *  exact multiple of it or the observed period won't match the number set
 *  here (10000 with a 7000 send interval would actually print every 14000). */
#define HEARTBEAT_TABLE_REPRINT_MS  14000U

/** A node is declared OFFLINE and dropped from the table after this long with
 *  no heartbeat — so pulling a board's USB shrinks the node count instead of
 *  leaving a row whose AGE(s) climbs forever. Three missed heartbeats, so a
 *  single dropped frame never evicts a healthy node. */
#define HEARTBEAT_STALE_MS       (3U * HEARTBEAT_INTERVAL_MS)

/** Heartbeats a child sends, 1 s apart, after its log closes and before it
 *  goes quiet — the root's "safe to export" report. More than one so a single
 *  lost frame doesn't hide it. */
#define HEARTBEAT_FINAL_SENDS    3

/* ═══════════════════════════════════════════════════════════════════════════
 * CSV LOGGER / LOCAL STORAGE
 * ═══════════════════════════════════════════════════════════════════════════ */

/** SPIFFS partition label — must match partitions.csv. */
#define FS_PARTITION_LABEL      "spiffs"

/** Base path where SPIFFS is mounted. */
#define FS_MOUNT_POINT          "/spiffs"

/** Write buffer size in bytes; flushed every LOGGER_FLUSH_RECORDS records. */
#define LOGGER_BUF_SIZE         256U

/** Flush to flash after this many records (thesis spec: every 10). */
#define LOGGER_FLUSH_RECORDS    10U

/** Milliseconds between fsync()s of the SD-card mirror files.
 *
 *  fflush() is NOT enough to make a mirrored row survive a reset. It pushes the
 *  stdio buffer through FatFs's f_write(), which allocates clusters and writes
 *  the data — but the file's DIRECTORY ENTRY (its recorded size) is only updated
 *  by f_sync()/f_close(), i.e. by fsync() or fclose() on the host side of the
 *  VFS. A board that browns out, is reset, or has its card pulled before
 *  csv_logger_close() runs therefore leaves a card file whose directory entry
 *  still says 0 bytes: the rows are physically on the card but unreachable, and
 *  every host-side tool counts the file as ZERO ROWS. That is the "sometimes we
 *  get 0 rows off the SD card" failure — see sd_mirror_sync() in csv_logger.c.
 *
 *  Deliberately TIME-based, not row-based: the analysis grid has already moved
 *  1 Hz -> 10 Hz once (D-9), and a row-count cadence silently changes meaning
 *  with it. Deliberately COARSER than LOGGER_FLUSH_RECORDS: each sync costs a
 *  FAT + directory write on a 4 MHz SPI card, and the logger's hot path has
 *  starved telemetry before when per-row flush cost grew (I-016/I-017). 5 s
 *  bounds worst-case loss to ~5 s of rows instead of the whole run. */
#define LOGGER_SD_SYNC_INTERVAL_MS  5000

/** Maximum CSV file size per run before log rotation (bytes). Not currently
 *  enforced by csv_logger.c (no rotation logic implemented) — this is
 *  aspirational sizing only. Raised alongside the 20 Hz sampling change
 *  (~12,000 rows * ~68 bytes/row ≈ 816 KB); the grown SPIFFS partition
 *  (partitions.csv, 2.4 MB) has room well beyond this. */
#define LOGGER_MAX_FILE_BYTES   (1200U * 1024U)    /* 1200 KB */

/** USB serial baud rate for log extraction (informational only — the export
 *  task streams over UART0 at the CONSOLE baud, set by
 *  CONFIG_ESP_CONSOLE_UART_BAUDRATE in sdkconfig, currently 115200). A 460800
 *  experiment was reverted (sdkconfig kept regenerating back to 115200 →
 *  export/wipe baud mismatch; see esp32-issues.md I-007). Keep this in sync with
 *  the sdkconfig value and export_logs.py's BAUD. */
#define SERIAL_BAUD             115200

/* Start the serial-export listener at boot instead of only after the terminate
 * phase. Set to 1 so a board is ALWAYS export-ready: a reset/reboot/crash (or the
 * run.ps1 monitor->export handoff, which toggles the reset line) no longer leaves
 * the listener disarmed and every board exports on the first pull. Does NOT change
 * any telemetry/phase/sampling behaviour — only WHEN the export task starts.
 * See esp32-issues.md (terminate-gated export). (0 = only-after-terminate.) */
#define CSV_EXPORT_ON_INIT     1

/* Log NO telemetry/arrival rows until this boot knows a run is on: it heard
 * the root's PREPARE signal (sent through the stabilisation window and the
 * roster wait, so those rows ARE recorded, as phase 255) or a real experiment
 * phase (phase_id 0-3; TERMINATE does not count). Applies to SPIFFS and the SD
 * card alike (sep. 25, 2026, team decision).
 *
 * Why: a single-USB board that is unplugged from its powerbank to be exported,
 * or reset by the monitor->export handoff, REBOOTS after the run. That boot
 * never hears the root, so it used to open a fresh ~1 KB "STILL RUNNING" file
 * of phase-255 rows (and append the same junk to SPIFFS behind the real run).
 * With this on, such a boot writes nothing, and the run's own file stays the
 * newest data on the board. Together with no longer archiving on boot (see
 * csv_logger_init()) the run file stays where LIST_SD and the importer see it.
 *
 * What is NOT recorded: rows from before the root starts stabilising (a child
 * flashed minutes before the root, searching for a mesh that does not exist
 * yet), and rows before a child is in the routing table (it cannot hear the
 * signal until it has joined). Formation convergence is therefore timed from
 * the first PREPARE a node hears, not from its boot. A node that reboots
 * MID-run starts logging again at the next phase broadcast it hears
 * (tools/verify_topology.py reports its convergence as NOT MEASURED); its
 * earlier file stays on the card, marked ABORTED.
 * A ROOT that reboots starts a new stabilisation, so it does log again - an
 * unplugged root leaves a phase-255-only file, which the tools already flag.
 * 0 = log from boot, as before. */
#define LOG_ONLY_DURING_RUN    1

/* ═══════════════════════════════════════════════════════════════════════════
 * SD CARD — status report + environment folder tree (diagnostic only)
 *
 * Adviser-requested storage option on top of the SPIFFS logging above. This is
 * NOT where telemetry goes — csv_logger.c is unchanged and still the run's
 * data path. sd_status.c mounts the card at boot, ensures a folder tree of
 * TOPOLOGY x LOCATION, and writes a one-shot diagnostic report into the folder
 * matching this board's build topology and its recorded site, then unmounts.
 * Never fatal: a missing/bad card must not stop the mesh run.
 *
 * SPI3 (VSPI) pins — proven in sd_card_test/, do not change without re-testing
 * on the jumper-wire rig:
 *   VCC must be VIN/5V, NOT 3V3 (AMS1117 regulator dropout on some modules).
 *   Avoid GPIO16/17 (WORMHOLE_UART_* above) and GPIO6-11 (flash) for any future
 *   pin change — 5/18/19/23 below don't collide with either.
 * ═══════════════════════════════════════════════════════════════════════════ */

#define SD_PIN_MOSI             23
#define SD_PIN_MISO             19
#define SD_PIN_SCK              18
#define SD_PIN_CS                5

/** Jumper wires can't reliably carry the ~20 MHz SDSPI default — higher than
 *  this reproducibly gives ESP_ERR_INVALID_CRC on the lab rig. */
#define SD_MAX_FREQ_KHZ         4000

#define SD_MOUNT_POINT          "/sdcard"

/** Operator-authored, one line, no rebuild required to change site:
 *  home | G402 | DLSU_Library | Goks (case-insensitive, whitespace trimmed). */
#define SD_LOCATION_FILE        SD_MOUNT_POINT "/location.txt"

/** Written at the card root (never inside a topology folder) when location.txt
 *  is missing or unrecognised — environment must be RECORDED, never guessed. */
#define SD_LOCATION_ERR_FILE    SD_MOUNT_POINT "/LOCATION_MISSING.txt"

/** HOST CLOCK ANCHOR — one line, a Unix epoch (UTC seconds), written by the
 *  SET_TIME console command (csv_logger.c) and read back at the next boot by
 *  sd_status_apply_clock_anchor().
 *
 *  This board has no RTC and never reaches NTP, so the ONLY real calendar it
 *  can ever have is one a laptop hands it over USB. Every host tool that opens
 *  a board's port pushes the current time here (tools/export_logs.py
 *  _push_host_time), so the anchor is refreshed on every export, MAC read and
 *  SET_LOCATION pass. The next boot starts its clock at anchor + uptime
 *  instead of BUILD TIME + uptime, which is what makes runs.csv's "started"
 *  column a real capture date rather than a rebuild date.
 *
 *  Card root, not a leaf folder: it describes the CARD's last contact with a
 *  laptop, not any one attack/topology/location run. Being at the root also
 *  keeps it out of DELETE_SD_FILE's reach (sd_rel_file_valid() only accepts
 *  *_telem.csv / *_arrivals.csv inside a leaf), exactly like location.txt. */
#define SD_CLOCK_FILE           SD_MOUNT_POINT "/clock.txt"

/** Every date the board WRITES (runs.csv, status report, console, FAT file
 *  times) is Philippine time, UTC+8 - the team's own clock. The clock itself
 *  still holds a true UTC epoch (clock.txt, SET_TIME); only the rendering is
 *  local. POSIX spelling: "PHT-8" means UTC+8 (the sign is inverted in TZ).
 *
 *  Also how the BUILD stamp is read: __DATE__/__TIME__ are the build laptop's
 *  wall clock, i.e. PH time. Read as UTC (the old behaviour) it landed 8 h in
 *  the future, so a real SET_TIME anchor always "lost" to it and every capture
 *  kept the build-time estimate. A team member building outside UTC+8 must
 *  change this, or their build stamps will be off by the difference. */
#define SD_CLOCK_TZ             "PHT-8"
#define SD_CLOCK_TZ_LABEL       "PHT"

/** Topology folder names — MUST stay byte-identical to _TOPOLOGY_DIR in
 *  tools/export_logs.py so the card mirrors exports/. Note PARTIAL's quirk:
 *  "partial_mesh", not "partial". Indexed by MESH_TOPOLOGY
 *  (NIS_TOPO_STAR..NIS_TOPO_PARTIAL above) — defined in sd_status.c. */
#define SD_LOCATION_HOME        "home"
#define SD_LOCATION_G402        "G402"
#define SD_LOCATION_DLSU_LIB    "DLSU_Library"
#define SD_LOCATION_GOKS        "Goks"

/** Operator-authored, optional. Overrides the MAC lookup table in
 *  node_identity.c. Two keys, one per line, '#' comments allowed:
 *      nickname=Node-3-BH
 *      role=blackhole
 *  Absent file / absent key / bad value each fall through to the MAC table. */
#define SD_NODE_CONFIG_FILE     SD_MOUNT_POINT "/node_config.txt"

/* ═══════════════════════════════════════════════════════════════════════════
 * TASK PRIORITIES AND STACK SIZES
 * ═══════════════════════════════════════════════════════════════════════════ */

#define TASK_PRIO_PHASE_LISTENER    8    /**< High priority — must wake quickly */
#define TASK_PRIO_TELEMETRY         5    /**< Normal sampling loop (victim/root) */
#define TASK_PRIO_PROBE_GEN         5    /**< Victim probe generator */
#define TASK_PRIO_PROBE_SINK        6    /**< Root probe receiver / attacker relay/tunnel */
#define TASK_PRIO_ATTACKER_TELEMETRY 7   /**< Attacker sampling loop. ABOVE the relay/
                                          *   tunnel sink (6) so heavy relay traffic on
                                          *   an intermediate attacker (esp. linear
                                          *   topology) can't starve it — the victim's
                                          *   plain prio-5 loop samples fine because it
                                          *   has no relay competing, but the blackhole/
                                          *   wormhole attacker at 5 dropped to <1 Hz and
                                          *   its attack-phase windows got discarded (<4
                                          *   samples/window). Kept BELOW the phase
                                          *   listener (8) so packet dispatch and the
                                          *   forward/drop attack timing are unaffected.
                                          *   Restores the uniform SAMPLING_INTERVAL_MS
                                          *   rate the telemetry loop (thesis Fig 4.24)
                                          *   assumes for every node. */
#define TASK_PRIO_SERIAL_EXPORT     3    /**< Low priority — only runs post-experiment */
#define TASK_PRIO_HEARTBEAT         4    /**< Below telemetry — a liveness/topology ping,
                                          *   not real-time data */

#define STACK_PHASE_LISTENER    6144U   /* also runs the non-phase data cb (probe sink) */
#define STACK_TELEMETRY         4096U
#define STACK_PROBE_GEN         4096U
#define STACK_PROBE_SINK        4096U
#define STACK_SERIAL_EXPORT     6144U
#define STACK_HEARTBEAT         6144U   /* root: also builds, renders and checks the topology graph */

/* ═══════════════════════════════════════════════════════════════════════════
 * NODE IDENTIFICATION
 * ═══════════════════════════════════════════════════════════════════════════ */

/** Maximum node ID string length (e.g. "NODE_AABBCCDDEEFF"). */
#define NODE_ID_LEN             24U

/** Maximum run ID string length (e.g. "RUN_20260606_143000"). */
#define RUN_ID_LEN              32U