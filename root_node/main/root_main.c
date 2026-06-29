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
#include "nvs.h"

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

/*
 * Cumulative probe counter — written by probe_data_cb, read by
 * telemetry_task.  Declared volatile so the compiler does not cache the
 * value in a register across the sampling loop.
 */
static volatile uint32_t s_probes_received = 0;

/*
 * Broadcast failure counter — incremented by experiment_controller_task
 * whenever phase_listener_broadcast() reports a failed esp_mesh_send().
 * Used as the root's proxy for MAC-layer retry activity: the root itself
 * only transmits during phase broadcasts, so failed sends are the only
 * meaningful "retry" signal available without a custom MAC hook.
 *
 * Mirrors the role of s_retry_count in victim_main.c.
 */
static volatile uint32_t s_broadcast_failures = 0;

/*
 * Cumulative broadcast send counter — incremented once per successful
 * phase broadcast attempt.  Used as tx_count in root telemetry rows,
 * mirroring s_tx_count in victim_main.c.
 */
static volatile uint32_t s_broadcast_sends = 0;

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void experiment_controller_task(void *arg);
static void probe_data_cb(const uint8_t *data, size_t len,
                          const uint8_t from_addr[6]);
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
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_ROOT));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 4. Probe sink: register a handler for incoming probe packets.
     *       esp_mesh_recv() must be called from ONE task only, so instead of a
     *       competing receive loop the phase listener (the single reader) hands
     *       us every non-phase packet via this callback. ──────────────────── */
    phase_listener_set_data_cb(probe_data_cb);
    ESP_LOGI(TAG, "Probe sink registered (via phase-listener dispatch).");

    /* ── 5. Start background tasks ───────────────────────────────────────── */
    xTaskCreate(telemetry_task,   "telemetry",   STACK_TELEMETRY,
                NULL, TASK_PRIO_TELEMETRY,   NULL);

    /* ── 6. Experiment controller (runs in its own task so app_main returns) */
    xTaskCreate(experiment_controller_task, "exp_ctrl", STACK_TELEMETRY * 2,
                NULL, TASK_PRIO_TELEMETRY + 1, NULL);

    /* ── 7. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 8. Finalise ─────────────────────────────────────────────────────── */
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
 *
 * Each call to phase_listener_broadcast() sends PHASE_BROADCAST_REPEAT
 * copies internally.  We count the individual esp_mesh_send outcomes via
 * s_broadcast_sends and s_broadcast_failures so the telemetry task has
 * real tx/retry numbers rather than zeros.
 * ═══════════════════════════════════════════════════════════════════════════ */

/*
 * Thin wrapper around phase_listener_broadcast() that updates the shared
 * send/failure counters used as the root's tx/retry telemetry proxies.
 *
 * phase_listener_broadcast() now does all the real work — one self-loopback
 * plus a routing-table unicast to every node, repeated PHASE_BROADCAST_REPEAT
 * times — and returns how many of those individual sends failed. We count one
 * logical broadcast per repeat as "tx", and the returned failures as "retry".
 */
static void broadcast_and_count(uint8_t phase_id)
{
    int failed = phase_listener_broadcast(phase_id);
    s_broadcast_failures += (uint32_t)failed;
    s_broadcast_sends    += PHASE_BROADCAST_REPEAT;
}

static void experiment_controller_task(void *arg)
{
    ESP_LOGI(TAG, "[CTRL] Waiting %u s for mesh to stabilise...",
             PHASE_STABILISE_S);
    vTaskDelay(pdMS_TO_TICKS(PHASE_STABILISE_S * 1000));

    /* ── Phase 0: Baseline ───────────────────────────────────────────────── */
    ESP_LOGI(TAG, "[CTRL] Starting PHASE 0 — Baseline (%u s)", PHASE_BASELINE_S);
    broadcast_and_count(PHASE_ID_BASELINE);
    vTaskDelay(pdMS_TO_TICKS(PHASE_BASELINE_S * 1000));
    ESP_LOGI(TAG, "[CTRL] Phase 0 complete.");

    /*
     * ── Phase 1 / 2: Attack (DEFERRED to Milestone 2) ───────────────────
     * Milestone 1 runs baseline only.  The stubs below show where the
     * Milestone-2 code will go.
     *
     *   broadcast_and_count(PHASE_ID_BLACKHOLE);   // or WORMHOLE
     *   vTaskDelay(pdMS_TO_TICKS(PHASE_ATTACK_S * 1000));
     */

    /* ── Phase 3: Cooldown ───────────────────────────────────────────────── */
    ESP_LOGI(TAG, "[CTRL] Starting PHASE 3 — Cooldown (%u s)", PHASE_COOLDOWN_S);
    broadcast_and_count(PHASE_ID_COOLDOWN);
    vTaskDelay(pdMS_TO_TICKS(PHASE_COOLDOWN_S * 1000));
    ESP_LOGI(TAG, "[CTRL] Phase 3 complete.");

    /* ── Phase 4: Terminate ──────────────────────────────────────────────── */
    ESP_LOGI(TAG, "[CTRL] Broadcasting TERMINATE.");
    broadcast_and_count(PHASE_ID_TERMINATE);

    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Probe sink callback
 *
 * Invoked by the phase listener (the single esp_mesh_recv() reader) for every
 * non-phase packet. Filters for probe_pkt_t messages and logs one
 * probe-arrival CSV row per received probe.
 *
 * Runs in the phase-listener task context — keep it short and non-blocking.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void probe_data_cb(const uint8_t *data, size_t len,
                          const uint8_t from_addr[6])
{
    (void)from_addr;  /* src_mac travels inside the probe payload */

    if (len < sizeof(probe_pkt_t)) return;

    const probe_pkt_t *pkt = (const probe_pkt_t *)data;
    if (pkt->magic != PROBE_MAGIC) return;

    int64_t now     = esp_timer_get_time();
    int64_t latency = now - pkt->send_ts_us;
    s_probes_received++;

    /* Cross-layer snapshot at time of arrival */
    uint8_t pmac[6] = {0};
    mesh_setup_get_parent_mac(pmac);  /* root has no parent → all zeros */
    int rssi = 0;
    esp_wifi_sta_get_rssi(&rssi);

    /*
     * retry_count and tx_count in the arrivals row reflect the root's
     * own outbound activity (phase broadcasts), not the incoming probe.
     * This keeps the schema consistent with victim rows and lets the
     * post-processing pipeline join on the same columns.
     */
    csv_logger_append_probe_arrival(
        now,
        s_node_id,
        mesh_setup_get_layer(),
        pmac,
        rssi,
        s_broadcast_failures,
        s_broadcast_sends,
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

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — 1 Hz cross-layer sampler
 *
 * Implements the VICTIM_TELEMETRY_LOOP from Figure 4.24 adapted for root.
 * Root has no parent so parent_mac is all-zeros; layer is always 0.
 *
 * retry_count ← s_broadcast_failures  (failed phase broadcast sends)
 * tx_count    ← s_broadcast_sends     (successful phase broadcast sends)
 *
 * Both are cumulative monotonic counters, consistent with the victim schema.
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

        /* ── MAC-layer proxy counters (atomic snapshot) ───────────────────── */
        uint32_t retry_snap = s_broadcast_failures;
        uint32_t tx_snap    = s_broadcast_sends;
        uint32_t probes_snap = s_probes_received;

        /* ── Log row ──────────────────────────────────────────────────────── */
        csv_logger_append_telemetry(
            ts,
            s_node_id,
            "root",
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
                 "probes_rx=%lu bcast_tx=%lu bcast_fail=%lu",
                 (long long)ts, rssi, layer,
                 phase_listener_get_phase_id(),
                 phase_listener_get_label(),
                 (unsigned long)probes_snap,
                 (unsigned long)tx_snap,
                 (unsigned long)retry_snap);

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
        /* Read current counter — default 0 if key doesn't exist yet */
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
