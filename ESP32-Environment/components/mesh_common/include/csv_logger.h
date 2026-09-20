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
 * A serial command interface (EXPORT_LOGS / DELETE_LOGS / ARCHIVE_SD /
 * LIST_FILES) lets a laptop pull CSVs over USB after each experimental run.
 *
 * SD MIRROR (best-effort): when sd_status_run_boot_check() succeeded, every row
 * is ALSO written to /sdcard/<attack>/<topology>/<location>/ as
 *   <role>_<node_id>_r<run>_b<boot>_telem.csv    (and _arrivals.csv on the root)
 * so a node deployed on a powerbank with no laptop can be recovered by pulling
 * the card (tools/import_sdcard.py files it into exports/). One file per run,
 * never appended. SPIFFS stays the primary path and is unaffected if the card
 * is absent or fails mid-run.
 *
 * The name carries TWO counters because they answer different questions:
 *   r<run>   gapless count of real, data-logging runs by this node in this
 *            folder (r1, r2, r3...) — read this one for "which run is this".
 *   b<boot>  the raw boot counter from sd_status.c, which also ticks for boots
 *            that never log anything (an esptool reset around a flash, a MAC
 *            read, a SET_LOCATION pass). It therefore SKIPS — and the size of
 *            each gap tells you how many resets happened in between.
 *
 * Each mirror file is opened LAZILY, on the first row this boot actually has
 * to log — not at init — so a boot that resets before logging anything (an
 * esptool connect/reset cycle, a MAC read, a SET_LOCATION pass) leaves no
 * file at all rather than a permanent 0-byte one. csv_logger_init() also
 * sweeps and removes any 0-byte mirror CSVs left over from before this fix.
 *
 * Alongside the mirrors, every run appends to a per-folder manifest,
 * <attack>/<topology>/<location>/runs.csv (boot,run,node_id,role,rows,
 * uptime_s,event), so a human or tools/import_sdcard.py can tell which run
 * is which and whether it ended cleanly. A "start" row is appended when the
 * telemetry mirror opens; a "clean" row (with the final row count) is
 * appended from csv_logger_close(). A run with a "start" and no matching
 * "clean" was aborted (power loss, a killed run) — the manifest is
 * append-only and never rewritten, so that gap IS the record.
 *
 * runs.csv is also the source of r<run>: the next run's number is the count
 * of distinct boots already recorded there for this node, plus one. There is
 * no separate counter file, so the number cannot drift from the log it
 * describes.
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
 * @brief Append one 14-column cross-layer telemetry row (schema v2).
 *
 * Columns:
 *   timestamp_us, node_id, role, layer, parent_mac,
 *   rssi_dbm, retry_count, tx_count, probes_count, phase_id, gt_label,
 *   recv_count, forward_count, drop_count
 *
 * The first 11 are schema v1, unchanged and in the same positions, so any
 * positional reader of a v1 capture still works. tools/validate_integrity.py
 * accepts both widths.
 *
 * ── F3: why the last three exist ─────────────────────────────────────────
 * The first eight columns mean DIFFERENT THINGS depending on which board wrote
 * the row (see docs/DATA-DICTIONARY.md for the full table). The damaging case
 * was retry_count: on a victim it counts failed esp_mesh_send() calls, but on
 * the blackhole attacker it was overloaded to count the packets that node
 * deliberately DROPPED. That made the derived RetryRate feature go 0.0033 ->
 * 0.9991 on the attacker while victims went 0.0008 -> 0.0000 — i.e. the one
 * feature that "detected" the attack was the attack's own control variable
 * wearing a MAC-layer name. It is the CTTHES2 panel's single-feature-
 * decidability objection (2:40-4:50), in the schema.
 *
 * These three mean the SAME THING on every role, always:
 *   recv_count    — frames received from another node FOR RELAY
 *                   (not frames this node originated)
 *   forward_count — frames passed on toward their destination
 *   drop_count    — frames received for relay and NOT passed on
 *
 * With them present, retry_count reverts to one meaning everywhere (send
 * failures), and ForwardingRatio becomes forward_count/recv_count for any node
 * that relays.
 *
 * ⚠️ A node that does not relay reports 0/0/0, which is the honest answer and
 * NOT the same as "forwarded nothing". Honest victims send with
 * MESH_DATA_TODS, so the mesh stack relays below the application layer and
 * their app code never sees transit traffic. Getting a populated
 * ForwardingRatio distribution across honest nodes needs Option 1 of
 * Plan/THESIS3-MEMBER-HOWTO.md §1 C7 (every node relaying explicitly to its
 * parent), which changes the traffic model. F3 alone removes the OVERLOAD; it
 * does not by itself remove the role gate.
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
    uint8_t     gt_label,
    uint32_t    recv_count,
    uint32_t    forward_count,
    uint32_t    drop_count
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

/** Flush and close all open files, and unmount the SD card if it was mirroring.
 *  The card is safe to remove once this returns. csv_logger_init() must be
 *  called again to log. */
esp_err_t csv_logger_close(void);

/* ── Serial export ───────────────────────────────────────────────────────── */

/**
 * @brief Start the serial-export FreeRTOS task.
 *
 * Waits on UART0 for:
 *   EXPORT_LOGS    — streams the telemetry CSV
 *   EXPORT_ARRIVALS — streams the arrivals CSV (root only)
 *   DELETE_LOGS    — deletes both files
 *   ARCHIVE_SD     — archives this boot's SD mirror CSVs (see csv_logger_archive_sd_now())
 *   LIST_FILES     — lists both file paths
 *   DELETE_SD_PATH=<attack>/<topology>/<location> — PERMANENTLY deletes that
 *                    SD card folder and everything under it
 */
esp_err_t csv_logger_start_export_task(void);

/** Return the path of the telemetry log file. */
const char *csv_logger_get_filepath(void);

/**
 * @brief Archive (never delete) this boot's own SD-mirror CSVs out of their
 *        run folder and into <run_dir>/_archive/, on demand.
 *
 * Same folder-tidying policy as the automatic sweep csv_logger_init() already
 * runs at the START of the NEXT boot (sd_archive_prior_run_mirrors()) — this
 * just lets the host trigger it right after confirming a good USB download,
 * instead of waiting for the board's next power-cycle. Safe to call even
 * though csv_logger_close() has already unmounted the card: it remounts just
 * for the move and unmounts again afterward.
 *
 * @return ESP_ERR_NOT_FOUND if this boot never had an SD run folder (no
 *         card / bad location.txt this boot); ESP_FAIL if the card could not
 *         be remounted; ESP_OK otherwise (including "nothing to archive").
 */
esp_err_t csv_logger_archive_sd_now(void);

/**
 * @brief True once a serial export has begun on this board.
 *
 * Anything that writes to the console with printf() MUST check this and stay
 * silent when it returns true. esp_log_level_set() mutes ESP_LOGx during a
 * transfer but does NOT gate printf, so an unguarded printf can splice itself
 * into the framed CSV and reproduce I-001 ("never saw END_OF_FILE").
 *
 * Latched: never returns false again until reboot. See csv_logger.c.
 */
bool csv_logger_export_in_progress(void);

#ifdef __cplusplus
}
#endif
