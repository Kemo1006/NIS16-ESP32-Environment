/**
 * @file csv_logger.h
 * @brief SPIFFS-backed CSV telemetry logger — common to all node roles.
 *
 * Victim nodes produce one file:
 *   <node_id>_<run_id>_telem.csv   (11 columns)
 *
 * Root node produces two files:
 *   <node_id>_<run_id>_telem.csv    (11 columns — periodic 1 Hz samples)
 *   <node_id>_<run_id>_arrivals.csv (14 columns — one row per probe received)
 *
 * Writes are buffered and flushed every LOGGER_FLUSH_RECORDS rows.
 * A serial command interface (EXPORT_LOGS / DELETE_LOGS / LIST_FILES) lets a
 * laptop pull CSVs over USB after each experimental run.
 *
 * NIS16 — CTTHES2 Milestone 1 — Common Module
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── Role tag ────────────────────────────────────────────────────────────── */

/**
 * @brief Controls which files and headers csv_logger_init() creates.
 *
 * CSV_ROLE_VICTIM — opens one telemetry file (11-column header).
 * CSV_ROLE_ROOT   — opens a telemetry file AND a probe-arrival file
 *                   (14-column header).
 */
typedef enum {
    CSV_ROLE_VICTIM = 0,
    CSV_ROLE_ROOT   = 1,
} csv_logger_role_t;

/* ── Initialisation ──────────────────────────────────────────────────────── */

/**
 * @brief Mount SPIFFS and open (or create) the log file(s) for this run.
 *
 * @param node_id  Null-terminated node identifier (e.g. "NODE_AABBCCDDEEFF").
 * @param run_id   Null-terminated run identifier   (e.g. "RUN_20260606_143000").
 * @param role     CSV_ROLE_VICTIM or CSV_ROLE_ROOT.
 * @return         ESP_OK on success; ESP_FAIL on any file or mount error.
 */
esp_err_t csv_logger_init(const char *node_id, const char *run_id,
                           csv_logger_role_t role);

/* ── Telemetry row (all roles) ───────────────────────────────────────────── */

/**
 * @brief Append one 11-column cross-layer telemetry row.
 *
 * Columns:
 *   timestamp_us, node_id, role, layer, parent_mac,
 *   rssi_dbm, retry_count, tx_count, probes_count, phase_id, gt_label
 *
 * probes_count = cumulative probes sent (victim) or received (root).
 */
esp_err_t csv_logger_append_telemetry(
    int64_t     timestamp_us,
    const char *node_id,
    const char *role_str,
    int         layer,
    uint8_t     parent_mac[6],
    int         rssi_dbm,
    uint32_t    retry_count,
    uint32_t    tx_count,
    uint32_t    probes_count,
    uint8_t     phase_id,
    uint8_t     gt_label
);

/* ── Probe-arrival row (root only) ───────────────────────────────────────── */

/**
 * @brief Append one 14-column probe-arrival row to the arrivals file.
 *
 * Only valid after csv_logger_init(..., CSV_ROLE_ROOT).
 * Returns ESP_ERR_INVALID_STATE if called on a victim node.
 *
 * Extra columns vs telemetry: src_mac, seq_num, latency_us.
 */
esp_err_t csv_logger_append_probe_arrival(
    int64_t     timestamp_us,
    const char *node_id,
    int         layer,
    uint8_t     parent_mac[6],
    int         rssi_dbm,
    uint32_t    retry_count,
    uint32_t    tx_count,
    uint32_t    probes_received,
    uint8_t     phase_id,
    uint8_t     gt_label,
    uint8_t     src_mac[6],
    uint32_t    seq_num,
    int64_t     latency_us
);

/* ── Flush / close ───────────────────────────────────────────────────────── */

/** Force an immediate flush of both open files. */
esp_err_t csv_logger_flush(void);

/** Flush and close all open files. csv_logger_init() must be called again to log. */
esp_err_t csv_logger_close(void);

/* ── Serial export ───────────────────────────────────────────────────────── */

/**
 * @brief Start the serial-export FreeRTOS task.
 *
 * Waits on UART0 for:
 *   EXPORT_LOGS    — streams the telemetry CSV
 *   EXPORT_ARRIVALS — streams the arrivals CSV (root only)
 *   DELETE_LOGS    — deletes both files
 *   LIST_FILES     — lists both file paths
 */
esp_err_t csv_logger_start_export_task(void);

/** Return the path of the telemetry log file. */
const char *csv_logger_get_filepath(void);

#ifdef __cplusplus
}
#endif
