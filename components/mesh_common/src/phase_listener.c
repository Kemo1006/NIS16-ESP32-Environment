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

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/event_groups.h"

#include "esp_log.h"
#include "esp_mesh.h"
#include "esp_timer.h"
#include "esp_mac.h"

/* ── Module-private state ────────────────────────────────────────────────── */

static const char *TAG = "PHASE_LISTENER";

/* Shared state — always accessed under s_phase_mutex. */
static SemaphoreHandle_t s_phase_mutex   = NULL;
static uint8_t           s_phase_id      = PHASE_ID_BASELINE;
static uint8_t           s_gt_label      = GT_LABEL_BASELINE;
static uint32_t          s_last_seq      = 0;

/* Termination signal. */
#define TERMINATE_BIT   BIT0
static EventGroupHandle_t s_term_eg = NULL;

/* Root-side broadcast sequence counter (only the root increments this). */
static uint32_t s_bcast_seq = 0;

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

bool phase_listener_is_terminated(void)
{
    if (!s_term_eg) return false;
    return (xEventGroupGetBits(s_term_eg) & TERMINATE_BIT) != 0;
}

void phase_listener_wait_for_terminate(void)
{
    xEventGroupWaitBits(s_term_eg, TERMINATE_BIT,
                        pdFALSE, pdFALSE, portMAX_DELAY);
}

void phase_listener_set_data_cb(phase_listener_data_cb_t cb)
{
    s_data_cb = cb;
}

int phase_listener_broadcast(uint8_t phase_id)
{
    phase_msg_t msg = {
        .magic      = PHASE_MSG_MAGIC,
        .phase_id   = phase_id,
        .seq_num    = ++s_bcast_seq,
        .timestamp_us = esp_timer_get_time(),
    };

    mesh_data_t mdata = {
        .data  = (uint8_t *)&msg,
        .size  = sizeof(msg),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    int failed = 0;

    /*
     * ESP-WIFI-MESH has no single "broadcast to all nodes" call. To reach every
     * node we:
     *   1. Send to NULL — which the mesh stack delivers to the ROOT (us). This
     *      is what keeps the root's OWN phase state and TERMINATE signal in
     *      sync; it's a guaranteed local loopback.
     *   2. Unicast P2P to every node in the routing table — this is the only
     *      way packets actually travel DOWNSTREAM to the children. (The old
     *      code did only step 1, so children never saw a single phase.)
     * The listener deduplicates by seq_num, so the root receiving its own
     * message twice (via NULL and possibly via its own routing-table entry) is
     * harmless. All PHASE_BROADCAST_REPEAT copies share one seq_num on purpose:
     * repeats add reliability but apply the phase exactly once.
     */
    for (int i = 0; i < PHASE_BROADCAST_REPEAT; i++) {
        /* (1) Root's own copy — guaranteed loopback to our recv queue. */
        esp_err_t err = esp_mesh_send(NULL, &mdata, MESH_DATA_FROMDS, NULL, 0);
        if (err != ESP_OK) {
            failed++;
            ESP_LOGW(TAG, "Self broadcast failed (iter %d): %s",
                     i, esp_err_to_name(err));
        }

        /* (2) Downstream copies — one unicast per node in the routing table. */
        mesh_addr_t route[MESH_ROUTE_TABLE_MAX];
        int table_size = 0;
        err = esp_mesh_get_routing_table(route, MESH_ROUTE_TABLE_MAX * 6,
                                         &table_size);
        if (err != ESP_OK) {
            failed++;
            ESP_LOGW(TAG, "get_routing_table failed (iter %d): %s",
                     i, esp_err_to_name(err));
        } else {
            for (int n = 0; n < table_size; n++) {
                err = esp_mesh_send(&route[n], &mdata, MESH_DATA_P2P, NULL, 0);
                if (err != ESP_OK) {
                    failed++;
                    ESP_LOGW(TAG, "Broadcast to " MACSTR " failed (iter %d): %s",
                             MAC2STR(route[n].addr), i, esp_err_to_name(err));
                }
            }
        }

        vTaskDelay(pdMS_TO_TICKS(PHASE_BROADCAST_GAP_MS));
    }

    ESP_LOGI(TAG, "[ROOT] Broadcast phase_id=%u  seq=%lu  label=%u  (%d failed sends)",
             phase_id, (unsigned long)s_bcast_seq,
             phase_id_to_label(phase_id), failed);

    return failed;
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
            if (s_data_cb) {
                s_data_cb(rx_buf, mdata.size, from.addr);
            }
            continue;
        }

        /* Sequence-number deduplication — discard older or duplicate msgs. */
        xSemaphoreTake(s_phase_mutex, portMAX_DELAY);

        if (msg->seq_num <= s_last_seq) {
            /* Duplicate or out-of-order broadcast — ignore. */
            xSemaphoreGive(s_phase_mutex);
            continue;
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
