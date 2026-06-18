/**
 * @file root_main.c
 * @brief Root node firmware — Milestone 1.
 *
 * Responsibilities:
 *  1. Initialise mesh (mesh_setup), phase listener, and CSV logger.
 *  2. Run the EXPERIMENT_CONTROLLER: sequence through Baseline → Attack →
 *     Cooldown → Terminate, broadcasting each phase transition.
 *  3. Run a PROBE_SINK task: receive probe packets from victim nodes, log
 *     per-arrival records (src_mac, seq_num, latency_us).
 *  4. Run a TELEMETRY task: sample cross-layer metrics at 1 Hz and log them.
 *  5. After experiment ends: flush, close, start serial-export task.
 *
 * Build target: root_node/
 *
 * NIS16 — CTTHES2 Milestone 1
 */

#include <stdio.h>
#include <string.h>
#include <time.h>

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

/* ── Module tag ──────────────────────────────────────────────────────────── */
static const char *TAG = "ROOT_MAIN";

/* ── Probe wire format (must match victim_main.c exactly) ────────────────── */
#define PROBE_MAGIC     0x50524F42U   /* "PROB" */

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t seq_num;
    int64_t  send_ts_us;    /* esp_timer_get_time() on the victim at send */
    uint8_t  src_mac[6];
} probe_pkt_t;

/* ── Shared run state ─────────────────────────────────────────────────────── */
static char s_node_id[NODE_ID_LEN]  = {0};
static char s_run_id[RUN_ID_LEN]    = {0};

/* Cumulative probe counter (all sources combined) */
static volatile uint32_t s_probes_received = 0;

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void experiment_controller_task(void *arg);
static void probe_sink_task(void *arg);
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */

void app_main(void)
{
    ESP_LOGI(TAG, "=== ROOT NODE STARTING ===");

    /* ── 1. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_ROOT));
    mesh_setup_get_node_id(s_node_id);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);

    /* ── 2. Phase listener (the root also receives its own broadcasts via
     *       the mesh receive queue, keeping its own state consistent) ─────── */
    ESP_ERROR_CHECK(phase_listener_start());

    /* ── 3. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 4. Start background tasks ───────────────────────────────────────── */
    xTaskCreate(probe_sink_task,  "probe_sink",  STACK_PROBE_SINK,
                NULL, TASK_PRIO_PROBE_SINK,  NULL);
    xTaskCreate(telemetry_task,   "telemetry",   STACK_TELEMETRY,
                NULL, TASK_PRIO_TELEMETRY,   NULL);

    /* ── 5. Experiment controller (runs in its own task so app_main returns) */
    xTaskCreate(experiment_controller_task, "exp_ctrl", STACK_TELEMETRY * 2,
                NULL, TASK_PRIO_TELEMETRY + 1, NULL);

    /* ── 6. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 7. Finalise ─────────────────────────────────────────────────────── */
    ESP_LOGI(TAG, "Experiment complete. Flushing and closing log.");
    csv_logger_flush();
    csv_logger_close();

    ESP_LOGI(TAG, "Starting serial export task. "
                  "Connect USB and send: EXPORT_LOGS");
    csv_logger_start_export_task();

    /* app_main may now return — the export task keeps running. */
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Experiment controller task
 *
 * Implements EXPERIMENT_CONTROLLER() from Figure 4.2 of the thesis.
 * For Milestone 1 we run the BASELINE-only sequence (no attack phase).
 * The attack-phase broadcasts (phase_id 1 or 2) are left as stubs so
 * Milestone 2 can simply fill them in.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void experiment_controller_task(void *arg)
{
    ESP_LOGI(TAG, "[CTRL] Waiting %u s for mesh to stabilise...",
             PHASE_STABILISE_S);
    vTaskDelay(pdMS_TO_TICKS(PHASE_STABILISE_S * 1000));

    /* ── Phase 0: Baseline ───────────────────────────────────────────────── */
    ESP_LOGI(TAG, "[CTRL] Starting PHASE 0 — Baseline (%u s)", PHASE_BASELINE_S);
    phase_listener_broadcast(PHASE_ID_BASELINE);
    vTaskDelay(pdMS_TO_TICKS(PHASE_BASELINE_S * 1000));
    ESP_LOGI(TAG, "[CTRL] Phase 0 complete.");

    /*
     * ── Phase 1 / 2: Attack (DEFERRED to Milestone 2) ───────────────────
     * Milestone 1 runs baseline only.  The stubs below show where the
     * Milestone-2 code will go.
     *
     *   phase_listener_broadcast(PHASE_ID_BLACKHOLE);   // or WORMHOLE
     *   vTaskDelay(pdMS_TO_TICKS(PHASE_ATTACK_S * 1000));
     */

    /* ── Phase 3: Cooldown ───────────────────────────────────────────────── */
    ESP_LOGI(TAG, "[CTRL] Starting PHASE 3 — Cooldown (%u s)", PHASE_COOLDOWN_S);
    phase_listener_broadcast(PHASE_ID_COOLDOWN);
    vTaskDelay(pdMS_TO_TICKS(PHASE_COOLDOWN_S * 1000));
    ESP_LOGI(TAG, "[CTRL] Phase 3 complete.");

    /* ── Phase 4: Terminate ──────────────────────────────────────────────── */
    ESP_LOGI(TAG, "[CTRL] Broadcasting TERMINATE.");
    phase_listener_broadcast(PHASE_ID_TERMINATE);

    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Probe sink task
 *
 * Blocks on esp_mesh_recv() and filters for probe_pkt_t messages.
 * Logs one probe-arrival CSV row per received probe.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void probe_sink_task(void *arg)
{
    static uint8_t rx_buf[sizeof(probe_pkt_t) + 64];
    mesh_addr_t from = {0};
    mesh_data_t mdata = {
        .data = rx_buf,
        .size = sizeof(rx_buf),
    };
    int flags = 0;

    ESP_LOGI(TAG, "Probe sink task running.");

    while (!phase_listener_is_terminated()) {
        mdata.size = sizeof(rx_buf);
        esp_err_t err = esp_mesh_recv(&from, &mdata,
                                      pdMS_TO_TICKS(200), &flags, NULL, 0);
        if (err == ESP_ERR_MESH_TIMEOUT) continue;
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "probe_sink recv error: %s", esp_err_to_name(err));
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        if (mdata.size < sizeof(probe_pkt_t)) continue;

        const probe_pkt_t *pkt = (const probe_pkt_t *)rx_buf;
        if (pkt->magic != PROBE_MAGIC) continue;

        int64_t now       = esp_timer_get_time();
        int64_t latency   = now - pkt->send_ts_us;
        s_probes_received++;

        /* Cross-layer snapshot at time of arrival */
        uint8_t pmac[6] = {0};
        mesh_setup_get_parent_mac(pmac);  /* root has no parent → all zeros */
        int rssi = 0;
        esp_wifi_sta_get_rssi(&rssi);

        csv_logger_append_probe_arrival(
            now,
            s_node_id,
            mesh_setup_get_layer(),
            pmac,
            rssi,
            0,  /* retry_count — root doesn't send, only receives */
            0,  /* tx_count   */
            s_probes_received,
            phase_listener_get_phase_id(),
            phase_listener_get_label(),
            (uint8_t *)pkt->src_mac,
            pkt->seq_num,
            latency
        );

        ESP_LOGD(TAG, "Probe from " MACSTR " seq=%lu lat=%lld us",
                 MAC2STR(pkt->src_mac),
                 (unsigned long)pkt->seq_num,
                 (long long)latency);
    }

    ESP_LOGI(TAG, "Probe sink task exiting.");
    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task  — 1 Hz cross-layer sampler
 *
 * Implements the VICTIM_TELEMETRY_LOOP from Figure 4.24 adapted for root.
 * Root has no parent so parent_mac is all-zeros; layer is always 0.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void telemetry_task(void *arg)
{
    uint32_t retry_prev = 0;
    uint32_t tx_prev    = 0;
    uint32_t retry_cum  = 0;
    uint32_t tx_cum     = 0;

    ESP_LOGI(TAG, "Telemetry task running at %u ms interval.",
             SAMPLING_INTERVAL_MS);

    while (!phase_listener_is_terminated()) {
        int64_t ts = esp_timer_get_time();

        /* Physical layer */
        int rssi = 0;
        esp_wifi_sta_get_rssi(&rssi);

        /* MAC layer counters — ESP-IDF wifi stats */
        wifi_pkt_rx_ctrl_t rx_ctrl = {0};
        /* Note: detailed per-packet retry counters require esp_wifi_get_tsf_time
         * or a custom MAC hook. For Milestone 1 we snapshot via wifi_sta_list
         * and accumulate a proxy counter. Full counter access added in M2. */
        (void)rx_ctrl;

        /* Network layer */
        int layer = mesh_setup_get_layer();
        uint8_t pmac[6] = {0};
        mesh_setup_get_parent_mac(pmac);

        csv_logger_append_telemetry(
            ts,
            s_node_id,
            "root",
            layer,
            pmac,
            rssi,
            retry_cum,
            tx_cum,
            s_probes_received,
            phase_listener_get_phase_id(),
            phase_listener_get_label()
        );

        (void)retry_prev;
        (void)tx_prev;

        vTaskDelay(pdMS_TO_TICKS(SAMPLING_INTERVAL_MS));
    }

    ESP_LOGI(TAG, "Telemetry task exiting.");
    vTaskDelete(NULL);
}

/* ── Utility ─────────────────────────────────────────────────────────────── */

static void build_run_id(char *buf, size_t len)
{
    /* Use esp_timer as a monotonic stand-in; real wall time needs SNTP. */
    int64_t ts = esp_timer_get_time() / 1000000LL;  /* seconds since boot */
    snprintf(buf, len, "RUN_%lld", (long long)ts);
}