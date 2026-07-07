/**
 * @file attacker_b_main.c
 * @brief Wormhole Attacker B firmware — Milestone 2.
 *
 * Attacker B sits NEAR THE VICTIMS. During the wormhole phase the victims send
 * a capture-copy of every probe to B (emulating B overhearing local mesh
 * traffic — the closed-source Wi-Fi firmware cannot be sniffed directly). B:
 *
 *   1. Extracts {seq_num, src_mac, send_ts_us} from each captured probe.
 *   2. Ships that metadata to Attacker A through the WIRED UART tunnel
 *      (CRC-protected — see wormhole.c). This out-of-band hop is what makes the
 *      attack a wormhole rather than ordinary mesh forwarding.
 *
 * B also logs 1 Hz cross-layer telemetry like any instrumented node, and joins
 * the mesh as an ordinary (non-root) node so it can receive the capture-copies.
 *
 * Build target: attacker_b_node/
 *
 * NIS16 — CTTHES2 Milestone 2
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "esp_log.h"
#include "esp_mesh.h"
#include "esp_wifi.h"
#include "esp_timer.h"
#include "esp_mac.h"

#include "mesh_config.h"
#include "mesh_setup.h"
#include "phase_listener.h"
#include "csv_logger.h"
#include "wormhole.h"
#include "nvs.h"

static const char *TAG = "ATTACKER_B_MAIN";

/* ── Shared state ─────────────────────────────────────────────────────────── */
static char s_node_id[NODE_ID_LEN] = {0};
static char s_run_id[RUN_ID_LEN]   = {0};

static QueueHandle_t s_capture_q = NULL;

/* Telemetry counters (cumulative). */
static volatile uint32_t s_captured     = 0;   /* probes captured off the mesh   */
static volatile uint32_t s_tunneled     = 0;   /* metadata records sent to A     */
static volatile uint32_t s_tunnel_fail  = 0;   /* failed UART tunnel writes       */

/* Queue item: one captured probe's metadata. */
typedef struct {
    uint32_t seq_num;
    uint8_t  src_mac[6];
    int64_t  send_ts_us;
} capture_item_t;

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void capture_cb(const uint8_t *data, size_t len, const uint8_t from[6]);
static void tunnel_sender_task(void *arg);
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */
void app_main(void)
{
    ESP_LOGI(TAG, "=== WORMHOLE ATTACKER B STARTING ===");

    /* ── 1. Mesh init (ordinary non-root node) ───────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_ATCK_WB));
    mesh_setup_get_node_id(s_node_id);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);
    ESP_LOGI(TAG, "*** Put THIS MAC into WORMHOLE_ATTACKER_B_MAC (mesh_config.h). ***");

    /* ── 2. Phase listener + capture dispatch ────────────────────────────── */
    ESP_ERROR_CHECK(phase_listener_start());
    s_capture_q = xQueueCreate(16, sizeof(capture_item_t));
    if (!s_capture_q) {
        ESP_LOGE(TAG, "Failed to create capture queue");
        abort();
    }
    phase_listener_set_data_cb(capture_cb);

    /* ── 3. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 4. UART tunnel to Attacker A ────────────────────────────────────── */
    ESP_ERROR_CHECK(wormhole_uart_init());

    /* ── 5. Tasks ────────────────────────────────────────────────────────── */
    xTaskCreate(tunnel_sender_task, "wh_tunnel", STACK_WORMHOLE,
                NULL, TASK_PRIO_WORMHOLE, NULL);
    xTaskCreate(telemetry_task,     "telemetry", STACK_TELEMETRY,
                NULL, TASK_PRIO_TELEMETRY, NULL);

    /* ── 6. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 7. Finalise ─────────────────────────────────────────────────────── */
    ESP_LOGI(TAG, "Experiment complete. captured=%lu tunneled=%lu fail=%lu",
             (unsigned long)s_captured, (unsigned long)s_tunneled,
             (unsigned long)s_tunnel_fail);
    csv_logger_flush();
    csv_logger_close();

    ESP_LOGI(TAG, "Send 'EXPORT_LOGS' via serial to retrieve the CSV.");
    csv_logger_start_export_task();
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Capture callback — runs in the phase-listener task context. Keep it short:
 * validate, then hand the metadata to the tunnel-sender task via a queue.
 * ═══════════════════════════════════════════════════════════════════════════ */
static void capture_cb(const uint8_t *data, size_t len, const uint8_t from[6])
{
    (void)from;

    if (len < sizeof(wormhole_probe_pkt_t)) return;
    const wormhole_probe_pkt_t *p = (const wormhole_probe_pkt_t *)data;
    if (p->magic != WORMHOLE_PROBE_MAGIC) return;

    /* Only relay during the wormhole window (defensive — victims only send
     * the capture-copy during that phase anyway). */
    if (phase_listener_get_phase_id() != PHASE_ID_WORMHOLE) return;

    capture_item_t it = {
        .seq_num    = p->seq_num,
        .send_ts_us = p->send_ts_us,
    };
    memcpy(it.src_mac, p->src_mac, 6);

    if (xQueueSend(s_capture_q, &it, 0) == pdTRUE) {
        s_captured++;
    }
    /* Queue full → drop; s_captured only counts what we accepted. */
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Tunnel-sender task — drains the capture queue into the UART tunnel to A.
 * ═══════════════════════════════════════════════════════════════════════════ */
static void tunnel_sender_task(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "Tunnel sender task running.");

    while (!phase_listener_is_terminated()) {
        capture_item_t it;
        if (xQueueReceive(s_capture_q, &it, pdMS_TO_TICKS(200)) == pdTRUE) {
            if (wormhole_tunnel_send(it.seq_num, it.src_mac,
                                     it.send_ts_us) == ESP_OK) {
                s_tunneled++;
                ESP_LOGD(TAG, "Tunneled seq=%lu to A", (unsigned long)it.seq_num);
            } else {
                s_tunnel_fail++;
            }
        }
    }

    ESP_LOGI(TAG, "Tunnel sender task exiting.");
    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — 1 Hz cross-layer sampler (same schema as every node).
 *   retry_count ← failed tunnel writes
 *   tx_count    ← records tunneled to A
 *   probes_count← probes captured off the mesh
 * ═══════════════════════════════════════════════════════════════════════════ */
static void telemetry_task(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "Telemetry task running at %u ms interval.",
             SAMPLING_INTERVAL_MS);

    while (!phase_listener_is_terminated()) {
        int64_t ts = esp_timer_get_time();

        int rssi = 0;
        esp_wifi_sta_get_rssi(&rssi);

        int layer = mesh_setup_get_layer();
        uint8_t pmac[6] = {0};
        mesh_setup_get_parent_mac(pmac);

        uint32_t retry_snap  = s_tunnel_fail;
        uint32_t tx_snap     = s_tunneled;
        uint32_t probes_snap = s_captured;

        csv_logger_append_telemetry(
            ts, s_node_id, "attacker_b", layer, pmac, rssi,
            retry_snap, tx_snap, probes_snap,
            phase_listener_get_phase_id(), phase_listener_get_label());

        vTaskDelay(pdMS_TO_TICKS(SAMPLING_INTERVAL_MS));
    }

    ESP_LOGI(TAG, "Telemetry task exiting.");
    vTaskDelete(NULL);
}

/* ── Utility ─────────────────────────────────────────────────────────────── */
static void build_run_id(char *buf, size_t len)
{
    nvs_handle_t h;
    uint32_t run_num = 0;

    esp_err_t err = nvs_open("nis16", NVS_READWRITE, &h);
    if (err == ESP_OK) {
        nvs_get_u32(h, "run_num", &run_num);
        run_num++;
        nvs_set_u32(h, "run_num", run_num);
        nvs_commit(h);
        nvs_close(h);
    } else {
        ESP_LOGW(TAG, "NVS open failed (%s) — using boot-time fallback",
                 esp_err_to_name(err));
        run_num = (uint32_t)(esp_timer_get_time() / 1000000LL);
    }

    snprintf(buf, len, "RUN_%03lu", (unsigned long)run_num);
}
