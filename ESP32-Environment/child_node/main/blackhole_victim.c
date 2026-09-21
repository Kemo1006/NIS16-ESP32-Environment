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
#include "sd_status.h"
#include "node_identity.h"
#include "blackhole_target.h"
#include "probe_relay.h"
#include "nvs.h"

/* ── Module tag ──────────────────────────────────────────────────────────── */
static const char *TAG = "BLACKHOLE";

/* Probe wire format + the relay itself now come from probe_relay.h (C7 Option
 * 1). This file used to own a private copy of both. */

/* ── Shared state ─────────────────────────────────────────────────────────── */
static char     s_node_id[NODE_ID_LEN] = {0};
static char     s_run_id[RUN_ID_LEN]   = {0};
static uint8_t  s_self_mac[6]          = {0};

/* C7 Option 1: the relay, its queue, its counters and its task all moved to
 * components/mesh_common/src/probe_relay.c, which every node now runs. THIS
 * FILE'S ONLY REMAINING DIFFERENCE FROM AN HONEST NODE IS THE FUNCTION BELOW.
 *
 * That is the point, and it is worth stating in the paper: the attacker is
 * byte-for-byte an ordinary relay except for a single boolean decision. There
 * is no separate attack path, no special addressing, no control-plane change -
 * exactly the "stays protocol-compliant at PHY/MAC" criterion in
 * docs/ATTACK-VALIDATION.md, now true by construction rather than by argument.
 */

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);

/**
 * The entire blackhole. Returns false to DROP, true to forward.
 *
 * Suppression is active exactly while the root is announcing PHASE_ID_BLACKHOLE
 * - paper Table 4.2's `suppression_active` flag, which is set when phase 1 is
 * received and cleared at phase 3. probe_relay.c counts the dropped packet in
 * drop_count (Table 4.2's `drop_counter`); nothing else about this node's
 * behaviour changes.
 */
static bool blackhole_forward_decision(const probe_pkt_t *pkt)
{
    if (phase_listener_get_phase_id() == PHASE_ID_BLACKHOLE) {
        ESP_LOGD(TAG, "BLACKHOLE: dropping probe seq=%lu",
                 (unsigned long)pkt->seq_num);
        return false;
    }
    return true;
}

/* Runs in the phase-listener task (the single esp_mesh_recv reader). Identical
 * to the honest victim's callback - the divergence is the decision hook above. */
static void attacker_recv_cb(const uint8_t *data, size_t len,
                             const uint8_t from_addr[6])
{
    (void)from_addr;
    probe_relay_ingest(data, len);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */

void app_main(void)
{
    ESP_LOGI(TAG, "=== BLACKHOLE ATTACKER (relay) STARTING ===");

    /* ── 0. SD environment check (non-fatal; telemetry stays on SPIFFS) ───── */
    sd_status_result_t sdres = sd_status_run_boot_check();
    if (sdres == SD_STATUS_OK) {
        ESP_LOGI(TAG, "SD ENV: OK -- %s", sd_status_report_path());
    } else {
        ESP_LOGE(TAG, "SD ENV: %s -- RUN CONTINUES, SPIFFS logging unaffected",
                 sd_status_result_str(sdres));
    }

    /* ── 0b. Identity (nickname). Must follow the SD boot check, which caches
     *        node_config.txt while the card is still mounted. ─────────────── */
    node_identity_resolve(NODE_ROLE_BLACKHOLE);

    /* ── 1. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_ATCK_B));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);
    ESP_LOGI(TAG, "This is the blackhole ATTACKER. Set BLACKHOLE_ATTACKER_MAC "
                  "on the victim boards to my STA MAC: " MACSTR,
             MAC2STR(s_self_mac));

    /* Loud pre-flight: victims send their probes P2P to whatever MAC was
     * COMPILED INTO THEM as BLACKHOLE_ATTACKER_MAC. If that is not this board,
     * every probe is addressed to a node that isn't here: the root logs zero
     * arrivals in EVERY phase, arrivals.csv comes out header-only, and BOTH
     * primary features (PDR and ForwardingRatio) are 100% NaN — while every
     * board still looks perfectly healthy. That exact silent failure cost a
     * full run on 2026-09-15 and again on 2026-09-16, so it is checked here
     * rather than discovered at analysis time 11 minutes later.
     *
     * This board can only warn: the stale value lives in the VICTIMS' firmware,
     * so the fix is always to re-flash them (the wizard patches mesh_config.h
     * for you, but only when you actually build/flash through it). */
    {
        /* F2: check the EFFECTIVE target (NVS override if one is set, else the
         * compiled constant) — checking the compiled constant alone would now
         * warn about a mismatch the victims have already been told to ignore,
         * and stay silent about a bad NVS value that actually would break the
         * run. The attacker resolves it the same way a victim does, so this
         * compares like with like. */
        uint8_t configured[6] = {0};
        bh_target_source_t src = blackhole_target_get(configured);
        if (memcmp(configured, s_self_mac, 6) != 0) {
            ESP_LOGE(TAG, "***********************************************************");
            ESP_LOGE(TAG, "***   ATTACKER MAC MISMATCH  —  RUN WILL BE EMPTY        ***");
            ESP_LOGE(TAG, "***********************************************************");
            ESP_LOGE(TAG, "  effective target MAC (%-8s): " MACSTR,
                     blackhole_target_source_str(src), MAC2STR(configured));
            ESP_LOGE(TAG, "  my actual STA MAC (the attacker): " MACSTR, MAC2STR(s_self_mac));
            ESP_LOGE(TAG, "  Victims are targeting a board that is NOT this one, so their");
            ESP_LOGE(TAG, "  probes reach nobody. Root will log ZERO arrivals and PDR +");
            ESP_LOGE(TAG, "  ForwardingRatio will be entirely NaN.");
            ESP_LOGE(TAG, "  FIX (no re-flash): send each victim over serial");
            ESP_LOGE(TAG, "       SET_ATTACKER_MAC=" MACSTR, MAC2STR(s_self_mac));
            ESP_LOGE(TAG, "       then power-cycle them. run.ps1 -AttackerMac does this for you.");
            ESP_LOGE(TAG, "  FIX (old way): point BLACKHOLE_ATTACKER_MAC at that MAC and");
            ESP_LOGE(TAG, "       re-flash every victim board. ABORT THIS RUN NOW.");
            ESP_LOGE(TAG, "***********************************************************");
        } else {
            ESP_LOGI(TAG, "Attacker MAC (%s) matches this board — victims will reach me.",
                     blackhole_target_source_str(src));
        }
    }

    /* ── 2. Phase listener + the SHARED relay, with our drop hook ────────── */
    ESP_ERROR_CHECK(phase_listener_start());
    /* Same relay every honest node runs; the only difference is the decision
     * callback. See blackhole_forward_decision() above. */
    ESP_ERROR_CHECK(probe_relay_start(blackhole_forward_decision));
    phase_listener_set_data_cb(attacker_recv_cb);

    /* ── 4. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 5. Tasks (the relay task is started by probe_relay_start above) ─── */
    ESP_ERROR_CHECK(heartbeat_start());
    /* Telemetry ABOVE the relay so heavy relay traffic can't starve sampling —
     * see TASK_PRIO_ATTACKER_TELEMETRY in mesh_config.h. */
    xTaskCreate(telemetry_task, "telemetry", STACK_TELEMETRY,  NULL, TASK_PRIO_ATTACKER_TELEMETRY, NULL);

    /* ── 6. Block until experiment ends ──────────────────────────────────── */
    phase_listener_wait_for_terminate();

    /* ── 7. Finalise ─────────────────────────────────────────────────────── */
    ESP_LOGI(TAG, "Experiment complete. Received: %lu  Forwarded: %lu  Dropped: %lu",
             (unsigned long)probe_relay_recv_count(),
             (unsigned long)probe_relay_forward_count(),
             (unsigned long)probe_relay_drop_count());
    csv_logger_flush();
    csv_logger_close();
    csv_logger_start_export_task();
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

        /* All four now come from the shared relay (probe_relay.c), which is
         * the same code every honest node runs. */
        uint32_t received  = probe_relay_recv_count();
        uint32_t forwarded = probe_relay_forward_count();
        uint32_t dropped   = probe_relay_drop_count();
        uint32_t send_fail = probe_relay_send_fail_count();

        csv_logger_append_telemetry(
            ts,
            s_node_id,
            "blackhole",   /* role column identifies this as the attacker */
            layer,
            pmac,
            rssi,
            /* F3: retry_count is now send FAILURES only, the same meaning it
             * carries on every other role. It used to be handed `dropped`, so
             * the attacker's deliberate drops were filed in a MAC-sounding
             * column — the leak that made RetryRate go 0.0033 -> 0.9991 on this
             * one board while every victim went to 0.0000, and the concrete
             * form of the panel's single-feature objection. The drops now have
             * their own column below, where they read as what they are:
             * attacker-side ground truth, not a measurement of the network. */
            send_fail,     /* retry_count  = failed esp_mesh_send() calls   */
            forwarded,     /* tx_count     = probes forwarded to root       */
            received,      /* probes_count = probes received from victims   */
            phase_listener_get_phase_id(),
            phase_listener_get_label(),
            /* F3 relay counters — same meaning as on every other role. This
             * board genuinely IS a relay, so unlike a victim its values are
             * real: recv > 0 is what makes ForwardingRatio defined here. */
            received,      /* recv_count    = frames accepted for relay     */
            forwarded,     /* forward_count = frames passed on              */
            dropped        /* drop_count    = accepted and not passed on    */
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
