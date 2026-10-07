/**
 * @file node_identity.c
 * @brief Boot-time nickname resolution. See node_identity.h.
 *
 * NIS16 — CTTHES3 — Command Center
 */

#include "node_identity.h"
#include "sd_status.h"

#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "esp_mac.h"
#include "esp_log.h"

static const char *TAG = "NODE_ID";

static node_identity_t s_identity;
static bool            s_resolved;

/* ── No MAC lookup table (removed oct. 1, 2026 hardcode audit) ──────────────
 * This file used to carry a MAC -> nickname table from the jul. 2026 layout
 * ("Node-5-Attacker" etc.). Roles are decided per RUN, not per board, so the
 * table went stale: b0:cb:d8:f3:32:18 kept booting as "Node-5-Attacker" while
 * it was the ROOT. The fallback name is now derived from the board's own MAC
 * as "Board-<first>:<last>" - the same first:last bytes member_boards.json
 * records - so it can never disagree with the hardware. A real name still
 * comes from node_config.txt on the SD card. Dashboard label only; never
 * written to the CSVs and never changes behaviour.
 * ─────────────────────────────────────────────────────────────────────────── */

/* ── Public API ───────────────────────────────────────────────────────────── */

void node_identity_resolve(uint8_t build_role)
{
    memset(&s_identity, 0, sizeof(s_identity));
    s_identity.role = build_role;

    /* eFuse read — valid before mesh init, same call sd_status.c uses. */
    esp_read_mac(s_identity.mac, ESP_MAC_WIFI_STA);

    const char *source = NULL;

    /* 1. SD card, if sd_status.c found and cached a nickname while mounted. */
    const char *sd_nick = sd_status_get_config_nickname();
    if (sd_nick != NULL && sd_nick[0] != '\0') {
        strlcpy(s_identity.nickname, sd_nick, sizeof(s_identity.nickname));
        source = "node_config.txt";
    }

    /* 2. Fall back to a name derived from the MAC itself - never guessed. */
    if (source == NULL) {
        snprintf(s_identity.nickname, sizeof(s_identity.nickname),
                 "Board-%02X:%02X", (unsigned)s_identity.mac[0],
                 (unsigned)s_identity.mac[5]);
        source = "MAC (no node_config.txt nickname)";
    }

    /* A role= line on the SD card cannot change behaviour (that comes from the
     * build flags), so honouring it would only let the dashboard lie. Warn and
     * ignore, so a stale card is visible rather than silently misleading. */
    const char *sd_role = sd_status_get_config_role();
    if (sd_role != NULL && sd_role[0] != '\0') {
        ESP_LOGW(TAG, "node_config.txt says role=\"%s\" -- IGNORED. Role is "
                      "fixed by this binary's build flags (%s).",
                 sd_role, node_role_to_str(s_identity.role));
    }

    s_resolved = true;

    ESP_LOGI(TAG, "Identity: \"%s\" role=%s mac=" MACSTR " (via %s)",
             s_identity.nickname, node_role_to_str(s_identity.role),
             MAC2STR(s_identity.mac), source);
}

const node_identity_t *node_identity_get(void)
{
    if (!s_resolved) {
        /* Caller ordering bug — resolve with an unknown role rather than
         * handing back a zeroed struct that would render as a blank row. */
        ESP_LOGW(TAG, "node_identity_get() before resolve() -- resolving now.");
        node_identity_resolve(NODE_ROLE_UNKNOWN);
    }
    return &s_identity;
}

const char *node_identity_nickname(void)
{
    return node_identity_get()->nickname;
}

uint8_t node_identity_role(void)
{
    return node_identity_get()->role;
}

void node_identity_set_role(uint8_t role)
{
    (void)node_identity_get();      /* resolves first if a caller skipped it */
    if (s_identity.role != role) {
        ESP_LOGI(TAG, "Role %s -> %s (decided at run time)",
                 node_role_to_str(s_identity.role), node_role_to_str(role));
        s_identity.role = role;
    }
}
