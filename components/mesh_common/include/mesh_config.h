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
 *  Set to 6 for multi-topology experiments; root is layer 0. */
#define MESH_MAX_LAYER      6

/** Maximum children per node (limits fan-out in star / tree topologies). */
#define MESH_MAX_CHILDREN   10

/* ── M3 topology shaping ──────────────────────────────────────────────────────
 * ESP-WIFI-MESH self-organises by RSSI + physical placement, so the four
 * proposal topologies are set up mostly by WHERE the boards sit. These knobs
 * bias the stack to match the intended shape and are overridable from the build
 * (-DMESH_TOPOLOGY=...) so a run can pick a topology with no source editing:
 *
 *   idf.py build                        → default (TREE, unchanged M1 behaviour)
 *   idf.py -DMESH_TOPOLOGY=0 build       → STAR (cap depth at 2)
 *   idf.py -DMESH_TOPOLOGY=2 build       → LINEAR (force a chain)
 *
 *   NIS_TOPO_STAR    — cap depth at 2: every node is a direct child of root.
 *   NIS_TOPO_TREE    — default self-organising tree (unchanged M1 behaviour).
 *   NIS_TOPO_LINEAR  — force a CHAIN so nodes line up hop-by-hop.
 *   NIS_TOPO_PARTIAL — tree that allows multiple potential parents (same code
 *                      path as TREE; the "partial" shape comes from physical
 *                      placement, not a firmware knob — see verify_topology.py).
 * Build ALL boards in a run with the SAME topology, or nodes will disagree on
 * max-layer/chain shaping. (Names are NIS_-prefixed to avoid clashing with the
 * IDF MESH_TOPO_* enum.)
 * ────────────────────────────────────────────────────────────────────────── */
#define NIS_TOPO_STAR       0
#define NIS_TOPO_TREE       1
#define NIS_TOPO_LINEAR     2
#define NIS_TOPO_PARTIAL    3

#ifndef MESH_TOPOLOGY
#define MESH_TOPOLOGY       NIS_TOPO_TREE
#endif

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