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
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "esp_log.h"
#include "esp_mesh.h"
#include "esp_wifi.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "esp_random.h"   /* jitter_extra_s() — TRAFFIC_PROFILE=jitter */

#include "mesh_config.h"
#include "mesh_setup.h"
#include "phase_listener.h"
#include "csv_logger.h"
#include "sd_status.h"
#include "mesh_messages.h"
#include "node_identity.h"
#include "nvs.h"

/* ── Module tag ──────────────────────────────────────────────────────────── */
static const char *TAG = "ROOT_MAIN";

/* ── Probe wire format (must match victim_main.c exactly) ────────────────── */
#define PROBE_MAGIC          0x50524F42U   /* "PROB" — normal probe            */
/* Wormhole tunnel ("fast") copy, stamped by wormhole Node A on re-injection.
 * The root logs these WITHOUT de-duping them against the normal copy, so the
 * same (src_mac, seq_num) shows up twice with a latency mismatch — the wormhole
 * signature. Must match wormhole_victim.c. ("PROW") */
#define PROBE_MAGIC_WORMHOLE 0x50524F57U

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
 * Probe de-duplication table.
 *
 * ESP-WIFI-MESH's own internal MAC-layer retry/ack mechanism can deliver
 * the same physical probe transmission to the root more than once (one
 * fast, correctly-timed arrival plus one or more much-delayed duplicates
 * with inflated latency). Without de-duplication, arrivals.csv ends up
 * with far more rows than probes actually sent, and downstream PDR /
 * latency features in later milestones would be computed over corrupted
 * data. We track the highest seq_num seen per source MAC and silently
 * drop any arrival whose seq_num was already logged for that source —
 * the same pattern phase_listener.c already uses for phase broadcasts.
 *
 * The table grows with the number of sending nodes - no source cap. Only
 * probe_data_cb (the phase-listener task) touches it, so no lock is needed.
 */
typedef struct {
    uint8_t  mac[6];
    uint32_t last_seq;
} probe_dedup_entry_t;

static probe_dedup_entry_t *s_dedup_table = NULL;
static size_t               s_dedup_count = 0;
static size_t               s_dedup_cap   = 0;

/**
 * @brief Return true if this (mac, seq_num) was already seen and logged.
 *        Updates the table as a side effect when it's a new arrival.
 */
static bool probe_is_duplicate(const uint8_t mac[6], uint32_t seq_num)
{
    for (size_t i = 0; i < s_dedup_count; i++) {
        if (memcmp(s_dedup_table[i].mac, mac, 6) == 0) {
            if (seq_num <= s_dedup_table[i].last_seq) {
                return true;   /* duplicate or stale/out-of-order retry */
            }
            s_dedup_table[i].last_seq = seq_num;
            return false;
        }
    }

    /* First time seeing this source MAC — register it. */
    if (s_dedup_count == s_dedup_cap) {
        size_t cap = s_dedup_cap ? s_dedup_cap * 2 : 8;
        probe_dedup_entry_t *grown = realloc(s_dedup_table, cap * sizeof(*grown));
        if (!grown) {
            ESP_LOGE(TAG, "Out of memory tracking probe source " MACSTR
                          " - its duplicates won't be filtered", MAC2STR(mac));
            return false;
        }
        s_dedup_table = grown;
        s_dedup_cap   = cap;
    }
    memcpy(s_dedup_table[s_dedup_count].mac, mac, 6);
    s_dedup_table[s_dedup_count].last_seq = seq_num;
    s_dedup_count++;
    return false;
}

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

    /* ── 0. SD environment check (non-fatal; telemetry stays on SPIFFS) ───── */
    sd_status_result_t sdres = sd_status_run_boot_check();
    if (sdres == SD_STATUS_OK) {
        ESP_LOGI(TAG, "SD ENV: OK -- %s", sd_status_report_path());
    } else {
        ESP_LOGE(TAG, "SD ENV: %s -- RUN CONTINUES, SPIFFS logging unaffected",
                 sd_status_result_str(sdres));
    }

    /* ── 0b. Identity (nickname). Must follow the SD boot check, which caches
     *        node_config.txt while the card is still mounted. Role is passed in
     *        because mesh_common cannot see this component's build flags. ──── */
    node_identity_resolve(NODE_ROLE_ROOT);

    /* ── 1. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(mesh_setup_init(MESH_ROLE_ROOT));
    mesh_setup_get_node_id(s_node_id);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);

    /* ── 2. Phase listener (the root also receives its own broadcasts via
     *       the mesh receive queue, keeping its own state consistent) ─────── */
    ESP_ERROR_CHECK(phase_listener_start());
    /* Keep hearing the children after TERMINATE: their final heartbeats are
     * what fill the dashboard's EXPORT column. */
    phase_listener_keep_running_after_terminate();

    /* ── 2b. Command Center heartbeat table — seeds the root's own row, then
     *        accepts updates via probe_data_cb below. Every connected node's
     *        MAC/layer/role becomes visible here, sorted by layer, as soon as
     *        each one's first heartbeat arrives. ───────────────────────────── */
    heartbeat_table_init();

    /* ── 3. Logger ───────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_ROOT));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* ── 4. Probe sink: register a handler for incoming probe packets.
     *       esp_mesh_recv() must be called from ONE task only, so instead of a
     *       competing receive loop the phase listener (the single reader) hands
     *       us every non-phase packet via this callback. It also demuxes
     *       heartbeat frames into heartbeat_ingest() — see probe_data_cb. ──── */
    phase_listener_set_data_cb(probe_data_cb);
    ESP_LOGI(TAG, "Probe sink + heartbeat table registered (via phase-listener dispatch).");

    /* ── 5. Start background tasks ───────────────────────────────────────── */
    xTaskCreate(telemetry_task,   "telemetry",   STACK_TELEMETRY,
                NULL, TASK_PRIO_TELEMETRY,   NULL);
    ESP_ERROR_CHECK(heartbeat_start());

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
 * Sequence: Baseline → [Attack, if ACTIVE_ATTACK set] → Cooldown → Terminate.
 * ACTIVE_ATTACK (mesh_config.h) selects the attack phase for a run; the default
 * ATTACK_NONE reproduces the Milestone-1 baseline-only sequence.
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

/*
 * Visual phase banner — one separator line so each phase boundary is easy to
 * find when scanning the console (and in screenshots). Console-only cosmetics;
 * nothing is logged to the CSV here.
 */
static void phase_banner(const char *name)
{
    ESP_LOGI(TAG, "════════════════════ %s ════════════════════", name);
}

/* Draw this run's extra seconds for one window (TRAFFIC_PROFILE=jitter).
 *
 * ADDITIVE ONLY, and the return value is added to the configured length -- see
 * the TIMING JITTER block in mesh_config.h for why shortening a window would
 * silently corrupt preprocess.py's baseline slice.
 *
 * esp_random() is the hardware RNG and is already seeded once Wi-Fi is up, which
 * it is by the time this task runs. Every board draws independently; only the
 * ROOT's draw matters, because only the root schedules phases. */
static uint32_t jitter_extra_s(uint32_t max_s)
{
#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_JITTER)
    if (max_s == 0) {
        return 0;
    }
    return esp_random() % (max_s + 1U);
#else
    (void)max_s;
    return 0;
#endif
}

static void experiment_controller_task(void *arg)
{
    /* Both draws happen HERE, before the first phase, so the whole run's
     * schedule is decided (and printed) up front rather than surprising the
     * operator mid-run. */
    const uint32_t jit_base   = jitter_extra_s(JITTER_BASELINE_MAX_S);
    const uint32_t jit_attack = jitter_extra_s(JITTER_ATTACK_MAX_S);
    /* On a plain baseline root (ACTIVE_ATTACK=NONE, TRAFFIC_PROFILE!=burst) BOTH
     * consumers of jit_attack are preprocessed out, so it reads as unused and
     * -Wunused-variable fires. Silenced here rather than restating those two #if
     * conditions a third time, which would rot the moment either one changes. */
    (void)jit_attack;

#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_JITTER)
    phase_banner("TIMING JITTER ACTIVE");
    ESP_LOGW(TAG, "[CTRL] TRAFFIC_PROFILE=jitter — this run's schedule is NOT the "
                  "standard one:");
    ESP_LOGW(TAG, "[CTRL]   baseline %u s (+%u jitter) , attack %u s (+%u jitter)",
             (unsigned)PHASE_BASELINE_S, (unsigned)jit_base,
             (unsigned)PHASE_ATTACK_S, (unsigned)jit_attack);
    ESP_LOGW(TAG, "[CTRL] Drawn fresh per boot so elapsed time stops predicting the "
                  "phase. Exact durations are recoverable from any node's CSV.");
#endif

    ESP_LOGI(TAG, "[CTRL] Waiting %u s for mesh to stabilise...",
             PHASE_STABILISE_S);
    vTaskDelay(pdMS_TO_TICKS(PHASE_STABILISE_S * 1000));

    /* ── Phase 0: Baseline ───────────────────────────────────────────────── */
    phase_banner("PHASE 0 — BASELINE");
    ESP_LOGI(TAG, "[CTRL] Starting PHASE 0 — Baseline (%u s)",
             (unsigned)(PHASE_BASELINE_S + jit_base));
    broadcast_and_count(PHASE_ID_BASELINE);
    vTaskDelay(pdMS_TO_TICKS((PHASE_BASELINE_S + jit_base) * 1000));
    ESP_LOGI(TAG, "[CTRL] Phase 0 complete.");

    /*
     * ── Phase 1 / 2: Attack (Milestone 2) ───────────────────────────────
     * ACTIVE_ATTACK (mesh_config.h, overridable with -DACTIVE_ATTACK=1) selects
     * the manipulation the root announces during the attack window:
     *   ATTACK_NONE            → skip; baseline-only run (Milestone 1 behaviour)
     *   PHASE_ID_BLACKHOLE (1) → blackhole phase (paired with blackhole_victim.c)
     * The root only announces the phase; the victim firmware reacts to it.
     */
#if (ACTIVE_ATTACK != ATTACK_NONE)
    phase_banner("PHASE — ATTACK");
    ESP_LOGI(TAG, "[CTRL] Starting PHASE %d — Attack (%u s)",
             ACTIVE_ATTACK, (unsigned)(PHASE_ATTACK_S + jit_attack));
    broadcast_and_count(ACTIVE_ATTACK);
    vTaskDelay(pdMS_TO_TICKS((PHASE_ATTACK_S + jit_attack) * 1000));
    ESP_LOGI(TAG, "[CTRL] Attack phase complete.");
#else
#if (TRAFFIC_PROFILE == TRAFFIC_PROFILE_BURST)
    /* Baseline run + burst traffic profile: hold an ATTACK-LENGTH window,
     * announced as PHASE_ID_BASELINE (gt_label stays 0 — this is NOT an
     * attack), so the burst-scenario's target child fires at the same offset
     * as it would in an attack run. This is what makes a baseline burst and
     * an attack-window burst a matched pair. Only burst builds pay this cost;
     * a plain baseline run (TRAFFIC_PROFILE=none) is unchanged. */
    phase_banner("PHASE 0b — BASELINE WINDOW (burst scenario)");
    ESP_LOGI(TAG, "[CTRL] ACTIVE_ATTACK=NONE, TRAFFIC_PROFILE=burst — holding an "
                  "attack-length baseline window (%u s) for the burst scenario.",
             PHASE_ATTACK_S);
    broadcast_and_count(PHASE_ID_BASELINE);   /* new seq_num, same phase 0 */
    /* Same jitter as a real attack window, so a jittered baseline run and a
     * jittered attack run stay a matched pair for the burst scenario. */
    vTaskDelay(pdMS_TO_TICKS((PHASE_ATTACK_S + jit_attack) * 1000));
    ESP_LOGI(TAG, "[CTRL] Baseline window complete.");
#else
    ESP_LOGI(TAG, "[CTRL] ACTIVE_ATTACK=NONE — skipping attack window (baseline run).");
#endif
#endif

    /* ── Phase 3: Cooldown ───────────────────────────────────────────────── */
    phase_banner("PHASE 3 — COOLDOWN");
    ESP_LOGI(TAG, "[CTRL] Starting PHASE 3 — Cooldown (%u s)", PHASE_COOLDOWN_S);
    broadcast_and_count(PHASE_ID_COOLDOWN);
    vTaskDelay(pdMS_TO_TICKS(PHASE_COOLDOWN_S * 1000));
    ESP_LOGI(TAG, "[CTRL] Phase 3 complete.");

    /* ── Phase 4: Terminate ──────────────────────────────────────────────── */
    phase_banner("PHASE 4 — TERMINATE");
    ESP_LOGI(TAG, "[CTRL] Broadcasting TERMINATE.");
    broadcast_and_count(PHASE_ID_TERMINATE);

    /* Re-send for a while: a child that was re-parenting (so not in the routing
     * table) missed the first round, and it would otherwise keep its file open. */
    for (uint32_t t = 0; t < TERMINATE_RESEND_S; t += TERMINATE_RESEND_GAP_S) {
        vTaskDelay(pdMS_TO_TICKS(TERMINATE_RESEND_GAP_S * 1000));
        phase_listener_broadcast(PHASE_ID_TERMINATE);
    }
    ESP_LOGI(TAG, "[CTRL] TERMINATE re-sends done.");

    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Probe sink callback
 *
 * Invoked by the phase listener (the single esp_mesh_recv() reader) for every
 * non-phase packet. Demuxes on magic (mesh_messages.h convention): heartbeat
 * frames go to heartbeat_ingest() (Command Center node table); everything
 * else is filtered for probe_pkt_t messages, logging one probe-arrival CSV
 * row per received probe.
 *
 * Runs in the phase-listener task context — keep it short and non-blocking.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void probe_data_cb(const uint8_t *data, size_t len,
                          const uint8_t from_addr[6])
{
    (void)from_addr;  /* src_mac travels inside the probe/heartbeat payload */

    if (heartbeat_ingest(data, len)) return;

    /* The listener now keeps running after TERMINATE (for the heartbeats
     * above). Probes past that point belong to no phase, and the log they
     * would go to is closing. */
    if (phase_listener_is_terminated()) return;

    if (len < sizeof(probe_pkt_t)) return;

    const probe_pkt_t *pkt = (const probe_pkt_t *)data;
    bool is_wormhole_copy = (pkt->magic == PROBE_MAGIC_WORMHOLE);
    if (pkt->magic != PROBE_MAGIC && !is_wormhole_copy) return;

    /* Normal probes: de-dup — ESP-MESH internal retry can deliver the same
     * probe to the root more than once, which would corrupt PDR/latency, so we
     * count/log only the first arrival per (src_mac, seq_num).
     *
     * Wormhole tunnel copies (PROBE_MAGIC_WORMHOLE, stamped by Node A): do NOT
     * de-dup. The whole point of the wormhole is that the same (src_mac,
     * seq_num) arrives a SECOND time via the tunnel with a different latency —
     * that duplicate + latency mismatch is the attack signature, so suppressing
     * it here would hide the very thing we're trying to capture. */
    if (!is_wormhole_copy &&
        probe_is_duplicate(pkt->src_mac, pkt->seq_num)) {
        ESP_LOGD(TAG, "Duplicate probe dropped: " MACSTR " seq=%lu",
                 MAC2STR(pkt->src_mac), (unsigned long)pkt->seq_num);
        return;
    }

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
 * Root has no parent so parent_mac is all-zeros; the stack reports it at layer 1.
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
            phase_listener_get_label(),
            /* F3 relay counters. recv_count is defined as "frames received
             * FOR RELAY" — and the root is the traffic's DESTINATION, not a
             * relay. Every probe that reaches it is consumed and logged to
             * arrivals.csv; none is ever passed on.
             *
             * So all three are 0 here, and specifically recv_count must NOT be
             * the arrival count. Setting it to probes_snap would give the root
             * recv > 0 with forward == 0, and features.compute_forwarding_
             * features() would compute ForwardingRatio = 0.0 for it — making
             * the node that MEASURES the attack look like the node COMMITTING
             * it, in every baseline window of every run.
             *
             * The arrival count is not lost: it is probes_count on this row,
             * and arrivals.csv holds one row per probe. */
            0,             /* recv_count    = the sink relays nothing       */
            0,             /* forward_count = the sink forwards nothing     */
            0              /* drop_count    = the sink drops nothing        */
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