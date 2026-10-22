/**
 * @file mesh_setup.h
 * @brief ESP-WIFI-MESH initialisation API (common to all node roles).
 *
 * Call mesh_setup_init() once from app_main() before starting any task that
 * uses the mesh.  The function blocks until the node is fully connected and
 * logs parent/layer information to the console.
 *
 * NIS16 — CTTHES2 Milestone 1 — Common Module
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "esp_mesh.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── Role tag embedded in CSV rows ──────────────────────────────────────── */
typedef enum {
    MESH_ROLE_ROOT   = 0,   /**< Root node (phase controller + probe sink)  */
    MESH_ROLE_VICTIM = 1,   /**< Regular victim node (probe generator)       */
    MESH_ROLE_ATCK_B = 2,   /**< Blackhole attacker (Milestone 2)            */
    MESH_ROLE_ATCK_WA= 3,   /**< Wormhole node A / root-side (Milestone 2)  */
    MESH_ROLE_ATCK_WB= 4,   /**< Wormhole node B / leaf-side (Milestone 2)  */
} mesh_node_role_t;

/**
 * @brief Initialise Wi-Fi, the mesh stack, and register event handlers.
 *
 * @param role  Role of this node — stored and used to build the node_id string.
 * @return      ESP_OK on success; panics on fatal hardware error.
 *
 * The function:
 *  1. Initialises NVS, TCP/IP stack, and the default Wi-Fi driver.
 *  2. Sets MESH_ID, MESH_PASSWORD, max layer, and max children from
 *     mesh_config.h.
 *  3. If MESH_USE_ROUTER == 1, configures the root uplink to the AP.
 *  4. Starts the mesh and waits (up to 60 s) for a MESH_EVENT_PARENT_CONNECTED
 *     event (or MESH_EVENT_ROOT_GOT_IP for the root).
 *  5. Logs node ID, layer, and parent MAC at INFO level.
 */
esp_err_t mesh_setup_init(mesh_node_role_t role);

/**
 * @brief Populate @p buf with this node's ID string ("NODE_<MAC6HEX>").
 *        Thread-safe; may be called after mesh_setup_init().
 *
 * @param buf   Destination buffer (at least NODE_ID_LEN bytes).
 */
void mesh_setup_get_node_id(char *buf);

/**
 * @brief Return the current mesh layer of this node as the stack reports it
 *        (1 = root, -1 = not connected).
 *        Thread-safe; may be called after mesh_setup_init().
 */
int mesh_setup_get_layer(void);

/**
 * @brief Copy the parent node's MAC address into @p mac (6 bytes).
 *        Returns false if this node is the root (no parent).
 */
bool mesh_setup_get_parent_mac(uint8_t mac[6]);

/**
 * @brief Return true if this node is the root of the mesh.
 */
bool mesh_setup_is_root(void);

/* ── Command Center heartbeat (NIS16 — CTTHES3) ──────────────────────────── */

/**
 * @brief Start this node's heartbeat sender task.
 *
 * Call on EVERY node — root included — after mesh_setup_init(),
 * node_identity_resolve() and phase_listener_start(). Sends a
 * node_heartbeat_pkt_t (mesh_messages.h) to the root every
 * HEARTBEAT_INTERVAL_MS carrying this node's MAC, nickname, role, mesh layer
 * and parent RSSI.
 */
esp_err_t heartbeat_start(void);

/**
 * @brief Root-only: seed the node table with this node's own row.
 *
 * Call once on the root, after mesh_setup_init()/node_identity_resolve() and
 * before packets can arrive (i.e. before/alongside phase_listener_start()).
 */
void heartbeat_table_init(void);

/**
 * @brief Root-only: feed one received mesh packet to the heartbeat table.
 *
 * Safe to call unconditionally from a shared packet dispatcher — this is a
 * no-op (returns false) for anything that isn't a HEARTBEAT_MSG_MAGIC frame.
 * Inserts/updates the sender's row; reprints the full table (sorted by
 * layer) whenever the sender is new or its layer/role/nickname changed, so
 * whether the connected nodes are following the built topology is visible
 * at a glance in the console.
 *
 * @return true if the packet was a heartbeat frame (handled).
 */
bool heartbeat_ingest(const uint8_t *data, size_t len);

/**
 * @brief Root-only: how many nodes currently hang directly under the node that
 *        reports role BLACKHOLE (the attacker), from the heartbeat table.
 *
 * Same parent-link resolution as the printed topology (parent = SoftAP BSSID =
 * STA MAC + 1). Rows with no heartbeat for HEARTBEAT_STALE_MS are ignored.
 * Used by the root's tree attacker-child gate (TREE_GATE_STABLE_S).
 *
 * @return child count (0 = attacker present but childless); -1 if no fresh
 *         BLACKHOLE row yet, the table is not initialised, or out of memory.
 */
int heartbeat_attacker_child_count(void);

/**
 * @brief Root-only: true when this build is TREE + BLACKHOLE, i.e. the root must
 *        hold Phase 0 until heartbeat_attacker_child_count() >= 1.
 *
 * A function, not a macro, on purpose: the root's main component is not
 * compiled with -DMESH_TOPOLOGY (only mesh_common is), so a compile-time test
 * in root_main.c would read the default (tree) in every build.
 */
bool heartbeat_tree_gate_active(void);

/**
 * @brief Root-only: true on a WORMHOLE build - the root then holds Phase 0
 *        until heartbeat_wormhole_ready() (oct. 16 2026).
 */
bool heartbeat_wormhole_gate_active(void);

/**
 * @brief Root-only: is the wormhole set up so the run can start? Exactly one
 *        WORMHOLE_A and one WORMHOLE_B, both reporting the UART link OK (both
 *        directions), both attached, and A closer to the root than B.
 * @param why  filled with the first problem found, or the OK summary.
 */
bool heartbeat_wormhole_ready(char *why, size_t len);

/**
 * @brief Root-only: record one wormhole TUNNEL TEST that arrived (sent by B over
 *        the UART before Phase 0, re-injected by A). Shown as the "Tunnel test"
 *        line of the WORMHOLE TUNNEL block.
 * @return how many tests have arrived so far
 */
uint32_t mesh_setup_note_tunnel_test(const uint8_t src_mac[6]);

/**
 * @brief Wormhole ends (tree / partial, D-30): the PEER end's mesh layer, from
 *        its UART HELLO. On the board flashed as B it sets the minimum parent
 *        depth (never shallower than A), bars A's own mesh AP (@p peer_mac = A's
 *        STA MAC) as a parent and, when @p may_repick (before Phase 0 only),
 *        moves B if A is as deep as B or B sits under A. Tree also keeps B at
 *        H03 (parent at H02, thesis Fig. 4.18). No-op elsewhere.
 */
void mesh_setup_wormhole_peer_layer(int peer_layer, const uint8_t peer_mac[6], bool may_repick);

#ifdef __cplusplus
}
#endif