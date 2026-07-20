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

/** Maximum hop depth the mesh is allowed to grow to.
 *  Set to 6 for multi-topology experiments; root is layer 1 (ESP-MESH
 *  convention — esp_mesh_get_layer() returns 1 at the root). */
#define MESH_MAX_LAYER      6

/** Default max children per node (fan-out cap). Per-topology overrides below
 *  narrow this for LINEAR (chain) and PARTIAL (constrained branching). */
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

/** Max nodes the root snapshots from the routing table when broadcasting a
 *  phase downstream. ESP-WIFI-MESH has no single broadcast primitive, so the
 *  root unicasts to every node in this table. Sized well above any topology. */
#define MESH_ROUTE_TABLE_MAX 32

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

/** Stabilisation window before Phase 0 starts (mesh formation, not logged). */
#define PHASE_STABILISE_S   60U

/** Phase 0 — Baseline: normal operation, no manipulation. */
#define PHASE_BASELINE_S    300U       /* 5 minutes */

/** Phase 1/2 — Manipulation window (blackhole or wormhole). */
#define PHASE_ATTACK_S      180U       /* 3 minutes */

/** Phase 3 — Cooldown: manipulation off, network stabilises. */
#define PHASE_COOLDOWN_S    120U       /* 2 minutes */

/* ═══════════════════════════════════════════════════════════════════════════
 * PHASE IDs  (broadcast in control messages)
 * ═══════════════════════════════════════════════════════════════════════════ */

#define PHASE_ID_BASELINE       0
#define PHASE_ID_BLACKHOLE      1
#define PHASE_ID_WORMHOLE       2
#define PHASE_ID_COOLDOWN       3
#define PHASE_ID_TERMINATE      4

/* Ground-truth labels embedded in every CSV row (Table 4.8). */
#define GT_LABEL_BASELINE       0
#define GT_LABEL_BLACKHOLE      1
#define GT_LABEL_WORMHOLE       2
/* Cooldown and Terminate both map to label 0 (normal) per Table 4.1. */

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
#define BLACKHOLE_ATTACKER_MAC   {0xB0, 0xCB, 0xD8, 0xF3, 0x32, 0x18} // COM26 (blackhole attacker) — b0:cb:d8:f3:32:18

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

/* ═══════════════════════════════════════════════════════════════════════════
 * TELEMETRY SAMPLING
 * ═══════════════════════════════════════════════════════════════════════════ */

/** Telemetry sample interval. Raised from the proposal's 1 Hz (1000ms) to 20 Hz
 *  (50ms) on 2026-07-12 per adviser direction: a single run's telemetry file
 *  must exceed 10,000 rows, and at 1 Hz the fixed 600s (Table 4.1) run only
 *  yields ~600-700 rows. 600s / 50ms = 12,000 rows nominal — a margin above
 *  the 10,000 floor. This is a DEVIATION from the proposal's stated "1 Hz" —
 *  see ../../thesis-deviate.md. Requires the 4MB-flash partition table (see
 *  partitions.csv) — a 1 Hz-sized SPIFFS partition cannot hold 20 Hz data. */
#define SAMPLING_INTERVAL_MS    50U

/* ═══════════════════════════════════════════════════════════════════════════
 * PROBE GENERATION (victim nodes)
 * ═══════════════════════════════════════════════════════════════════════════ */

/** Interval between application-layer probes sent by victim nodes. */
#define PROBE_INTERVAL_MS       1000U

/** Maximum payload length for probe packets (bytes). */
#define PROBE_PAYLOAD_LEN       32U

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

#define STACK_PHASE_LISTENER    6144U   /* also runs the non-phase data cb (probe sink) */
#define STACK_TELEMETRY         4096U
#define STACK_PROBE_GEN         4096U
#define STACK_PROBE_SINK        4096U
#define STACK_SERIAL_EXPORT     6144U

/* ═══════════════════════════════════════════════════════════════════════════
 * NODE IDENTIFICATION
 * ═══════════════════════════════════════════════════════════════════════════ */

/** Maximum node ID string length (e.g. "NODE_AABBCCDDEEFF"). */
#define NODE_ID_LEN             24U

/** Maximum run ID string length (e.g. "RUN_20260606_143000"). */
#define RUN_ID_LEN              32U