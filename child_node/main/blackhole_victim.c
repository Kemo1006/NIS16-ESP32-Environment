/**
 * @file blackhole_victim.c
 * @brief Blackhole ATTACKER (relay) firmware — Milestone 2.
 *
 * TRUE RELAY MODEL (thesis §4.2.1.2 C, Milestone 2): this board is the blackhole
 * ATTACKER. Victim boards address their probe packets to THIS node's MAC (they
 * are built with BLACKHOLE_ROLE=1, which points them at BLACKHOLE_ATTACKER_MAC).
 * This node receives those probes and either:
 *   - Baseline / cooldown: FORWARDS each probe to the root (normal relay), so
 *     the root receives the victims' probes as usual.
 *   - Attack phase (PHASE_ID_BLACKHOLE): silently DROPS them — the packets
 *     vanish, so the root sees the victims' probes stop arriving during the
 *     window and resume afterwards. That drop-in-arrivals is the blackhole
 *     signature (Milestone 2: "zero forwarded probes reach the root during the
 *     attack window").
 *
 * The attacker does NOT generate its own probes; it only relays the victims'.
 * It stays a legitimate mesh participant throughout — no control-plane changes,
 * only the application-layer relay decision (forward vs drop) is altered.
 *
 * Telemetry counter mapping (shared 11-col schema, role column = "blackhole"):
 *   probes_count = probes RECEIVED from victims (climbs the whole run)
 *   tx_count     = probes FORWARDED to root (climbs baseline/cooldown, FLAT during attack)
 *   retry_count  = probes DROPPED (0 in baseline, climbs during attack; also send-fails)
 *
 * Build (selected by child_node/main/CMakeLists.txt on the flags):
 *   cd child_node && idf.py -DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=0 build flash  # THIS (attacker relay)
 *   cd child_node && idf.py -DACTIVE_ATTACK=1 -DBLACKHOLE_ROLE=1 build flash  # a victim that targets the attacker
 *   cd root_node   && idf.py -DACTIVE_ATTACK=1                    build flash  # root announces PHASE_ID_BLACKHOLE
 * Set BLACKHOLE_ATTACKER_MAC in mesh_config.h to THIS board's STA MAC (printed
 * at boot below) before building the victim boards. See BLACKHOLE-SETUP.md.
 *
 * NIS16 — CTTHES2 Milestone 2 — Blackhole Attack (relay)
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

/* Relay counters */
static volatile uint32_t s_probes_received  = 0;  /* from victims             */
static volatile uint32_t s_probes_forwarded = 0;  /* to root (non-attack)     */
static volatile uint32_t s_probes_dropped   = 0;  /* during attack + fails    */

/* Queue of received victim probes awaiting the forward/drop decision. Sized
 * generously (was 32) so a transient slow-mesh burst — e.g. the attacker
 * briefly re-scanning for its parent — doesn't overflow and force congestion
 * drops that would muddy the forwarded/dropped counters during baseline/cooldown.
 * If you still see "Relay queue full" spam, the attacker's link to the root is
 * too weak: move it closer to the root. */
static QueueHandle_t s_relay_queue = NULL;
#define RELAY_QUEUE_SIZE 128

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void relay_task(void *arg);
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/*
 * Data callback (runs in the phase-listener task context — the single
 * esp_mesh_recv reader). Every non-phase packet lands here; we keep only probe
 * packets (which the victims addressed to our MAC), copy them out, and hand
 * them to the relay task. Kept short + non-blocking per the cb contract.
 */
static void attacker_recv_cb(const uint8_t *data, size_t len,
                             const uint8_t from_addr[6])
{
    (void)from_addr;   /* the victim's MAC travels inside the probe payload */
    if (len < sizeof(probe_pkt_t)) return;

    const probe_pkt_t *pkt = (const probe_pkt_t *)data;
    if (pkt->magic != PROBE_MAGIC) return;

    s_probes_received++;
    probe_pkt_t copy = *pkt;
    if (s_relay_queue && xQueueSend(s_relay_queue, &copy, 0) != pdTRUE) {
        ESP_LOGW(TAG, "Relay queue full — dropping victim probe seq=%lu",
                 (unsigned long)copy.seq_num);
        s_probes_dropped++;
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */

void app_main(void)
{
    ESP_LOGI(TAG, "=== BLACKHOLE ATTACKER (relay) STARTING ===");

    /* ── 1. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_ATCK_B));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);
    ESP_LOGI(TAG, "This is the blackhole ATTACKER. Set BLACKHOLE_ATTACKER_MAC "
                  "on the victim boards to my STA MAC: " MACSTR,
             MAC2STR(s_self_mac));

    /* ── 2. Relay queue ──────────────────────────────────────────────────── */
    s_relay_queue = xQueueCreate(RELAY_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_relay_queue) {
        ESP_LOGE(TAG, "Failed to create relay queue");
        return;
    }

    /* ── 3. Phase listener + receive victim probes via its data dispatch ──── */
    ESP_ERROR_CHECK(phase_listener_start());
    phase_listener_set_data_cb(attacker_recv_cb);

    /* ── 4. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 5. Tasks ────────────────────────────────────────────────────────── */
    xTaskCreate(relay_task,     "bh_relay",  STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    /* Telemetry ABOVE the relay so heavy relay traffic can't starve sampling —
     * see TASK_PRIO_ATTACKER_TELEMETRY in mesh_config.h. */
    xTaskCreate(telemetry_task, "telemetry", STACK_TELEMETRY,  NULL, TASK_PRIO_ATTACKER_TELEMETRY, NULL);

    /* ── 6. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 7. Finalise ─────────────────────────────────────────────────────── */
    ESP_LOGI(TAG, "Experiment complete. Received: %lu  Forwarded: %lu  Dropped: %lu",
             (unsigned long)s_probes_received,
             (unsigned long)s_probes_forwarded,
             (unsigned long)s_probes_dropped);
    csv_logger_flush();
    csv_logger_close();
    csv_logger_start_export_task();
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Relay task
 *
 * For each probe received from a victim: forward it to the root
 * (baseline/cooldown) or DROP it (attack phase = PHASE_ID_BLACKHOLE). The probe
 * payload is forwarded verbatim, so the root logs it with the VICTIM's src_mac —
 * during the attack the root simply stops seeing that victim's probes.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void relay_task(void *arg)
{
    probe_pkt_t pkt;
    mesh_data_t mdata = {
        .data  = (uint8_t *)&pkt,
        .size  = sizeof(pkt),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    ESP_LOGI(TAG, "Relay task running.");

    while (true) {
        if (xQueueReceive(s_relay_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        if (phase_listener_get_phase_id() == PHASE_ID_BLACKHOLE) {
            /* ── BLACKHOLE: silently drop the victim's probe ─────────────── */
            s_probes_dropped++;
            ESP_LOGD(TAG, "BLACKHOLE: dropped victim probe seq=%lu",
                     (unsigned long)pkt.seq_num);
        } else {
            /* ── Normal relay: forward to root (NULL + TODS = "to root") ──── */
            esp_err_t err = esp_mesh_send(NULL, &mdata, MESH_DATA_TODS, NULL, 0);
            if (err == ESP_OK) {
                s_probes_forwarded++;
                ESP_LOGD(TAG, "Forwarded victim probe seq=%lu to root",
                         (unsigned long)pkt.seq_num);
            } else {
                s_probes_dropped++;
                ESP_LOGW(TAG, "Forward failed seq=%lu: %s",
                         (unsigned long)pkt.seq_num, esp_err_to_name(err));
            }
        }
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — cross-layer sampler
 * ═══════════════════════════════════════════════════════════════════════════ */

/* Diagnostic: time each segment of the sampling loop to find what caps the
 * attacker's sample rate (it logs ~0.6 Hz instead of the expected ~20 Hz). Set
 * to 0 to strip the overhead once the blocker is identified. The summary is
 * emitted with ESP_LOGW so it shows at the default log level, and prefixed
 * "INSTR" so it's easy to grep out of the monitor. It does NOT touch the CSV —
 * data collection is byte-for-byte identical whether this is 0 or 1. */
#define ATTACKER_TELEM_INSTRUMENT 0   /* diagnosis complete: the blocker was the
                                       * SPIFFS write (log_max hit 3–7 s) on a
                                       * ~70%-full flash. Fixed operationally by
                                       * erase-flashing the board. Left here (off)
                                       * so it's one flag-flip away if needed. */

static void telemetry_task(void *arg)
{
    ESP_LOGI(TAG, "Telemetry task running at %u ms interval.",
             SAMPLING_INTERVAL_MS);

#if ATTACKER_TELEM_INSTRUMENT
    const int WIN = 32;                 /* report every WIN samples */
    int     win_n         = 0;
    int64_t prev_start_us = 0;
    int64_t sum_period_us = 0;
    int64_t max_period_us = 0, max_body_us = 0;
    int64_t max_rssi_us = 0, max_mesh_us = 0, max_log_us = 0;
    int     slow_iters    = 0;          /* iterations with period > 150 ms */
#endif

    while (!phase_listener_is_terminated()) {
        int64_t ts = esp_timer_get_time();

#if ATTACKER_TELEM_INSTRUMENT
        if (prev_start_us != 0) {
            int64_t period = ts - prev_start_us;
            sum_period_us += period;
            if (period > max_period_us) max_period_us = period;
            if (period > 150000)        slow_iters++;
        }
        prev_start_us = ts;
#endif

        int rssi = 0;
        esp_wifi_sta_get_rssi(&rssi);
#if ATTACKER_TELEM_INSTRUMENT
        int64_t after_rssi = esp_timer_get_time();
#endif
        int layer = mesh_setup_get_layer();
        uint8_t pmac[6] = {0};
        mesh_setup_get_parent_mac(pmac);
#if ATTACKER_TELEM_INSTRUMENT
        int64_t after_mesh = esp_timer_get_time();
#endif

        uint32_t received  = s_probes_received;
        uint32_t forwarded = s_probes_forwarded;
        uint32_t dropped   = s_probes_dropped;

        csv_logger_append_telemetry(
            ts,
            s_node_id,
            "blackhole",   /* role column identifies this as the attacker */
            layer,
            pmac,
            rssi,
            dropped,       /* retry_count  = probes dropped                */
            forwarded,     /* tx_count     = probes forwarded to root      */
            received,      /* probes_count = probes received from victims  */
            phase_listener_get_phase_id(),
            phase_listener_get_label()
        );

#if ATTACKER_TELEM_INSTRUMENT
        int64_t after_log = esp_timer_get_time();
        int64_t d_rssi = after_rssi - ts;
        int64_t d_mesh = after_mesh - after_rssi;
        int64_t d_log  = after_log  - after_mesh;
        int64_t d_body = after_log  - ts;
        if (d_rssi > max_rssi_us) max_rssi_us = d_rssi;
        if (d_mesh > max_mesh_us) max_mesh_us = d_mesh;
        if (d_log  > max_log_us)  max_log_us  = d_log;
        if (d_body > max_body_us) max_body_us = d_body;
        if (++win_n >= WIN) {
            /* period ≈ body + vTaskDelay(50ms) + time preempted. So:
             *   body_max large            -> a CALL blocks (see rssi/mesh/log max)
             *   body small, period large  -> task STARVED (scheduling), not blocking */
            ESP_LOGW(TAG,
                "INSTR n=%d avg_period=%lldms max_period=%lldms body_max=%lldus | "
                "rssi_max=%lldus mesh_max=%lldus log_max=%lldus | slow(>150ms)=%d",
                win_n,
                (long long)(sum_period_us / win_n / 1000),
                (long long)(max_period_us / 1000),
                (long long)max_body_us,
                (long long)max_rssi_us, (long long)max_mesh_us, (long long)max_log_us,
                slow_iters);
            win_n = 0; sum_period_us = 0; slow_iters = 0;
            max_period_us = max_body_us = 0;
            max_rssi_us = max_mesh_us = max_log_us = 0;
        }
#endif

        ESP_LOGD(TAG,
                 "Sample: ts=%lld rssi=%d layer=%d phase=%u label=%u "
                 "recv=%lu fwd=%lu drop=%lu",
                 (long long)ts, rssi, layer,
                 phase_listener_get_phase_id(),
                 phase_listener_get_label(),
                 (unsigned long)received,
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
