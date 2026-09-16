/**
 * @file node_identity.c
 * @brief Boot-time nickname resolution. See node_identity.h.
 *
 * NIS16 — CTTHES3 — Command Center
 */

#include "node_identity.h"
#include "sd_status.h"

#include <string.h>
#include <stdbool.h>

#include "esp_mac.h"
#include "esp_log.h"

static const char *TAG = "NODE_ID";

static node_identity_t s_identity;
static bool            s_resolved;

/* ── MAC lookup table ─────────────────────────────────────────────────────────
 * Real board MACs from Resources/reference/NODE-INVENTORY.md (built from flash
 * logs, jul. 26-27 2026). The STA MAC is the board's true identity; the softAP
 * MAC is always +1, so match on STA only.
 *
 * ⚠ The root's MAC is recorded in NODE-INVENTORY.md only as a partial
 * ("28:05:…:D7:B4") and is therefore NOT in this table — the root falls through
 * to "Unassigned" until someone reads the full value off a boot banner and adds
 * it here. That is cosmetic: it changes the dashboard label only, never
 * behaviour.
 *
 * Nicknames are kept short deliberately — they are a fixed-width dashboard
 * column, not prose.
 * ─────────────────────────────────────────────────────────────────────────── */
typedef struct {
    uint8_t     mac[6];
    const char *nickname;
} mac_nickname_entry_t;

static const mac_nickname_entry_t MAC_LOOKUP_TABLE[] = {
    { {0xb4, 0xbf, 0xe9, 0x34, 0xed, 0x80}, "Node-2-Victim" },
    { {0x70, 0x4b, 0xca, 0x25, 0xb7, 0x68}, "Node-3-Victim" },
    { {0xb4, 0xbf, 0xe9, 0x32, 0xfe, 0x90}, "Node-4-Victim" },
    { {0xb0, 0xcb, 0xd8, 0xf3, 0x32, 0x18}, "Node-5-Attacker" },
};

#define MAC_LOOKUP_COUNT \
    (sizeof(MAC_LOOKUP_TABLE) / sizeof(MAC_LOOKUP_TABLE[0]))

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

    /* 2. MAC lookup table. */
    if (source == NULL) {
        for (size_t i = 0; i < MAC_LOOKUP_COUNT; i++) {
            if (memcmp(MAC_LOOKUP_TABLE[i].mac, s_identity.mac, 6) == 0) {
                strlcpy(s_identity.nickname, MAC_LOOKUP_TABLE[i].nickname,
                        sizeof(s_identity.nickname));
                source = "MAC table";
                break;
            }
        }
    }

    /* 3. Give up, but keep running — a nameless row still beats no row. */
    if (source == NULL) {
        strlcpy(s_identity.nickname, "Unassigned", sizeof(s_identity.nickname));
        source = "default";
        ESP_LOGW(TAG, "MAC " MACSTR " is not in node_config.txt or the MAC "
                      "table -- add it to node_identity.c or the SD file.",
                 MAC2STR(s_identity.mac));
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
