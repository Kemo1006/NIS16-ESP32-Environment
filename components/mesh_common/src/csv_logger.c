/**
 * @file csv_logger.c
 * @brief LittleFS-backed CSV telemetry logger implementation.
 *
 * NIS16 — CTTHES2 Milestone 1 — Common Module
 */

#include "csv_logger.h"
#include "mesh_config.h"

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_log.h"
#include "esp_spiffs.h"
#include "driver/uart.h"
#include "esp_timer.h"

/* ── Module-private state ────────────────────────────────────────────────── */

static const char *TAG = "CSV_LOGGER";

static FILE  *s_log_fp        = NULL;
static char   s_filepath[128] = {0};
static uint32_t s_row_count   = 0;   /* rows written since last flush */
static bool   s_mounted       = false;

/* UART port used for log export */
#define EXPORT_UART     UART_NUM_0
#define EXPORT_BUF_SIZE 512

/* ── CSV header strings ──────────────────────────────────────────────────── */

/* Extra header for root probe-arrival rows */
static const char *PROBE_ARRIVAL_HEADER =
    "timestamp_us,node_id,role,layer,parent_mac,"
    "rssi_dbm,retry_count,tx_count,probes_received,"
    "phase_id,gt_label,src_mac,seq_num,latency_us\n";

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void serial_export_task(void *arg);

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Initialisation
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_init(const char *node_id, const char *run_id)
{
    esp_err_t ret;

    /* ── 1. Mount LittleFS ───────────────────────────────────────────────── */
    if (!s_mounted) {
        esp_vfs_spiffs_conf_t spiffs_cfg = {
            .base_path              = FS_MOUNT_POINT,
            .partition_label        = FS_PARTITION_LABEL,
            .max_files              = 5,
            .format_if_mount_failed = true,
        };
        ret = esp_vfs_spiffs_register(&spiffs_cfg);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "SPIFFS mount failed: %s", esp_err_to_name(ret));
            return ret;
        }
        s_mounted = true;

        size_t total = 0, used = 0;
        esp_spiffs_info(FS_PARTITION_LABEL, &total, &used);
        ESP_LOGI(TAG, "SPIFFS mounted. Total: %u KB  Used: %u KB",
                 (unsigned)(total / 1024), (unsigned)(used / 1024));
    }

    /* ── 2. Build file path ──────────────────────────────────────────────── */
    snprintf(s_filepath, sizeof(s_filepath),
             "%s/%s_%s.csv", FS_MOUNT_POINT, node_id, run_id);
    ESP_LOGI(TAG, "Log file: %s", s_filepath);

    /* ── 3. Open file (create or append) ─────────────────────────────────── */
    bool file_exists = false;
    {
        struct stat st;
        file_exists = (stat(s_filepath, &st) == 0);
    }

    s_log_fp = fopen(s_filepath, "a");
    if (!s_log_fp) {
        ESP_LOGE(TAG, "Failed to open log file: %s", s_filepath);
        return ESP_FAIL;
    }

    /* ── 4. Write header only if the file is brand-new ───────────────────── */
    if (!file_exists) {
        /*
         * Write the broader probe-arrival header — it is a superset of the
         * telemetry header.  The root uses this file for both telemetry rows
         * and probe-arrival rows; victim nodes only write telemetry rows (the
         * extra columns just remain absent from those rows).
         *
         * For strict schema separation, callers may pass a role flag; for
         * Milestone 1 the single combined header is sufficient.
         */
        fputs(PROBE_ARRIVAL_HEADER, s_log_fp);
    }

    s_row_count = 0;
    ESP_LOGI(TAG, "Logger ready (file_existed=%d).", (int)file_exists);

#if CSV_EXPORT_ON_INIT
    /* Debug helper: start serial export task immediately so host tools can
     * request logs over USB without waiting for experiment end. Enable only
     * in debug builds (see mesh_config.h). */
    esp_err_t rc = csv_logger_start_export_task();
    if (rc == ESP_OK) {
        ESP_LOGI(TAG, "CSV export task started on init (debug).");
    } else {
        ESP_LOGW(TAG, "CSV export task failed to start on init: %s", esp_err_to_name(rc));
    }
#endif

    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Append rows
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_append_telemetry(
    int64_t    timestamp_us,
    const char *node_id,
    const char *role_str,
    int         layer,
    uint8_t     parent_mac[6],
    int         rssi_dbm,
    uint32_t    retry_count,
    uint32_t    tx_count,
    uint32_t    probes_count,
    uint8_t     phase_id,
    uint8_t     gt_label)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;

    char parent_str[18];
    snprintf(parent_str, sizeof(parent_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             parent_mac[0], parent_mac[1], parent_mac[2],
             parent_mac[3], parent_mac[4], parent_mac[5]);

    int n = fprintf(s_log_fp,
        "%lld,%s,%s,%d,%s,%d,%lu,%lu,%lu,%u,%u\n",
        (long long)timestamp_us,
        node_id,
        role_str,
        layer,
        parent_str,
        rssi_dbm,
        (unsigned long)retry_count,
        (unsigned long)tx_count,
        (unsigned long)probes_count,
        (unsigned)phase_id,
        (unsigned)gt_label
    );

    if (n < 0) {
        ESP_LOGE(TAG, "fprintf failed");
        return ESP_FAIL;
    }

    s_row_count++;
    if (s_row_count >= LOGGER_FLUSH_RECORDS) {
        fflush(s_log_fp);
        s_row_count = 0;
    }

    return ESP_OK;
}

esp_err_t csv_logger_append_probe_arrival(
    int64_t    timestamp_us,
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
    int64_t     latency_us)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;

    char parent_str[18], src_str[18];
    snprintf(parent_str, sizeof(parent_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             parent_mac[0], parent_mac[1], parent_mac[2],
             parent_mac[3], parent_mac[4], parent_mac[5]);
    snprintf(src_str, sizeof(src_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             src_mac[0], src_mac[1], src_mac[2],
             src_mac[3], src_mac[4], src_mac[5]);

    int n = fprintf(s_log_fp,
        "%lld,%s,root,%d,%s,%d,%lu,%lu,%lu,%u,%u,%s,%lu,%lld\n",
        (long long)timestamp_us,
        node_id,
        layer,
        parent_str,
        rssi_dbm,
        (unsigned long)retry_count,
        (unsigned long)tx_count,
        (unsigned long)probes_received,
        (unsigned)phase_id,
        (unsigned)gt_label,
        src_str,
        (unsigned long)seq_num,
        (long long)latency_us
    );

    if (n < 0) {
        ESP_LOGE(TAG, "fprintf (probe arrival) failed");
        return ESP_FAIL;
    }

    s_row_count++;
    if (s_row_count >= LOGGER_FLUSH_RECORDS) {
        fflush(s_log_fp);
        s_row_count = 0;
    }

    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Flush / close
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_flush(void)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;
    fflush(s_log_fp);
    s_row_count = 0;
    return ESP_OK;
}

esp_err_t csv_logger_close(void)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;
    fflush(s_log_fp);
    fclose(s_log_fp);
    s_log_fp = NULL;
    ESP_LOGI(TAG, "Log file closed: %s", s_filepath);
    return ESP_OK;
}

const char *csv_logger_get_filepath(void)
{
    return s_filepath;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Serial export task
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_start_export_task(void)
{
    BaseType_t rc = xTaskCreate(
        serial_export_task,
        "csv_export",
        STACK_SERIAL_EXPORT,
        NULL,
        TASK_PRIO_SERIAL_EXPORT,
        NULL
    );
    if (rc != pdPASS) {
        ESP_LOGE(TAG, "Failed to create serial export task");
        return ESP_FAIL;
    }
    return ESP_OK;
}

/* ── Serial export task implementation ───────────────────────────────────── */

static void serial_export_task(void *arg)
{
    ESP_LOGI(TAG, "Serial export task waiting for EXPORT_LOGS command...");

    /* Re-use UART0 (USB-Serial) which is already initialised by IDF. */
    char cmd_buf[32] = {0};
    int  cmd_idx     = 0;

    while (true) {
        uint8_t ch = 0;
        int len = uart_read_bytes(EXPORT_UART, &ch, 1,
                                  pdMS_TO_TICKS(100));
        if (len <= 0) continue;

        if (ch == '\n' || ch == '\r') {
            cmd_buf[cmd_idx] = '\0';

            /* ── Command: EXPORT_LOGS ─────────────────────────────────── */
            if (strcmp(cmd_buf, "EXPORT_LOGS") == 0) {
                ESP_LOGI(TAG, "EXPORT_LOGS received — streaming %s", s_filepath);

                FILE *fp = fopen(s_filepath, "r");
                if (!fp) {
                    uart_write_bytes(EXPORT_UART,
                                     "ERROR:FILE_NOT_FOUND\n", 21);
                } else {
                    uart_write_bytes(EXPORT_UART, "READY_TO_SEND\n", 14);

                    char line[256];
                    while (fgets(line, sizeof(line), fp)) {
                        uart_write_bytes(EXPORT_UART, line, strlen(line));
                    }
                    fclose(fp);
                    uart_write_bytes(EXPORT_UART, "END_OF_FILE\n", 12);
                    ESP_LOGI(TAG, "File streamed successfully.");
                }

            /* ── Command: DELETE_LOGS ────────────────────────────────── */
            } else if (strcmp(cmd_buf, "DELETE_LOGS") == 0) {
                if (remove(s_filepath) == 0) {
                    uart_write_bytes(EXPORT_UART, "LOGS_DELETED\n", 13);
                    ESP_LOGI(TAG, "Log file deleted.");
                } else {
                    uart_write_bytes(EXPORT_UART, "ERROR:DELETE_FAILED\n", 20);
                    ESP_LOGE(TAG, "Failed to delete log file.");
                }

            /* ── Command: LIST_FILES ─────────────────────────────────── */
            } else if (strcmp(cmd_buf, "LIST_FILES") == 0) {
                /* Convenience command: list all CSV files on the partition */
                char out[160];
                snprintf(out, sizeof(out), "FILE:%s\n", s_filepath);
                uart_write_bytes(EXPORT_UART, out, strlen(out));
                uart_write_bytes(EXPORT_UART, "END_LIST\n", 9);
            }

            cmd_idx = 0;
            memset(cmd_buf, 0, sizeof(cmd_buf));

        } else if (cmd_idx < (int)sizeof(cmd_buf) - 1) {
            cmd_buf[cmd_idx++] = (char)ch;
        }
    }
}