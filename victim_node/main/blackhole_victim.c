/**
 * @file blackhole_victim.c
 * @brief Combined Victim + Blackhole Attacker firmware — Milestone 2.
 *
 * Runs on ESP32 #2 (the "victim" board).
 * - Baseline/Cooldown: probes forwarded normally to root
 * - Attack phase (PHASE_ID_BLACKHOLE): probes are silently dropped
 *
 * Build target: victim_node/
 * 
 * in CMakeLists.txt set: SRCS to blackhole_victim.c
 * and in root_main.c uncomment line 246 & 247 to run 
 * the blackhole attack phase
 *
 * NIS16 — CTTHES2 Milestone 2 — Blackhole Attack
 */

#include <stdio.h>
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
#include "nvs.h"

/* ── Module tag ──────────────────────────────────────────────────────────── */
static const char *TAG = "BLACKHOLE";

/* ── Probe wire format (must match root_main.c) ─────────────────────────── */
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

/* Attack counters */
static volatile uint32_t s_probes_generated = 0;
static volatile uint32_t s_probes_forwarded = 0;
static volatile uint32_t s_probes_dropped   = 0;
static volatile uint32_t s_probes_queued    = 0;

/* Queue for probe forwarding */
static QueueHandle_t s_probe_queue = NULL;
#define PROBE_QUEUE_SIZE 32

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void probe_gen_task(void *arg);
static void probe_forwarder_task(void *arg);
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */

void app_main(void)
{
    ESP_LOGI(TAG, "=== BLACKHOLE NODE STARTING ===");

    /* ── 1. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_VICTIM));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);

    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s", s_node_id);

    /* ── 2. Create queue for probe forwarding ─────────────────────────────── */
    s_probe_queue = xQueueCreate(PROBE_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_probe_queue) {
        ESP_LOGE(TAG, "Failed to create probe queue");
        return;
    }

    /* ── 3. Phase listener ────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(phase_listener_start());

    /* ── 4. Logger ────────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 5. Start tasks ──────────────────────────────────────────────────── */
    xTaskCreate(probe_gen_task,      "probe_gen",    STACK_PROBE_GEN,     NULL, 5, NULL);
    xTaskCreate(probe_forwarder_task,"forwarder",    STACK_PROBE_SINK,    NULL, 6, NULL);
    xTaskCreate(telemetry_task,      "telemetry",    STACK_TELEMETRY,     NULL, 5, NULL);

    /* ── 6. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 7. Finalise ─────────────────────────────────────────────────────── */
    ESP_LOGI(TAG, "Experiment complete.");
    ESP_LOGI(TAG, "Probes generated: %lu, Forwarded: %lu, Dropped: %lu",
             (unsigned long)s_probes_generated,
             (unsigned long)s_probes_forwarded,
             (unsigned long)s_probes_dropped);

    csv_logger_flush();
    csv_logger_close();
    csv_logger_start_export_task();
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Probe generator task
 *
 * Generates probe packets and queues them for the forwarder.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void probe_gen_task(void *arg)
{
    ESP_LOGI(TAG, "Probe generator task running at %u ms interval.",
             PROBE_INTERVAL_MS);

    probe_pkt_t pkt = { .magic = PROBE_MAGIC };
    memcpy(pkt.src_mac, s_self_mac, 6);
    uint32_t seq = 0;

    while (!phase_listener_is_terminated()) {
        pkt.seq_num = ++seq;
        pkt.send_ts_us = esp_timer_get_time();
        s_probes_generated++;

        /* Send to forwarder via queue */
        if (xQueueSend(s_probe_queue, &pkt, pdMS_TO_TICKS(10)) != pdTRUE) {
            ESP_LOGW(TAG, "Probe queue full! seq=%lu dropped at source",
                     (unsigned long)seq);
        } else {
            s_probes_queued++;
        }

        vTaskDelay(pdMS_TO_TICKS(PROBE_INTERVAL_MS));
    }

    ESP_LOGI(TAG, "Probe generator exiting.");
    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Probe forwarder task
 *
 * Implements BLACKHOLE behavior:
 * - During baseline (Phase 0): forward probes to root
 * - During attack (Phase 1): drop probes silently
 * - During cooldown (Phase 3): resume forwarding
 *
 * Per Section 4.2.1.2 of thesis:
 *   "Victim nodes intentionally send their application-layer probe packets
 *    to the attacker (destination = attacker's MAC address). The attacker
 *    either forwards these packets to the root (during baseline) or drops
 *    them (during the manipulation window)."
 * ═══════════════════════════════════════════════════════════════════════════ */

static void probe_forwarder_task(void *arg)
{
    probe_pkt_t pkt;
    mesh_data_t mdata = {
        .data  = (uint8_t *)&pkt,
        .size  = sizeof(pkt),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    ESP_LOGI(TAG, "Probe forwarder task running.");

    while (true) {
        if (xQueueReceive(s_probe_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        /* Check current phase - determines forwarding behavior */
        uint8_t phase = phase_listener_get_phase_id();
        bool is_attack = (phase == PHASE_ID_BLACKHOLE);

        if (is_attack) {
            /* ── BLACKHOLE: drop the probe silently ─────────────────────── */
            s_probes_dropped++;
            ESP_LOGD(TAG, "BLACKHOLE: dropped probe seq=%lu (phase=%u)",
                     (unsigned long)pkt.seq_num, phase);
        } else {
            /* ── FORWARD to root (NULL destination = root with TODS) ────── */
            esp_err_t err = esp_mesh_send(NULL, &mdata,
                                          MESH_DATA_TODS | MESH_DATA_P2P,
                                          NULL, 0);
            if (err == ESP_OK) {
                s_probes_forwarded++;
                ESP_LOGD(TAG, "Forwarded probe seq=%lu to root (phase=%u)",
                         (unsigned long)pkt.seq_num, phase);
            } else {
                ESP_LOGW(TAG, "Forward failed for seq=%lu: %s",
                         (unsigned long)pkt.seq_num, esp_err_to_name(err));
                /* Count failed sends as dropped (proxy for retry) */
                s_probes_dropped++;
            }
        }
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — 1 Hz cross-layer sampler
 *
 * Records blackhole-specific metrics:
 * - probes_generated: total probes created
 * - probes_forwarded: probes successfully sent to root
 * - probes_dropped: probes dropped (attack phase or send failures)
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

        /* ── Blackhole counters (atomic snapshot) ─────────────────────────── */
        uint32_t generated = s_probes_generated;
        uint32_t forwarded = s_probes_forwarded;
        uint32_t dropped   = s_probes_dropped;

        /* ── Log row ──────────────────────────────────────────────────────── */
        csv_logger_append_telemetry(
            ts,
            s_node_id,
            "blackhole",  /* Role identifies this as attacker */
            layer,
            pmac,
            rssi,
            dropped,      /* retry_count = probes dropped */
            forwarded,    /* tx_count = probes forwarded */
            generated,    /* probes_count = total generated */
            phase_listener_get_phase_id(),
            phase_listener_get_label()
        );

        ESP_LOGD(TAG,
                 "Sample: ts=%lld rssi=%d layer=%d phase=%u label=%u "
                 "gen=%lu fwd=%lu drop=%lu",
                 (long long)ts, rssi, layer,
                 phase_listener_get_phase_id(),
                 phase_listener_get_label(),
                 (unsigned long)generated,
                 (unsigned long)forwarded,
                 (unsigned long)dropped);

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
        run_num = (uint32_t)(esp_timer_get_time() / 1000000LL);
    }

    snprintf(buf, len, "RUN_%03lu", (unsigned long)run_num);
}