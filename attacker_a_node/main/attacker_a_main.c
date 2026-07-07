/**
 * @file attacker_a_main.c
 * @brief Wormhole Attacker A firmware — Milestone 2.
 *
 * Attacker A sits NEAR THE ROOT. It reads probe metadata that Attacker B ships
 * across the WIRED UART tunnel and, for each record, reconstructs a REPLICA
 * probe carrying the ORIGINAL seq_num / src_mac / send_ts_us. It re-injects the
 * replica toward root via the legitimate mesh path (to=NULL + MESH_DATA_TODS).
 *
 * Because A is one hop from root while the victim's own probe travels the slow
 * multi-hop path, the root logs the SAME logical probe twice in arrivals.csv —
 * once slow, once fast — a duplicate with a measurable latency mismatch: the
 * wormhole signature.
 *
 * A joins the mesh as an ordinary (non-root) node and logs 1 Hz telemetry.
 *
 * Build target: attacker_a_node/
 *
 * NIS16 — CTTHES2 Milestone 2
 */

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

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

static const char *TAG = "ATTACKER_A_MAIN";

/* ── Shared state ─────────────────────────────────────────────────────────── */
static char s_node_id[NODE_ID_LEN] = {0};
static char s_run_id[RUN_ID_LEN]   = {0};

/* Telemetry counters (cumulative). */
static volatile uint32_t s_injected    = 0;   /* replicas re-injected to root   */
static volatile uint32_t s_inject_fail = 0;   /* failed mesh re-injection sends  */

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void reinjector_task(void *arg);
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */
void app_main(void)
{
    ESP_LOGI(TAG, "=== WORMHOLE ATTACKER A STARTING ===");

    /* ── 1. Mesh init (ordinary non-root node, placed near root) ──────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_ATCK_WA));
    mesh_setup_get_node_id(s_node_id);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);

    /* ── 2. Phase listener (A consumes no mesh data → no data cb) ─────────── */
    ESP_ERROR_CHECK(phase_listener_start());

    /* ── 3. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 4. UART tunnel from Attacker B ──────────────────────────────────── */
    ESP_ERROR_CHECK(wormhole_uart_init());

    /* ── 5. Tasks ────────────────────────────────────────────────────────── */
    xTaskCreate(reinjector_task, "wh_reinject", STACK_WORMHOLE,
                NULL, TASK_PRIO_WORMHOLE, NULL);
    xTaskCreate(telemetry_task,  "telemetry",   STACK_TELEMETRY,
                NULL, TASK_PRIO_TELEMETRY, NULL);

    /* ── 6. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 7. Finalise ─────────────────────────────────────────────────────── */
    ESP_LOGI(TAG, "Experiment complete. injected=%lu fail=%lu",
             (unsigned long)s_injected, (unsigned long)s_inject_fail);
    csv_logger_flush();
    csv_logger_close();

    ESP_LOGI(TAG, "Send 'EXPORT_LOGS' via serial to retrieve the CSV.");
    csv_logger_start_export_task();
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Re-injector task — reads the tunnel and re-injects replica probes to root.
 * Only injects while the wormhole phase is active, so a late-arriving frame
 * cannot leak a mislabelled arrival into the cooldown window.
 * ═══════════════════════════════════════════════════════════════════════════ */
static void reinjector_task(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "Re-injector task running.");

    uint32_t seq;
    uint8_t  src_mac[6];
    int64_t  send_ts_us;

    while (!phase_listener_is_terminated()) {
        if (!wormhole_tunnel_recv(&seq, src_mac, &send_ts_us, 200)) {
            continue;   /* timeout / corrupt frame — retry */
        }

        if (phase_listener_get_phase_id() != PHASE_ID_WORMHOLE) {
            continue;   /* window closed — discard */
        }

        /* Reconstruct the probe with its ORIGINAL identifiers so root sees the
         * same logical probe twice (slow real copy + this fast wormhole copy). */
        wormhole_probe_pkt_t replica = {
            .magic      = WORMHOLE_PROBE_MAGIC,
            .seq_num    = seq,
            .send_ts_us = send_ts_us,
        };
        memcpy(replica.src_mac, src_mac, 6);

        mesh_data_t mdata = {
            .data  = (uint8_t *)&replica,
            .size  = sizeof(replica),
            .proto = MESH_PROTO_BIN,
            .tos   = MESH_TOS_P2P,
        };

        esp_err_t err = esp_mesh_send(NULL, &mdata, MESH_DATA_TODS, NULL, 0);
        if (err == ESP_OK) {
            s_injected++;
            ESP_LOGD(TAG, "Re-injected seq=%lu to root", (unsigned long)seq);
        } else {
            s_inject_fail++;
            ESP_LOGD(TAG, "Re-inject seq=%lu failed: %s",
                     (unsigned long)seq, esp_err_to_name(err));
        }
    }

    ESP_LOGI(TAG, "Re-injector task exiting.");
    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — 1 Hz cross-layer sampler (same schema as every node).
 *   retry_count ← failed re-injections
 *   tx_count    ← replicas re-injected
 *   probes_count← replicas re-injected (A's "sent" count)
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

        uint32_t retry_snap  = s_inject_fail;
        uint32_t tx_snap     = s_injected;
        uint32_t probes_snap = s_injected;

        csv_logger_append_telemetry(
            ts, s_node_id, "attacker_a", layer, pmac, rssi,
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
