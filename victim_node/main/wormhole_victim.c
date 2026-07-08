/**
 * @file wormhole_victim.c
 * @brief Combined Victim + Wormhole Attacker firmware — Milestone 2.
 *
 * The wormhole is a TWO-node colluding attack, emulated entirely at the
 * application layer (normal esp_mesh_send/esp_mesh_recv — no raw 802.11 frames,
 * per the thesis method). One board is Node A (exit / root-side), the other is
 * Node B (entry / leaf-side); the tunnel end is chosen at build time with
 * WORMHOLE_END (see mesh_config.h). This single file implements BOTH ends;
 * the endpoint-specific code is selected with `#if (WORMHOLE_END == ...)`.
 *
 * Behaviour (baseline/cooldown = ordinary victim on both ends):
 *   Node B (WORMHOLE_END_B, entry) — generates probes. During the wormhole
 *     phase it does NOT send them to the root; it encapsulates each probe in a
 *     tunnel packet and sends it to Node A (addressed by A's MAC).
 *   Node A (WORMHOLE_END_A, exit)  — during the wormhole phase it receives the
 *     tunnelled probes and RE-INJECTS the original probe to the root, so B's
 *     traffic surfaces near A: the root logs B's probes with an inflated,
 *     fabricated-shortcut latency, and both attackers show tunnel traffic.
 *
 * Telemetry counter mapping (11-col schema has retry/tx/probes — we overload
 * them the same way blackhole_victim.c overloads retry_count for drops, so the
 * attack shows a crisp phase-correlated signature without a schema change):
 *   Node B: probes_count = probes generated (steady 1 Hz),
 *           tx_count      = probes sent DIRECT to root (climbs baseline/cooldown,
 *                           FLAT during the wormhole phase),
 *           retry_count   = probes TUNNELLED to A (0 in baseline, climbs during
 *                           the wormhole phase; also counts tunnel send fails).
 *   Node A: probes_count = tunnelled probes RECEIVED from B (0 until attack),
 *           tx_count      = probes RE-INJECTED to root (0 until attack),
 *           retry_count   = re-inject send failures.
 *
 * Build (same -DACTIVE_ATTACK=2 on all three boards; end flag on attackers):
 *     cd root_node   && idf.py -DACTIVE_ATTACK=2                  build flash
 *     cd victim_node && idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=0 build flash  # A
 *     cd victim_node && idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=1 build flash  # B
 * The victim CMakeLists selects THIS file when ACTIVE_ATTACK=2; the root
 * announces PHASE_ID_WORMHOLE during the attack window (root code is generic —
 * it broadcasts whatever ACTIVE_ATTACK is, so no root edit is needed).
 *
 * NIS16 — CTTHES2 Milestone 2 — Wormhole Attack
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
#if (WORMHOLE_END == WORMHOLE_END_B)
static const char *TAG = "WORMHOLE_B";
#define WH_ROLE_STR   "wormhole_b"
#define WH_MESH_ROLE  MESH_ROLE_ATCK_WB
#else
static const char *TAG = "WORMHOLE_A";
#define WH_ROLE_STR   "wormhole_a"
#define WH_MESH_ROLE  MESH_ROLE_ATCK_WA
#endif

/* ── Probe wire format (must match root_main.c) ──────────────────────────── */
#define PROBE_MAGIC     0x50524F42U   /* "PROB" */

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t seq_num;
    int64_t  send_ts_us;
    uint8_t  src_mac[6];
} probe_pkt_t;

/* ── Tunnel wire format (A<->B only) ─────────────────────────────────────── */
typedef struct __attribute__((packed)) {
    uint32_t   magic;    /* WORMHOLE_TUNNEL_MAGIC */
    probe_pkt_t probe;   /* the captured probe, verbatim */
} tunnel_pkt_t;

/* ── Shared state ─────────────────────────────────────────────────────────── */
static char     s_node_id[NODE_ID_LEN] = {0};
static char     s_run_id[RUN_ID_LEN]   = {0};
static uint8_t  s_self_mac[6]          = {0};

#define TUNNEL_QUEUE_SIZE 32

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/* ═══════════════════════════════════════════════════════════════════════════
 * Node B — entry / leaf-side (captures probes, tunnels to A during attack)
 * ═══════════════════════════════════════════════════════════════════════════ */
#if (WORMHOLE_END == WORMHOLE_END_B)

static const uint8_t s_peer_a_mac[6] = WORMHOLE_NODE_A_MAC;

/* Counters (see file header for the telemetry mapping). */
static volatile uint32_t s_probes_generated = 0;
static volatile uint32_t s_probes_to_root   = 0;  /* direct sends (baseline)   */
static volatile uint32_t s_probes_tunneled  = 0;  /* tunnelled to A (attack)   */
static volatile uint32_t s_tunnel_fail      = 0;  /* failed sends of either    */

static QueueHandle_t s_probe_queue = NULL;

static void probe_gen_task(void *arg);
static void tunnel_forwarder_task(void *arg);

static bool peer_mac_is_placeholder(void)
{
    static const uint8_t placeholder_default[6] = {0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00};
    return memcmp(s_peer_a_mac, placeholder_default, 6) == 0;
}

void app_main(void)
{
    ESP_LOGI(TAG, "=== WORMHOLE NODE B (entry) STARTING ===");

    ESP_ERROR_CHECK(mesh_setup_init(WH_MESH_ROLE));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);
    ESP_LOGI(TAG, "Tunnel peer (Node A) MAC: " MACSTR, MAC2STR(s_peer_a_mac));
    if (peer_mac_is_placeholder()) {
        ESP_LOGW(TAG, "WORMHOLE_NODE_A_MAC is still the PLACEHOLDER — every "
                      "tunnel send will FAIL. Set it to Node A's STA MAC in "
                      "mesh_config.h and rebuild. (See WORKFLOWS.md.)");
    }

    s_probe_queue = xQueueCreate(TUNNEL_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_probe_queue) {
        ESP_LOGE(TAG, "Failed to create probe queue");
        return;
    }

    ESP_ERROR_CHECK(phase_listener_start());
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    xTaskCreate(probe_gen_task,         "probe_gen",  STACK_PROBE_GEN,  NULL, 5, NULL);
    xTaskCreate(tunnel_forwarder_task,  "wh_fwd",     STACK_PROBE_SINK, NULL, 6, NULL);
    xTaskCreate(telemetry_task,         "telemetry",  STACK_TELEMETRY,  NULL, 5, NULL);

    phase_listener_wait_for_terminate();

    ESP_LOGI(TAG, "Experiment complete. Generated: %lu  ToRoot: %lu  Tunnelled: %lu  Fail: %lu",
             (unsigned long)s_probes_generated, (unsigned long)s_probes_to_root,
             (unsigned long)s_probes_tunneled,  (unsigned long)s_tunnel_fail);
    csv_logger_flush();
    csv_logger_close();
    csv_logger_start_export_task();
}

/* Generate a probe every PROBE_INTERVAL_MS and queue it for the forwarder. */
static void probe_gen_task(void *arg)
{
    ESP_LOGI(TAG, "Probe generator running at %u ms interval.", PROBE_INTERVAL_MS);

    probe_pkt_t pkt = { .magic = PROBE_MAGIC };
    memcpy(pkt.src_mac, s_self_mac, 6);
    uint32_t seq = 0;

    while (!phase_listener_is_terminated()) {
        pkt.seq_num    = ++seq;
        pkt.send_ts_us = esp_timer_get_time();
        s_probes_generated++;

        if (xQueueSend(s_probe_queue, &pkt, pdMS_TO_TICKS(10)) != pdTRUE) {
            ESP_LOGW(TAG, "Probe queue full! seq=%lu dropped at source",
                     (unsigned long)seq);
        }
        vTaskDelay(pdMS_TO_TICKS(PROBE_INTERVAL_MS));
    }
    ESP_LOGI(TAG, "Probe generator exiting.");
    vTaskDelete(NULL);
}

/*
 * Forwarder: baseline/cooldown → send probe DIRECT to root (to=NULL + TODS, the
 * proven data-plane path). Wormhole phase → wrap the probe in a tunnel packet
 * and P2P-unicast it to Node A's MAC instead. The root never sees B's probes
 * during the attack; A re-injects them.
 */
static void tunnel_forwarder_task(void *arg)
{
    probe_pkt_t pkt;

    /* Direct-to-root descriptor (baseline/cooldown). */
    mesh_data_t root_data = {
        .size  = sizeof(probe_pkt_t),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    /* Tunnel-to-A descriptor (wormhole phase). */
    tunnel_pkt_t tp = { .magic = WORMHOLE_TUNNEL_MAGIC };
    mesh_data_t tunnel_data = {
        .data  = (uint8_t *)&tp,
        .size  = sizeof(tp),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };
    mesh_addr_t peer_a = {0};
    memcpy(peer_a.addr, s_peer_a_mac, 6);

    ESP_LOGI(TAG, "Tunnel forwarder running.");

    while (true) {
        if (xQueueReceive(s_probe_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        if (phase_listener_get_phase_id() == PHASE_ID_WORMHOLE) {
            /* ── WORMHOLE: tunnel the probe to Node A ─────────────────────── */
            tp.probe = pkt;
            esp_err_t err = esp_mesh_send(&peer_a, &tunnel_data,
                                          MESH_DATA_P2P, NULL, 0);
            if (err == ESP_OK) {
                s_probes_tunneled++;
                ESP_LOGD(TAG, "Tunnelled probe seq=%lu -> " MACSTR,
                         (unsigned long)pkt.seq_num, MAC2STR(s_peer_a_mac));
            } else {
                s_tunnel_fail++;
                ESP_LOGW(TAG, "Tunnel send failed seq=%lu: %s",
                         (unsigned long)pkt.seq_num, esp_err_to_name(err));
            }
        } else {
            /* ── NORMAL: send the probe direct to root ────────────────────── */
            root_data.data = (uint8_t *)&pkt;
            esp_err_t err = esp_mesh_send(NULL, &root_data,
                                          MESH_DATA_TODS, NULL, 0);
            if (err == ESP_OK) {
                s_probes_to_root++;
            } else {
                s_tunnel_fail++;
                ESP_LOGW(TAG, "Direct send failed seq=%lu: %s",
                         (unsigned long)pkt.seq_num, esp_err_to_name(err));
            }
        }
    }
}

#else  /* ═══════════════════════════════════════════════════════════════════
        * Node A — exit / root-side (receives tunnelled probes, re-injects)
        * ═══════════════════════════════════════════════════════════════════ */

/* Counters (see file header for the telemetry mapping). */
static volatile uint32_t s_tunnel_received   = 0;  /* from B (attack)          */
static volatile uint32_t s_probes_reinjected = 0;  /* re-sent to root (attack) */
static volatile uint32_t s_reinject_fail     = 0;  /* failed re-injects        */

static QueueHandle_t s_reinject_queue = NULL;

static void reinject_task(void *arg);

/*
 * Data callback (runs in the phase-listener task): every non-phase packet lands
 * here. We keep only WORMHOLE_TUNNEL_MAGIC packets, copy out the inner probe,
 * and hand it to the re-inject task. Kept short and non-blocking per the
 * phase_listener_set_data_cb contract.
 */
static void tunnel_recv_cb(const uint8_t *data, size_t len, const uint8_t from_addr[6])
{
    (void)from_addr;
    if (len < sizeof(tunnel_pkt_t)) return;

    const tunnel_pkt_t *tp = (const tunnel_pkt_t *)data;
    if (tp->magic != WORMHOLE_TUNNEL_MAGIC) return;
    if (tp->probe.magic != PROBE_MAGIC)     return;

    s_tunnel_received++;
    probe_pkt_t inner = tp->probe;
    if (s_reinject_queue &&
        xQueueSend(s_reinject_queue, &inner, 0) != pdTRUE) {
        ESP_LOGW(TAG, "Re-inject queue full — dropping tunnelled seq=%lu",
                 (unsigned long)inner.seq_num);
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "=== WORMHOLE NODE A (exit) STARTING ===");

    ESP_ERROR_CHECK(mesh_setup_init(WH_MESH_ROLE));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);
    ESP_LOGI(TAG, "This is Node A (exit). My STA MAC (set as WORMHOLE_NODE_A_MAC "
                  "on Node B): " MACSTR, MAC2STR(s_self_mac));

    s_reinject_queue = xQueueCreate(TUNNEL_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_reinject_queue) {
        ESP_LOGE(TAG, "Failed to create re-inject queue");
        return;
    }

    ESP_ERROR_CHECK(phase_listener_start());
    phase_listener_set_data_cb(tunnel_recv_cb);   /* receive tunnelled probes */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    xTaskCreate(reinject_task, "wh_reinject", STACK_PROBE_SINK, NULL, 6, NULL);
    xTaskCreate(telemetry_task, "telemetry",  STACK_TELEMETRY,  NULL, 5, NULL);

    phase_listener_wait_for_terminate();

    ESP_LOGI(TAG, "Experiment complete. Received: %lu  Re-injected: %lu  Fail: %lu",
             (unsigned long)s_tunnel_received, (unsigned long)s_probes_reinjected,
             (unsigned long)s_reinject_fail);
    csv_logger_flush();
    csv_logger_close();
    csv_logger_start_export_task();
}

/*
 * Re-inject task: for each tunnelled probe from B, re-send the ORIGINAL probe
 * to the root (to=NULL + TODS). The payload keeps B's src_mac and B's original
 * send timestamp, so the root logs the probe as B's — but with the inflated
 * latency of the whole tunnel round-trip. That latency anomaly, plus the tunnel
 * traffic on A and B, is the wormhole signature.
 */
static void reinject_task(void *arg)
{
    probe_pkt_t pkt;
    mesh_data_t mdata = {
        .data  = (uint8_t *)&pkt,
        .size  = sizeof(pkt),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    ESP_LOGI(TAG, "Re-inject task running.");

    while (true) {
        if (xQueueReceive(s_reinject_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        esp_err_t err = esp_mesh_send(NULL, &mdata, MESH_DATA_TODS, NULL, 0);
        if (err == ESP_OK) {
            s_probes_reinjected++;
            ESP_LOGD(TAG, "Re-injected probe src=" MACSTR " seq=%lu",
                     MAC2STR(pkt.src_mac), (unsigned long)pkt.seq_num);
        } else {
            s_reinject_fail++;
            ESP_LOGW(TAG, "Re-inject failed seq=%lu: %s",
                     (unsigned long)pkt.seq_num, esp_err_to_name(err));
        }
    }
}

#endif  /* WORMHOLE_END */

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — 1 Hz cross-layer sampler (both ends)
 *
 * Uses the shared 11-col schema. The retry/tx/probes columns carry the
 * endpoint-specific counters described in the file header, so the wormhole
 * shows a phase-correlated signature the pipeline can pick up without any
 * schema change.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void telemetry_task(void *arg)
{
    ESP_LOGI(TAG, "Telemetry task running at %u ms interval.", SAMPLING_INTERVAL_MS);

    while (!phase_listener_is_terminated()) {
        int64_t ts = esp_timer_get_time();

        int rssi = 0;
        esp_wifi_sta_get_rssi(&rssi);
        int layer = mesh_setup_get_layer();
        uint8_t pmac[6] = {0};
        mesh_setup_get_parent_mac(pmac);

#if (WORMHOLE_END == WORMHOLE_END_B)
        uint32_t retry_col  = s_probes_tunneled;   /* attack-phase tunnel count */
        uint32_t tx_col     = s_probes_to_root;    /* direct sends (baseline)   */
        uint32_t probes_col = s_probes_generated;
#else
        uint32_t retry_col  = s_reinject_fail;
        uint32_t tx_col     = s_probes_reinjected; /* re-injected to root       */
        uint32_t probes_col = s_tunnel_received;   /* received from B           */
#endif

        csv_logger_append_telemetry(
            ts,
            s_node_id,
            WH_ROLE_STR,
            layer,
            pmac,
            rssi,
            retry_col,
            tx_col,
            probes_col,
            phase_listener_get_phase_id(),
            phase_listener_get_label()
        );

        ESP_LOGD(TAG, "Sample: ts=%lld rssi=%d layer=%d phase=%u label=%u "
                      "retry=%lu tx=%lu probes=%lu",
                 (long long)ts, rssi, layer,
                 phase_listener_get_phase_id(), phase_listener_get_label(),
                 (unsigned long)retry_col, (unsigned long)tx_col,
                 (unsigned long)probes_col);

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
