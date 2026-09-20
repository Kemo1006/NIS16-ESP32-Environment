/**
 * @file blackhole_target.h
 * @brief Runtime-settable blackhole attacker MAC (F2).
 *
 * WHY THIS EXISTS
 * ---------------
 * Blackhole victims address their probes to the attacker board's STA MAC. That
 * MAC used to exist only as the compile-time constant BLACKHOLE_ATTACKER_MAC in
 * mesh_config.h, which had two costs:
 *
 *  1. CHANGING THE ATTACKER MEANT RE-FLASHING EVERY VICTIM. The CTTHES2 panel
 *     (12:45-16:00) asked for variation between runs, specifically naming
 *     "different position of the attackers". With a compiled-in MAC, every
 *     attacker position costs a full re-flash of the whole victim fleet, which
 *     is what made that request unaffordable and left r1-r3 differing only in
 *     RF noise.
 *
 *  2. IT FAILED SILENTLY. A stale value means every probe is addressed to a
 *     board that is not in the mesh: the root logs ZERO arrivals in every
 *     phase, arrivals.csv comes out header-only, and BOTH primary features (PDR
 *     and ForwardingRatio) are 100% NaN -- while every board still looks
 *     perfectly healthy and probes_count climbs normally. That cost a full run
 *     on 2026-09-15 and again on 2026-09-16.
 *
 * RESOLUTION ORDER
 *   1. NVS namespace "nis16", key "bh_mac" (6-byte blob)  -- set over serial
 *   2. BLACKHOLE_ATTACKER_MAC from mesh_config.h          -- compiled fallback
 *
 * The fallback is deliberate: a board that has never been told anything behaves
 * exactly as it did before this module existed, so nothing breaks if a victim
 * is flashed and deployed without the wizard touching it.
 *
 * Set it over the SAME USB link already used to flash and export:
 *   SET_ATTACKER_MAC=aa:bb:cc:dd:ee:ff  -> "ATTACKER_MAC_SET"
 *   GET_ATTACKER_MAC                    -> "ATTACKER_MAC:aa:bb:cc:dd:ee:ff (nvs|compiled)"
 *   CLEAR_ATTACKER_MAC                  -> "ATTACKER_MAC_CLEARED" (revert to compiled)
 *
 * Takes effect on the NEXT BOOT: the value is read once during app_main and the
 * probe destination is built from it, so a mid-run change cannot make a node
 * switch targets halfway through a phase.
 *
 * NIS16 -- CTTHES3 -- F2
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Where the effective attacker MAC came from. */
typedef enum {
    BH_TARGET_SRC_COMPILED = 0,  /**< BLACKHOLE_ATTACKER_MAC in mesh_config.h */
    BH_TARGET_SRC_NVS      = 1,  /**< set at runtime over serial              */
} bh_target_source_t;

/**
 * @brief Resolve the attacker MAC this board should target.
 *
 * Never fails: falls back to the compiled constant on any NVS error, so a
 * corrupt or absent NVS partition degrades to the old behaviour rather than
 * leaving a victim with no destination.
 *
 * @param out_mac  Receives the 6-byte STA MAC. Must not be NULL.
 * @return         Which source supplied it.
 */
bh_target_source_t blackhole_target_get(uint8_t out_mac[6]);

/**
 * @brief Persist an attacker MAC in NVS, overriding the compiled constant.
 *
 * @param mac  6-byte STA MAC. A broadcast or all-zero MAC is rejected: both
 *             would produce the exact silent-failure mode this module exists
 *             to prevent.
 * @return     ESP_OK, ESP_ERR_INVALID_ARG for a rejected MAC, or the NVS error.
 */
esp_err_t blackhole_target_set(const uint8_t mac[6]);

/** @brief Remove the NVS override so the compiled constant applies again. */
esp_err_t blackhole_target_clear(void);

/**
 * @brief Parse "aa:bb:cc:dd:ee:ff" (or "aabbccddeeff") into 6 bytes.
 * @return true on success; out_mac is untouched on failure.
 */
bool blackhole_target_parse(const char *text, uint8_t out_mac[6]);

/** @brief "nvs" or "compiled", for log lines and the serial reply. */
const char *blackhole_target_source_str(bh_target_source_t src);

#ifdef __cplusplus
}
#endif
