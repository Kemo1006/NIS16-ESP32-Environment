/**
 * @file victim_main.c
 * @brief Victim node firmware — Milestone 1.
 *
 * Responsibilities:
 *  1. Initialise mesh, phase listener, and CSV logger.
 *  2. PROBE_GEN task: send probe_pkt_t packets to the root at PROBE_INTERVAL_MS.
 *     Each probe carries a monotonically increasing seq_num and a send timestamp
 *     so the root can compute one-way latency.
 *  3. TELEMETRY task: sample cross-layer metrics at 1 Hz and log to flash.
 *  4. After experiment ends: flush, close, start serial export task.
 *
 * Build target: victim_node/
 *
 * NIS16 — CTTHES2 Milestone 1
 */

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/atomic.h"

#include "esp_log.h"
#include "esp_mesh.h"
#include "esp_wifi.h"
#include "esp_timer.h"
#include "esp_mac.h"

#include "mesh_config.h"
#include "mesh_setup.h"
#include "phase_listener.h"
#include "csv_logger.h"

/* ── Module tag ──────────────────────────────────────────────────────────── */
static const char *TAG = "VICTIM_MAIN";

/* ── Probe wire format (must match root_main.c exactly) ──────────────────── */
#define PROBE_MAGIC     0x50524F42U   /* "PROB" */

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t seq_num;
    int64_t  send_ts_us;
    uint8_t  src_mac[6];
} probe_pkt_t;

/* ── Shared state ─────────────────────────────────────────────────────────── */
static char     s_node_id[NODE_ID_LEN] = {0};
static char     s_run_id[RUN_ID_LEN]   = {0};
static uint8_t  s_self_mac[6]          = {0};

/* Probe counter — written by probe_gen, read by telemetry task. */
static volatile uint32_t s_probes_sent = 0;

/* MAC-layer cumulative counters (monotonically increasing). */
static volatile uint32_t s_retry_count = 0;
static volatile uint32_t s_tx_count    = 0;

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void probe_gen_task(void *arg);
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */

void app_main(void)
{
    ESP_LOGI(TAG, "=== VICTIM NODE STARTING ===");

    /* ── 1. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_VICTIM));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);

    /* ── 2. Phase listener ───────────────────────────────────────────────── */
    ESP_ERROR_CHECK(phase_listener_start());

    /* ── 3. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 4. Start tasks ──────────────────────────────────────────────────── */
    xTaskCreate(probe_gen_task,  "probe_gen",  STACK_PROBE_GEN,
                NULL, TASK_PRIO_PROBE_GEN,  NULL);
    xTaskCreate(telemetry_task,  "telemetry",  STACK_TELEMETRY,
                NULL, TASK_PRIO_TELEMETRY,  NULL);

    /* ── 5. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 6. Finalise ─────────────────────────────────────────────────────── */
    ESP_LOGI(TAG, "Experiment complete. Total probes sent: %lu",
             (unsigned long)s_probes_sent);
    csv_logger_flush();
    csv_logger_close();

    ESP_LOGI(TAG, "Send 'EXPORT_LOGS' via serial to retrieve the CSV.");
    csv_logger_start_export_task();
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Probe generator task
 *
 * Sends a probe_pkt_t toward the root every PROBE_INTERVAL_MS milliseconds.
 * The root is addressed via esp_mesh_send() with MESH_DATA_TODS flag, which
 * routes the packet up the tree to the root regardless of intermediate hops.
 *
 * For Milestone 2 (blackhole), victim nodes will instead send directly to the
 * attacker's MAC address.  For Milestone 1, root is always the destination.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void probe_gen_task(void *arg)
{
    ESP_LOGI(TAG, "Probe generator task running at %u ms interval.",
             PROBE_INTERVAL_MS);

    /* Destination: root node (addressed with the TODS flag). */
    mesh_addr_t to = {0};
    /* MESH_ADDR_TODS is a special address constant meaning "toward the root". */
    memset(to.addr, 0, 6);   /* zero addr + TODS flag = root */

    probe_pkt_t pkt = {
        .magic = PROBE_MAGIC,
    };
    memcpy(pkt.src_mac, s_self_mac, 6);

    mesh_data_t mdata = {
        .data  = (uint8_t *)&pkt,
        .size  = sizeof(pkt),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    uint32_t seq = 0;

    while (!phase_listener_is_terminated()) {
        pkt.seq_num      = ++seq;
        pkt.send_ts_us   = esp_timer_get_time();

        esp_err_t err = esp_mesh_send(&to, &mdata,
                                      MESH_DATA_P2P | MESH_DATA_TODS,
                                      NULL, 0);
        if (err == ESP_OK) {
            s_probes_sent++;
            s_tx_count++;
            ESP_LOGD(TAG, "Probe sent seq=%lu", (unsigned long)seq);
        } else {
            /* Count failed sends as retries (proxy for MAC retry counter). */
            s_retry_count++;
            ESP_LOGW(TAG, "Probe send failed seq=%lu: %s",
                     (unsigned long)seq, esp_err_to_name(err));
        }

        vTaskDelay(pdMS_TO_TICKS(PROBE_INTERVAL_MS));
    }

    ESP_LOGI(TAG, "Probe generator task exiting. Total sent: %lu",
             (unsigned long)s_probes_sent);
    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — 1 Hz cross-layer sampler
 *
 * Directly implements VICTIM_TELEMETRY_LOOP from Figure 4.24 of the thesis:
 *
 *   timestamp ← get_high_resolution_time()
 *   rssi      ← esp_wifi_sta_get_rssi()
 *   retry_count, tx_count ← read_MAC_counters()
 *   layer, parent_mac     ← esp_mesh_get_layer / get_parent_bssid()
 *   probes_sent           ← read_probe_counter()
 *   append CSV row
 *   sleep(SAMPLING_INTERVAL_MS)
 * ═══════════════════════════════════════════════════════════════════════════ */

static void telemetry_task(void *arg)
{
    ESP_LOGI(TAG, "Telemetry task running at %u ms interval.",
             SAMPLING_INTERVAL_MS);

    while (!phase_listener_is_terminated()) {
        int64_t ts = esp_timer_get_time();

        /* ── Physical layer ───────────────────────────────────────────────── */
        int rssi = 0;
        esp_wifi_sta_get_rssi(&rssi);

        /* ── Network layer ────────────────────────────────────────────────── */
        int layer = mesh_setup_get_layer();
        uint8_t pmac[6] = {0};
        mesh_setup_get_parent_mac(pmac);

        /* ── Application layer counters (atomic snapshot) ─────────────────── */
        uint32_t retry_snap  = s_retry_count;
        uint32_t tx_snap     = s_tx_count;
        uint32_t probes_snap = s_probes_sent;

        /* ── Log row ──────────────────────────────────────────────────────── */
        csv_logger_append_telemetry(
            ts,
            s_node_id,
            "victim",
            layer,
            pmac,
            rssi,
            retry_snap,
            tx_snap,
            probes_snap,
            phase_listener_get_phase_id(),
            phase_listener_get_label()
        );

        ESP_LOGD(TAG,
                 "Sample: ts=%lld rssi=%d layer=%d phase=%u label=%u "
                 "probes=%lu",
                 (long long)ts, rssi, layer,
                 phase_listener_get_phase_id(),
                 phase_listener_get_label(),
                 (unsigned long)probes_snap);

        vTaskDelay(pdMS_TO_TICKS(SAMPLING_INTERVAL_MS));
    }

    ESP_LOGI(TAG, "Telemetry task exiting.");
    vTaskDelete(NULL);
}

/* ── Utility ─────────────────────────────────────────────────────────────── */

static void build_run_id(char *buf, size_t len)
{
    int64_t ts = esp_timer_get_time() / 1000000LL;
    snprintf(buf, len, "RUN_%lld", (long long)ts);
}