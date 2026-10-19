/**
 * @file mesh_messages.h
 * @brief Command Center wire formats — heartbeat and (Phase 2) command packets.
 *
 * EVERY packet type on this mesh leads with a uint32_t magic. phase_msg_t
 * (PHASE_MSG_MAGIC) and probe_pkt_t (PROBE_MAGIC / PROBE_MAGIC_WORMHOLE) already
 * do, and the single esp_mesh_recv() reader in phase_listener.c demuxes on it.
 * A packet that led with a 1-byte msg_type instead could not be told apart from
 * the first byte of an existing magic, so msg_type is the SECOND field here and
 * is informational only — never dispatch on it before checking magic.
 *
 * NIS16 — CTTHES3 — Command Center
 */

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Magics (first 4 bytes of every payload) ─────────────────────────────── */

/* v2 carries parent_mac and a 16-bit layer. The v1 magic is kept only so the
 * root can name a board that still runs the old firmware instead of silently
 * never listing it. */
#define HEARTBEAT_MSG_MAGIC      0x48454132U   /* "HEA2" */
#define HEARTBEAT_MSG_MAGIC_V1   0x48454152U   /* "HEAR" - pre-parent_mac firmware */
#define COMMAND_MSG_MAGIC     0x434D4E44U   /* "CMND" — Phase 2 */

/** Nickname buffer. 24, not 16: "Node-3-Blackhole-G402" is 21 chars + NUL. */
#define NODE_NICKNAME_LEN     24U

/* ── Message / role / status enums ───────────────────────────────────────── */

typedef enum {
    MSG_TYPE_PHASE_SYNC = 0x01,
    MSG_TYPE_HEARTBEAT  = 0x02,
    MSG_TYPE_COMMAND    = 0x03
} mesh_msg_type_t;

/**
 * Runtime role, reported by a node about itself for display purposes ONLY.
 *
 * This does NOT drive behaviour — behaviour still comes from the build flags
 * (ACTIVE_ATTACK / BLACKHOLE_ROLE / WORMHOLE_END), because the three child
 * firmwares remain three separate binaries. This enum exists so the dashboard
 * can label a row. Deliberately distinct from mesh_setup.h's MESH_ROLE_*, which
 * is the mesh-layer root/child distinction and means something different.
 */
typedef enum {
    NODE_ROLE_UNKNOWN    = 0,
    NODE_ROLE_ROOT       = 1,
    NODE_ROLE_VICTIM     = 2,
    NODE_ROLE_BLACKHOLE  = 3,
    NODE_ROLE_WORMHOLE_A = 4,
    NODE_ROLE_WORMHOLE_B = 5
} node_role_t;

/** Phase 2 (force-export). Phase 1 always reports IDLE / 0 %. */
typedef enum {
    EXPORT_STATUS_IDLE        = 0x00,
    EXPORT_STATUS_IN_PROGRESS = 0x01,
    EXPORT_STATUS_COMPLETE    = 0x02,
    EXPORT_STATUS_FAILED      = 0x03,
    /** Run over and csv_logger_close() done: files closed, card unmounted.
     *  Safe to export. Shown in the root's EXPORT column. */
    EXPORT_STATUS_LOG_CLOSED  = 0x04
} export_status_t;

/* ── Heartbeat ───────────────────────────────────────────────────────────── */

/**
 * Child → root, every HEARTBEAT_INTERVAL_MS.
 *
 * export_status / export_percent are Phase 2 fields carried from the start on
 * purpose: adding them later would change the wire format and force a reflash
 * of every board mid-campaign. Phase 1 populates them as IDLE / 0.
 *
 * parent_mac is what lets the root rebuild the actual tree (and check it
 * against the built topology) instead of only sorting rows by layer. layer is
 * 16-bit because a chain may be up to 1000 layers deep (mesh_config.h).
 *
 * wh_link (oct. 14 2026) is APPENDED, not inserted: an old board's 52-byte
 * beat is still accepted by a new root (heartbeat_ingest reads wh_link only
 * when the frame is long enough), and an old root ignores the extra byte.
 *
 * 54 bytes (sd_log appended oct. 19 2026) — comfortably inside phase_listener.c's 128-byte rx_buf.
 */
typedef struct __attribute__((packed)) {
    uint32_t magic;                        /**< HEARTBEAT_MSG_MAGIC — must be first */
    uint8_t  msg_type;                     /**< MSG_TYPE_HEARTBEAT (informational)  */
    uint8_t  src_mac[6];                   /**< STA MAC — the board's true identity */
    char     nickname[NODE_NICKNAME_LEN];  /**< NUL-terminated, may be truncated    */
    uint8_t  assigned_role;                /**< node_role_t                         */
    int8_t   parent_rssi;                  /**< dBm; 0 on the root (no parent)      */
    int16_t  layer;                        /**< as the stack reports it; -1 = none  */
    uint8_t  parent_mac[6];                /**< parent's SoftAP BSSID; 0 = no parent */
    uint32_t uptime_sec;                   /**< seconds since boot                  */
    uint8_t  current_phase;                /**< phase_listener_get_phase_id()       */
    uint8_t  export_status;                /**< export_status_t — Phase 2           */
    uint8_t  export_percent;               /**< 0-100 — Phase 2                     */
    uint8_t  wh_link;                      /**< wh_link_t — wormhole ends only      */
    uint8_t  sd_log;                       /**< sd_log_state_t (oct. 19 2026), appended
                                                like wh_link: a 53-byte beat (older
                                                boards) is still read, without it */
} node_heartbeat_pkt_t;

/** Wormhole A<->B UART link as each END sees it (heartbeat wh_link). Lets the
 *  root's dashboard say "the wire is dead" instead of only showing the symptom
 *  (ends reversed / no shortcut) - with no HELLO, each end silently falls back
 *  to its build-time role. */
typedef enum {
    WH_LINK_NA      = 0,   /**< not a wormhole end, or pre-oct-14 firmware   */
    WH_LINK_OK      = 1,   /**< peer's HELLO heard within PEER_FRESH_MS       */
    WH_LINK_NONE    = 2,   /**< NOTHING ever heard from the peer over UART    */
    WH_LINK_LOST    = 3,   /**< heard before, silent for PEER_FRESH_MS now    */
    WH_LINK_WAITING = 4,   /**< just booted - still inside the first window   */
    WH_LINK_ONEWAY  = 5,   /**< this end hears the peer, the peer does NOT hear
                                it (oct. 16 2026): one jumper of the crossed
                                pair is loose. Before this, each end trusted its
                                own view and both could pick the SAME role.   */
    WH_LINK_ECHO    = 6    /**< this end hears its OWN HELLOs (oct. 17 2026):
                                its TX is bridged to its own RX. Before this the
                                echo was taken for the peer - 'UART OK' on a
                                board that never heard the other one, and both
                                ends B.                                        */
} wh_link_t;

/* ── Command (Phase 2 — defined now so the wire format is stable) ────────── */

typedef enum {
    CMD_NONE         = 0x00,
    CMD_FORCE_EXPORT = 0x01,
    CMD_SOFT_RESET   = 0x02
} mesh_command_id_t;

/** Root → children. target_mac all-FF means "every node". */
typedef struct __attribute__((packed)) {
    uint32_t magic;          /**< COMMAND_MSG_MAGIC — must be first */
    uint8_t  msg_type;       /**< MSG_TYPE_COMMAND                  */
    uint8_t  target_mac[6];  /**< FF:FF:FF:FF:FF:FF = broadcast     */
    uint8_t  command_id;     /**< mesh_command_id_t                 */
} mesh_command_pkt_t;

/** Human-readable role name for dashboard rendering. Never returns NULL. */
static inline const char *node_role_to_str(uint8_t role)
{
    switch (role) {
        case NODE_ROLE_ROOT:       return "ROOT";
        /* "CHILD", not "VICTIM": this is what the node IS by build. Whether it
         * is a VICTIM depends on where the attacker landed in THIS run, which
         * only the root can see -- it prints that separately once the tree is
         * up (heartbeat_table_print). The enum VALUE is on the wire and must
         * not change; only the word shown to a human does. */
        case NODE_ROLE_VICTIM:     return "CHILD";
        case NODE_ROLE_BLACKHOLE:  return "BLACKHOLE";
        case NODE_ROLE_WORMHOLE_A: return "WORMHOLE_A";
        case NODE_ROLE_WORMHOLE_B: return "WORMHOLE_B";
        default:                   return "UNKNOWN";
    }
}

#ifdef __cplusplus
}
#endif
