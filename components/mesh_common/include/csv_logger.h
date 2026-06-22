/**
 * @file csv_logger.h
 * @brief LittleFS-backed CSV telemetry logger — common to all node roles.
 *
 * Rows are appended in CSV format to a file on the ESP32's onboard flash.
 * Writes are buffered (LOGGER_BUF_SIZE bytes) and flushed every
 * LOGGER_FLUSH_RECORDS rows to balance write latency against power-loss risk.
 *
 * File naming: <FS_MOUNT_POINT>/<node_id>_<run_id>.csv
 *
 * A serial command interface (EXPORT_LOGS / DELETE_LOGS) lets a laptop pull
 * the CSV over USB after each experimental run.
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

/* ── Initialisation ──────────────────────────────────────────────────────── */

/**
 * @brief Mount LittleFS and open (or create) the log file for this run.
 *
 * @param node_id  Null-terminated node identifier string (e.g. "NODE_AABBCC").
 * @param run_id   Null-terminated run identifier string (e.g. "RUN_20260606_143000").
 * @return         ESP_OK on success; ESP_ERR_NO_MEM or ESP_FAIL on error.
 *
 * Writes the CSV header row as the first line of the file.
 */
typedef enum {
    CSV_ROLE_VICTIM = 0,   /* 11-column telemetry rows only        */
    CSV_ROLE_ROOT   = 1,   /* opens two files: telemetry + arrivals */
} csv_logger_role_t;

esp_err_t csv_logger_init(const char *node_id, const char *run_id,
                           csv_logger_role_t role);

/* ── Victim / Common telemetry row ──────────────────────────────────────── */

/**
 * @brief Append one cross-layer telemetry row (victim / root role).
 *
 * Columns (matching thesis Table 4.4 / 4.5 / 4.9 schema):
 *   timestamp_us, node_id, role, layer, parent_mac,
 *   rssi_dbm, retry_count, tx_count, probes_sent_or_received,
 *   phase_id, gt_label
 *
 * For the root node, @p probes_count is the cumulative probes received.
 * For victim nodes, @p probes_count is the cumulative probes sent.
 *
 * @return ESP_OK on success.
 */
esp_err_t csv_logger_append_telemetry(
    int64_t   timestamp_us,
    const char *node_id,
    const char *role_str,       /**< "root" | "victim" */
    int        layer,
    uint8_t    parent_mac[6],
    int        rssi_dbm,
    uint32_t   retry_count,
    uint32_t   tx_count,
    uint32_t   probes_count,
    uint8_t    phase_id,
    uint8_t    gt_label
);

/* ── Root probe-arrival row (extra columns for latency / src) ─────────────── */

/**
 * @brief Append a probe-arrival record on the root node.
 *
 * Extra columns: src_mac, seq_num, latency_us (round-trip from victim to root).
 *
 * @return ESP_OK on success.
 */
esp_err_t csv_logger_append_probe_arrival(
    int64_t   timestamp_us,
    const char *node_id,
    int        layer,
    uint8_t    parent_mac[6],
    int        rssi_dbm,
    uint32_t   retry_count,
    uint32_t   tx_count,
    uint32_t   probes_received,
    uint8_t    phase_id,
    uint8_t    gt_label,
    uint8_t    src_mac[6],
    uint32_t   seq_num,
    int64_t    latency_us
);

/* ── Flush / close ───────────────────────────────────────────────────────── */

/**
 * @brief Force an immediate flush of the write buffer to flash.
 *        Call before initiating log extraction.
 */
esp_err_t csv_logger_flush(void);

/**
 * @brief Flush and close the current log file.
 *        After this call, csv_logger_init() must be called again to log.
 */
esp_err_t csv_logger_close(void);

/* ── Serial export (called from the serial-export task) ─────────────────── */

/**
 * @brief Start the serial-export FreeRTOS task.
 *
 * The task waits on UART for the command "EXPORT_LOGS\n", responds with
 * "READY_TO_SEND\n", streams the CSV file content, and waits for
 * "DELETE_LOGS\n" before erasing the file.
 *
 * Should be started after csv_logger_close() at the end of an experiment.
 *
 * @return ESP_OK on success.
 */
esp_err_t csv_logger_start_export_task(void);

/**
 * @brief Return the full path of the current log file.
 *        Useful for logging the filename at experiment start.
 */
const char *csv_logger_get_filepath(void);

#ifdef __cplusplus
}
#endif
