/*
 * sim.h — host stand-ins for the ESP-IDF / FreeRTOS calls wormhole_victim.c
 * makes, so the REAL firmware file compiles and runs on a PC (gcc).
 *
 * board.c includes this, then wormhole_victim.c itself, ONCE PER SIMULATED
 * BOARD (it is compiled twice: board_b1.o, board_b2.o). Everything here is
 * `static`, so each board gets its own copy: its own MAC, layer and UART
 * buffers - exactly like two physical boards. Only the simulated clock, the
 * root's phase and "terminated" are shared (extern, defined in test.c).
 *
 * Only what the firmware file needs is provided; the real mesh_config.h,
 * mesh_messages.h and probe_relay.h are used unchanged.
 */
#ifndef WH_SIM_H
#define WH_SIM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* ── shared simulated world (defined in test.c) ──────────────────────────── */
extern int64_t g_now_us;        /* esp_timer_get_time()                      */
extern uint8_t g_phase;         /* what the root has announced               */
extern bool    g_terminated;
extern bool    g_verbose;       /* print the firmware's log lines            */

#ifndef BOARD_NAME
#define BOARD_NAME "board"
#endif

/* ── esp_err / logging ───────────────────────────────────────────────────── */
typedef int esp_err_t;
#define ESP_OK                    0
#define ESP_FAIL                 -1
#define ESP_ERR_INVALID_STATE     0x103
#define ESP_ERROR_CHECK(x)        do { (void)(x); } while (0)
static inline const char *esp_err_to_name(esp_err_t e) { return e == ESP_OK ? "ESP_OK" : "ERR"; }

#define WH_LOG(lvl, tag, fmt, ...) \
    do { (void)(tag); if (g_verbose) printf("    [%s %s] " fmt "\n", BOARD_NAME, lvl, ##__VA_ARGS__); } while (0)
#define ESP_LOGI(tag, fmt, ...) WH_LOG("I", tag, fmt, ##__VA_ARGS__)
#define ESP_LOGW(tag, fmt, ...) WH_LOG("W", tag, fmt, ##__VA_ARGS__)
#define ESP_LOGE(tag, fmt, ...) WH_LOG("E", tag, fmt, ##__VA_ARGS__)
#define ESP_LOGD(tag, fmt, ...) do { } while (0)

#define MACSTR "%02x:%02x:%02x:%02x:%02x:%02x"
#define MAC2STR(a) (a)[0], (a)[1], (a)[2], (a)[3], (a)[4], (a)[5]
#define ESP_MAC_WIFI_STA 0

/* ── FreeRTOS ────────────────────────────────────────────────────────────── */
typedef uint32_t TickType_t;
typedef int      BaseType_t;
typedef void    *QueueHandle_t;
typedef void    *TaskHandle_t;
#define pdTRUE  1
#define pdFALSE 0
#define portMAX_DELAY 0xFFFFFFFFu
#define pdMS_TO_TICKS(ms) ((TickType_t)(ms))
static int s_dummy_queue;
static inline QueueHandle_t xQueueCreate(int n, int sz) { (void)n; (void)sz; return &s_dummy_queue; }
static int s_queued;   /* counts xQueueSend calls (re-inject path) */
static inline BaseType_t xQueueSend(QueueHandle_t q, const void *p, TickType_t t)
{ (void)q; (void)p; (void)t; s_queued++; return pdTRUE; }
static inline BaseType_t xQueueReceive(QueueHandle_t q, void *p, TickType_t t)
{ (void)q; (void)p; (void)t; return pdFALSE; }
static inline BaseType_t xTaskCreate(void (*fn)(void *), const char *n, uint32_t st,
                                     void *a, int pr, TaskHandle_t *h)
{ (void)fn; (void)n; (void)st; (void)a; (void)pr; (void)h; return pdTRUE; }
static inline void vTaskDelay(TickType_t t) { (void)t; }
static inline void vTaskDelete(void *t) { (void)t; }
static inline TickType_t xTaskGetTickCount(void) { return 0; }
static inline void xTaskDelayUntil(TickType_t *p, TickType_t t) { (void)p; (void)t; }

/* ── timer / mac / wifi ──────────────────────────────────────────────────── */
static inline int64_t esp_timer_get_time(void) { return g_now_us; }
static uint8_t s_sim_mac[6];
static inline esp_err_t esp_read_mac(uint8_t *m, int type) { (void)type; memcpy(m, s_sim_mac, 6); return ESP_OK; }
static inline esp_err_t esp_wifi_sta_get_rssi(int *r) { *r = -60; return ESP_OK; }

/* Same polynomial as the ESP32 ROM's little-endian CRC32. Both ends use it,
 * so only consistency matters here. */
static inline uint32_t esp_rom_crc32_le(uint32_t crc, const uint8_t *buf, uint32_t len)
{
    crc = ~crc;
    while (len--) {
        crc ^= *buf++;
        for (int k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

/* ── UART: per-board TX outbox + RX inbox, moved across by test.c ────────── */
typedef struct { int baud_rate, data_bits, parity, stop_bits, flow_ctrl, source_clk; } uart_config_t;
#define UART_DATA_8_BITS 3
#define UART_PARITY_DISABLE 0
#define UART_STOP_BITS_1 1
#define UART_HW_FLOWCTRL_DISABLE 0
#define UART_SCLK_DEFAULT 0
#define UART_PIN_NO_CHANGE -1
#define SIM_UART_CAP 8192
static uint8_t s_tx[SIM_UART_CAP]; static size_t s_tx_len;
static uint8_t s_rx[SIM_UART_CAP]; static size_t s_rx_len, s_rx_pos;
static inline esp_err_t uart_driver_install(int p, int a, int b, int c, void *d, int e)
{ (void)p; (void)a; (void)b; (void)c; (void)d; (void)e; return ESP_OK; }
static inline esp_err_t uart_param_config(int p, const uart_config_t *c) { (void)p; (void)c; return ESP_OK; }
static inline esp_err_t uart_set_pin(int p, int a, int b, int c, int d)
{ (void)p; (void)a; (void)b; (void)c; (void)d; return ESP_OK; }
static inline int uart_write_bytes(int port, const void *src, size_t n)
{
    (void)port;
    if (s_tx_len + n > SIM_UART_CAP) return -1;
    memcpy(s_tx + s_tx_len, src, n); s_tx_len += n; return (int)n;
}
static inline int uart_read_bytes(int port, void *dst, uint32_t n, TickType_t t)
{
    (void)port; (void)t;
    size_t avail = s_rx_len - s_rx_pos; if (n > avail) n = (uint32_t)avail;
    memcpy(dst, s_rx + s_rx_pos, n); s_rx_pos += n; return (int)n;
}

/* ── project modules the file calls (behaviour irrelevant to the role logic) */
typedef enum { MESH_ROLE_VICTIM = 0, MESH_ROLE_ROOT = 1, MESH_ROLE_ATCK_BH = 2,
               MESH_ROLE_ATCK_WA = 3, MESH_ROLE_ATCK_WB = 4 } mesh_node_role_t;
static int s_sim_layer = -1;
static inline esp_err_t mesh_setup_init(mesh_node_role_t r) { (void)r; return ESP_OK; }
static inline void mesh_setup_get_node_id(char *b) { strcpy(b, "NODE_SIM"); }
static inline int  mesh_setup_get_layer(void) { return s_sim_layer; }
static inline bool mesh_setup_get_parent_mac(uint8_t m[6]) { memset(m, 0, 6); return true; }
static inline esp_err_t heartbeat_start(void) { return ESP_OK; }

static inline esp_err_t phase_listener_start(void) { return ESP_OK; }
static inline void phase_listener_set_data_cb(void *cb) { (void)cb; }
static inline uint8_t phase_listener_get_phase_id(void) { return g_phase; }
static inline uint8_t phase_listener_get_label(void) { return 0; }
static inline bool phase_listener_is_terminated(void) { return g_terminated; }
static inline void phase_listener_wait_for_terminate(void) { }

typedef enum { CSV_ROLE_VICTIM = 0, CSV_ROLE_ROOT = 1 } csv_role_t;
static inline esp_err_t csv_logger_init(const char *a, const char *b, csv_role_t r)
{ (void)a; (void)b; (void)r; return ESP_OK; }
static inline const char *csv_logger_get_filepath(void) { return "sim.csv"; }
static inline void csv_logger_append_telemetry(int64_t ts, const char *id, const char *role,
        int layer, const uint8_t *pmac, int rssi, uint32_t a, uint32_t b, uint32_t c,
        uint8_t ph, uint8_t lab, uint32_t d, uint32_t e, uint32_t f)
{ (void)ts; (void)id; (void)role; (void)layer; (void)pmac; (void)rssi; (void)a; (void)b;
  (void)c; (void)ph; (void)lab; (void)d; (void)e; (void)f; }
static inline void csv_logger_flush(void) { }
static inline void csv_logger_close(void) { }
static inline void csv_logger_start_export_task(void) { }

typedef enum { SD_STATUS_OK = 0, SD_STATUS_FAIL = 1 } sd_status_result_t;
static inline sd_status_result_t sd_status_run_boot_check(void) { return SD_STATUS_OK; }
static inline const char *sd_status_report_path(void) { return "/sd"; }
static inline const char *sd_status_result_str(sd_status_result_t r) { (void)r; return "OK"; }

typedef uint32_t nvs_handle_t;
#define NVS_READWRITE 1
static inline esp_err_t nvs_open(const char *n, int m, nvs_handle_t *h) { (void)n; (void)m; *h = 1; return ESP_OK; }
static inline esp_err_t nvs_get_u32(nvs_handle_t h, const char *k, uint32_t *v) { (void)h; (void)k; *v = 0; return ESP_OK; }
static inline esp_err_t nvs_set_u32(nvs_handle_t h, const char *k, uint32_t v) { (void)h; (void)k; (void)v; return ESP_OK; }
static inline esp_err_t nvs_commit(nvs_handle_t h) { (void)h; return ESP_OK; }
static inline void nvs_close(nvs_handle_t h) { (void)h; }

#endif
