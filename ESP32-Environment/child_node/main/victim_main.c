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
 * Build target: child_node/
 *
 * NIS16 — CTTHES2 Milestone 1
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
#include "sd_status.h"
#include "node_identity.h"
#include "blackhole_target.h"
#include "probe_relay.h"
#include "nvs.h"

/* ── Module tag ──────────────────────────────────────────────────────────── */
static const char *TAG = "VICTIM_MAIN";

/* Probe wire format and the relay itself now live in probe_relay.h/.c, shared
 * by every role. It used to be copy-pasted into this file, blackhole_victim.c,
 * wormhole_victim.c and root_main.c independently — four copies of one wire
 * format that had to be kept byte-identical by hand. */

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

/* Runs in the phase-listener task (the single esp_mesh_recv reader). Every
 * non-phase packet lands here; probe_relay_ingest keeps probes and ignores
 * anything else, so passing everything through is safe. Kept short and
 * non-blocking per the data-callback contract. */
static void victim_recv_cb(const uint8_t *data, size_t len,
                           const uint8_t from_addr[6])
{
    (void)from_addr;   /* the originator travels inside the probe payload */
    probe_relay_ingest(data, len);
}

static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);
#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_BURST)
static bool send_probe(probe_pkt_t *pkt, uint32_t *seq);
static void fire_burst(probe_pkt_t *pkt, uint32_t *seq);
#endif

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main
 * ═══════════════════════════════════════════════════════════════════════════ */

void app_main(void)
{
    ESP_LOGI(TAG, "=== VICTIM NODE STARTING ===");

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
    node_identity_resolve(NODE_ROLE_VICTIM);

    /* ── 1. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_VICTIM));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);

    /* ── 2. Phase listener + hop-by-hop relay ────────────────────────────── */
    ESP_ERROR_CHECK(phase_listener_start());

    /* C7 Option 1: an honest node is now a RELAY as well as a source. It
     * forwards every probe its children send up toward the root, and counts
     * what it carries — which is what finally makes ForwardingRatio a real
     * distribution across all nodes instead of a single attacker-only value.
     * NULL decision = always forward (only the blackhole installs a hook). */
    ESP_ERROR_CHECK(probe_relay_start(NULL));
    phase_listener_set_data_cb(victim_recv_cb);

    /* ── 3. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 4. Start tasks ──────────────────────────────────────────────────── */
    xTaskCreate(probe_gen_task,  "probe_gen",  STACK_PROBE_GEN,
                NULL, TASK_PRIO_PROBE_GEN,  NULL);
    xTaskCreate(telemetry_task,  "telemetry",  STACK_TELEMETRY,
                NULL, TASK_PRIO_TELEMETRY,  NULL);
    ESP_ERROR_CHECK(heartbeat_start());

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

#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_BURST)
/* ═══════════════════════════════════════════════════════════════════════════
 * Burst traffic profile (TRAFFIC_PROFILE=1) — panel scenario: "a user node
 * sends 100 packets to root", to see whether the detector can tell a legit
 * burst apart from a blackhole/wormhole run. This board is built with
 * -DTRAFFIC_PROFILE=1 because run.ps1 -Scenario burst -ScenarioTarget picked
 * it as the sender; every other board on the run is a plain build.
 * ═══════════════════════════════════════════════════════════════════════════ */

/* Send one probe over the SAME path the regular loop below uses (root direct,
 * or via the attacker for a blackhole victim). Retries a bounded number of
 * times on a full mesh TX queue (ESP_ERR_MESH_QUEUE_FULL) so a fast burst
 * doesn't just fail outright — see BURST_GAP_MS / BURST_QUEUE_RETRY in
 * mesh_config.h. Returns true on success; failures still count into
 * s_retry_count, same as the normal loop. */
static bool send_probe(probe_pkt_t *pkt, uint32_t *seq)
{
    pkt->seq_num    = ++(*seq);
    pkt->send_ts_us = esp_timer_get_time();

    esp_err_t err;
    for (int attempt = 0; ; attempt++) {
        /* C7 Option 1: to our parent, hop by hop (paper 3.1.3.2). */
        err = probe_relay_send_own(pkt);
        if (err != ESP_ERR_MESH_QUEUE_FULL || attempt >= BURST_QUEUE_RETRY) {
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(2 * BURST_GAP_MS));
    }

    if (err == ESP_OK) {
        s_probes_sent++;
        s_tx_count++;
        return true;
    }
    s_retry_count++;
    ESP_LOGW(TAG, "BURST: probe send failed seq=%lu: %s",
             (unsigned long)pkt->seq_num, esp_err_to_name(err));
    return false;
}

/* Fire BURST_COUNT probes back-to-back (BURST_GAP_MS apart). One-shot — called
 * exactly once per boot, when the attack-length window opens. */
static void fire_burst(probe_pkt_t *pkt, uint32_t *seq)
{
    uint32_t first_seq = *seq + 1;
    uint32_t ok        = 0;
    int64_t  t0        = esp_timer_get_time();

    ESP_LOGW(TAG, "BURST: firing %u probes (starting seq=%lu, gap=%u ms)",
             BURST_COUNT, (unsigned long)first_seq, BURST_GAP_MS);

    for (uint32_t n = 0; n < BURST_COUNT; n++) {
        if (send_probe(pkt, seq)) {
            ok++;
        }
        vTaskDelay(pdMS_TO_TICKS(BURST_GAP_MS));
    }

    ESP_LOGW(TAG, "BURST: done - %lu/%u sent ok in %lld ms (seq %lu..%lu)",
             (unsigned long)ok, BURST_COUNT,
             (long long)((esp_timer_get_time() - t0) / 1000),
             (unsigned long)first_seq, (unsigned long)*seq);
}
#endif /* TRAFFIC_PROFILE_BURST */

/* ═══════════════════════════════════════════════════════════════════════════
 * Probe generator task
 *
 * Sends a probe_pkt_t toward the root every PROBE_INTERVAL_MS milliseconds.
 * The root is addressed by passing `to = NULL` with the MESH_DATA_TODS flag:
 * per the ESP-WIFI-MESH API, a NULL destination means "the root", and TODS
 * marks the packet as travelling upward through the mesh. The root receives it
 * on the normal esp_mesh_recv() path. (Passing a zeroed mesh_addr_t instead of
 * NULL was the old bug — a 00:00:00:00:00:00 MAC is not the root, so no probe
 * ever arrived.)
 *
 * For Milestone 2 (blackhole), victim nodes will instead send directly to the
 * attacker's MAC address.  For Milestone 1, root is always the destination.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void probe_gen_task(void *arg)
{
    ESP_LOGI(TAG, "Probe generator task running at %u ms interval.",
             PROBE_INTERVAL_MS);

    probe_pkt_t pkt = {
        .magic = PROBE_MAGIC,
    };
    memcpy(pkt.src_mac, s_self_mac, 6);

    /* C7 Option 1: no per-destination setup here any more.
     *
     * This board used to build either a root-bound MESH_DATA_TODS send or, on a
     * blackhole victim build, a P2P send addressed to the attacker's MAC. Both
     * are gone: every probe now goes to THIS node's parent and is relayed hop by
     * hop (probe_relay_send_own), which is what paper Section 3.1.3.2's
     * "Forwarding Discipline" specifies.
     *
     * Consequence worth stating plainly: a victim no longer needs to know the
     * attacker exists. The attacker intercepts traffic because of WHERE IT SITS
     * in the tree, not because victims were compiled to address it - so
     * BLACKHOLE_ATTACKER_MAC is no longer load-bearing for targeting, and
     * attacker POSITION becomes a real experimental variable. */

    uint32_t seq = 0;

#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_BURST)
    /* Window detection: a "window" is either an announced attack phase
     * (blackhole/wormhole run) or the 2nd accepted phase broadcast (baseline
     * run — root_main.c's burst branch re-announces PHASE_ID_BASELINE so this
     * board sees a seq change even though phase_id never leaves 0). One-shot. */
    uint32_t last_bcast_seq = phase_listener_get_bcast_seq();
    int      n_bcasts_seen  = last_bcast_seq ? 1 : 0;
    bool     window_open    = false;
    bool     burst_done     = false;
    int64_t  window_t0_us   = 0;

    ESP_LOGW(TAG, "TRAFFIC_PROFILE=burst: will fire %u probes, %u s into the "
                  "attack-length window.", BURST_COUNT, BURST_OFFSET_S);
#endif

    while (!phase_listener_is_terminated()) {
        pkt.seq_num      = ++seq;
        pkt.send_ts_us   = esp_timer_get_time();

        /* C7 Option 1: send to OUR PARENT, hop by hop, and let every node on
         * the path relay it upward. This is paper Section 3.1.3.2's mandated
         * "Forwarding Discipline" (MESH_DATA_P2P), which the previous
         * MESH_DATA_TODS call did not satisfy — the stack relayed below the
         * app layer, so no intermediate node could observe its own forwarding.
         *
         * Note there is no longer a BLACKHOLE_VICTIM_TARGET branch here. The
         * attacker no longer has to be addressed by MAC to intercept anything:
         * it intercepts whatever passes through it because of WHERE IT SITS in
         * the tree. That is what makes attacker position a real variable. */
        esp_err_t err = probe_relay_send_own(&pkt);
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

#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_BURST)
        /* Sleep PROBE_INTERVAL_MS in BURST_POLL_MS slices instead of one long
         * vTaskDelay, so the window edge and the fire offset are each caught
         * within ~BURST_POLL_MS instead of up to a full PROBE_INTERVAL_MS late. */
        for (uint32_t slept_ms = 0; slept_ms < PROBE_INTERVAL_MS; slept_ms += BURST_POLL_MS) {
            vTaskDelay(pdMS_TO_TICKS(BURST_POLL_MS));
            if (burst_done) {
                continue;
            }

            uint32_t s = phase_listener_get_bcast_seq();
            if (s != last_bcast_seq) {
                last_bcast_seq = s;
                n_bcasts_seen++;
            }
            uint8_t pid = phase_listener_get_phase_id();

            if (!window_open) {
                bool attack_pid = (pid == PHASE_ID_BLACKHOLE || pid == PHASE_ID_WORMHOLE);
                bool past_window = (pid == PHASE_ID_COOLDOWN || pid == PHASE_ID_TERMINATE);
                if (past_window) {
                    ESP_LOGW(TAG, "BURST: window never detected before cooldown - skipped.");
                    burst_done = true;
                } else if (attack_pid || n_bcasts_seen >= 2) {
                    window_open  = true;
                    window_t0_us = esp_timer_get_time();
                    ESP_LOGW(TAG, "BURST: window opened (bcast seq=%lu, phase=%u); "
                                  "firing in %u s.",
                             (unsigned long)s, pid, BURST_OFFSET_S);
                }
            } else if (esp_timer_get_time() - window_t0_us >=
                       (int64_t)BURST_OFFSET_S * 1000000LL) {
                fire_burst(&pkt, &seq);
                burst_done = true;
            }
        }
#else
        vTaskDelay(pdMS_TO_TICKS(PROBE_INTERVAL_MS));
#endif
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

    /* Fixed-PERIOD sampling anchor. vTaskDelay() below used to sleep
     * SAMPLING_INTERVAL_MS *after* the body finished, so the real period was
     * body_time + 100ms. With CONFIG_FREERTOS_HZ=100 the tick is 10ms, so any
     * non-zero body time pushed the wake to the next tick and the node sampled
     * at 110ms = 9.09Hz. Measured on the 2026-09-22 home capture: the root sat
     * at exactly 110.0ms median and scored 93.6% against validate_integrity.py's
     * 10Hz expectation -- the M5 "95% of expected samples" blocker. Nothing was
     * being dropped (longest gap in the whole run: 0.36s); the cadence was just
     * slower than nominal, and no node whose body takes >0ms could ever pass.
     *
     * xTaskDelayUntil() sleeps until anchor + period instead, so the body's
     * duration is absorbed and the period is a true SAMPLING_INTERVAL_MS. */
    TickType_t next_sample = xTaskGetTickCount();
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
            /* "child", not "victim": this string is what the node IS by build,
             * and a plain child is only a VICTIM if the attacker happens to sit
             * between it and the root. Since C7 the blackhole is positional, so
             * a child above it is never touched -- yet it used to log itself
             * "victim" exactly like the one below that loses everything, which
             * is what made a pooled PDR describe neither node. Who was actually
             * exposed is derived from the tree in analysis/exposure.py and lands
             * in the feature table's `exposure` column. */
            "child",
            layer,
            pmac,
            rssi,
            retry_snap,
            tx_snap,
            probes_snap,
            phase_listener_get_phase_id(),
            phase_listener_get_label(),
            /* F3 relay counters — REAL now, not 0/0/0.
             *
             * Before C7 Option 1 an honest victim genuinely could not observe
             * its own forwarding: MESH_DATA_TODS meant the stack relayed below
             * the application layer. It now relays explicitly to its parent, so
             * these are measured values, and a node that carries transit
             * traffic reports recv > 0 like any other relay. That is what turns
             * ForwardingRatio from an attacker-only column into a distribution.
             *
             * A LEAF still reports 0/0/0 - correctly: it has no children, so
             * nothing transits it. That is an honest zero, and features.py
             * leaves ForwardingRatio undefined there (recv == 0) rather than
             * computing 0/0. */
            probe_relay_recv_count(),
            probe_relay_forward_count(),
            probe_relay_drop_count()
        );

        ESP_LOGD(TAG,
                 "Sample: ts=%lld rssi=%d layer=%d phase=%u label=%u "
                 "probes=%lu",
                 (long long)ts, rssi, layer,
                 phase_listener_get_phase_id(),
                 phase_listener_get_label(),
                 (unsigned long)probes_snap);

        xTaskDelayUntil(&next_sample, pdMS_TO_TICKS(SAMPLING_INTERVAL_MS));
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
