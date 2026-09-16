/**
 * @file node_identity.h
 * @brief Boot-time resolution of this board's display nickname.
 *
 * Resolution order for the NICKNAME:
 *   1. /sdcard/node_config.txt  → "nickname=..."   (read by sd_status.c while
 *                                                   the card is still mounted)
 *   2. MAC lookup table in node_identity.c
 *   3. "Unassigned"
 *
 * The ROLE is NOT resolved from the SD card. Behaviour still comes from the
 * build flags (ACTIVE_ATTACK / BLACKHOLE_ROLE / WORMHOLE_END) because the three
 * child firmwares are still three separate binaries — so a role read from SD
 * could disagree with what the board is actually doing and make the dashboard
 * display something false. The caller passes its own build-time role in, and a
 * conflicting "role=" line in node_config.txt is warned about and ignored.
 *
 * NIS16 — CTTHES3 — Command Center
 */

#pragma once

#include <stdint.h>
#include "mesh_messages.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t mac[6];                       /**< STA MAC (esp_read_mac)     */
    char    nickname[NODE_NICKNAME_LEN];  /**< display name, NUL-terminated */
    uint8_t role;                         /**< node_role_t — from build flags */
} node_identity_t;

/**
 * @brief Resolve this board's identity. Call once from app_main, AFTER
 *        sd_status_run_boot_check() and BEFORE heartbeat_start().
 *
 * Never fails: with no SD card and no MAC-table match the nickname becomes
 * "Unassigned" and the run continues, matching sd_status.c's report-and-continue
 * behaviour.
 *
 * @param build_role This binary's role (node_role_t), from the caller's own
 *                   build flags. mesh_common cannot read ACTIVE_ATTACK itself —
 *                   it is scoped to the app components — so it must be passed in.
 */
void node_identity_resolve(uint8_t build_role);

/** Resolved identity. Valid after node_identity_resolve(); never NULL. */
const node_identity_t *node_identity_get(void);

/** Convenience accessor — never NULL. */
const char *node_identity_nickname(void);

/** Convenience accessor — node_role_t. */
uint8_t node_identity_role(void);

#ifdef __cplusplus
}
#endif
