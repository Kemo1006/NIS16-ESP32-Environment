/**
 * @file blackhole_target.c
 * @brief Runtime-settable blackhole attacker MAC (F2). See blackhole_target.h.
 *
 * NIS16 -- CTTHES3 -- F2
 */

#include "blackhole_target.h"
#include "mesh_config.h"

#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "BH_TARGET";

/* Same namespace the run counter already uses (see build_run_id() in the node
 * firmwares) -- one NVS namespace for this project, not one per feature. */
#define BH_NVS_NAMESPACE "nis16"
#define BH_NVS_KEY       "bh_mac"

/* A MAC that cannot be a real STA MAC, and would therefore reproduce exactly
 * the silent failure this module exists to prevent: probes addressed to nobody,
 * zero root arrivals in every phase, PDR and ForwardingRatio 100% NaN, every
 * board looking healthy. Rejected at the point of entry instead. */
static bool mac_is_unusable(const uint8_t mac[6])
{
    bool all_zero = true, all_ff = true;
    for (int i = 0; i < 6; i++) {
        if (mac[i] != 0x00) all_zero = false;
        if (mac[i] != 0xFF) all_ff = false;
    }
    /* Bit 0 of the first octet set = group/multicast address. A station MAC is
     * always unicast, so this catches a broadcast or multicast value too. */
    bool multicast = (mac[0] & 0x01) != 0;
    return all_zero || all_ff || multicast;
}

bh_target_source_t blackhole_target_get(uint8_t out_mac[6])
{
    const uint8_t compiled[6] = BLACKHOLE_ATTACKER_MAC;

    nvs_handle_t h;
    esp_err_t err = nvs_open(BH_NVS_NAMESPACE, NVS_READONLY, &h);
    if (err == ESP_OK) {
        uint8_t stored[6] = {0};
        size_t len = sizeof(stored);
        err = nvs_get_blob(h, BH_NVS_KEY, stored, &len);
        nvs_close(h);

        if (err == ESP_OK && len == 6 && !mac_is_unusable(stored)) {
            memcpy(out_mac, stored, 6);
            ESP_LOGI(TAG, "Attacker MAC from NVS: " MACSTR, MAC2STR(stored));
            return BH_TARGET_SRC_NVS;
        }
        if (err == ESP_OK && (len != 6 || mac_is_unusable(stored))) {
            /* Something wrote a malformed value. Say so loudly rather than
             * quietly targeting nobody -- the whole point of this module. */
            ESP_LOGE(TAG, "NVS holds an unusable attacker MAC (%u bytes) -- "
                          "ignoring it and using the compiled constant. "
                          "Re-issue SET_ATTACKER_MAC to fix.", (unsigned)len);
        }
    }

    memcpy(out_mac, compiled, 6);
    ESP_LOGI(TAG, "Attacker MAC from compiled default: " MACSTR,
             MAC2STR(compiled));
    return BH_TARGET_SRC_COMPILED;
}

esp_err_t blackhole_target_set(const uint8_t mac[6])
{
    if (!mac || mac_is_unusable(mac)) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t h;
    esp_err_t err = nvs_open(BH_NVS_NAMESPACE, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nvs_open failed: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_blob(h, BH_NVS_KEY, mac, 6);
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "Attacker MAC set to " MACSTR " -- takes effect on the "
                      "NEXT boot.", MAC2STR(mac));
    } else {
        ESP_LOGE(TAG, "Failed to store attacker MAC: %s", esp_err_to_name(err));
    }
    return err;
}

esp_err_t blackhole_target_clear(void)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(BH_NVS_NAMESPACE, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }

    err = nvs_erase_key(h, BH_NVS_KEY);
    /* Already absent is the desired end state, not a failure. */
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        err = ESP_OK;
    }
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "Attacker MAC override cleared -- the compiled constant "
                      "applies from the NEXT boot.");
    }
    return err;
}

static int hex_nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool blackhole_target_parse(const char *text, uint8_t out_mac[6])
{
    if (!text || !out_mac) return false;

    uint8_t parsed[6];
    int byte = 0;
    const char *p = text;

    while (*p && byte < 6) {
        /* Accept ':' and '-' as separators, and no separator at all. */
        if (*p == ':' || *p == '-') { p++; continue; }

        int hi = hex_nibble(*p);
        if (hi < 0) return false;
        int lo = hex_nibble(*(p + 1));
        if (lo < 0) return false;

        parsed[byte++] = (uint8_t)((hi << 4) | lo);
        p += 2;
    }

    /* Skip trailing whitespace/CR/LF the serial reader may have left on. */
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;

    if (byte != 6 || *p != '\0') return false;

    memcpy(out_mac, parsed, 6);
    return true;
}

const char *blackhole_target_source_str(bh_target_source_t src)
{
    return (src == BH_TARGET_SRC_NVS) ? "nvs" : "compiled";
}
