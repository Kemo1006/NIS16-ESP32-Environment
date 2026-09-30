/**
 * @file phase_listener.c
 * @brief Phase-listener background task implementation.
 *
 * Runs on every node (root and victim alike).  Listens for phase-broadcast
 * messages from the root, deduplicates by sequence number, updates the shared
 * phase/label state under a mutex, and (on the root) provides the broadcast
 * helper used by root_main.c.
 *
 * NIS16 — CTTHES2 Milestone 1 — Common Module
 */

#include "phase_listener.h"
#include "mesh_config.h"

#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/event_groups.h"

#include "esp_log.h"
#include "esp_mesh.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "esp_random.h"

/* ── Module-private state ────────────────────────────────────────────────── */

static const char *TAG = "PHASE_LISTENER";

/* Shared state — always accessed under s_phase_mutex. */
static SemaphoreHandle_t s_phase_mutex   = NULL;

/* F1: start UNSET, not BASELINE. A node that has not yet heard a phase
 * broadcast does not know what the network is doing, and must not claim to.
 * These two initialisers used to read PHASE_ID_BASELINE / GT_LABEL_BASELINE,
 * which is what let 38% of the 2026-09-18 G402 capture record itself as
 * baseline while the root was not even in the mesh. See mesh_config.h
 * PHASE_ID_UNSET for the full incident. The first real broadcast overwrites
 * both below; until then every logged row is honestly marked unknown. */
static uint8_t           s_phase_id      = PHASE_ID_UNSET;
static uint8_t           s_gt_label      = GT_LABEL_UNSET;
static uint32_t          s_last_seq      = 0;
/* Session of the root whose seq_nums s_last_seq belongs to; 0 = none heard. */
static uint32_t          s_session_id    = 0;

/* Termination signal. */
#define TERMINATE_BIT   BIT0
static EventGroupHandle_t s_term_eg = NULL;

/* When the current phase was entered (esp_timer us), for the cooldown watchdog
 * in phase_listener_wait_for_terminate(). Written under s_phase_mutex. */
static int64_t           s_phase_since_us = 0;

/* Set when TERMINATE was declared by the watchdog, not received from the root. */
static volatile bool     s_term_timed_out = false;

/* Set by END_RUN (phase_listener_end_run_now). s_manual_complete says whether
 * the run had already reached cooldown, i.e. its labelled content is whole. */
static volatile bool     s_term_manual     = false;
static volatile bool     s_manual_complete = false;

/* Root only: keep receiving after TERMINATE (see
 * phase_listener_keep_running_after_terminate()). */
static bool              s_keep_running = false;
/* Latched by the root's PREPARE signal (PHASE_ID_PREPARE): a run is being
 * set up, so csv_logger may start logging - see LOG_ONLY_DURING_RUN. */
static volatile bool     s_prepare_heard = false;
bool phase_listener_prepare_heard(void) { return s_prepare_heard; }

/* Set by the START_ANYWAY serial command - see the root's roster gate. */
static volatile bool     s_start_anyway = false;

void phase_listener_request_start_anyway(void) { s_start_anyway = true; }
bool phase_listener_start_anyway_requested(void) { return s_start_anyway; }

/* Root-side broadcast sequence counter (only the root increments this). */
static uint32_t s_bcast_seq = 0;

/* Root-side: this boot's session id, drawn on the first broadcast. */
static uint32_t s_root_session = 0;

static uint32_t root_session(void)
{
    while (s_root_session == 0) {
        s_root_session = esp_random();
    }
    return s_root_session;
}

/* Handler for non-phase packets (e.g. probe arrivals). NULL = drop them. */
static phase_listener_data_cb_t s_data_cb = NULL;

/* ── Forward declarations ────────────────────────────────────────────────── */
static void     phase_listener_task(void *arg);
static uint8_t  phase_id_to_label(uint8_t phase_id);

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t phase_listener_start(void)
{
    s_phase_mutex = xSemaphoreCreateMutex();
    if (!s_phase_mutex) {
        ESP_LOGE(TAG, "Failed to create phase mutex");
        return ESP_ERR_NO_MEM;
    }

    s_term_eg = xEventGroupCreate();
    if (!s_term_eg) {
        ESP_LOGE(TAG, "Failed to create termination event group");
        return ESP_ERR_NO_MEM;
    }

    BaseType_t rc = xTaskCreate(
        phase_listener_task,
        "phase_listener",
        STACK_PHASE_LISTENER,
        NULL,
        TASK_PRIO_PHASE_LISTENER,
        NULL
    );

    if (rc != pdPASS) {
        ESP_LOGE(TAG, "Failed to create phase_listener task");
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Phase listener started.");
    return ESP_OK;
}

uint8_t phase_listener_get_label(void)
{
    xSemaphoreTake(s_phase_mutex, portMAX_DELAY);
    uint8_t label = s_gt_label;
    xSemaphoreGive(s_phase_mutex);
    return label;
}

uint8_t phase_listener_get_phase_id(void)
{
    xSemaphoreTake(s_phase_mutex, portMAX_DELAY);
    uint8_t pid = s_phase_id;
    xSemaphoreGive(s_phase_mutex);
    return pid;
}

uint32_t phase_listener_get_bcast_seq(void)
{
    xSemaphoreTake(s_phase_mutex, portMAX_DELAY);
    uint32_t seq = s_last_seq;
    xSemaphoreGive(s_phase_mutex);
    return seq;
}

bool phase_listener_is_terminated(void)
{
    if (!s_term_eg) return false;
    return (xEventGroupGetBits(s_term_eg) & TERMINATE_BIT) != 0;
}

/* A node that misses all PHASE_BROADCAST_REPEAT copies of TERMINATE (it was
 * mid-reparent, or the root lost power right at the end) used to wait here
 * forever: its SD mirror stayed open, the card listing said STILL RUNNING, and
 * pulling the card left the run with no "clean" manifest row, so it read as
 * ABORTED. By the time cooldown has run its full length plus a grace period,
 * the run's labelled content is complete, so the node ends it itself.
 *
 * Only COOLDOWN arms this. Any earlier phase can legitimately go silent for a
 * whole window, and a node that loses the mesh mid-run must keep logging: that
 * disconnection is exactly what a blackhole capture needs to show. */
void phase_listener_wait_for_terminate(void)
{
    const int64_t limit_us =
        (int64_t)(PHASE_COOLDOWN_S + TERMINATE_GRACE_S) * 1000000LL;
    for (;;) {
        EventBits_t bits = xEventGroupWaitBits(s_term_eg, TERMINATE_BIT,
                                               pdFALSE, pdFALSE,
                                               pdMS_TO_TICKS(5000));
        if (bits & TERMINATE_BIT) {
            return;
        }
        xSemaphoreTake(s_phase_mutex, portMAX_DELAY);
        bool in_cooldown = (s_phase_id == PHASE_ID_COOLDOWN);
        int64_t since_us = s_phase_since_us;
        xSemaphoreGive(s_phase_mutex);
        if (in_cooldown && esp_timer_get_time() - since_us > limit_us) {
            s_term_timed_out = true;
            ESP_LOGE(TAG, "No TERMINATE received %u s into cooldown -- ending the "
                          "run locally. Manifest will record term_timeout.",
                     (unsigned)(PHASE_COOLDOWN_S + TERMINATE_GRACE_S));
            xEventGroupSetBits(s_term_eg, TERMINATE_BIT);
            return;
        }
    }
}

bool phase_listener_terminate_timed_out(void)
{
    return s_term_timed_out;
}

int phase_listener_end_run_now(void)
{
    if (!s_term_eg || !s_phase_mutex) {
        return PL_END_NOT_RUNNING;
    }
    if (phase_listener_is_terminated()) {
        return PL_END_ALREADY;
    }
    xSemaphoreTake(s_phase_mutex, portMAX_DELAY);
    bool complete = (s_phase_id == PHASE_ID_COOLDOWN);
    xSemaphoreGive(s_phase_mutex);

    s_manual_complete = complete;
    s_term_manual     = true;
    ESP_LOGW(TAG, "END_RUN from USB -- ending the run now (%s). Manifest will "
                  "record manual_end.",
             complete ? "cooldown reached, data complete"
                      : "BEFORE cooldown, capture is cut short");
    xEventGroupSetBits(s_term_eg, TERMINATE_BIT);
    return complete ? PL_END_COMPLETE : PL_END_CUT_SHORT;
}

bool phase_listener_ended_manually(bool *complete)
{
    if (complete) {
        *complete = s_manual_complete;
    }
    return s_term_manual;
}

void phase_listener_keep_running_after_terminate(void)
{
    s_keep_running = true;
}

void phase_listener_set_data_cb(phase_listener_data_cb_t cb)
{
    s_data_cb = cb;
}

/*
 * One delivery round of a root message. ESP-WIFI-MESH has no single
 * "broadcast to all nodes" call. To reach every node we:
 *   1. Send to NULL — which the mesh stack delivers to the ROOT (us). This
 *      is what keeps the root's OWN phase state and TERMINATE signal in
 *      sync; it's a guaranteed local loopback.
 *   2. Unicast P2P to every node in the routing table — this is the only
 *      way packets actually travel DOWNSTREAM to the children. (The old
 *      code did only step 1, so children never saw a single phase.)
 * The listener deduplicates by seq_num, so the root receiving its own
 * message twice (via NULL and possibly via its own routing-table entry) is
 * harmless. Returns the number of failed esp_mesh_send() calls; quiet
 * suppresses the per-send warnings (PREPARE, sent every few seconds while
 * children are still joining, would otherwise flood the root's console).
 */
static int send_round(mesh_data_t *mdata, bool quiet)
{
    int failed = 0;

    /* (1) Root's own copy — guaranteed loopback to our recv queue. */
    esp_err_t err = esp_mesh_send(NULL, mdata, MESH_DATA_FROMDS, NULL, 0);
    if (err != ESP_OK) {
        failed++;
        if (!quiet) {
            ESP_LOGW(TAG, "Self broadcast failed: %s", esp_err_to_name(err));
        }
    }

    /* (2) Downstream copies — one unicast per node in the routing table.
     * Sized from the live table every time (plus headroom for a node that
     * joins between the size query and the copy), so every node gets the
     * message however large the mesh is. */
    int want = esp_mesh_get_routing_table_size() + 4;
    mesh_addr_t *route = malloc((size_t)want * sizeof(mesh_addr_t));
    int table_size = 0;
    err = route ? esp_mesh_get_routing_table(route, want * 6, &table_size)
                : ESP_ERR_NO_MEM;
    if (err != ESP_OK) {
        failed++;
        if (!quiet) {
            ESP_LOGW(TAG, "get_routing_table failed: %s", esp_err_to_name(err));
        }
    } else {
        for (int n = 0; n < table_size; n++) {
            err = esp_mesh_send(&route[n], mdata, MESH_DATA_P2P, NULL, 0);
            if (err != ESP_OK) {
                failed++;
                if (!quiet) {
                    ESP_LOGW(TAG, "Broadcast to " MACSTR " failed: %s",
                             MAC2STR(route[n].addr), esp_err_to_name(err));
                }
            }
        }
    }
    free(route);
    return failed;
}

int phase_listener_broadcast(uint8_t phase_id)
{
    phase_msg_t msg = {
        .magic      = PHASE_MSG_MAGIC,
        .phase_id   = phase_id,
        .seq_num    = ++s_bcast_seq,
        .timestamp_us = esp_timer_get_time(),
        .session_id = root_session(),
    };

    mesh_data_t mdata = {
        .data  = (uint8_t *)&msg,
        .size  = sizeof(msg),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    /* All PHASE_BROADCAST_REPEAT rounds share one seq_num on purpose: repeats
     * add reliability but apply the phase exactly once. */
    int failed = 0;
    for (int i = 0; i < PHASE_BROADCAST_REPEAT; i++) {
        failed += send_round(&mdata, false);
        vTaskDelay(pdMS_TO_TICKS(PHASE_BROADCAST_GAP_MS));
    }

    ESP_LOGI(TAG, "[ROOT] Broadcast phase_id=%u  seq=%lu  label=%u  (%d failed sends)",
             phase_id, (unsigned long)s_bcast_seq,
             phase_id_to_label(phase_id), failed);

    return failed;
}

void phase_listener_broadcast_prepare(void)
{
    /* Shares s_bcast_seq with real phases on purpose: the seq keeps rising, so
     * the Phase 0 broadcast that follows always outranks every PREPARE in the
     * listener's dedupe, and a late PREPARE can never be taken after it. */
    phase_msg_t msg = {
        .magic      = PHASE_MSG_MAGIC,
        .phase_id   = PHASE_ID_PREPARE,
        .seq_num    = ++s_bcast_seq,
        .timestamp_us = esp_timer_get_time(),
        .session_id = root_session(),
    };
    mesh_data_t mdata = {
        .data  = (uint8_t *)&msg,
        .size  = sizeof(msg),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };
    int failed = send_round(&mdata, true);
    ESP_LOGD(TAG, "[ROOT] PREPARE seq=%lu (%d failed sends)",
             (unsigned long)s_bcast_seq, failed);
    (void)failed;   /* only read by ESP_LOGD, which a build may compile out */
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Background task
 * ═══════════════════════════════════════════════════════════════════════════ */

static void phase_listener_task(void *arg)
{
    /*
     * Buffer large enough for any application packet we expect on the mesh
     * (phase broadcasts AND probe packets, which are larger). This is the
     * single esp_mesh_recv() reader on the node; non-phase packets are handed
     * to the registered data callback rather than dropped.
     */
    static uint8_t rx_buf[128];

    mesh_addr_t   from  = {0};
    mesh_data_t   mdata = {
        .data = rx_buf,
        .size = sizeof(rx_buf),
    };
    int flags = 0;

    ESP_LOGI(TAG, "Phase listener task running.");

    while (true) {
        /* Reset size before each receive call. */
        mdata.size = sizeof(rx_buf);

        esp_err_t err = esp_mesh_recv(&from, &mdata, portMAX_DELAY,
                                      &flags, NULL, 0);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "esp_mesh_recv error: %s", esp_err_to_name(err));
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }

        /*
         * Decide whether this is a phase broadcast. Anything else (probe
         * packets, etc.) is dispatched to the registered data callback — we
         * are the only esp_mesh_recv() reader, so we must not drop it.
         */
        const phase_msg_t *msg = (const phase_msg_t *)rx_buf;
        bool is_phase = (mdata.size >= sizeof(phase_msg_t) &&
                         msg->magic == PHASE_MSG_MAGIC);
        if (!is_phase) {
            /* After a watchdog ending this task is still alive (a received
             * TERMINATE deletes it on a child). Stop dispatching there, so the
             * node behaves as if TERMINATE had arrived. The root keeps
             * dispatching: it still needs the children's final heartbeats, and
             * its own callback ignores probes once terminated. */
            if (s_data_cb && (s_keep_running || !phase_listener_is_terminated())) {
                s_data_cb(rx_buf, mdata.size, from.addr);
            }
            continue;
        }

        xSemaphoreTake(s_phase_mutex, portMAX_DELAY);

        /* NEW ROOT SESSION. The root's seq_num restarts at 1 on every boot, and
         * Phase 0 is always the same seq (13, after 12 PREPAREs). A node that
         * joined an EARLIER root session kept that session's seq, so the new
         * root's PREPAREs and its Phase 0 all failed the dedupe below and the
         * node carried the dead session's phase on. 2026-09-26 21:11 home run:
         * the root board booted its previous firmware before the wizard wiped
         * it, reached Phase 0 with the children, was reflashed - and the
         * children logged 129 s of "baseline" before the real root's Phase 0.
         * A different session id means a different run: forget the old seq,
         * and go back to UNSET until the new root announces Phase 0. */
        if (msg->session_id != s_session_id) {
            if (phase_listener_is_terminated()) {
                /* This node's run is over; a new root session is a new run it
                 * is not part of (its logs are already closed). */
                xSemaphoreGive(s_phase_mutex);
                continue;
            }
            bool restarted = (s_session_id != 0);
            uint8_t old_phase = s_phase_id;
            s_session_id = msg->session_id;
            s_last_seq   = 0;
            if (restarted && s_phase_id != PHASE_ID_UNSET) {
                s_phase_id       = PHASE_ID_UNSET;
                s_gt_label       = GT_LABEL_UNSET;
                s_phase_since_us = esp_timer_get_time();
            }
            if (restarted) {
                ESP_LOGW(TAG, "Root RESTARTED (new session %08lx) - dropped phase %u "
                              "from the old session; rows stay phase 255 until the "
                              "new root's Phase 0.",
                         (unsigned long)s_session_id, old_phase);
            }
        }

        /* Sequence-number deduplication — discard older or duplicate msgs. */
        if (msg->seq_num <= s_last_seq) {
            /* Duplicate or out-of-order broadcast — ignore. */
            xSemaphoreGive(s_phase_mutex);
            continue;
        }

        /* PREPARE is not a phase: latch it for the logger and leave phase_id /
         * gt_label at 255, so stabilisation rows are logged but never labelled
         * baseline. Nothing else changes (no phase timer, no terminate). */
        if (msg->phase_id == PHASE_ID_PREPARE) {
            bool first = !s_prepare_heard;
            s_last_seq      = msg->seq_num;
            s_prepare_heard = true;
            xSemaphoreGive(s_phase_mutex);
            if (first) {
                ESP_LOGI(TAG, "Root is preparing a run (stabilisation) - logging starts, "
                              "rows stay phase 255 until Phase 0.");
            }
            continue;
        }

        /* The root re-sends TERMINATE for a while, and a node may already have
         * ended locally (watchdog / END_RUN). Take such a copy quietly; a child
         * then exits as it would have on the first one. */
        if (msg->phase_id == PHASE_ID_TERMINATE && phase_listener_is_terminated()) {
            s_last_seq = msg->seq_num;
            xSemaphoreGive(s_phase_mutex);
            if (!s_keep_running) {
                vTaskDelete(NULL);
            }
            continue;
        }

        if (msg->phase_id != s_phase_id) {
            s_phase_since_us = esp_timer_get_time();
        }
        s_last_seq  = msg->seq_num;
        s_phase_id  = msg->phase_id;
        s_gt_label  = phase_id_to_label(msg->phase_id);

        xSemaphoreGive(s_phase_mutex);

        ESP_LOGI(TAG, "Phase update → phase_id=%u  gt_label=%u  seq=%lu  "
                      "root_ts=%lld us",
                 msg->phase_id, phase_id_to_label(msg->phase_id),
                 (unsigned long)msg->seq_num,
                 (long long)msg->timestamp_us);

        /* Signal termination to anyone waiting. */
        if (msg->phase_id == PHASE_ID_TERMINATE) {
            xEventGroupSetBits(s_term_eg, TERMINATE_BIT);
            if (s_keep_running) {
                ESP_LOGI(TAG, "Experiment terminated — listener stays up for "
                              "the nodes' final heartbeats.");
                continue;
            }
            ESP_LOGI(TAG, "Experiment terminated — phase listener task exiting.");
            vTaskDelete(NULL);
        }
    }
}

/* ── Utility ─────────────────────────────────────────────────────────────── */

/**
 * Map phase ID → ground-truth label per Table 4.1 and Table 4.8 of thesis.
 *   Phase 0 (Baseline)   → label 0
 *   Phase 1 (Blackhole)  → label 1
 *   Phase 2 (Wormhole)   → label 2
 *   Phase 3 (Cooldown)   → label 0  (normal)
 *   Phase 4 (Terminate)  → label 0  (normal)
 */
static uint8_t phase_id_to_label(uint8_t phase_id)
{
    switch (phase_id) {
    case PHASE_ID_BLACKHOLE: return GT_LABEL_BLACKHOLE;
    case PHASE_ID_WORMHOLE:  return GT_LABEL_WORMHOLE;
    default:                 return GT_LABEL_BASELINE;
    }
}
