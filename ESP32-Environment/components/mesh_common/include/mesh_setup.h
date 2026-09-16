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
 * @brief Return the current mesh layer of this node (0 = root).
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

#ifdef __cplusplus
}
#endif