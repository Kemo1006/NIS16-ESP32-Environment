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

void phase_listener_broadcast(uint8_t phase_id)
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

    /* Broadcast target — all nodes in the mesh. */
    mesh_addr_t to = {0};
    memset(to.addr, 0, 6); 

    for (int i = 0; i < PHASE_BROADCAST_REPEAT; i++) {
        esp_err_t err = esp_mesh_send(NULL, &mdata,
                                      MESH_DATA_P2P | MESH_DATA_TODS,
                                      NULL, 0);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "Broadcast send failed (iter %d): %s",
                     i, esp_err_to_name(err));
        }
        vTaskDelay(pdMS_TO_TICKS(PHASE_BROADCAST_GAP_MS));
    }

    ESP_LOGI(TAG, "[ROOT] Broadcast phase_id=%u  seq=%lu  label=%u",
             phase_id, (unsigned long)s_bcast_seq,
             phase_id_to_label(phase_id));
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Background task
 * ═══════════════════════════════════════════════════════════════════════════ */

static void phase_listener_task(void *arg)
{
    /*
     * Buffer large enough for a phase_msg_t plus any future extension.
     * esp_mesh_recv() fills both the data and the source address.
     */
    static uint8_t rx_buf[sizeof(phase_msg_t) + 16];

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

        /* Ignore packets that are too small to be a phase message. */
        if (mdata.size < sizeof(phase_msg_t)) {
            continue;
        }

        const phase_msg_t *msg = (const phase_msg_t *)rx_buf;

        /* Check magic cookie — filters out probe and other traffic. */
        if (msg->magic != PHASE_MSG_MAGIC) {
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