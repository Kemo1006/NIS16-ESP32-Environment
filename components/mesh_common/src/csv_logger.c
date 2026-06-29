/**
 * @file csv_logger.c
 * @brief SPIFFS-backed CSV telemetry logger implementation.
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

static FILE    *s_log_fp          = NULL;   /* telemetry file (all roles)   */
static FILE    *s_arrivals_fp     = NULL;   /* probe arrivals (root only)   */
static char     s_filepath[128]   = {0};    /* path of telemetry file       */
static char     s_arrivals_path[128] = {0}; /* path of arrivals file        */
static uint32_t s_row_count       = 0;     /* rows since last flush         */
static bool     s_mounted         = false;

/* UART port used for log export */
#define EXPORT_UART     UART_NUM_0
#define EXPORT_BUF_SIZE 512

/* ── CSV headers ─────────────────────────────────────────────────────────── */

static const char *TELEMETRY_HEADER =
    "timestamp_us,node_id,role,layer,parent_mac,"
    "rssi_dbm,retry_count,tx_count,probes_count,"
    "phase_id,gt_label\n";

static const char *PROBE_ARRIVAL_HEADER =
    "timestamp_us,node_id,role,layer,parent_mac,"
    "rssi_dbm,retry_count,tx_count,probes_received,"
    "phase_id,gt_label,src_mac,seq_num,latency_us\n";

/* ── Forward declarations ────────────────────────────────────────────────── */
static void serial_export_task(void *arg);

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Initialisation
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_init(const char *node_id, const char *run_id,
                           csv_logger_role_t role)
{
    esp_err_t ret;

    /* ── 1. Mount SPIFFS (once) ──────────────────────────────────────────── */
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

   /* ── 2. Open telemetry file ──────────────────────────────────────────── */
    snprintf(s_filepath, sizeof(s_filepath),
             "%s/telem.csv", FS_MOUNT_POINT);
    ESP_LOGI(TAG, "Telemetry file: %s", s_filepath);

    /* Use "a+" mode - creates if doesn't exist, appends if it does */
    s_log_fp = fopen(s_filepath, "a+");
    if (!s_log_fp) {
        ESP_LOGE(TAG, "Failed to open telemetry file: %s", s_filepath);
        return ESP_FAIL;
    }

    /* Check if file is empty or missing header */
    fseek(s_log_fp, 0, SEEK_SET);
    char header_check[64] = {0};
    fgets(header_check, sizeof(header_check), s_log_fp);
    if (strncmp(header_check, "timestamp_us", 12) != 0) {
        /* File is empty or has wrong header - write the header */
        fseek(s_log_fp, 0, SEEK_SET);
        fputs(TELEMETRY_HEADER, s_log_fp);
    }
    fseek(s_log_fp, 0, SEEK_END);

    /* ── 3. Open arrivals file (root only) ───────────────────────────────── */
    /* ── 3. Open arrivals file (root only) ───────────────────────────────── */
    if (role == CSV_ROLE_ROOT) {
        snprintf(s_arrivals_path, sizeof(s_arrivals_path),
                 "%s/arrivals.csv", FS_MOUNT_POINT);
        ESP_LOGI(TAG, "Arrivals file:  %s", s_arrivals_path);

        s_arrivals_fp = fopen(s_arrivals_path, "a+");
        if (!s_arrivals_fp) {
            ESP_LOGE(TAG, "Failed to open arrivals file: %s", s_arrivals_path);
            fclose(s_log_fp);
            s_log_fp = NULL;
            return ESP_FAIL;
        }

        /* Check if file is empty or missing header */
        fseek(s_arrivals_fp, 0, SEEK_SET);
        char header_check[64] = {0};
        fgets(header_check, sizeof(header_check), s_arrivals_fp);
        if (strncmp(header_check, "timestamp_us", 12) != 0) {
            fseek(s_arrivals_fp, 0, SEEK_SET);
            fputs(PROBE_ARRIVAL_HEADER, s_arrivals_fp);
        }
        fseek(s_arrivals_fp, 0, SEEK_END);
    }

    s_row_count = 0;
    ESP_LOGI(TAG, "Logger ready. Role: %s",
             role == CSV_ROLE_ROOT ? "root" : "victim");

#if CSV_EXPORT_ON_INIT
    esp_err_t rc = csv_logger_start_export_task();
    if (rc == ESP_OK) {
        ESP_LOGI(TAG, "CSV export task started on init (debug).");
    } else {
        ESP_LOGW(TAG, "CSV export task failed to start: %s", esp_err_to_name(rc));
    }
#endif

    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Append rows
 * ═══════════════════════════════════════════════════════════════════════════ */

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
        ESP_LOGE(TAG, "fprintf (telemetry) failed");
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
    int64_t     latency_us)
{
    if (!s_arrivals_fp) {
        ESP_LOGE(TAG, "append_probe_arrival called but arrivals file not open "
                      "(was csv_logger_init called with CSV_ROLE_ROOT?)");
        return ESP_ERR_INVALID_STATE;
    }

    char parent_str[18], src_str[18];
    snprintf(parent_str, sizeof(parent_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             parent_mac[0], parent_mac[1], parent_mac[2],
             parent_mac[3], parent_mac[4], parent_mac[5]);
    snprintf(src_str, sizeof(src_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             src_mac[0], src_mac[1], src_mac[2],
             src_mac[3], src_mac[4], src_mac[5]);

    int n = fprintf(s_arrivals_fp,
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

    /* Flush arrivals on the same cadence as telemetry. */
    if (s_row_count >= LOGGER_FLUSH_RECORDS) {
        fflush(s_arrivals_fp);
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
    if (s_arrivals_fp) fflush(s_arrivals_fp);
    s_row_count = 0;
    return ESP_OK;
}

esp_err_t csv_logger_close(void)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;

    fflush(s_log_fp);
    fclose(s_log_fp);
    s_log_fp = NULL;
    ESP_LOGI(TAG, "Telemetry file closed: %s", s_filepath);

    if (s_arrivals_fp) {
        fflush(s_arrivals_fp);
        fclose(s_arrivals_fp);
        s_arrivals_fp = NULL;
        ESP_LOGI(TAG, "Arrivals file closed: %s", s_arrivals_path);
    }

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

/* ── Serial export task ──────────────────────────────────────────────────── */

static void serial_export_task(void *arg)
{
    uart_driver_install(EXPORT_UART, 256, 0, 0, NULL, 0);
    
    ESP_LOGI(TAG, "Serial export task ready. Commands: "
                  "EXPORT_LOGS | EXPORT_ARRIVALS | DELETE_LOGS | LIST_FILES");

    char cmd_buf[32] = {0};
    int  cmd_idx     = 0;
    int  read_len    = 0;

    while (true) {
        uint8_t ch = 0;
        /* Use non-blocking read with shorter timeout */
        int len = uart_read_bytes(EXPORT_UART, &ch, 1, pdMS_TO_TICKS(50));
        if (len <= 0) {
            /* Wait a bit before trying again to avoid flooding */
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        if (ch == '\n' || ch == '\r') {
            cmd_buf[cmd_idx] = '\0';

            /* ── EXPORT_LOGS — stream telemetry CSV ───────────────────── */
            if (strcmp(cmd_buf, "EXPORT_LOGS") == 0) {
                ESP_LOGI(TAG, "EXPORT_LOGS — streaming %s", s_filepath);
                FILE *fp = fopen(s_filepath, "r");
                if (!fp) {
                    uart_write_bytes(EXPORT_UART, "ERROR:FILE_NOT_FOUND\n", 21);
                } else {
                    uart_write_bytes(EXPORT_UART, "READY_TO_SEND\n", 14);
                    char line[256];
                    while (fgets(line, sizeof(line), fp)) {
                        uart_write_bytes(EXPORT_UART, line, strlen(line));
                    }
                    fclose(fp);
                    uart_write_bytes(EXPORT_UART, "END_OF_FILE\n", 12);
                    ESP_LOGI(TAG, "Telemetry file streamed.");
                }

            /* ── EXPORT_ARRIVALS — stream arrivals CSV (root only) ────── */
            } else if (strcmp(cmd_buf, "EXPORT_ARRIVALS") == 0) {
                ESP_LOGI(TAG, "EXPORT_ARRIVALS — streaming %s", s_arrivals_path);
                if (s_arrivals_path[0] == '\0') {
                    uart_write_bytes(EXPORT_UART, "ERROR:NOT_ROOT_NODE\n", 20);
                } else {
                    FILE *fp = fopen(s_arrivals_path, "r");
                    if (!fp) {
                        uart_write_bytes(EXPORT_UART, "ERROR:FILE_NOT_FOUND\n", 21);
                    } else {
                        uart_write_bytes(EXPORT_UART, "READY_TO_SEND\n", 14);
                        char line[256];
                        while (fgets(line, sizeof(line), fp)) {
                            uart_write_bytes(EXPORT_UART, line, strlen(line));
                        }
                        fclose(fp);
                        uart_write_bytes(EXPORT_UART, "END_OF_FILE\n", 12);
                        ESP_LOGI(TAG, "Arrivals file streamed.");
                    }
                }

            /* ── DELETE_LOGS — erase both files ──────────────────────── */
            } else if (strcmp(cmd_buf, "DELETE_LOGS") == 0) {
                bool ok = true;
                if (remove(s_filepath) != 0) {
                    ESP_LOGE(TAG, "Failed to delete %s", s_filepath);
                    ok = false;
                }
                if (s_arrivals_path[0] != '\0' && remove(s_arrivals_path) != 0) {
                    ESP_LOGE(TAG, "Failed to delete %s", s_arrivals_path);
                    ok = false;
                }
                if (ok) {
                    uart_write_bytes(EXPORT_UART, "LOGS_DELETED\n", 13);
                    ESP_LOGI(TAG, "Log files deleted.");
                } else {
                    uart_write_bytes(EXPORT_UART, "ERROR:DELETE_FAILED\n", 20);
                }

            /* ── LIST_FILES — print both file paths ──────────────────── */
            } else if (strcmp(cmd_buf, "LIST_FILES") == 0) {
                char out[160];
                snprintf(out, sizeof(out), "FILE:%s\n", s_filepath);
                uart_write_bytes(EXPORT_UART, out, strlen(out));
                if (s_arrivals_path[0] != '\0') {
                    snprintf(out, sizeof(out), "FILE:%s\n", s_arrivals_path);
                    uart_write_bytes(EXPORT_UART, out, strlen(out));
                }
                uart_write_bytes(EXPORT_UART, "END_LIST\n", 9);
            }

            cmd_idx = 0;
            memset(cmd_buf, 0, sizeof(cmd_buf));

        } else if (cmd_idx < (int)sizeof(cmd_buf) - 1) {
            cmd_buf[cmd_idx++] = (char)ch;
        }
    }
}