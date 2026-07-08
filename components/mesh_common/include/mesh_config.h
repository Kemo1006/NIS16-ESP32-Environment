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

/** Node A's Wi-Fi STA MAC — Node B tunnels captured probes to this address.
 *  ⚠️ SET THIS to your Node-A board's STA MAC (the MAC export_logs.py and the
 *  boot log report for that board, e.g. B0:CB:D8:F3:32:18). Only Node B reads
 *  it; Node A ignores it. Node B logs a boot-time WARNING and every tunnel send
 *  fails (visible as a climbing retry_count with tx frozen) if it is left at the
 *  placeholder below — that is the #1 "wormhole didn't work" pitfall. */
#define WORMHOLE_NODE_A_MAC     {0xF4, 0x2D, 0xC9, 0x73, 0xE6, 0x18}

/** Magic cookie prefixing every tunnelled packet on the A<->B channel, so Node A
 *  can tell a tunnelled probe from ordinary mesh traffic. ("TNL1") */
#define WORMHOLE_TUNNEL_MAGIC   0x544E4C31U

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

/** Telemetry sample interval — 1 Hz as specified in the thesis. */
#define SAMPLING_INTERVAL_MS    1000U

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

/** Maximum CSV file size per run before log rotation (bytes). */
#define LOGGER_MAX_FILE_BYTES   (500U * 1024U)    /* 500 KB */

/** USB serial baud rate for log extraction (informational only — the export
 *  task streams over UART0 at the CONSOLE baud, set by
 *  CONFIG_ESP_CONSOLE_UART_BAUDRATE in sdkconfig, currently 115200). A 460800
 *  experiment was reverted (sdkconfig kept regenerating back to 115200 →
 *  export/wipe baud mismatch; see esp32-issues.md I-007). Keep this in sync with
 *  the sdkconfig value and export_logs.py's BAUD. */
#define SERIAL_BAUD             115200

/* Debug: start serial-export task at init for quick host pulls (0 = disabled) */
#define CSV_EXPORT_ON_INIT     0

/* ═══════════════════════════════════════════════════════════════════════════
 * TASK PRIORITIES AND STACK SIZES
 * ═══════════════════════════════════════════════════════════════════════════ */

#define TASK_PRIO_PHASE_LISTENER    8    /**< High priority — must wake quickly */
#define TASK_PRIO_TELEMETRY         5    /**< Normal sampling loop */
#define TASK_PRIO_PROBE_GEN         5    /**< Victim probe generator */
#define TASK_PRIO_PROBE_SINK        6    /**< Root probe receiver */
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