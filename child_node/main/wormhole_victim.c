/**
 * @file wormhole_victim.c
 * @brief Combined Victim + Wormhole Attacker firmware — Milestone 2.
 *
 * The wormhole is a TWO-node colluding attack. Mesh traffic (probes to root,
 * phase broadcasts) still goes over normal esp_mesh_send/esp_mesh_recv — no
 * raw 802.11 frames are touched there. The A<->B tunnel itself, however, is a
 * PHYSICAL WIRED UART1 LINK directly between the two attacker boards
 * (see WORMHOLE_UART_* in mesh_config.h and wormhole_uart_init() below) — that
 * out-of-band, non-wireless channel is what makes this a wormhole rather than
 * ordinary mesh forwarding, per Milestone 2 and the thesis's Figure 4.9. One
 * board is Node A (exit / root-side), the other is Node B (entry / leaf-side);
 * the tunnel end is chosen at build time with WORMHOLE_END (see
 * mesh_config.h). This single file implements BOTH ends; the endpoint-specific
 * code is selected with `#if (WORMHOLE_END == ...)`.
 *
 * Behaviour (baseline/cooldown = ordinary victim on both ends):
 *   Node B (WORMHOLE_END_B, entry) — generates probes and ALWAYS forwards each
 *     one to the root over the mesh (the "slow"/normal copy). During the
 *     wormhole phase it ADDITIONALLY wraps each probe in a CRC32-protected frame
 *     and writes it out the wired UART link to Node A.
 *   Node A (WORMHOLE_END_A, exit)  — during the wormhole phase it reads tunnel
 *     frames off the wired UART link, validates their CRC, and RE-INJECTS the
 *     probe to the root as a SECOND ("fast") copy, tagged PROBE_MAGIC_WORMHOLE
 *     so the root can tell it apart from the normal copy and NOT de-dup it.
 *     The root therefore logs the same seq TWICE during the attack — once via
 *     B's normal mesh path, once via the tunnel — with a measurable latency
 *     mismatch. That duplicate + latency mismatch IS the wormhole signature
 *     (Milestone 2 / thesis Fig 4.10, §4.2.1.3 J).
 *
 * Telemetry counter mapping (11-col schema has retry/tx/probes — we overload
 * them the same way blackhole_victim.c overloads retry_count for drops, so the
 * attack shows a crisp phase-correlated signature without a schema change):
 *   Node B: probes_count = probes generated (steady 1 Hz),
 *           tx_count      = probes forwarded DIRECT to root (climbs the WHOLE
 *                           run — B always sends the normal copy),
 *           retry_count   = probes ALSO TUNNELLED to A (0 in baseline, climbs
 *                           during the wormhole phase; also counts UART fails).
 *   Node A: probes_count = tunnelled probes RECEIVED from B over UART (0 until attack),
 *           tx_count      = probes RE-INJECTED to root as the fast copy (0 until attack),
 *           retry_count   = re-inject send failures.
 *
 * Build (same -DACTIVE_ATTACK=2 on all three boards; end flag on attackers):
 *     cd root_node   && idf.py -DACTIVE_ATTACK=2                  build flash
 *     cd child_node && idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=0 build flash  # A
 *     cd child_node && idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=1 build flash  # B
 * The victim CMakeLists selects THIS file when ACTIVE_ATTACK=2; the root
 * announces PHASE_ID_WORMHOLE during the attack window (root code is generic —
 * it broadcasts whatever ACTIVE_ATTACK is, so no root edit is needed).
 *
 * NIS16 — CTTHES2 Milestone 2 — Wormhole Attack
 */

#include <stdio.h>
#include <string.h>
#include <stddef.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "esp_log.h"
#include "esp_mesh.h"
#include "esp_wifi.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "esp_rom_crc.h"
#include "driver/uart.h"

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
#define PROBE_MAGIC          0x50524F42U   /* "PROB" — normal probe            */
/* Second magic that Node A stamps on the tunnel-reinjected ("fast") copy so
 * the root recognises it as the wormhole duplicate and does NOT de-dup it
 * against B's normal copy. Must match root_main.c. ("PROW") */
#define PROBE_MAGIC_WORMHOLE 0x50524F57U

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t seq_num;
    int64_t  send_ts_us;
    uint8_t  src_mac[6];
} probe_pkt_t;

/* ── Tunnel wire format (A<->B UART link only — thesis Figure 4.9) ────────── */
typedef struct __attribute__((packed)) {
    uint32_t    magic;   /* WORMHOLE_TUNNEL_MAGIC                              */
    probe_pkt_t probe;   /* the captured probe, verbatim                       */
    uint32_t    crc;     /* CRC32 over magic+probe — detects UART bit errors,
                           * per Milestone 2's "CRC-protected" requirement      */
} tunnel_pkt_t;

/* ── Shared state ─────────────────────────────────────────────────────────── */
static char     s_node_id[NODE_ID_LEN] = {0};
static char     s_run_id[RUN_ID_LEN]   = {0};
static uint8_t  s_self_mac[6]          = {0};

#define TUNNEL_QUEUE_SIZE 32

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/*
 * Shared by both ends: bring up the physical UART1 link used as the wormhole's
 * out-of-band tunnel (Milestone 2 requirement). This is a SEPARATE port from
 * UART0 (console / csv_logger's serial-export task), and a separate physical
 * cable from the USB connection to your laptop — it only ever talks to the
 * other attacker board, wired directly GPIO-to-GPIO.
 */
static void wormhole_uart_init(void)
{
    const uart_config_t uart_cfg = {
        .baud_rate  = WORMHOLE_UART_BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    ESP_ERROR_CHECK(uart_driver_install(WORMHOLE_UART_PORT, 512, 512, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(WORMHOLE_UART_PORT, &uart_cfg));
    ESP_ERROR_CHECK(uart_set_pin(WORMHOLE_UART_PORT,
                                  WORMHOLE_UART_TX_PIN, WORMHOLE_UART_RX_PIN,
                                  UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    ESP_LOGI(TAG, "Wormhole UART tunnel ready: UART%d  TX=GPIO%d  RX=GPIO%d  %d baud",
             WORMHOLE_UART_PORT, WORMHOLE_UART_TX_PIN, WORMHOLE_UART_RX_PIN,
             WORMHOLE_UART_BAUD);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Node B — entry / leaf-side (captures probes, tunnels to A during attack)
 * ═══════════════════════════════════════════════════════════════════════════ */
#if (WORMHOLE_END == WORMHOLE_END_B)

/* Counters (see file header for the telemetry mapping). */
static volatile uint32_t s_probes_generated = 0;
static volatile uint32_t s_probes_to_root   = 0;  /* direct sends (baseline)   */
static volatile uint32_t s_probes_tunneled  = 0;  /* tunnelled to A (attack)   */
static volatile uint32_t s_tunnel_fail      = 0;  /* failed sends of either    */

static QueueHandle_t s_probe_queue = NULL;

static void probe_gen_task(void *arg);
static void tunnel_forwarder_task(void *arg);

void app_main(void)
{
    ESP_LOGI(TAG, "=== WORMHOLE NODE B (entry) STARTING ===");

    ESP_ERROR_CHECK(mesh_setup_init(WH_MESH_ROLE));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);
    wormhole_uart_init();

    s_probe_queue = xQueueCreate(TUNNEL_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_probe_queue) {
        ESP_LOGE(TAG, "Failed to create probe queue");
        return;
    }

    ESP_ERROR_CHECK(phase_listener_start());
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    xTaskCreate(probe_gen_task,         "probe_gen",  STACK_PROBE_GEN,  NULL, TASK_PRIO_PROBE_GEN,  NULL);
    xTaskCreate(tunnel_forwarder_task,  "wh_fwd",     STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    /* Telemetry ABOVE the tunnel forwarder so it isn't starved — see
     * TASK_PRIO_ATTACKER_TELEMETRY in mesh_config.h. */
    xTaskCreate(telemetry_task,         "telemetry",  STACK_TELEMETRY,  NULL, TASK_PRIO_ATTACKER_TELEMETRY, NULL);

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
 * Forwarder: baseline/cooldown → send probe DIRECT to root over the mesh
 * (to=NULL + TODS, the proven data-plane path). Wormhole phase → wrap the
 * probe in a tunnel packet, CRC it, and write it out the wired UART link to
 * Node A — NOT the mesh. That physical separation from the wireless path is
 * what makes this a wormhole shortcut rather than ordinary forwarding. The
 * root never sees B's probes over the mesh during the attack; A re-injects
 * them after receiving them over UART.
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

    /* Tunnel-to-A frame (wormhole phase) — sent over UART1, not the mesh. */
    tunnel_pkt_t tp = { .magic = WORMHOLE_TUNNEL_MAGIC };

    ESP_LOGI(TAG, "Tunnel forwarder running.");

    while (true) {
        if (xQueueReceive(s_probe_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        /* ── Step 1: ALWAYS forward the probe to root over the mesh ────────
         * This is the normal "slow" copy the root receives in every phase.
         * During the attack it becomes the first of the two duplicate
         * arrivals (the tunnel copy from A is the second). */
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

        /* ── Step 2: during the wormhole phase, ADDITIONALLY tunnel the probe
         * to Node A over the wired UART. A re-injects it as the "fast" copy,
         * so root gets the same seq twice with a latency mismatch. */
        if (phase_listener_get_phase_id() == PHASE_ID_WORMHOLE) {
            tp.probe = pkt;
            tp.crc = esp_rom_crc32_le(0, (const uint8_t *)&tp,
                                       offsetof(tunnel_pkt_t, crc));
            int written = uart_write_bytes(WORMHOLE_UART_PORT,
                                            (const char *)&tp, sizeof(tp));
            if (written == (int)sizeof(tp)) {
                s_probes_tunneled++;
                ESP_LOGD(TAG, "Tunnelled probe seq=%lu -> Node A via UART",
                         (unsigned long)pkt.seq_num);
            } else {
                s_tunnel_fail++;
                ESP_LOGW(TAG, "UART tunnel send failed seq=%lu (wrote %d/%u bytes)",
                         (unsigned long)pkt.seq_num, written, (unsigned)sizeof(tp));
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
static void uart_tunnel_rx_task(void *arg);

/*
 * UART tunnel receiver: reassembles tunnel_pkt_t frames off the wired UART1
 * link from Node B (NOT the mesh — see wormhole_uart_init() and mesh_config.h),
 * validating magic + CRC32 to reject corrupted/garbage frames (Milestone 2's
 * "CRC-protected to detect errors") before handing the inner probe to the
 * re-inject task.
 *
 * SELF-RESYNCHRONISING: a raw UART link has no packet boundaries, so a single
 * dropped/spurious byte (loose jumper, noise) would otherwise misalign every
 * subsequent frame forever. When a full-frame window fails validation we slide
 * the buffer forward ONE byte and retry, so the receiver re-locks onto the next
 * real frame instead of staying permanently desynced.
 */
static void uart_tunnel_rx_task(void *arg)
{
    tunnel_pkt_t tp;
    uint8_t *buf = (uint8_t *)&tp;
    size_t   got = 0;

    ESP_LOGI(TAG, "UART tunnel receiver running.");

    while (true) {
        /* Top up the buffer to a full frame's worth of bytes. */
        int n = uart_read_bytes(WORMHOLE_UART_PORT, buf + got,
                                 sizeof(tp) - got, pdMS_TO_TICKS(100));
        if (n <= 0) {
            continue;
        }
        got += (size_t)n;
        if (got < sizeof(tp)) {
            continue;   /* wait for the rest of this frame */
        }

        /* Validate the assembled window: both magics AND the CRC32 must match. */
        uint32_t crc = esp_rom_crc32_le(0, buf, offsetof(tunnel_pkt_t, crc));
        bool valid = (tp.magic == WORMHOLE_TUNNEL_MAGIC) &&
                     (tp.probe.magic == PROBE_MAGIC) &&
                     (crc == tp.crc);

        if (valid) {
            s_tunnel_received++;
            probe_pkt_t inner = tp.probe;
            if (s_reinject_queue &&
                xQueueSend(s_reinject_queue, &inner, 0) != pdTRUE) {
                ESP_LOGW(TAG, "Re-inject queue full — dropping tunnelled seq=%lu",
                         (unsigned long)inner.seq_num);
            }
            got = 0;    /* consumed a good frame — start the next one fresh */
        } else {
            /* Bad window: drop the oldest byte and slide the rest down, so the
             * next uart_read_bytes() only tops up by 1 and we re-test at the
             * next byte offset until magic+CRC re-align. */
            ESP_LOGD(TAG, "UART tunnel: window invalid (magic/CRC) — resyncing");
            memmove(buf, buf + 1, sizeof(tp) - 1);
            got = sizeof(tp) - 1;
        }
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
    wormhole_uart_init();

    s_reinject_queue = xQueueCreate(TUNNEL_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_reinject_queue) {
        ESP_LOGE(TAG, "Failed to create re-inject queue");
        return;
    }

    ESP_ERROR_CHECK(phase_listener_start());
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    xTaskCreate(uart_tunnel_rx_task, "wh_uart_rx", STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    xTaskCreate(reinject_task,  "wh_reinject", STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    /* Telemetry ABOVE the tunnel RX/reinject tasks so it isn't starved — see
     * TASK_PRIO_ATTACKER_TELEMETRY in mesh_config.h. */
    xTaskCreate(telemetry_task, "telemetry",   STACK_TELEMETRY,  NULL, TASK_PRIO_ATTACKER_TELEMETRY, NULL);

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
        /* Tag this as the tunnel ("fast") copy: root recognises PROBE_MAGIC_WORMHOLE
         * and logs it as a SECOND arrival for the same (src_mac, seq_num) instead
         * of de-duping it against B's normal copy. src_mac and seq_num stay B's,
         * so the two rows correlate — same probe, two latencies. */
        pkt.magic = PROBE_MAGIC_WORMHOLE;
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
